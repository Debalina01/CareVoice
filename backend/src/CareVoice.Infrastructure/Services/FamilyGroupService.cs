using System;
using System.Collections.Generic;
using System.Linq;
using System.Security.Cryptography;
using System.Threading.Tasks;
using Microsoft.EntityFrameworkCore;
using CareVoice.Application.DTOs;
using CareVoice.Application.Interfaces;
using CareVoice.Domain.Entities;
using CareVoice.Domain.Enums;
using CareVoice.Infrastructure.Persistence;

namespace CareVoice.Infrastructure.Services;

public class FamilyGroupService : IFamilyGroupService
{
    private readonly CareVoiceDbContext _dbContext;
    private readonly IPermissionService _permissionService;

    public FamilyGroupService(CareVoiceDbContext dbContext, IPermissionService permissionService)
    {
        _dbContext = dbContext;
        _permissionService = permissionService;
    }

    private static string GenerateUniqueFamilyCode()
    {
        const string chars = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
        var bytes = new byte[5];
        using var rng = RandomNumberGenerator.Create();
        rng.GetBytes(bytes);
        var codeChars = new char[5];
        for (int i = 0; i < 5; i++)
        {
            codeChars[i] = chars[bytes[i] % chars.Length];
        }
        return $"CV-{new string(codeChars)}";
    }

    public async Task<FamilyGroupDto> CreateFamilyGroupAsync(Guid creatorUserId, CreateFamilyGroupDto dto)
    {
        var creator = await _dbContext.Users.FirstOrDefaultAsync(u => u.Id == creatorUserId);
        if (creator == null) throw new UnauthorizedAccessException("Creator user not found.");

        var groupName = string.IsNullOrWhiteSpace(dto.Name)
            ? $"{creator.FullName}'s Family"
            : dto.Name.Trim();

        var existing = await _dbContext.FamilyGroups
            .Include(fg => fg.Members)
            .ThenInclude(m => m.User)
            .FirstOrDefaultAsync(fg => fg.CreatorUserId == creatorUserId && fg.Name.ToLower() == groupName.ToLower());

        if (existing != null)
        {
            return MapToDto(existing, creatorUserId);
        }

        string code;
        do
        {
            code = GenerateUniqueFamilyCode();
        } while (await _dbContext.FamilyGroups.AnyAsync(fg => fg.FamilyCode == code));

        var familyGroup = new FamilyGroup
        {
            Id = Guid.NewGuid(),
            FamilyCode = code,
            Name = groupName,
            CreatorUserId = creatorUserId,
            CreatedAt = DateTime.UtcNow,
            UpdatedAt = DateTime.UtcNow,
            CreatorUser = creator
        };

        var memberRecord = new FamilyGroupMember
        {
            Id = Guid.NewGuid(),
            FamilyGroupId = familyGroup.Id,
            UserId = creatorUserId,
            Role = "Creator",
            Status = "Approved",
            JoinedAt = DateTime.UtcNow,
            User = creator
        };

        familyGroup.Members.Add(memberRecord);

        _dbContext.FamilyGroups.Add(familyGroup);
        await _dbContext.SaveChangesAsync();

        return MapToDto(familyGroup, creatorUserId);
    }

    public async Task<List<FamilyGroupDto>> GetAllMyFamilyGroupsAsync(Guid userId)
    {
        var groupIds = await _dbContext.FamilyGroupMembers
            .AsNoTracking()
            .Where(m => m.UserId == userId && m.Status == "Approved")
            .Select(m => m.FamilyGroupId)
            .ToListAsync();

        var createdGroupIds = await _dbContext.FamilyGroups
            .AsNoTracking()
            .Where(fg => fg.CreatorUserId == userId)
            .Select(fg => fg.Id)
            .ToListAsync();

        var allIds = groupIds.Union(createdGroupIds).Distinct().ToList();

        if (allIds.Count == 0)
        {
            var defaultGroup = await GetMyFamilyGroupAsync(userId);
            return defaultGroup != null ? new List<FamilyGroupDto> { defaultGroup } : new List<FamilyGroupDto>();
        }

        var groups = await _dbContext.FamilyGroups
            .AsNoTracking()
            .Include(fg => fg.CreatorUser)
            .Include(fg => fg.Members)
                .ThenInclude(m => m.User)
            .Where(fg => allIds.Contains(fg.Id))
            .OrderByDescending(fg => fg.CreatorUserId == userId)
            .ThenBy(fg => fg.CreatedAt)
            .ToListAsync();

        return groups.Select(g => MapToDto(g, userId)).ToList();
    }

