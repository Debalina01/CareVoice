using System;
using System.Collections.Generic;
using System.Threading.Tasks;
using CareVoice.Application.DTOs;

namespace CareVoice.Application.Interfaces;

public interface IInviteService
{
    Task<InviteDto> CreateInviteAsync(Guid callerUserId, CreateInviteDto dto);
    Task<IEnumerable<InviteDto>> GetInvitesAsync(Guid callerUserId);
    Task<bool> AcceptInviteAsync(Guid callerUserId, AcceptInviteDto dto);
    Task<bool> CancelInviteAsync(Guid callerUserId, Guid inviteId);
}
