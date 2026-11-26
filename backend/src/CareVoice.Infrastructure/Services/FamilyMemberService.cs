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

public class FamilyMemberService : IFamilyMemberService
{
    private readonly CareVoiceDbContext _dbContext;
    private readonly IPermissionService _permissionService;

    public FamilyMemberService(CareVoiceDbContext dbContext, IPermissionService permissionService)
    {
        _dbContext = dbContext;
        _permissionService = permissionService;
    }

    public async Task<IEnumerable<FamilyMemberDto>> GetFamilyMembersAsync(Guid callerUserId)
    {
        var hasAnyMembers = await _dbContext.FamilyMembers.AnyAsync(fm => fm.UserId == callerUserId && !fm.IsDeleted);
        if (!hasAnyMembers)
        {
            var callerUser = await _dbContext.Users.FirstOrDefaultAsync(u => u.Id == callerUserId);
            if (callerUser == null)
            {
                var uniqueSuffix = callerUserId.ToString("N")[..8];
                callerUser = new User
                {
                    Id = callerUserId,
                    Email = $"caregiver_{uniqueSuffix}@carevoice.app",
                    Username = $"caregiver_{uniqueSuffix}",
                    FullName = "Primary Caregiver",
                    Role = "Caregiver",
                    PasswordHash = BCrypt.Net.BCrypt.HashPassword("Password123!"),
                    CreatedAt = DateTime.UtcNow,
                    UpdatedAt = DateTime.UtcNow
                };
                _dbContext.Users.Add(callerUser);
            }

            _dbContext.FamilyMembers.Add(new FamilyMember
            {
                Id = Guid.NewGuid(),
                UserId = callerUserId,
                FullName = callerUser.FullName,
                Relation = "Self",
                PreferredLanguage = "en",
                VoicePreference = "en-US-Standard-A",
                IsDeleted = false,
                CreatedAt = DateTime.UtcNow
            });

            _dbContext.FamilyMembers.Add(new FamilyMember
            {
                Id = Guid.NewGuid(),
                UserId = callerUserId,
                FullName = "Papa",
                Relation = "Parent",
                PreferredLanguage = "en",
                VoicePreference = "en-US-Standard-A",
                IsDeleted = false,
                CreatedAt = DateTime.UtcNow
            });

            await _dbContext.SaveChangesAsync();
        }

        var callerPrimaryMemberId = await _permissionService.GetPrimaryMemberIdAsync(callerUserId);
        var caller = await _dbContext.Users.AsNoTracking().FirstOrDefaultAsync(u => u.Id == callerUserId);
        var callerUsername = caller?.Username ?? caller?.Email;

        var directMembers = await _dbContext.FamilyMembers
            .AsNoTracking()
            .Include(fm => fm.LinkedUser)
            .Where(fm => fm.UserId == callerUserId && !fm.IsDeleted)
            .OrderBy(fm => fm.Relation == "Self" ? 0 : 1)
            .ThenBy(fm => fm.CreatedAt)
            .ToListAsync();

        var result = directMembers.Select(fm => new FamilyMemberDto
        {
            Id = fm.Id,
            UserId = fm.UserId,
            LinkedUserId = fm.LinkedUserId,
            FullName = fm.FullName,
            Relation = fm.Relation,
            PreferredLanguage = fm.PreferredLanguage,
            VoicePreference = fm.VoicePreference,
            IsSelf = fm.Relation == "Self",
            CanSetReminders = true,
            CanViewLogs = true,
            CreatedAt = fm.CreatedAt,
            Username = fm.LinkedUser != null ? (fm.LinkedUser.Username ?? fm.LinkedUser.Email) : (fm.Relation == "Self" ? callerUsername : null),
            HasLoginCredentials = fm.LinkedUserId != null || (fm.Relation == "Self" && callerUsername != null)
        }).ToList();

        var grantedPermissions = await _dbContext.FamilyPermissions
            .AsNoTracking()
            .Include(fp => fp.GranterMember)
                .ThenInclude(gm => gm.LinkedUser)
            .Where(fp => fp.GranteeMemberId == callerPrimaryMemberId && fp.GranterMember != null && !fp.GranterMember.IsDeleted)
            .ToListAsync();

        foreach (var perm in grantedPermissions)
        {
            var gm = perm.GranterMember;
            if (gm == null || gm.IsDeleted) continue;

            if (result.Any(r => r.Id == gm.Id || 
                               (r.LinkedUserId.HasValue && r.LinkedUserId == gm.UserId) ||
                               (gm.LinkedUserId.HasValue && gm.LinkedUserId == r.UserId)))
            {
                continue;
            }

            result.Add(new FamilyMemberDto
            {
                Id = gm.Id,
                UserId = gm.UserId,
                LinkedUserId = gm.LinkedUserId,
                FullName = gm.FullName,
                Relation = gm.Relation == "Self" ? "Family Member" : gm.Relation,
                PreferredLanguage = gm.PreferredLanguage,
                VoicePreference = gm.VoicePreference,
                IsSelf = false,
                CanSetReminders = perm.CanSetReminders,
                CanViewLogs = perm.CanViewLogs,
                CreatedAt = gm.CreatedAt,
                Username = gm.LinkedUser != null ? (gm.LinkedUser.Username ?? gm.LinkedUser.Email) : null,
                HasLoginCredentials = gm.LinkedUserId != null
            });
        }

        return result;
    }