    public async Task<FamilyGroupDto?> GetFamilyGroupByIdAsync(Guid userId, Guid familyGroupId)
    {
        var group = await _dbContext.FamilyGroups
            .AsNoTracking()
            .Include(fg => fg.CreatorUser)
            .Include(fg => fg.Members)
                .ThenInclude(m => m.User)
            .FirstOrDefaultAsync(fg => fg.Id == familyGroupId);

        if (group == null) return null;

        var isMemberOrCreator = group.CreatorUserId == userId || group.Members.Any(m => m.UserId == userId);
        if (!isMemberOrCreator)
        {
            throw new UnauthorizedAccessException("You are not an authorized member of this family group.");
        }

        return MapToDto(group, userId);
    }

    public async Task<FamilyGroupDto?> GetMyFamilyGroupAsync(Guid userId)
    {
        var membership = await _dbContext.FamilyGroupMembers
            .AsNoTracking()
            .FirstOrDefaultAsync(m => m.UserId == userId && m.Status != "Rejected");

        Guid? targetGroupId = membership?.FamilyGroupId;

        if (!targetGroupId.HasValue)
        {
            var created = await _dbContext.FamilyGroups
                .AsNoTracking()
                .FirstOrDefaultAsync(fg => fg.CreatorUserId == userId);
            targetGroupId = created?.Id;
        }

        if (!targetGroupId.HasValue)
        {
            var user = await _dbContext.Users.FirstOrDefaultAsync(u => u.Id == userId);
            if (user != null)
            {
                return await CreateFamilyGroupAsync(userId, new CreateFamilyGroupDto { Name = $"{user.FullName}'s Family" });
            }
            return null;
        }

        var group = await _dbContext.FamilyGroups
            .AsNoTracking()
            .Include(fg => fg.CreatorUser)
            .Include(fg => fg.Members)
                .ThenInclude(m => m.User)
            .FirstOrDefaultAsync(fg => fg.Id == targetGroupId.Value);

        return group != null ? MapToDto(group, userId) : null;
    }

    public async Task<FamilyGroupDto> JoinFamilyGroupByCodeAsync(Guid userId, string familyCode)
    {
        if (string.IsNullOrWhiteSpace(familyCode))
            throw new ArgumentException("Family code cannot be empty.", nameof(familyCode));

        var cleanCode = familyCode.Trim().ToUpperInvariant();
        var familyGroup = await _dbContext.FamilyGroups
            .Include(fg => fg.CreatorUser)
            .Include(fg => fg.Members)
                .ThenInclude(m => m.User)
            .FirstOrDefaultAsync(fg => fg.FamilyCode == cleanCode);

        if (familyGroup == null)
            throw new ArgumentException($"No family found with unique ID '{cleanCode}'. Please verify and try again.");

        var existingMember = familyGroup.Members.FirstOrDefault(m => m.UserId == userId);
        if (existingMember != null)
        {
            if (existingMember.Status == "Approved")
                throw new InvalidOperationException("You are already an approved member of this family.");
            if (existingMember.Status == "Pending")
                throw new InvalidOperationException("Your join request is currently pending approval by the family creator.");
            
            existingMember.Status = "Pending";
            existingMember.JoinedAt = DateTime.UtcNow;
            await _dbContext.SaveChangesAsync();
            return MapToDto(familyGroup, userId);
        }

        var user = await _dbContext.Users.FirstOrDefaultAsync(u => u.Id == userId);
        if (user == null) throw new UnauthorizedAccessException("User not found.");

        var newMembership = new FamilyGroupMember
        {
            Id = Guid.NewGuid(),
            FamilyGroupId = familyGroup.Id,
            UserId = userId,
            Role = "Member",
            Status = "Pending",
            JoinedAt = DateTime.UtcNow
        };

        _dbContext.FamilyGroupMembers.Add(newMembership);
        await _dbContext.SaveChangesAsync();

        return (await GetMyFamilyGroupAsync(userId))!;
    }

