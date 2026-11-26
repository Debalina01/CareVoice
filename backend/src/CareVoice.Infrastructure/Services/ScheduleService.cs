using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;
using Microsoft.EntityFrameworkCore;
using CareVoice.Application.Common;
using CareVoice.Application.DTOs;
using CareVoice.Application.Interfaces;
using CareVoice.Domain.Entities;
using CareVoice.Infrastructure.Persistence;

namespace CareVoice.Infrastructure.Services;

public class ScheduleService : IScheduleService
{
    private readonly CareVoiceDbContext _dbContext;
    private readonly IPermissionService _permissionService;

    public ScheduleService(CareVoiceDbContext dbContext, IPermissionService permissionService)
    {
        _dbContext = dbContext;
        _permissionService = permissionService;
    }

    public async Task<IEnumerable<ScheduleDto>> GetSchedulesAsync(Guid callerUserId, Guid? targetMemberId = null)
    {
        var callerPrimaryMemberId = await _permissionService.GetPrimaryMemberIdAsync(callerUserId);

        IQueryable<MedicineSchedule> query = _dbContext.MedicineSchedules
            .AsNoTracking()
            .Include(s => s.Medicine)
            .Include(s => s.TargetMember)
            .Include(s => s.CreatedByMember)
            .Where(s => s.IsActive && !s.Medicine.IsDeleted);

        if (targetMemberId.HasValue)
        {
            var isAuthorized = await _permissionService.IsAuthorizedForMemberAsync(callerUserId, targetMemberId.Value);
            if (!isAuthorized) return Enumerable.Empty<ScheduleDto>();
            query = query.Where(s => s.TargetMemberId == targetMemberId.Value);
        }
        else
        {
            query = query.Where(s => s.TargetMember.UserId == callerUserId ||
                                     _dbContext.FamilyPermissions.Any(fp => fp.GranterMemberId == s.TargetMemberId &&
                                                                            fp.GranteeMemberId == callerPrimaryMemberId));
        }

        var schedules = await query.OrderBy(s => s.TimeOfDay).ToListAsync();

        return schedules.Select(s => new ScheduleDto
        {
            Id = s.Id,
            MedicineId = s.MedicineId,
            MedicineName = s.Medicine.Name,
            Dosage = s.Medicine.Dosage,
            Instructions = s.Medicine.Instructions,
            FoodRelation = s.Medicine.FoodRelation,
            TargetMemberId = s.TargetMemberId,
            TargetMemberName = s.TargetMember.FullName,
            CreatedByMemberId = s.CreatedByMemberId,
            CreatedByName = s.CreatedByMember.FullName,
            TimeOfDay = s.TimeOfDay.ToString(@"hh\:mm"),
            DaysOfWeekMask = s.DaysOfWeekMask,
            IsActive = s.IsActive,
            CreatedAt = s.CreatedAt
        }).ToList();
    }

    public async Task<ScheduleDto?> GetScheduleByIdAsync(Guid callerUserId, Guid id)
    {
        var schedule = await _dbContext.MedicineSchedules
            .AsNoTracking()
            .Include(s => s.Medicine)
            .Include(s => s.TargetMember)
            .Include(s => s.CreatedByMember)
            .FirstOrDefaultAsync(s => s.Id == id && s.IsActive);

        if (schedule == null) return null;

        var isAuthorized = await _permissionService.IsAuthorizedForMemberAsync(callerUserId, schedule.TargetMemberId);
        if (!isAuthorized) return null;

        return new ScheduleDto
        {
            Id = schedule.Id,
            MedicineId = schedule.MedicineId,
            MedicineName = schedule.Medicine.Name,
            Dosage = schedule.Medicine.Dosage,
            Instructions = schedule.Medicine.Instructions,
            FoodRelation = schedule.Medicine.FoodRelation,
            TargetMemberId = schedule.TargetMemberId,
            TargetMemberName = schedule.TargetMember.FullName,
            CreatedByMemberId = schedule.CreatedByMemberId,
            CreatedByName = schedule.CreatedByMember.FullName,
            TimeOfDay = schedule.TimeOfDay.ToString(@"hh\:mm"),
            DaysOfWeekMask = schedule.DaysOfWeekMask,
            IsActive = schedule.IsActive,
            CreatedAt = schedule.CreatedAt
        };
    }