    public async Task<FamilyMemberDto?> GetFamilyMemberByIdAsync(Guid callerUserId, Guid id)
    {
        var isAuthorized = await _permissionService.IsAuthorizedForMemberAsync(callerUserId, id);
        if (!isAuthorized) return null;

        var member = await _dbContext.FamilyMembers
            .AsNoTracking()
            .Include(fm => fm.LinkedUser)
            .FirstOrDefaultAsync(fm => fm.Id == id && !fm.IsDeleted);

        if (member == null) return null;

        var callerUser = await _dbContext.Users.AsNoTracking().FirstOrDefaultAsync(u => u.Id == callerUserId);
        var callerUsername = callerUser?.Username ?? callerUser?.Email;

        var canSet = await _permissionService.CanSetRemindersAsync(callerUserId, id);
        var canView = await _permissionService.CanViewLogsAsync(callerUserId, id);

        return new FamilyMemberDto
        {
            Id = member.Id,
            UserId = member.UserId,
            LinkedUserId = member.LinkedUserId,
            FullName = member.FullName,
            Relation = member.Relation,
            PreferredLanguage = member.PreferredLanguage,
            VoicePreference = member.VoicePreference,
            IsSelf = member.Relation == "Self" && member.UserId == callerUserId,
            CanSetReminders = canSet,
            CanViewLogs = canView,
            CreatedAt = member.CreatedAt,
            Username = member.LinkedUser != null ? (member.LinkedUser.Username ?? member.LinkedUser.Email) : (member.Relation == "Self" ? callerUsername : null),
            HasLoginCredentials = member.LinkedUserId != null || (member.Relation == "Self" && callerUsername != null)
        };
    }

