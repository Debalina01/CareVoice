using System;
using System.Collections.Generic;
using System.Threading.Tasks;
using CareVoice.Application.DTOs;

namespace CareVoice.Application.Interfaces;

public interface ILogService
{
    Task<IEnumerable<SyncActionResponseDto>> SyncActionsAsync(Guid callerUserId, IEnumerable<SyncActionRequestDto> actions);
    Task<IEnumerable<DoseHistoryDto>> GetAdherenceHistoryAsync(Guid callerUserId, Guid? targetMemberId = null, DateTime? date = null);
}
