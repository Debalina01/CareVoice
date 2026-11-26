using System;
using System.Linq;
using System.Threading.Tasks;
using Microsoft.EntityFrameworkCore;
using Xunit;
using CareVoice.Application.DTOs;
using CareVoice.Domain.Entities;
using CareVoice.Infrastructure.Persistence;
using CareVoice.Infrastructure.Services;

namespace CareVoice.Tests;

public class FamilyMemberServiceTests
{
    private CareVoiceDbContext CreateDbContext(string dbName)
    {
        var options = new DbContextOptionsBuilder<CareVoiceDbContext>()
            .UseInMemoryDatabase(databaseName: dbName)
            .Options;
        return new CareVoiceDbContext(options);
    }

    [Fact]
    public async Task CreateFamilyMember_ShouldPersist_AndBeRetrievable()
    {
        var db = CreateDbContext("CreateMemberDb");
        var permService = new PermissionService(db);
        var service = new FamilyMemberService(db, permService);
        var userId = Guid.NewGuid();

        db.FamilyMembers.Add(new FamilyMember
        {
            Id = Guid.NewGuid(),
            UserId = userId,
            FullName = "Caregiver",
            Relation = "Self"
        });
        await db.SaveChangesAsync();

        var dto = new CreateFamilyMemberDto
        {
            FullName = "Grandma Mary",
            Relation = "Grandmother",
            PreferredLanguage = "en",
            VoicePreference = "en-US-Standard-B"
        };

        var created = await service.CreateFamilyMemberAsync(userId, dto);

        Assert.NotNull(created);
        Assert.Equal("Grandma Mary", created.FullName);
        Assert.Equal("Grandmother", created.Relation);

        var members = (await service.GetFamilyMembersAsync(userId)).ToList();
        Assert.Equal(2, members.Count);
        Assert.Contains(members, m => m.FullName == "Grandma Mary");
    }

    [Fact]
    public async Task DeleteFamilyMember_ShouldSoftDelete_WhenNotSelf()
    {
        var db = CreateDbContext("DeleteMemberDb");
        var permService = new PermissionService(db);
        var service = new FamilyMemberService(db, permService);
        var userId = Guid.NewGuid();

        var member = new FamilyMember
        {
            Id = Guid.NewGuid(),
            UserId = userId,
            FullName = "Uncle Bob",
            Relation = "Uncle"
        };
        db.FamilyMembers.Add(member);
        await db.SaveChangesAsync();

        var success = await service.DeleteFamilyMemberAsync(userId, member.Id);

        Assert.True(success);
        var inDb = await db.FamilyMembers.FindAsync(member.Id);
        Assert.NotNull(inDb);
        Assert.True(inDb.IsDeleted);
    }

    [Fact]
    public async Task DeleteFamilyMember_ShouldThrow_WhenAttemptingToDeleteSelf()
    {
        var db = CreateDbContext("DeleteSelfMemberDb");
        var permService = new PermissionService(db);
        var service = new FamilyMemberService(db, permService);
        var userId = Guid.NewGuid();

        var selfMember = new FamilyMember
        {
            Id = Guid.NewGuid(),
            UserId = userId,
            FullName = "Primary Self",
            Relation = "Self"
        };
        db.FamilyMembers.Add(selfMember);
        await db.SaveChangesAsync();

        await Assert.ThrowsAsync<InvalidOperationException>(() =>
            service.DeleteFamilyMemberAsync(userId, selfMember.Id));
    }

    [Fact]
    public async Task CreateFamilyMember_WithLoginCredentials_ShouldCreateUser_HashPassword_AndLinkFamilyGroup()
    {
        var db = CreateDbContext("CreateMemberCredentialsDb");
        var permService = new PermissionService(db);
        var service = new FamilyMemberService(db, permService);
        var caretakerUserId = Guid.NewGuid();

        var caretakerUser = new User
        {
            Id = caretakerUserId,
            Email = "caretaker@carevoice.app",
            FullName = "Jane Caregiver",
            Role = "Caregiver"
        };
        db.Users.Add(caretakerUser);

        var selfMember = new FamilyMember
        {
            Id = Guid.NewGuid(),
            UserId = caretakerUserId,
            FullName = "Jane Caregiver",
            Relation = "Self"
        };
        db.FamilyMembers.Add(selfMember);

        var familyGroup = new FamilyGroup
        {
            Id = Guid.NewGuid(),
            FamilyCode = "CV-TEST1",
            Name = "Jane's Family",
            CreatorUserId = caretakerUserId
        };
        familyGroup.Members.Add(new FamilyGroupMember
        {
            Id = Guid.NewGuid(),
            FamilyGroupId = familyGroup.Id,
            UserId = caretakerUserId,
            Role = "Creator",
            Status = "Approved"
        });
        db.FamilyGroups.Add(familyGroup);
        await db.SaveChangesAsync();

        var dto = new CreateFamilyMemberDto
        {
            FullName = "Papa John",
            Relation = "Parent",
            PreferredLanguage = "bn",
            VoicePreference = "bn-IN-Standard-A",
            Username = "papa2026",
            Password = "SecurePassword123!"
        };

        var created = await service.CreateFamilyMemberAsync(caretakerUserId, dto);

        Assert.NotNull(created);
        Assert.True(created.HasLoginCredentials);
        Assert.Equal("papa2026", created.Username);
        Assert.NotNull(created.LinkedUserId);

        var createdUser = await db.Users.FirstOrDefaultAsync(u => u.Id == created.LinkedUserId.Value);
        Assert.NotNull(createdUser);
        Assert.Equal("papa2026", createdUser.Username);
        Assert.NotEqual("SecurePassword123!", createdUser.PasswordHash);
        Assert.True(BCrypt.Net.BCrypt.Verify("SecurePassword123!", createdUser.PasswordHash));

        var membership = await db.FamilyGroupMembers
            .FirstOrDefaultAsync(m => m.FamilyGroupId == familyGroup.Id && m.UserId == createdUser.Id);
        Assert.NotNull(membership);
        Assert.Equal("Approved", membership.Status);
        Assert.Equal("Member", membership.Role);

        var members = (await service.GetFamilyMembersAsync(caretakerUserId)).ToList();
        var papa = members.FirstOrDefault(m => m.FullName == "Papa John");
        Assert.NotNull(papa);
        Assert.Equal(1, members.Count(m => m.FullName == "Papa John"));
        Assert.True(papa.HasLoginCredentials);
        Assert.Equal("papa2026", papa.Username);

        var deleted = await service.DeleteFamilyMemberAsync(caretakerUserId, papa.Id);
        Assert.True(deleted);

        var refreshedMembers = (await service.GetFamilyMembersAsync(caretakerUserId)).ToList();
        Assert.DoesNotContain(refreshedMembers, m => m.FullName == "Papa John");
    }

