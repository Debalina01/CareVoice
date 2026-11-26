using System;
using System.Collections.Generic;
using System.Threading.Tasks;
using CareVoice.Application.DTOs;

namespace CareVoice.Application.Interfaces;

public interface IScheduleService
{
    Task<IEnumerable<ScheduleDto>> GetSchedulesAsync(Guid callerUserId, Guid? targetMemberId = null);
    Task<ScheduleDto?> GetScheduleByIdAsync(Guid callerUserId, Guid id);
    Task<ScheduleDto> CreateScheduleAsync(Guid callerUserId, CreateScheduleDto dto);
    Task<ScheduleDto?> UpdateScheduleAsync(Guid callerUserId, Guid id, UpdateScheduleDto dto);
    Task<bool> DeleteScheduleAsync(Guid callerUserId, Guid id);
    Task<IEnumerable<DoseSyncDto>> Get48HourSyncWindowAsync(Guid callerUserId, Guid? targetMemberId = null);
}
