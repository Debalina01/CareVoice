using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;
using Microsoft.EntityFrameworkCore;
using Xunit;
using CareVoice.Application.DTOs;
using CareVoice.Domain.Entities;
using CareVoice.Domain.Enums;
using CareVoice.Infrastructure.Persistence;
using CareVoice.Infrastructure.Services;

namespace CareVoice.Tests;

public class SerbomAiServiceTests
{
    private CareVoiceDbContext CreateDbContext(string dbName)
    {
        var options = new DbContextOptionsBuilder<CareVoiceDbContext>()
            .UseInMemoryDatabase(databaseName: dbName)
            .Options;
        return new CareVoiceDbContext(options);
    }

    private (CareVoiceDbContext db, SerbomAiService aiService, User user, FamilyMember selfMember, FamilyMember parentMember) SetupEnvironment(string dbName)
    {
        var db = CreateDbContext(dbName);
        var permService = new PermissionService(db);
        var medService = new MedicineService(db, permService);
        var schedService = new ScheduleService(db, permService);
        var aiService = new SerbomAiService(db, medService, schedService, permService);

        var user = new User { Id = Guid.NewGuid(), Email = "caregiver@test.com", FullName = "Caregiver", Role = "Caregiver" };
        var selfMember = new FamilyMember { Id = Guid.NewGuid(), UserId = user.Id, FullName = "Caregiver", Relation = "Self" };
        var parentMember = new FamilyMember { Id = Guid.NewGuid(), UserId = user.Id, FullName = "Papa", Relation = "Parent" };

        db.Users.Add(user);
        db.FamilyMembers.AddRange(selfMember, parentMember);
        db.SaveChanges();

        return (db, aiService, user, selfMember, parentMember);
    }

    [Fact]
    public async Task ProcessCommandAsync_EnglishFullInput_ReturnsReadyForConfirmation()
    {
        var (db, aiService, user, selfMember, parentMember) = SetupEnvironment("SerbomEnFull");

        var request = new SerbomAiRequestDto
        {
            Message = "Schedule Paracetamol 500mg twice daily after meals at 8:00 AM and 8:00 PM for Papa for 7 days",
            Language = "en"
        };

        var response = await aiService.ProcessCommandAsync(user.Id, request);

        Assert.Equal("CreateSchedule", response.Intent);
        Assert.Equal("ReadyForConfirmation", response.Status);
        Assert.NotNull(response.ExtractedSchedule);
        Assert.Equal("Paracetamol", response.ExtractedSchedule.MedicineName);
        Assert.Equal("500mg", response.ExtractedSchedule.Dosage);
        Assert.Equal(FoodRelation.AfterFood, response.ExtractedSchedule.FoodRelation);
        Assert.Equal(parentMember.Id, response.ExtractedSchedule.TargetMemberId);
        Assert.Contains("08:00", response.ExtractedSchedule.TimesOfDay);
        Assert.Contains("20:00", response.ExtractedSchedule.TimesOfDay);
        Assert.Equal(7, response.ExtractedSchedule.DurationDays);
        Assert.NotEmpty(response.ReplyMessage);
        Assert.NotEmpty(response.ReplyMessageBn);
    }

    [Fact]
    public async Task ProcessCommandAsync_BengaliFullInput_ReturnsReadyForConfirmation()
    {
        var (db, aiService, user, selfMember, parentMember) = SetupEnvironment("SerbomBnFull");

        var request = new SerbomAiRequestDto
        {
            Message = "বাবার জন্য প্রতিদিন সকাল ৮টা এবং রাত ৮টায় খাওয়ার পর প্যারাসিটামল ৫০০ মিলিগ্রাম ৭ দিনের জন্য দিন",
            Language = "bn"
        };

        var response = await aiService.ProcessCommandAsync(user.Id, request);

        Assert.Equal("CreateSchedule", response.Intent);
        Assert.Equal("ReadyForConfirmation", response.Status);
        Assert.NotNull(response.ExtractedSchedule);
        Assert.Equal("প্যারাসিটামল", response.ExtractedSchedule.MedicineName);
        Assert.Equal(FoodRelation.AfterFood, response.ExtractedSchedule.FoodRelation);
        Assert.Equal(parentMember.Id, response.ExtractedSchedule.TargetMemberId);
        Assert.Contains("08:00", response.ExtractedSchedule.TimesOfDay);
        Assert.Contains("20:00", response.ExtractedSchedule.TimesOfDay);
        Assert.Equal(7, response.ExtractedSchedule.DurationDays);
    }

