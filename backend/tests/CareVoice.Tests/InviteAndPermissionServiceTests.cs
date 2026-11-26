using System;
using System.Threading.Tasks;
using Microsoft.EntityFrameworkCore;
using Xunit;
using CareVoice.Application.DTOs;
using CareVoice.Domain.Entities;
using CareVoice.Domain.Enums;
using CareVoice.Infrastructure.Persistence;
using CareVoice.Infrastructure.Services;

namespace CareVoice.Tests;

public class InviteAndPermissionServiceTests
{
    private CareVoiceDbContext CreateDbContext(string dbName)
    {
        var options = new DbContextOptionsBuilder<CareVoiceDbContext>()
            .UseInMemoryDatabase(databaseName: dbName)
            .Options;
        return new CareVoiceDbContext(options);
    }

    [Fact]
    public async Task CreateInvite_ShouldGenerateCryptographicToken()
    {
        var db = CreateDbContext("CreateInviteDb");
        var permService = new PermissionService(db);
        var inviteService = new InviteService(db, permService);
        var inviterUser = new User { Id = Guid.NewGuid(), Email = "caregiver@test.com", FullName = "Caregiver" };
        var inviterMember = new FamilyMember { Id = Guid.NewGuid(), UserId = inviterUser.Id, FullName = "Caregiver", Relation = "Self" };
        db.Users.Add(inviterUser);
        db.FamilyMembers.Add(inviterMember);
        await db.SaveChangesAsync();

        var invite = await inviteService.CreateInviteAsync(inviterUser.Id, new CreateInviteDto
        {
            InvitedEmail = "recipient@test.com"
        });

        Assert.NotNull(invite);
        Assert.Equal("recipient@test.com", invite.InvitedEmail);
        Assert.Equal(64, invite.InviteToken.Length);
        Assert.Equal(InviteStatus.Pending, invite.Status);
    }

    [Fact]
    public async Task AcceptInvite_ShouldEstablishFamilyPermission_AndMarkAccepted()
    {
        var db = CreateDbContext("AcceptInviteDb");
        var permService = new PermissionService(db);
        var inviteService = new InviteService(db, permService);

        var cgUser = new User { Id = Guid.NewGuid(), Email = "cg@test.com", FullName = "CG" };
        var cgMember = new FamilyMember { Id = Guid.NewGuid(), UserId = cgUser.Id, FullName = "CG", Relation = "Self" };
        var recUser = new User { Id = Guid.NewGuid(), Email = "rec@test.com", FullName = "REC" };
        var recMember = new FamilyMember { Id = Guid.NewGuid(), UserId = recUser.Id, FullName = "REC", Relation = "Self" };

        db.Users.AddRange(cgUser, recUser);
        db.FamilyMembers.AddRange(cgMember, recMember);
        await db.SaveChangesAsync();

        var invite = await inviteService.CreateInviteAsync(cgUser.Id, new CreateInviteDto
        {
            InvitedEmail = "rec@test.com"
        });

        var result = await inviteService.AcceptInviteAsync(recUser.Id, new AcceptInviteDto
        {
            InviteToken = invite.InviteToken
        });

        Assert.True(result);

        var canSet = await permService.CanSetRemindersAsync(cgUser.Id, recMember.Id);
        var canView = await permService.CanViewLogsAsync(cgUser.Id, recMember.Id);

        Assert.True(canSet);
        Assert.True(canView);
    }

    [Fact]
    public async Task AcceptInvite_ShouldThrow_WhenEmailMismatches()
    {
        var db = CreateDbContext("EmailMismatchDb");
        var permService = new PermissionService(db);
        var inviteService = new InviteService(db, permService);

        var cgUser = new User { Id = Guid.NewGuid(), Email = "cg@test.com", FullName = "CG" };
        var cgMember = new FamilyMember { Id = Guid.NewGuid(), UserId = cgUser.Id, FullName = "CG", Relation = "Self" };
        var intruderUser = new User { Id = Guid.NewGuid(), Email = "intruder@test.com", FullName = "Intruder" };
        var intruderMember = new FamilyMember { Id = Guid.NewGuid(), UserId = intruderUser.Id, FullName = "Intruder", Relation = "Self" };

        db.Users.AddRange(cgUser, intruderUser);
        db.FamilyMembers.AddRange(cgMember, intruderMember);
        await db.SaveChangesAsync();

        var invite = await inviteService.CreateInviteAsync(cgUser.Id, new CreateInviteDto
        {
            InvitedEmail = "intended_recipient@test.com"
        });

        await Assert.ThrowsAsync<InvalidOperationException>(() =>
            inviteService.AcceptInviteAsync(intruderUser.Id, new AcceptInviteDto
            {
                InviteToken = invite.InviteToken
            }));
    }
}