    public async Task<bool> ApproveMemberAsync(Guid adminUserId, Guid familyGroupId, Guid targetUserId)
    {
        var group = await _dbContext.FamilyGroups
            .Include(fg => fg.Members)
            .FirstOrDefaultAsync(fg => fg.Id == familyGroupId);

        if (group == null) throw new ArgumentException("Family group not found.");
        if (group.CreatorUserId != adminUserId)
            throw new UnauthorizedAccessException("Only the family creator can approve member requests.");

        var member = group.Members.FirstOrDefault(m => m.UserId == targetUserId);
        if (member == null) throw new ArgumentException("Member request not found.");

        member.Status = "Approved";

        var adminPrimaryId = await _permissionService.GetPrimaryMemberIdAsync(adminUserId);
        var targetPrimaryId = await _permissionService.GetPrimaryMemberIdAsync(targetUserId);

        if (adminPrimaryId != Guid.Empty && targetPrimaryId != Guid.Empty)
        {
            if (!await _dbContext.FamilyPermissions.AnyAsync(fp => fp.GranterMemberId == targetPrimaryId && fp.GranteeMemberId == adminPrimaryId))
            {
                _dbContext.FamilyPermissions.Add(new FamilyPermission
                {
                    Id = Guid.NewGuid(),
                    GranterMemberId = targetPrimaryId,
                    GranteeMemberId = adminPrimaryId,
                    CanSetReminders = true,
                    CanViewLogs = true
                });
            }

            if (!await _dbContext.FamilyPermissions.AnyAsync(fp => fp.GranterMemberId == adminPrimaryId && fp.GranteeMemberId == targetPrimaryId))
            {
                _dbContext.FamilyPermissions.Add(new FamilyPermission
                {
                    Id = Guid.NewGuid(),
                    GranterMemberId = adminPrimaryId,
                    GranteeMemberId = targetPrimaryId,
                    CanSetReminders = true,
                    CanViewLogs = true
                });
            }
        }

        await _dbContext.SaveChangesAsync();
        return true;
    }

    public async Task<bool> RejectMemberAsync(Guid adminUserId, Guid familyGroupId, Guid targetUserId)
    {
        var group = await _dbContext.FamilyGroups
            .Include(fg => fg.Members)
            .FirstOrDefaultAsync(fg => fg.Id == familyGroupId);

        if (group == null) throw new ArgumentException("Family group not found.");
        if (group.CreatorUserId != adminUserId)
            throw new UnauthorizedAccessException("Only the family creator can reject member requests.");

        var member = group.Members.FirstOrDefault(m => m.UserId == targetUserId);
        if (member == null) return false;

        member.Status = "Rejected";
        await _dbContext.SaveChangesAsync();
        return true;
    }

    public async Task<bool> RemoveMemberAsync(Guid adminUserId, Guid familyGroupId, Guid targetUserId)
    {
        var group = await _dbContext.FamilyGroups
            .Include(fg => fg.Members)
            .FirstOrDefaultAsync(fg => fg.Id == familyGroupId);

        if (group == null) throw new ArgumentException("Family group not found.");
        if (group.CreatorUserId != adminUserId)
            throw new UnauthorizedAccessException("Only the family creator can remove family members.");

        if (group.CreatorUserId == targetUserId)
            throw new InvalidOperationException("The family creator cannot be removed from their own family.");

        var member = group.Members.FirstOrDefault(m => m.UserId == targetUserId);
        if (member == null) return false;

        _dbContext.FamilyGroupMembers.Remove(member);
        await _dbContext.SaveChangesAsync();
        return true;
    }