    [Fact]
    public async Task ProcessCommandAsync_MissingDosage_ReturnsClarificationNeeded()
    {
        var (db, aiService, user, selfMember, parentMember) = SetupEnvironment("SerbomMissingDose");

        var request = new SerbomAiRequestDto
        {
            Message = "Schedule Aspirin for Papa at 09:00 AM",
            Language = "en"
        };

        var response = await aiService.ProcessCommandAsync(user.Id, request);

        Assert.Equal("ClarificationNeeded", response.Intent);
        Assert.Equal("Incomplete", response.Status);
        Assert.Contains("dosage", response.MissingFields);
        Assert.NotNull(response.FollowUpQuestion);
    }

    [Fact]
    public async Task ConfirmAndSaveScheduleAsync_CreatesMedicineAndSchedulesAtomically()
    {
        var (db, aiService, user, selfMember, parentMember) = SetupEnvironment("SerbomConfirmSave");

        var confirmDto = new ConfirmScheduleDto
        {
            TargetMemberId = parentMember.Id,
            MedicineName = "Metformin",
            Dosage = "500mg",
            Instructions = "Take with dinner",
            FoodRelation = FoodRelation.WithFood,
            TimesOfDay = new List<string> { "08:00", "20:00" },
            DaysOfWeekMask = 127
        };

        var response = await aiService.ConfirmAndSaveScheduleAsync(user.Id, confirmDto);

        Assert.NotEqual(Guid.Empty, response.MedicineId);
        Assert.Equal(2, response.ScheduleIds.Count);

        var savedMed = await db.Medicines.Include(m => m.Schedules).FirstOrDefaultAsync(m => m.Id == response.MedicineId);
        Assert.NotNull(savedMed);
        Assert.Equal("Metformin", savedMed.Name);
        Assert.Equal(2, savedMed.Schedules.Count);
        Assert.All(savedMed.Schedules, s => Assert.Equal(parentMember.Id, s.TargetMemberId));
    }

    [Fact]
    public async Task ProcessCommandAsync_DeleteCommand_DeletesScheduleSuccessfully()
    {
        var (db, aiService, user, selfMember, parentMember) = SetupEnvironment("SerbomDelete");

        var med = new Medicine
        {
            Id = Guid.NewGuid(),
            OwnerMemberId = parentMember.Id,
            Name = "Paracetamol",
            Dosage = "500mg",
            StartDate = DateTime.UtcNow
        };
        var sched = new MedicineSchedule
        {
            Id = Guid.NewGuid(),
            MedicineId = med.Id,
            TargetMemberId = parentMember.Id,
            CreatedByMemberId = selfMember.Id,
            TimeOfDay = new TimeSpan(8, 0, 0),
            IsActive = true
        };
        db.Medicines.Add(med);
        db.MedicineSchedules.Add(sched);
        await db.SaveChangesAsync();

        var request = new SerbomAiRequestDto
        {
            Message = "Delete schedule for Paracetamol",
            Language = "en"
        };

        var response = await aiService.ProcessCommandAsync(user.Id, request);

        Assert.Equal("DeleteSchedule", response.Intent);
        Assert.Equal("Executed", response.Status);

        var updatedSched = await db.MedicineSchedules.FindAsync(sched.Id);
        Assert.False(updatedSched!.IsActive);
    }
}