    public async Task<FamilyMemberDto> CreateFamilyMemberAsync(Guid callerUserId, CreateFamilyMemberDto dto)
    {
        if (string.IsNullOrWhiteSpace(dto.FullName))
        {
            throw new ArgumentException("Full name is required.", nameof(dto.FullName));
        }

        Guid? createdMemberUserId = null;
        string? assignedUsername = null;
        FamilyMember? newMemberSelfRecord = null;

        if (!string.IsNullOrWhiteSpace(dto.Username) || !string.IsNullOrWhiteSpace(dto.Password))
        {
            if (string.IsNullOrWhiteSpace(dto.Username))
            {
                throw new ArgumentException("Username is required when creating login credentials for a member.", nameof(dto.Username));
            }

            if (string.IsNullOrWhiteSpace(dto.Password) || dto.Password.Length < 6)
            {
                throw new ArgumentException("Password must be at least 6 characters long.", nameof(dto.Password));
            }

            var cleanUsername = dto.Username.Trim().ToLower();

            var isTaken = await _dbContext.Users.AnyAsync(u => 
                u.Email.ToLower() == cleanUsername || 
                (u.Username != null && u.Username.ToLower() == cleanUsername));

            if (isTaken)
            {
                throw new InvalidOperationException($"The username or email '{dto.Username.Trim()}' is already taken. Please choose another username.");
            }

            var emailIdentifier = cleanUsername.Contains('@') ? cleanUsername : $"{cleanUsername}@carevoice.local";

            var newMemberUser = new User
            {
                Id = Guid.NewGuid(),
                Email = emailIdentifier,
                Username = cleanUsername,
                PasswordHash = BCrypt.Net.BCrypt.HashPassword(dto.Password),
                FullName = dto.FullName.Trim(),
                Role = "Patient",
                CreatedAt = DateTime.UtcNow,
                UpdatedAt = DateTime.UtcNow
            };

            newMemberSelfRecord = new FamilyMember
            {
                Id = Guid.NewGuid(),
                UserId = newMemberUser.Id,
                FullName = dto.FullName.Trim(),
                Relation = "Self",
                PreferredLanguage = string.IsNullOrWhiteSpace(dto.PreferredLanguage) ? "en" : dto.PreferredLanguage.Trim(),
                VoicePreference = string.IsNullOrWhiteSpace(dto.VoicePreference) ? "en-US-Standard-A" : dto.VoicePreference.Trim(),
                IsDeleted = false,
                CreatedAt = DateTime.UtcNow
            };
            newMemberUser.FamilyMembers.Add(newMemberSelfRecord);

            var familyGroup = await _dbContext.FamilyGroups
                .FirstOrDefaultAsync(fg => fg.CreatorUserId == callerUserId);

            if (familyGroup == null)
            {
                var callerMembership = await _dbContext.FamilyGroupMembers
                    .FirstOrDefaultAsync(m => m.UserId == callerUserId && m.Status == "Approved");
                if (callerMembership != null)
                {
                    familyGroup = await _dbContext.FamilyGroups
                        .FirstOrDefaultAsync(fg => fg.Id == callerMembership.FamilyGroupId);
                }
            }

            if (familyGroup != null)
            {
                _dbContext.FamilyGroupMembers.Add(new FamilyGroupMember
                {
                    Id = Guid.NewGuid(),
                    FamilyGroupId = familyGroup.Id,
                    UserId = newMemberUser.Id,
                    Role = "Member",
                    Status = "Approved",
                    JoinedAt = DateTime.UtcNow
                });
            }

            _dbContext.Users.Add(newMemberUser);
            createdMemberUserId = newMemberUser.Id;
            assignedUsername = cleanUsername;
        }

        var member = new FamilyMember
        {
            Id = Guid.NewGuid(),
            UserId = callerUserId,
            LinkedUserId = createdMemberUserId,
            FullName = dto.FullName.Trim(),
            Relation = string.IsNullOrWhiteSpace(dto.Relation) ? "Family Member" : dto.Relation.Trim(),
            PreferredLanguage = string.IsNullOrWhiteSpace(dto.PreferredLanguage) ? "en" : dto.PreferredLanguage.Trim(),
            VoicePreference = string.IsNullOrWhiteSpace(dto.VoicePreference) ? "en-US-Standard-A" : dto.VoicePreference.Trim(),
            IsDeleted = false,
            CreatedAt = DateTime.UtcNow
        };

        _dbContext.FamilyMembers.Add(member);
        await _dbContext.SaveChangesAsync();

        if (createdMemberUserId.HasValue && newMemberSelfRecord != null)
        {
            var callerPrimaryId = await _permissionService.GetPrimaryMemberIdAsync(callerUserId);
            if (callerPrimaryId != Guid.Empty)
            {
                _dbContext.FamilyPermissions.Add(new FamilyPermission
                {
                    Id = Guid.NewGuid(),
                    GranterMemberId = newMemberSelfRecord.Id,
                    GranteeMemberId = callerPrimaryId,
                    CanSetReminders = true,
                    CanViewLogs = true
                });

                _dbContext.FamilyPermissions.Add(new FamilyPermission
                {
                    Id = Guid.NewGuid(),
                    GranterMemberId = callerPrimaryId,
                    GranteeMemberId = newMemberSelfRecord.Id,
                    CanSetReminders = true,
                    CanViewLogs = true
                });

                _dbContext.FamilyPermissions.Add(new FamilyPermission
                {
                    Id = Guid.NewGuid(),
                    GranterMemberId = member.Id,
                    GranteeMemberId = newMemberSelfRecord.Id,
                    CanSetReminders = true,
                    CanViewLogs = true
                });

                await _dbContext.SaveChangesAsync();
            }
        }

        return new FamilyMemberDto
        {
            Id = member.Id,
            UserId = member.UserId,
            LinkedUserId = member.LinkedUserId,
            FullName = member.FullName,
            Relation = member.Relation,
            PreferredLanguage = member.PreferredLanguage,
            VoicePreference = member.VoicePreference,
            IsSelf = false,
            CanSetReminders = true,
            CanViewLogs = true,
            CreatedAt = member.CreatedAt,
            Username = assignedUsername,
            HasLoginCredentials = !string.IsNullOrEmpty(assignedUsername)
        };
    }

