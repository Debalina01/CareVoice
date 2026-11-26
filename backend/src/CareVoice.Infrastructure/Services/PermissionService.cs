using System;
using System.Threading.Tasks;
using Microsoft.EntityFrameworkCore;
using CareVoice.Application.Interfaces;
using CareVoice.Domain.Entities;
using CareVoice.Infrastructure.Persistence;

namespace CareVoice.Infrastructure.Services;

public class PermissionService : IPermissionService
{
    private readonly CareVoiceDbContext _dbContext;

    public PermissionService(CareVoiceDbContext dbContext)
    {
        _dbContext = dbContext;
    }

    public async Task<Guid> GetPrimaryMemberIdAsync(Guid userId)
    {
        var primaryMember = await _dbContext.FamilyMembers
            .AsNoTracking()
            .Where(fm => fm.UserId == userId && !fm.IsDeleted)
            .OrderBy(fm => fm.Relation == "Self" ? 0 : 1)
            .ThenBy(fm => fm.CreatedAt)
            .FirstOrDefaultAsync();

        if (primaryMember != null)
        {
            return primaryMember.Id;
        }

        var user = await _dbContext.Users.FindAsync(userId);
        if (user == null)
        {
            var uniqueSuffix = userId.ToString("N")[..8];
            user = new User
            {
                Id = userId,
                Email = $"caregiver_{uniqueSuffix}@carevoice.app",
                Username = $"caregiver_{uniqueSuffix}",
                FullName = "Primary Caregiver",
                Role = "Caregiver",
                PasswordHash = BCrypt.Net.BCrypt.HashPassword("Password123!"),
                CreatedAt = DateTime.UtcNow,
                UpdatedAt = DateTime.UtcNow
            };
            _dbContext.Users.Add(user);
        }

        var newSelf = new FamilyMember
        {
            Id = Guid.NewGuid(),
            UserId = user.Id,
            FullName = user.FullName,
            Relation = "Self",
            PreferredLanguage = "en",
            VoicePreference = "en-US-Standard-A",
            IsDeleted = false,
            CreatedAt = DateTime.UtcNow
        };
        _dbContext.FamilyMembers.Add(newSelf);
        await _dbContext.SaveChangesAsync();

        return newSelf.Id;
    }

    public async Task<bool> CanSetRemindersAsync(Guid callerUserId, Guid targetMemberId)
    {
        var targetMember = await _dbContext.FamilyMembers
            .AsNoTracking()
            .FirstOrDefaultAsync(fm => fm.Id == targetMemberId && !fm.IsDeleted);

        if (targetMember == null) return false;

        if (targetMember.UserId == callerUserId) return true;

        var sharesGroup = await _dbContext.FamilyGroupMembers
            .AsNoTracking()
            .AnyAsync(m1 => m1.UserId == callerUserId && m1.Status == "Approved" &&
                            _dbContext.FamilyGroupMembers.Any(m2 => m2.UserId == targetMember.UserId && m2.FamilyGroupId == m1.FamilyGroupId && m2.Status == "Approved"));
        if (sharesGroup) return true;

        var callerPrimaryMemberId = await GetPrimaryMemberIdAsync(callerUserId);
        return await _dbContext.FamilyPermissions
            .AsNoTracking()
            .AnyAsync(fp => fp.GranterMemberId == targetMemberId &&
                            fp.GranteeMemberId == callerPrimaryMemberId &&
                            fp.CanSetReminders);
    }

    public async Task<bool> CanViewLogsAsync(Guid callerUserId, Guid targetMemberId)
    {
        var targetMember = await _dbContext.FamilyMembers
            .AsNoTracking()
            .FirstOrDefaultAsync(fm => fm.Id == targetMemberId && !fm.IsDeleted);

        if (targetMember == null) return false;

        if (targetMember.UserId == callerUserId) return true;

        var sharesGroup = await _dbContext.FamilyGroupMembers
            .AsNoTracking()
            .AnyAsync(m1 => m1.UserId == callerUserId && m1.Status == "Approved" &&
                            _dbContext.FamilyGroupMembers.Any(m2 => m2.UserId == targetMember.UserId && m2.FamilyGroupId == m1.FamilyGroupId && m2.Status == "Approved"));
        if (sharesGroup) return true;

        var callerPrimaryMemberId = await GetPrimaryMemberIdAsync(callerUserId);
        return await _dbContext.FamilyPermissions
            .AsNoTracking()
            .AnyAsync(fp => fp.GranterMemberId == targetMemberId &&
                            fp.GranteeMemberId == callerPrimaryMemberId &&
                            fp.CanViewLogs);
    }

    public async Task<bool> IsAuthorizedForMemberAsync(Guid callerUserId, Guid targetMemberId)
    {
        var targetMember = await _dbContext.FamilyMembers
            .AsNoTracking()
            .FirstOrDefaultAsync(fm => fm.Id == targetMemberId && !fm.IsDeleted);

        if (targetMember == null) return false;
        if (targetMember.UserId == callerUserId) return true;

        var sharesGroup = await _dbContext.FamilyGroupMembers
            .AsNoTracking()
            .AnyAsync(m1 => m1.UserId == callerUserId && m1.Status == "Approved" &&
                            _dbContext.FamilyGroupMembers.Any(m2 => m2.UserId == targetMember.UserId && m2.FamilyGroupId == m1.FamilyGroupId && m2.Status == "Approved"));
        if (sharesGroup) return true;

        var callerPrimaryMemberId = await GetPrimaryMemberIdAsync(callerUserId);
        return await _dbContext.FamilyPermissions
            .AsNoTracking()
            .AnyAsync(fp => (fp.GranterMemberId == targetMemberId && fp.GranteeMemberId == callerPrimaryMemberId) ||
                            (fp.GranterMemberId == callerPrimaryMemberId && fp.GranteeMemberId == targetMemberId));
    }
}
