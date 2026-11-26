using System;
using System.Linq;
using System.Threading.Tasks;
using Microsoft.EntityFrameworkCore;
using Xunit;
using CareVoice.Domain.Entities;
using CareVoice.Domain.Enums;
using CareVoice.Infrastructure.Persistence;
using CareVoice.Infrastructure.Services;

namespace CareVoice.Tests;

public class MissedReminderRelayServiceTests
{
    private CareVoiceDbContext CreateDbContext(string dbName)
    {
        var options = new DbContextOptionsBuilder<CareVoiceDbContext>()
            .UseInMemoryDatabase(databaseName: dbName)
            .Options;
        return new CareVoiceDbContext(options);
    }

    [Fact]
    public async Task ProcessOverdueDoses_ShouldCreateMissedLog_AndNotifyCreator()
    {
        var db = CreateDbContext("MissedRelayDb");
        var service = new MissedReminderRelayService(db);

        var cgUser = new User { Id = Guid.NewGuid(), Email = "cg@relay.com", FullName = "Caregiver" };
        var cgMember = new FamilyMember { Id = Guid.NewGuid(), UserId = cgUser.Id, FullName = "Caregiver", Relation = "Self" };
        var recUser = new User { Id = Guid.NewGuid(), Email = "rec@relay.com", FullName = "Recipient" };
        var recMember = new FamilyMember { Id = Guid.NewGuid(), UserId = recUser.Id, FullName = "Recipient", Relation = "Self" };

        var med = new Medicine
        {
            Id = Guid.NewGuid(),
            OwnerMemberId = recMember.Id,
            Name = "Blood Pressure Med",
            Dosage = "1 Pill",
            StartDate = DateTime.UtcNow.AddDays(-10)
        };

        var pastTime = DateTime.UtcNow.TimeOfDay.Subtract(TimeSpan.FromMinutes(45));
        var schedule = new MedicineSchedule
        {
            Id = Guid.NewGuid(),
            MedicineId = med.Id,
            TargetMemberId = recMember.Id,
            CreatedByMemberId = cgMember.Id,
            TimeOfDay = pastTime,
            DaysOfWeekMask = 127,
            IsActive = true
        };

        db.Users.AddRange(cgUser, recUser);
        db.FamilyMembers.AddRange(cgMember, recMember);
        db.Medicines.Add(med);
        db.MedicineSchedules.Add(schedule);
        await db.SaveChangesAsync();

        int processed = await service.ProcessOverdueDosesAsync(gracePeriodMinutes: 30);

        Assert.Equal(1, processed);

        var missedLog = await db.MedicineLogs.FirstOrDefaultAsync();
        Assert.NotNull(missedLog);
        Assert.Equal(LogStatus.Missed, missedLog.Status);
        Assert.Equal(schedule.Id, missedLog.ScheduleId);

        var notification = await db.Notifications.FirstOrDefaultAsync();
        Assert.NotNull(notification);
        Assert.Equal(cgUser.Id, notification.RecipientUserId);
        Assert.Contains("Missed Medicine Alert", notification.Title);

        int processedAgain = await service.ProcessOverdueDosesAsync(gracePeriodMinutes: 30);
        Assert.Equal(0, processedAgain);
        Assert.Equal(1, await db.Notifications.CountAsync());
    }
}