    public async Task<FamilyMemberDto?> UpdateFamilyMemberAsync(Guid callerUserId, Guid id, UpdateFamilyMemberDto dto)
    {
        var member = await _dbContext.FamilyMembers
            .Include(fm => fm.LinkedUser)
            .FirstOrDefaultAsync(fm => fm.Id == id && fm.UserId == callerUserId && !fm.IsDeleted);

        if (member == null) return null;

        if (!string.IsNullOrWhiteSpace(dto.FullName))
        {
            member.FullName = dto.FullName.Trim();
        }

        if (member.Relation != "Self" && !string.IsNullOrWhiteSpace(dto.Relation))
        {
            member.Relation = dto.Relation.Trim();
        }

        if (!string.IsNullOrWhiteSpace(dto.PreferredLanguage))
        {
            member.PreferredLanguage = dto.PreferredLanguage.Trim();
        }

        if (!string.IsNullOrWhiteSpace(dto.VoicePreference))
        {
            member.VoicePreference = dto.VoicePreference.Trim();
        }

        if (member.LinkedUserId.HasValue)
        {
            var linkedUser = await _dbContext.Users
                .Include(u => u.FamilyMembers)
                .FirstOrDefaultAsync(u => u.Id == member.LinkedUserId.Value);

            if (linkedUser != null)
            {
                if (!string.IsNullOrWhiteSpace(dto.FullName))
                {
                    linkedUser.FullName = dto.FullName.Trim();
                }

                var linkedSelf = linkedUser.FamilyMembers.FirstOrDefault(fm => fm.Relation == "Self");
                if (linkedSelf != null)
                {
                    if (!string.IsNullOrWhiteSpace(dto.FullName)) linkedSelf.FullName = dto.FullName.Trim();
                    if (!string.IsNullOrWhiteSpace(dto.PreferredLanguage)) linkedSelf.PreferredLanguage = dto.PreferredLanguage.Trim();
                    if (!string.IsNullOrWhiteSpace(dto.VoicePreference)) linkedSelf.VoicePreference = dto.VoicePreference.Trim();
                }
            }
        }

        await _dbContext.SaveChangesAsync();

        return new FamilyMemberDto
        {
            Id = member.Id,
            UserId = member.UserId,
            LinkedUserId = member.LinkedUserId,
            FullName = member.FullName,
            Relation = member.Relation,
            PreferredLanguage = member.PreferredLanguage,
            VoicePreference = member.VoicePreference,
            IsSelf = member.Relation == "Self",
            CanSetReminders = true,
            CanViewLogs = true,
            CreatedAt = member.CreatedAt,
            Username = member.LinkedUser != null ? (member.LinkedUser.Username ?? member.LinkedUser.Email) : null,
            HasLoginCredentials = member.LinkedUserId != null || member.Relation == "Self"
        };
    }

