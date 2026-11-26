using System;
using System.Collections.Generic;
using System.Threading.Tasks;
using CareVoice.Application.DTOs;

namespace CareVoice.Application.Interfaces;

public interface IFamilyMemberService
{
    Task<IEnumerable<FamilyMemberDto>> GetFamilyMembersAsync(Guid callerUserId);
    Task<FamilyMemberDto?> GetFamilyMemberByIdAsync(Guid callerUserId, Guid id);
    Task<FamilyMemberDto> CreateFamilyMemberAsync(Guid callerUserId, CreateFamilyMemberDto dto);
    Task<FamilyMemberDto?> UpdateFamilyMemberAsync(Guid callerUserId, Guid id, UpdateFamilyMemberDto dto);
    Task<bool> DeleteFamilyMemberAsync(Guid callerUserId, Guid id);
}
