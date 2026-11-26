using System;
using System.Linq;
using System.Text.Json;
using System.Threading.Tasks;
using Microsoft.EntityFrameworkCore;
using CareVoice.Application.Interfaces;
using CareVoice.Domain.Entities;
using CareVoice.Domain.Enums;
using CareVoice.Infrastructure.Persistence;

namespace CareVoice.Infrastructure.Services;

public class MissedReminderRelayService : IMissedReminderRelayService
{
    private readonly CareVoiceDbContext _dbContext;

    public MissedReminderRelayService(CareVoiceDbContext dbContext)
    {
        _dbContext = dbContext;
    }

    public async Task<int> ProcessOverdueDosesAsync(int gracePeriodMinutes = 30)
    {
        var nowUtc = DateTime.UtcNow;
        var cutoffTime = nowUtc.AddMinutes(-gracePeriodMinutes);
        var startOfDay = nowUtc.Date;

        var activeSchedules = await _dbContext.MedicineSchedules
            .Include(s => s.Medicine)
            .Include(s => s.TargetMember)
            .Include(s => s.CreatedByMember)
                .ThenInclude(cbm => cbm.User)
            .Where(s => s.IsActive && !s.Medicine.IsDeleted)
            .ToListAsync();

        int missedCount = 0;
        var dayBit = 1 << (int)nowUtc.DayOfWeek;

        foreach (var schedule in activeSchedules)
        {
            if ((schedule.DaysOfWeekMask & dayBit) == 0) continue;

            if (nowUtc.Date < schedule.Medicine.StartDate.Date) continue;
            if (schedule.Medicine.EndDate.HasValue && nowUtc.Date > schedule.Medicine.EndDate.Value.Date) continue;

            var scheduledTimeUtc = nowUtc.Date.Add(schedule.TimeOfDay);

            if (scheduledTimeUtc > cutoffTime || scheduledTimeUtc < startOfDay) continue;

            var existingLog = await _dbContext.MedicineLogs
                .AsNoTracking()
                .AnyAsync(l => l.ScheduleId == schedule.Id && l.ScheduledTime == scheduledTimeUtc);

            if (existingLog) continue;

            var missedLog = new MedicineLog
            {
                Id = Guid.NewGuid(),
                ScheduleId = schedule.Id,
                TargetMemberId = schedule.TargetMemberId,
                ScheduledTime = scheduledTimeUtc,
                ActionTime = nowUtc,
                Status = LogStatus.Missed,
                ClientLogId = Guid.NewGuid(),
                CreatedAt = nowUtc
            };

            _dbContext.MedicineLogs.Add(missedLog);

            var creatorUserId = schedule.CreatedByMember.UserId;

            var notification = new Notification
            {
                Id = Guid.NewGuid(),
                RecipientUserId = creatorUserId,
                Title = $"Missed Medicine Alert: {schedule.Medicine.Name}",
                Body = $"{schedule.TargetMember.FullName} has not confirmed taking {schedule.Medicine.Name} ({schedule.Medicine.Dosage}) scheduled for {schedule.TimeOfDay:hh\\:mm}.",
                PayloadJson = JsonSerializer.Serialize(new
                {
                    scheduleId = schedule.Id,
                    medicineName = schedule.Medicine.Name,
                    targetMemberId = schedule.TargetMemberId,
                    targetMemberName = schedule.TargetMember.FullName,
                    scheduledTime = scheduledTimeUtc,
                    alertType = "MISSED_RELAY"
                }),
                IsRead = false,
                CreatedAt = nowUtc
            };

            _dbContext.Notifications.Add(notification);
            missedCount++;
        }

        if (missedCount > 0)
        {
            await _dbContext.SaveChangesAsync();
        }

        return missedCount;
    }
}
