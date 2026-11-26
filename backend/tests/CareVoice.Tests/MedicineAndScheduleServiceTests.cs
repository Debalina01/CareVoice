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

public class MedicineAndScheduleServiceTests
{
    private CareVoiceDbContext CreateDbContext(string dbName)
    {
        var options = new DbContextOptionsBuilder<CareVoiceDbContext>()
            .UseInMemoryDatabase(databaseName: dbName)
            .Options;
        return new CareVoiceDbContext(options);
    }

    [Fact]
    public async Task CreateMedicine_ShouldSucceed_ForAuthorizedMember()
    {
        var db = CreateDbContext("CreateMedicineDb");
        var permService = new PermissionService(db);
        var medService = new MedicineService(db, permService);

        var user = new User { Id = Guid.NewGuid(), Email = "user@test.com", FullName = "User" };
        var member = new FamilyMember { Id = Guid.NewGuid(), UserId = user.Id, FullName = "User", Relation = "Self" };
        db.Users.Add(user);
        db.FamilyMembers.Add(member);
        await db.SaveChangesAsync();

        var dto = new CreateMedicineDto
        {
            OwnerMemberId = member.Id,
            Name = "Metformin 500mg",
            Dosage = "1 Tablet",
            Instructions = "Take with dinner",
            FoodRelation = FoodRelation.WithFood,
            StartDate = DateTime.UtcNow
        };

        var created = await medService.CreateMedicineAsync(user.Id, dto);

        Assert.NotNull(created);
        Assert.Equal("Metformin 500mg", created.Name);
        Assert.Equal(FoodRelation.WithFood, created.FoodRelation);

        var list = (await medService.GetMedicinesAsync(user.Id)).ToList();
        Assert.Single(list);
    }

    [Fact]
    public async Task CreateSchedule_And_Get48HourSyncWindow_ShouldReturnDoses()
    {
        var db = CreateDbContext("SyncWindowDb");
        var permService = new PermissionService(db);
        var medService = new MedicineService(db, permService);
        var scheduleService = new ScheduleService(db, permService);

        var user = new User { Id = Guid.NewGuid(), Email = "sync_user@test.com", FullName = "Sync User" };
        var member = new FamilyMember
        {
            Id = Guid.NewGuid(),
            UserId = user.Id,
            FullName = "Sync User",
            Relation = "Self",
            PreferredLanguage = "en",
            VoicePreference = "en-US-Standard-B"
        };
        db.Users.Add(user);
        db.FamilyMembers.Add(member);
        await db.SaveChangesAsync();

        var med = await medService.CreateMedicineAsync(user.Id, new CreateMedicineDto
        {
            OwnerMemberId = member.Id,
            Name = "Lisinopril 10mg",
            Dosage = "1 Pill",
            StartDate = DateTime.UtcNow.AddDays(-1)
        });

        var schedule = await scheduleService.CreateScheduleAsync(user.Id, new CreateScheduleDto
        {
            MedicineId = med.Id,
            TargetMemberId = member.Id,
            TimeOfDay = "10:00",
            DaysOfWeekMask = 127
        });

        Assert.NotNull(schedule);
        Assert.Equal("10:00", schedule.TimeOfDay);

        var doses = (await scheduleService.Get48HourSyncWindowAsync(user.Id)).ToList();

        Assert.NotEmpty(doses);
        Assert.All(doses, d => Assert.Equal("Lisinopril 10mg", d.MedicineName));
        Assert.All(doses, d => Assert.Equal("en-US-Standard-B", d.VoicePreference));
    }

