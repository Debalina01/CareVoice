using System;
using System.Collections.Generic;
using System.Threading.Tasks;
using CareVoice.Application.DTOs;

namespace CareVoice.Application.Interfaces;

public interface IFamilyGroupService
{
    Task<FamilyGroupDto> CreateFamilyGroupAsync(Guid creatorUserId, CreateFamilyGroupDto dto);
    Task<FamilyGroupDto?> GetMyFamilyGroupAsync(Guid userId);
    Task<List<FamilyGroupDto>> GetAllMyFamilyGroupsAsync(Guid userId);
    Task<FamilyGroupDto?> GetFamilyGroupByIdAsync(Guid userId, Guid familyGroupId);
    Task<FamilyGroupDto> JoinFamilyGroupByCodeAsync(Guid userId, string familyCode);
    Task<bool> ApproveMemberAsync(Guid adminUserId, Guid familyGroupId, Guid targetUserId);
    Task<bool> RejectMemberAsync(Guid adminUserId, Guid familyGroupId, Guid targetUserId);
    Task<bool> RemoveMemberAsync(Guid adminUserId, Guid familyGroupId, Guid targetUserId);
    Task<List<SharedFamilyUpdateDto>> GetSharedUpdatesAsync(Guid userId, Guid familyGroupId);
    Task AddSharedUpdateAsync(Guid familyGroupId, string type, string title, string titleBn, string desc, string descBn, string actorName);
}