    public async Task<ScheduleDto> CreateScheduleAsync(Guid callerUserId, CreateScheduleDto dto)
    {
        var canSet = await _permissionService.CanSetRemindersAsync(callerUserId, dto.TargetMemberId);
        if (!canSet)
        {
            throw new UnauthorizedAccessException("You do not have permission to set reminders for this member.");
        }

        var medicine = await _dbContext.Medicines.FindAsync(dto.MedicineId);
        if (medicine == null || medicine.IsDeleted)
        {
            throw new ArgumentException("Associated medicine not found.");
        }

        if (!TimeOfDayParser.TryParse(dto.TimeOfDay, out var parsedTime))
        {
            throw new ArgumentException("Invalid TimeOfDay format. Expected HH:mm (e.g. '08:30') or 12-hour format (e.g. '8:00 AM').");
        }

        var callerPrimaryMemberId = await _permissionService.GetPrimaryMemberIdAsync(callerUserId);
        var targetMember = await _dbContext.FamilyMembers.FindAsync(dto.TargetMemberId);
        var callerMember = await _dbContext.FamilyMembers.FindAsync(callerPrimaryMemberId);

        var existing = await _dbContext.MedicineSchedules
            .FirstOrDefaultAsync(s => s.MedicineId == dto.MedicineId &&
                                      s.TargetMemberId == dto.TargetMemberId &&
                                      s.TimeOfDay == parsedTime &&
                                      s.IsActive);

        if (existing != null)
        {
            existing.DaysOfWeekMask = dto.DaysOfWeekMask > 0 ? dto.DaysOfWeekMask : 127;
            await _dbContext.SaveChangesAsync();

            return new ScheduleDto
            {
                Id = existing.Id,
                MedicineId = existing.MedicineId,
                MedicineName = medicine.Name,
                Dosage = medicine.Dosage,
                Instructions = medicine.Instructions,
                FoodRelation = medicine.FoodRelation,
                TargetMemberId = existing.TargetMemberId,
                TargetMemberName = targetMember?.FullName ?? "Member",
                CreatedByMemberId = existing.CreatedByMemberId,
                CreatedByName = callerMember?.FullName ?? "Caregiver",
                TimeOfDay = existing.TimeOfDay.ToString(@"hh\:mm"),
                DaysOfWeekMask = existing.DaysOfWeekMask,
                IsActive = existing.IsActive,
                CreatedAt = existing.CreatedAt
            };
        }

        var schedule = new MedicineSchedule
        {
            Id = Guid.NewGuid(),
            MedicineId = dto.MedicineId,
            TargetMemberId = dto.TargetMemberId,
            CreatedByMemberId = callerPrimaryMemberId,
            TimeOfDay = parsedTime,
            DaysOfWeekMask = dto.DaysOfWeekMask > 0 ? dto.DaysOfWeekMask : 127,
            IsActive = true,
            CreatedAt = DateTime.UtcNow
        };

        _dbContext.MedicineSchedules.Add(schedule);
        await _dbContext.SaveChangesAsync();

        return new ScheduleDto
        {
            Id = schedule.Id,
            MedicineId = schedule.MedicineId,
            MedicineName = medicine.Name,
            Dosage = medicine.Dosage,
            Instructions = medicine.Instructions,
            FoodRelation = medicine.FoodRelation,
            TargetMemberId = schedule.TargetMemberId,
            TargetMemberName = targetMember?.FullName ?? "Member",
            CreatedByMemberId = schedule.CreatedByMemberId,
            CreatedByName = callerMember?.FullName ?? "Caregiver",
            TimeOfDay = schedule.TimeOfDay.ToString(@"hh\:mm"),
            DaysOfWeekMask = schedule.DaysOfWeekMask,
            IsActive = schedule.IsActive,
            CreatedAt = schedule.CreatedAt
        };
    }

    public async Task<ScheduleDto?> UpdateScheduleAsync(Guid callerUserId, Guid id, UpdateScheduleDto dto)
    {
        var schedule = await _dbContext.MedicineSchedules
            .Include(s => s.Medicine)
            .Include(s => s.TargetMember)
            .Include(s => s.CreatedByMember)
            .FirstOrDefaultAsync(s => s.Id == id);

        if (schedule == null) return null;

        var canSet = await _permissionService.CanSetRemindersAsync(callerUserId, schedule.TargetMemberId);
        if (!canSet)
        {
            throw new UnauthorizedAccessException("You do not have permission to modify this reminder schedule.");
        }

        if (!TimeOfDayParser.TryParse(dto.TimeOfDay, out var parsedTime))
        {
            throw new ArgumentException("Invalid TimeOfDay format. Expected HH:mm or 12-hour format (e.g. '8:00 AM').");
        }

        schedule.TimeOfDay = parsedTime;
        schedule.DaysOfWeekMask = dto.DaysOfWeekMask > 0 ? dto.DaysOfWeekMask : 127;
        schedule.IsActive = dto.IsActive;

        await _dbContext.SaveChangesAsync();

        return new ScheduleDto
        {
            Id = schedule.Id,
            MedicineId = schedule.MedicineId,
            MedicineName = schedule.Medicine.Name,
            Dosage = schedule.Medicine.Dosage,
            Instructions = schedule.Medicine.Instructions,
            FoodRelation = schedule.Medicine.FoodRelation,
            TargetMemberId = schedule.TargetMemberId,
            TargetMemberName = schedule.TargetMember.FullName,
            CreatedByMemberId = schedule.CreatedByMemberId,
            CreatedByName = schedule.CreatedByMember.FullName,
            TimeOfDay = schedule.TimeOfDay.ToString(@"hh\:mm"),
            DaysOfWeekMask = schedule.DaysOfWeekMask,
            IsActive = schedule.IsActive,
            CreatedAt = schedule.CreatedAt
        };
    }