    public async Task<bool> DeleteFamilyMemberAsync(Guid callerUserId, Guid id)
    {
        var directMember = await _dbContext.FamilyMembers
            .FirstOrDefaultAsync(fm => fm.Id == id && fm.UserId == callerUserId && !fm.IsDeleted);

        if (directMember != null)
        {
            if (directMember.Relation == "Self")
            {
                throw new InvalidOperationException("The default 'Self' family member cannot be deleted.");
            }

            directMember.IsDeleted = true;

            var directPerms = await _dbContext.FamilyPermissions
                .Where(fp => fp.GranterMemberId == directMember.Id || fp.GranteeMemberId == directMember.Id ||
                             (directMember.LinkedUserId.HasValue &&
                              _dbContext.FamilyMembers.Any(fm => fm.UserId == directMember.LinkedUserId.Value && (fp.GranterMemberId == fm.Id || fp.GranteeMemberId == fm.Id))))
                .ToListAsync();
            _dbContext.FamilyPermissions.RemoveRange(directPerms);

            if (directMember.LinkedUserId.HasValue)
            {
                var myGroupIds = await _dbContext.FamilyGroups
                    .Where(fg => fg.CreatorUserId == callerUserId)
                    .Select(fg => fg.Id)
                    .ToListAsync();

                var groupMemberships = await _dbContext.FamilyGroupMembers
                    .Where(fgm => myGroupIds.Contains(fgm.FamilyGroupId) && fgm.UserId == directMember.LinkedUserId.Value)
                    .ToListAsync();
                _dbContext.FamilyGroupMembers.RemoveRange(groupMemberships);

                var linkedMemberSelf = await _dbContext.FamilyMembers
                    .FirstOrDefaultAsync(fm => fm.UserId == directMember.LinkedUserId.Value && fm.Relation == "Self" && !fm.IsDeleted);
                if (linkedMemberSelf != null)
                {
                    linkedMemberSelf.IsDeleted = true;
                    var extraPerms = await _dbContext.FamilyPermissions
                        .Where(fp => fp.GranterMemberId == linkedMemberSelf.Id || fp.GranteeMemberId == linkedMemberSelf.Id)
                        .ToListAsync();
                    _dbContext.FamilyPermissions.RemoveRange(extraPerms);
                }
            }

            await _dbContext.SaveChangesAsync();
            return true;
        }

        var otherMember = await _dbContext.FamilyMembers
            .FirstOrDefaultAsync(fm => fm.Id == id && !fm.IsDeleted);

        if (otherMember != null)
        {
            if (otherMember.UserId == callerUserId && otherMember.Relation == "Self")
            {
                throw new InvalidOperationException("The default 'Self' family member cannot be deleted.");
            }

            var callerPrimaryId = await _permissionService.GetPrimaryMemberIdAsync(callerUserId);

            var linkedPerms = await _dbContext.FamilyPermissions
                .Where(fp => (fp.GranterMemberId == id && fp.GranteeMemberId == callerPrimaryId) ||
                             (fp.GranterMemberId == callerPrimaryId && fp.GranteeMemberId == id) ||
                             (fp.GranterMember.UserId == otherMember.UserId && fp.GranteeMember.UserId == callerUserId) ||
                             (fp.GranterMember.UserId == callerUserId && fp.GranteeMember.UserId == otherMember.UserId))
                .ToListAsync();
            _dbContext.FamilyPermissions.RemoveRange(linkedPerms);

            var callerGroupIds = await _dbContext.FamilyGroups
                .Where(fg => fg.CreatorUserId == callerUserId)
                .Select(fg => fg.Id)
                .ToListAsync();

            var memberships = await _dbContext.FamilyGroupMembers
                .Where(fgm => callerGroupIds.Contains(fgm.FamilyGroupId) && fgm.UserId == otherMember.UserId)
                .ToListAsync();
            _dbContext.FamilyGroupMembers.RemoveRange(memberships);

            var directMatch = await _dbContext.FamilyMembers
                .FirstOrDefaultAsync(fm => fm.UserId == callerUserId && fm.LinkedUserId == otherMember.UserId && !fm.IsDeleted);
            if (directMatch != null)
            {
                directMatch.IsDeleted = true;
            }

            var memberUser = await _dbContext.Users.FirstOrDefaultAsync(u => u.Id == otherMember.UserId);
            if (memberUser != null && memberUser.Role == "Patient")
            {
                otherMember.IsDeleted = true;
            }

            await _dbContext.SaveChangesAsync();
            return true;
        }

        return false;
    }
}