    [Fact]
    public async Task CreateFamilyMember_WithDuplicateUsername_ShouldThrow()
    {
        var db = CreateDbContext("DuplicateUsernameDb");
        var permService = new PermissionService(db);
        var service = new FamilyMemberService(db, permService);
        var caretakerUserId = Guid.NewGuid();

        db.Users.Add(new User
        {
            Id = Guid.NewGuid(),
            Email = "existinguser@carevoice.app",
            Username = "existinguser",
            PasswordHash = "hashed",
            FullName = "Existing User"
        });
        db.FamilyMembers.Add(new FamilyMember
        {
            Id = Guid.NewGuid(),
            UserId = caretakerUserId,
            FullName = "Caretaker",
            Relation = "Self"
        });
        await db.SaveChangesAsync();

        var dto = new CreateFamilyMemberDto
        {
            FullName = "Second Member",
            Relation = "Parent",
            Username = "EXISTINGUSER",
            Password = "Password123!"
        };

        var ex = await Assert.ThrowsAsync<InvalidOperationException>(() =>
            service.CreateFamilyMemberAsync(caretakerUserId, dto));

        Assert.Contains("already taken", ex.Message, StringComparison.OrdinalIgnoreCase);
    }

    [Fact]
    public async Task CreateFamilyMember_WithShortPassword_ShouldThrow()
    {
        var db = CreateDbContext("ShortPasswordDb");
        var permService = new PermissionService(db);
        var service = new FamilyMemberService(db, permService);
        var caretakerUserId = Guid.NewGuid();

        db.FamilyMembers.Add(new FamilyMember
        {
            Id = Guid.NewGuid(),
            UserId = caretakerUserId,
            FullName = "Caretaker",
            Relation = "Self"
        });
        await db.SaveChangesAsync();

        var dto = new CreateFamilyMemberDto
        {
            FullName = "Short Pass Member",
            Relation = "Parent",
            Username = "user123",
            Password = "123"
        };

        var ex = await Assert.ThrowsAsync<ArgumentException>(() =>
            service.CreateFamilyMemberAsync(caretakerUserId, dto));

        Assert.Contains("at least 6 characters", ex.Message);
    }

    [Fact]
    public async Task LoginWithMemberCredentials_ShouldSucceed()
    {
        var db = CreateDbContext("LoginMemberCredentialsDb");
        var permService = new PermissionService(db);
        var familyService = new FamilyMemberService(db, permService);
        var authService = new AuthService(db, new MockJwtTokenGenerator());

        var caretakerUserId = Guid.NewGuid();
        db.Users.Add(new User
        {
            Id = caretakerUserId,
            Email = "caretaker@carevoice.app",
            FullName = "Jane Caregiver",
            Role = "Caregiver"
        });
        db.FamilyMembers.Add(new FamilyMember
        {
            Id = Guid.NewGuid(),
            UserId = caretakerUserId,
            FullName = "Jane Caregiver",
            Relation = "Self"
        });
        await db.SaveChangesAsync();

        var dto = new CreateFamilyMemberDto
        {
            FullName = "Grandpa Joe",
            Relation = "Grandfather",
            Username = "grandpa_joe",
            Password = "MySecretPassword2026!"
        };
        var created = await familyService.CreateFamilyMemberAsync(caretakerUserId, dto);
        Assert.NotNull(created);

        var loginResponse = await authService.LoginAsync(new LoginRequestDto("grandpa_joe", "MySecretPassword2026!"));

        Assert.NotNull(loginResponse);
        Assert.False(string.IsNullOrEmpty(loginResponse.AccessToken));
        Assert.Equal("Grandpa Joe", loginResponse.User.FullName);
        Assert.Equal("grandpa_joe", loginResponse.User.Username);
    }
}

public class MockJwtTokenGenerator : CareVoice.Application.Interfaces.IJwtTokenGenerator
{
    public string GenerateAccessToken(User user, Guid primaryMemberId) => "mock_jwt_access_token";
    public string GenerateRefreshToken() => "mock_jwt_refresh_token";
    public System.Security.Claims.ClaimsPrincipal? GetPrincipalFromExpiredToken(string token) => null;
}
