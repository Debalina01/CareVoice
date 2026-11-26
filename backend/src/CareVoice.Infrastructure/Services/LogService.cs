using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;
using Microsoft.EntityFrameworkCore;
using CareVoice.Application.DTOs;
using CareVoice.Application.Interfaces;
using CareVoice.Domain.Entities;
using CareVoice.Infrastructure.Persistence;

namespace CareVoice.Infrastructure.Services;

public class LogService : ILogService
{
    private readonly CareVoiceDbContext _dbContext;
    private readonly IPermissionService _permissionService;

    public LogService(CareVoiceDbContext dbContext, IPermissionService permissionService)
    {
        _dbContext = dbContext;
        _permissionService = permissionService;
    }

    public async Task<IEnumerable<SyncActionResponseDto>> SyncActionsAsync(
        Guid callerUserId,
        IEnumerable<SyncActionRequestDto> actions)
    {
        var responses = new List<SyncActionResponseDto>();

        foreach (var action in actions)
        {
            var alreadyExists = await _dbContext.MedicineLogs
                .AsNoTracking()
                .AnyAsync(l => l.ClientLogId == action.ClientLogId);

            if (alreadyExists)
            {
                responses.Add(new SyncActionResponseDto
                {
                    ClientLogId = action.ClientLogId,
                    Success = true,
                    Message = "Already synchronized (idempotent duplicate skipped)."
                });
                continue;
            }

            var schedule = await _dbContext.MedicineSchedules
                .AsNoTracking()
                .FirstOrDefaultAsync(s => s.Id == action.ScheduleId);

            if (schedule == null)
            {
                responses.Add(new SyncActionResponseDto
                {
                    ClientLogId = action.ClientLogId,
                    Success = false,
                    Message = $"Schedule with ID {action.ScheduleId} does not exist."
                });
                continue;
            }

            var isAuthorized = await _permissionService.IsAuthorizedForMemberAsync(callerUserId, action.TargetMemberId);
            if (!isAuthorized)
            {
                responses.Add(new SyncActionResponseDto
                {
                    ClientLogId = action.ClientLogId,
                    Success = false,
                    Message = "Unauthorized action for target family member."
                });
                continue;
            }

            var logEntry = new MedicineLog
            {
                Id = Guid.NewGuid(),
                ScheduleId = action.ScheduleId,
                TargetMemberId = action.TargetMemberId,
                ScheduledTime = action.ScheduledTime,
                ActionTime = action.ActionTime ?? DateTime.UtcNow,
                Status = action.Status,
                ClientLogId = action.ClientLogId,
                CreatedAt = DateTime.UtcNow
            };

            _dbContext.MedicineLogs.Add(logEntry);

            responses.Add(new SyncActionResponseDto
            {
                ClientLogId = action.ClientLogId,
                Success = true,
                Message = $"Logged {action.Status} successfully."
            });
        }

        await _dbContext.SaveChangesAsync();
        return responses;
    }

    public async Task<IEnumerable<DoseHistoryDto>> GetAdherenceHistoryAsync(
        Guid callerUserId,
        Guid? targetMemberId = null,
        DateTime? date = null)
    {
        var callerPrimaryMemberId = await _permissionService.GetPrimaryMemberIdAsync(callerUserId);

        IQueryable<MedicineLog> query = _dbContext.MedicineLogs
            .AsNoTracking()
            .Include(l => l.Schedule)
                .ThenInclude(s => s.Medicine)
            .Include(l => l.TargetMember);

        if (targetMemberId.HasValue)
        {
            var canView = await _permissionService.CanViewLogsAsync(callerUserId, targetMemberId.Value);
            if (!canView) return Enumerable.Empty<DoseHistoryDto>();
            query = query.Where(l => l.TargetMemberId == targetMemberId.Value);
        }
        else
        {
            var callerGroupIds = await _dbContext.FamilyGroupMembers
                .AsNoTracking()
                .Where(m => m.UserId == callerUserId && m.Status == "Approved")
                .Select(m => m.FamilyGroupId)
                .ToListAsync();

            query = query.Where(l => l.TargetMember.UserId == callerUserId ||
                                     _dbContext.FamilyPermissions.Any(fp => fp.GranterMemberId == l.TargetMemberId &&
                                                                            fp.GranteeMemberId == callerPrimaryMemberId &&
                                                                            fp.CanViewLogs) ||
                                     _dbContext.FamilyGroupMembers.Any(fgm => callerGroupIds.Contains(fgm.FamilyGroupId) &&
                                                                             fgm.UserId == l.TargetMember.UserId &&
                                                                             fgm.Status == "Approved"));
        }

        if (date.HasValue)
        {
            var startOfDay = date.Value.Date;
            var endOfDay = startOfDay.AddDays(1);
            query = query.Where(l => l.ScheduledTime >= startOfDay && l.ScheduledTime < endOfDay);
        }

        var logs = await query.OrderByDescending(l => l.ScheduledTime).ToListAsync();

        return logs.Select(l => new DoseHistoryDto
        {
            LogId = l.Id,
            ClientLogId = l.ClientLogId,
            ScheduleId = l.ScheduleId,
            MedicineName = l.Schedule?.Medicine?.Name ?? "Medicine",
            Dosage = l.Schedule?.Medicine?.Dosage ?? "",
            TargetMemberId = l.TargetMemberId,
            TargetMemberName = l.TargetMember?.FullName ?? "Member",
            ScheduledTime = l.ScheduledTime,
            ActionTime = l.ActionTime,
            Status = l.Status,
            CreatedAt = l.CreatedAt
        }).ToList();
    }
}