    public async Task<bool> DeleteScheduleAsync(Guid callerUserId, Guid id)
    {
        var schedule = await _dbContext.MedicineSchedules
            .FirstOrDefaultAsync(s => s.Id == id);

        if (schedule == null) return false;

        var canSet = await _permissionService.CanSetRemindersAsync(callerUserId, schedule.TargetMemberId);
        if (!canSet)
        {
            throw new UnauthorizedAccessException("You do not have permission to delete this schedule.");
        }

        schedule.IsActive = false;
        await _dbContext.SaveChangesAsync();
        return true;
    }

    public async Task<IEnumerable<DoseSyncDto>> Get48HourSyncWindowAsync(Guid callerUserId, Guid? targetMemberId = null)
    {
        var callerPrimaryMemberId = await _permissionService.GetPrimaryMemberIdAsync(callerUserId);

        IQueryable<MedicineSchedule> query = _dbContext.MedicineSchedules
            .AsNoTracking()
            .Include(s => s.Medicine)
            .Include(s => s.TargetMember)
            .Where(s => s.IsActive && !s.Medicine.IsDeleted);

        if (targetMemberId.HasValue)
        {
            var isAuthorized = await _permissionService.IsAuthorizedForMemberAsync(callerUserId, targetMemberId.Value);
            if (!isAuthorized) return Enumerable.Empty<DoseSyncDto>();
            query = query.Where(s => s.TargetMemberId == targetMemberId.Value);
        }
        else
        {
            var callerGroupIds = await _dbContext.FamilyGroupMembers
                .AsNoTracking()
                .Where(m => m.UserId == callerUserId && m.Status == "Approved")
                .Select(m => m.FamilyGroupId)
                .ToListAsync();

            query = query.Where(s => s.TargetMember.UserId == callerUserId ||
                                     _dbContext.FamilyPermissions.Any(fp => fp.GranterMemberId == s.TargetMemberId &&
                                                                            fp.GranteeMemberId == callerPrimaryMemberId) ||
                                     _dbContext.FamilyGroupMembers.Any(fgm => callerGroupIds.Contains(fgm.FamilyGroupId) &&
                                                                              fgm.UserId == s.TargetMember.UserId &&
                                                                              fgm.Status == "Approved"));
        }

        var activeSchedules = await query.ToListAsync();
        var nowUtc = DateTime.UtcNow;
        var endUtc = nowUtc.AddHours(48);

        var result = new List<DoseSyncDto>();

        for (var date = nowUtc.Date; date <= endUtc.Date; date = date.AddDays(1))
        {
            var dayBit = 1 << (int)date.DayOfWeek;

            foreach (var schedule in activeSchedules)
            {
                if ((schedule.DaysOfWeekMask & dayBit) == 0) continue;

                if (date < schedule.Medicine.StartDate.Date) continue;
                if (schedule.Medicine.EndDate.HasValue && date > schedule.Medicine.EndDate.Value.Date) continue;

                var doseTimeUtc = date.Add(schedule.TimeOfDay);

                if (doseTimeUtc >= nowUtc.Date && doseTimeUtc <= endUtc)
                {
                    result.Add(new DoseSyncDto
                    {
                        ScheduleId = schedule.Id,
                        MedicineId = schedule.MedicineId,
                        MedicineName = schedule.Medicine.Name,
                        Dosage = schedule.Medicine.Dosage,
                        Instructions = schedule.Medicine.Instructions,
                        FoodRelation = schedule.Medicine.FoodRelation,
                        TargetMemberId = schedule.TargetMemberId,
                        TargetMemberName = schedule.TargetMember.FullName,
                        ScheduledTimeUtc = doseTimeUtc,
                        TimeOfDay = schedule.TimeOfDay.ToString(@"hh\:mm"),
                        PreferredLanguage = schedule.TargetMember.PreferredLanguage,
                        VoicePreference = schedule.TargetMember.VoicePreference
                    });
                }
            }
        }

        return result.OrderBy(d => d.ScheduledTimeUtc);
    }
}