    [Fact]
    public async Task SyncActions_ShouldAppendLog_AndBeIdempotentOnDuplicate()
    {
        var db = CreateDbContext("AppendOnlyDb");
        var permService = new PermissionService(db);
        var logService = new LogService(db, permService);

        var user = new User { Id = Guid.NewGuid(), Email = "log_user@test.com", FullName = "Log User" };
        var member = new FamilyMember { Id = Guid.NewGuid(), UserId = user.Id, FullName = "Log User", Relation = "Self" };
        var med = new Medicine { Id = Guid.NewGuid(), OwnerMemberId = member.Id, Name = "Aspirin", Dosage = "1 Tab" };
        var schedule = new MedicineSchedule
        {
            Id = Guid.NewGuid(),
            MedicineId = med.Id,
            TargetMemberId = member.Id,
            CreatedByMemberId = member.Id,
            TimeOfDay = new TimeSpan(8, 0, 0)
        };

        db.Users.Add(user);
        db.FamilyMembers.Add(member);
        db.Medicines.Add(med);
        db.MedicineSchedules.Add(schedule);
        await db.SaveChangesAsync();

        var clientLogId = Guid.NewGuid();
        var actions = new List<SyncActionRequestDto>
        {
            new SyncActionRequestDto
            {
                ClientLogId = clientLogId,
                ScheduleId = schedule.Id,
                TargetMemberId = member.Id,
                ScheduledTime = DateTime.UtcNow,
                ActionTime = DateTime.UtcNow,
                Status = LogStatus.Taken
            }
        };

        var results1 = (await logService.SyncActionsAsync(user.Id, actions)).ToList();
        Assert.True(results1[0].Success);
        Assert.Equal(1, await db.MedicineLogs.CountAsync());

        var results2 = (await logService.SyncActionsAsync(user.Id, actions)).ToList();
        Assert.True(results2[0].Success);
        Assert.Contains("idempotent", results2[0].Message.ToLower());

        Assert.Equal(1, await db.MedicineLogs.CountAsync());

        var secondClientLogId = Guid.NewGuid();
        var actions2 = new List<SyncActionRequestDto>
        {
            new SyncActionRequestDto
            {
                ClientLogId = secondClientLogId,
                ScheduleId = schedule.Id,
                TargetMemberId = member.Id,
                ScheduledTime = DateTime.UtcNow,
                ActionTime = DateTime.UtcNow.AddMinutes(15),
                Status = LogStatus.Taken
            }
        };

        var results3 = (await logService.SyncActionsAsync(user.Id, actions2)).ToList();
        Assert.True(results3[0].Success);

        Assert.Equal(2, await db.MedicineLogs.CountAsync());
    }

    [Theory]
    [InlineData("8:00 AM", "08:00")]
    [InlineData("08:00 AM", "08:00")]
    [InlineData("8:30 PM", "20:30")]
    [InlineData("8:30pm", "20:30")]
    [InlineData("8am", "08:00")]
    [InlineData("8 pm", "20:00")]
    [InlineData("20:00", "20:00")]
    [InlineData("08:30:00", "08:30")]
    [InlineData("8.30 AM", "08:30")]
    [InlineData("০৮:৩০", "08:30")]
    [InlineData("12:00 AM", "00:00")]
    [InlineData("12:00 PM", "12:00")]
    public async Task CreateSchedule_ShouldAcceptFlexibleTimeFormats(string inputTime, string expectedNormalizedTime)
    {
        var db = CreateDbContext($"FlexibleTimeDb_{Guid.NewGuid()}");
        var permService = new PermissionService(db);
        var medService = new MedicineService(db, permService);
        var scheduleService = new ScheduleService(db, permService);

        var user = new User { Id = Guid.NewGuid(), Email = $"time_user_{Guid.NewGuid()}@test.com", FullName = "Time User" };
        var member = new FamilyMember { Id = Guid.NewGuid(), UserId = user.Id, FullName = "Time User", Relation = "Self" };
        db.Users.Add(user);
        db.FamilyMembers.Add(member);
        await db.SaveChangesAsync();

        var med = await medService.CreateMedicineAsync(user.Id, new CreateMedicineDto
        {
            OwnerMemberId = member.Id,
            Name = "Paracetamol 500mg",
            Dosage = "1 Tab",
            StartDate = DateTime.UtcNow
        });

        var schedule = await scheduleService.CreateScheduleAsync(user.Id, new CreateScheduleDto
        {
            MedicineId = med.Id,
            TargetMemberId = member.Id,
            TimeOfDay = inputTime,
            DaysOfWeekMask = 127
        });

        Assert.NotNull(schedule);
        Assert.Equal(expectedNormalizedTime, schedule.TimeOfDay);
    }

    [Fact]
    public async Task CreateSchedule_WithInvalidTime_ShouldThrowArgumentException()
    {
        var db = CreateDbContext("InvalidTimeDb");
        var permService = new PermissionService(db);
        var medService = new MedicineService(db, permService);
        var scheduleService = new ScheduleService(db, permService);

        var user = new User { Id = Guid.NewGuid(), Email = "invalid_user@test.com", FullName = "Invalid User" };
        var member = new FamilyMember { Id = Guid.NewGuid(), UserId = user.Id, FullName = "Invalid User", Relation = "Self" };
        db.Users.Add(user);
        db.FamilyMembers.Add(member);
        await db.SaveChangesAsync();

        var med = await medService.CreateMedicineAsync(user.Id, new CreateMedicineDto
        {
            OwnerMemberId = member.Id,
            Name = "Aspirin",
            Dosage = "1 Tab",
            StartDate = DateTime.UtcNow
        });

        await Assert.ThrowsAsync<ArgumentException>(() => scheduleService.CreateScheduleAsync(user.Id, new CreateScheduleDto
        {
            MedicineId = med.Id,
            TargetMemberId = member.Id,
            TimeOfDay = "invalid_time_string",
            DaysOfWeekMask = 127
        }));
    }
}