    public async Task<List<SharedFamilyUpdateDto>> GetSharedUpdatesAsync(Guid userId, Guid familyGroupId)
    {
        var group = await _dbContext.FamilyGroups
            .AsNoTracking()
            .Include(fg => fg.Members)
            .FirstOrDefaultAsync(fg => fg.Id == familyGroupId);

        if (group == null) return new List<SharedFamilyUpdateDto>();

        var isMember = group.Members.Any(m => m.UserId == userId && m.Status == "Approved");
        if (!isMember) return new List<SharedFamilyUpdateDto>();

        var approvedUserIds = group.Members
            .Where(m => m.Status == "Approved")
            .Select(m => m.UserId)
            .ToList();

        var updates = new List<SharedFamilyUpdateDto>();

        var recentLogs = await _dbContext.MedicineLogs
            .AsNoTracking()
            .Include(ml => ml.Schedule)
                .ThenInclude(ms => ms.Medicine)
            .Include(ml => ml.TargetMember)
            .Where(ml => approvedUserIds.Contains(ml.TargetMember.UserId))
            .OrderByDescending(ml => ml.CreatedAt)
            .Take(20)
            .ToListAsync();

        foreach (var log in recentLogs)
        {
            var medName = log.Schedule?.Medicine?.Name ?? "Medicine";
            var targetName = log.TargetMember?.FullName ?? "Family Member";
            var statusStr = log.Status.ToString();

            updates.Add(new SharedFamilyUpdateDto
            {
                Id = log.Id,
                FamilyGroupId = familyGroupId,
                Type = statusStr == "Taken" ? "DoseTaken" : statusStr == "Missed" ? "DoseMissed" : "DoseLogged",
                Title = $"{medName} • {statusStr}",
                TitleBn = $"{medName} • {(statusStr == "Taken" ? "খেয়েছে" : statusStr == "Missed" ? "মিস হয়েছে" : "বাদ দিয়েছে")}",
                Description = $"{targetName} {statusStr.ToLower()} {medName} at {log.ScheduledTime:HH:mm}.",
                DescriptionBn = $"{targetName} {log.ScheduledTime:HH:mm} সময়ে {medName} {(statusStr == "Taken" ? "খেয়েছেন" : "মিস করেছেন")}।",
                ActorName = targetName,
                Timestamp = log.ActionTime ?? log.CreatedAt
            });
        }

        foreach (var m in group.Members.Where(m => m.Status == "Approved"))
        {
            updates.Add(new SharedFamilyUpdateDto
            {
                Id = m.Id,
                FamilyGroupId = familyGroupId,
                Type = "MemberJoined",
                Title = $"{m.User?.FullName ?? "Member"} joined the family",
                TitleBn = $"{m.User?.FullName ?? "সদস্য"} পরিবারে যোগ দিয়েছেন",
                Description = $"{m.User?.FullName ?? "Member"} is now an active member of this family.",
                DescriptionBn = $"{m.User?.FullName ?? "সদস্য"} এখন পরিবারের একজন সক্রিয় সদস্য।",
                ActorName = m.User?.FullName ?? "Member",
                Timestamp = m.JoinedAt
            });
        }

        return updates.OrderByDescending(u => u.Timestamp).Take(30).ToList();
    }

    public Task AddSharedUpdateAsync(Guid familyGroupId, string type, string title, string titleBn, string desc, string descBn, string actorName)
    {
        _dbContext.AuditLogs.Add(new AuditLog
        {
            Id = Guid.NewGuid(),
            Action = type,
            EntityName = "FamilyGroup",
            EntityId = familyGroupId.ToString(),
            ChangesJson = $"{actorName}: {title}",
            Timestamp = DateTime.UtcNow
        });
        return _dbContext.SaveChangesAsync();
    }

    private static FamilyGroupDto MapToDto(FamilyGroup fg, Guid callerUserId)
    {
        var myMembership = fg.Members.FirstOrDefault(m => m.UserId == callerUserId);
        var isCreator = fg.CreatorUserId == callerUserId;

        var approvedMembers = fg.Members
            .Where(m => m.Status == "Approved")
            .Select(m => new FamilyGroupMemberDto
            {
                Id = m.Id,
                UserId = m.UserId,
                FullName = m.User?.FullName ?? "Member",
                Email = m.User?.Email ?? string.Empty,
                Role = m.Role,
                Status = m.Status,
                JoinedAt = m.JoinedAt
            })
            .ToList();

        var pendingRequests = isCreator
            ? fg.Members
                .Where(m => m.Status == "Pending")
                .Select(m => new FamilyGroupMemberDto
                {
                    Id = m.Id,
                    UserId = m.UserId,
                    FullName = m.User?.FullName ?? "Member",
                    Email = m.User?.Email ?? string.Empty,
                    Role = m.Role,
                    Status = m.Status,
                    JoinedAt = m.JoinedAt
                })
                .ToList()
            : new List<FamilyGroupMemberDto>();

        return new FamilyGroupDto
        {
            Id = fg.Id,
            FamilyCode = fg.FamilyCode,
            Name = fg.Name,
            CreatorUserId = fg.CreatorUserId,
            CreatorName = fg.CreatorUser?.FullName ?? "Family Creator",
            IsCreator = isCreator,
            MembersCount = approvedMembers.Count,
            UserMembershipStatus = myMembership?.Status ?? (isCreator ? "Approved" : "None"),
            CreatedAt = fg.CreatedAt,
            Members = approvedMembers,
            PendingRequests = pendingRequests
        };
    }
}
