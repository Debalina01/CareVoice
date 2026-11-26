using System;
using System.Threading.Tasks;

namespace CareVoice.Application.Interfaces;

public interface IPermissionService
{
    Task<bool> CanSetRemindersAsync(Guid callerUserId, Guid targetMemberId);
    Task<bool> CanViewLogsAsync(Guid callerUserId, Guid targetMemberId);
    Task<bool> IsAuthorizedForMemberAsync(Guid callerUserId, Guid targetMemberId);
    Task<Guid> GetPrimaryMemberIdAsync(Guid userId);
}
