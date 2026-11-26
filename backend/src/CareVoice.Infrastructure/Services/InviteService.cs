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

public class InviteService : IInviteService
{
    private readonly CareVoiceDbContext _dbContext;
    private readonly IPermissionService _permissionService;

    public InviteService(CareVoiceDbContext dbContext, IPermissionService permissionService)
    {
        _dbContext = dbContext;
        _permissionService = permissionService;
    }

    public async Task<InviteDto> CreateInviteAsync(Guid callerUserId, CreateInviteDto dto)
    {
        if (string.IsNullOrWhiteSpace(dto.InvitedEmail))
        {
            throw new ArgumentException("Invited email is required.", nameof(dto.InvitedEmail));
        }

        var inviterPrimaryMemberId = await _permissionService.GetPrimaryMemberIdAsync(callerUserId);
        var inviterMember = await _dbContext.FamilyMembers
            .AsNoTracking()
            .FirstOrDefaultAsync(fm => fm.Id == inviterPrimaryMemberId);

        var tokenBytes = new byte[32];
        using var rng = RandomNumberGenerator.Create();
        rng.GetBytes(tokenBytes);
        var inviteToken = Convert.ToHexString(tokenBytes).ToLowerInvariant();

        var invite = new Invite
        {
            Id = Guid.NewGuid(),
            InviterMemberId = inviterPrimaryMemberId,
            InvitedEmail = dto.InvitedEmail.Trim().ToLowerInvariant(),
            InviteToken = inviteToken,
            Status = InviteStatus.Pending,
            ExpiresAt = DateTime.UtcNow.AddDays(7),
            CreatedAt = DateTime.UtcNow
        };

        _dbContext.Invites.Add(invite);
        await _dbContext.SaveChangesAsync();

        return new InviteDto
        {
            Id = invite.Id,
            InviterMemberId = invite.InviterMemberId,
            InviterName = inviterMember?.FullName ?? "Caregiver",
            InvitedEmail = invite.InvitedEmail,
            InviteToken = invite.InviteToken,
            Status = invite.Status,
            ExpiresAt = invite.ExpiresAt,
            CreatedAt = invite.CreatedAt
        };
    }

    public async Task<IEnumerable<InviteDto>> GetInvitesAsync(Guid callerUserId)
    {
        var callerPrimaryMemberId = await _permissionService.GetPrimaryMemberIdAsync(callerUserId);

        var invites = await _dbContext.Invites
            .AsNoTracking()
            .Include(i => i.InviterMember)
            .Where(i => i.InviterMemberId == callerPrimaryMemberId)
            .OrderByDescending(i => i.CreatedAt)
            .ToListAsync();

        return invites.Select(i => new InviteDto
        {
            Id = i.Id,
            InviterMemberId = i.InviterMemberId,
            InviterName = i.InviterMember.FullName,
            InvitedEmail = i.InvitedEmail,
            InviteToken = i.InviteToken,
            Status = i.Status,
            ExpiresAt = i.ExpiresAt,
            CreatedAt = i.CreatedAt
        }).ToList();
    }

    public async Task<bool> AcceptInviteAsync(Guid callerUserId, AcceptInviteDto dto)
    {
        if (string.IsNullOrWhiteSpace(dto.InviteToken))
        {
            throw new ArgumentException("Invite token is required.", nameof(dto.InviteToken));
        }

        var invite = await _dbContext.Invites
            .Include(i => i.InviterMember)
            .FirstOrDefaultAsync(i => i.InviteToken == dto.InviteToken.Trim().ToLowerInvariant());

        if (invite == null)
        {
            throw new InvalidOperationException("Invalid invitation token.");
        }

        if (invite.Status != InviteStatus.Pending)
        {
            throw new InvalidOperationException($"Invitation is no longer active (Status: {invite.Status}).");
        }

        if (invite.ExpiresAt <= DateTime.UtcNow)
        {
            invite.Status = InviteStatus.Expired;
            await _dbContext.SaveChangesAsync();
            throw new InvalidOperationException("Invitation has expired.");
        }

        var callerUser = await _dbContext.Users
            .AsNoTracking()
            .FirstOrDefaultAsync(u => u.Id == callerUserId);

        if (callerUser == null)
        {
            throw new UnauthorizedAccessException("Authenticated user not found.");
        }

        if (!string.Equals(callerUser.Email, invite.InvitedEmail, StringComparison.OrdinalIgnoreCase))
        {
            throw new InvalidOperationException("This invitation was sent to a different email address.");
        }

        var acceptorPrimaryMemberId = await _permissionService.GetPrimaryMemberIdAsync(callerUserId);

        if (invite.InviterMemberId == acceptorPrimaryMemberId)
        {
            throw new InvalidOperationException("You cannot accept an invitation you created.");
        }

        var existingPermission = await _dbContext.FamilyPermissions
            .FirstOrDefaultAsync(fp => fp.GranterMemberId == acceptorPrimaryMemberId && 
                                       fp.GranteeMemberId == invite.InviterMemberId);

        if (existingPermission != null)
        {
            existingPermission.CanSetReminders = true;
            existingPermission.CanViewLogs = true;
        }
        else
        {
            _dbContext.FamilyPermissions.Add(new FamilyPermission
            {
                Id = Guid.NewGuid(),
                GranterMemberId = acceptorPrimaryMemberId,
                GranteeMemberId = invite.InviterMemberId,
                CanSetReminders = true,
                CanViewLogs = true,
                CreatedAt = DateTime.UtcNow
            });
        }

        invite.Status = InviteStatus.Accepted;
        await _dbContext.SaveChangesAsync();

        return true;
    }

    public async Task<bool> CancelInviteAsync(Guid callerUserId, Guid inviteId)
    {
        var callerPrimaryMemberId = await _permissionService.GetPrimaryMemberIdAsync(callerUserId);

        var invite = await _dbContext.Invites
            .FirstOrDefaultAsync(i => i.Id == inviteId && i.InviterMemberId == callerPrimaryMemberId);

        if (invite == null || invite.Status != InviteStatus.Pending)
        {
            return false;
        }

        invite.Status = InviteStatus.Rejected;
        await _dbContext.SaveChangesAsync();
        return true;
    }
}
