using System;
using System.Linq;
using System.Security.Claims;
using System.Threading.Tasks;
using Microsoft.EntityFrameworkCore;
using CareVoice.Application.DTOs;
using CareVoice.Application.Interfaces;
using CareVoice.Domain.Entities;
using CareVoice.Infrastructure.Persistence;

namespace CareVoice.Infrastructure.Services;

public class AuthService : IAuthService
{
    private readonly CareVoiceDbContext _dbContext;
    private readonly IJwtTokenGenerator _tokenGenerator;

    public AuthService(CareVoiceDbContext dbContext, IJwtTokenGenerator tokenGenerator)
    {
        _dbContext = dbContext;
        _tokenGenerator = tokenGenerator;
    }

    public async Task<AuthResponseDto> RegisterAsync(RegisterRequestDto request)
    {
        var cleanEmail = request.Email.Trim().ToLower();
        var existingUser = await _dbContext.Users.AnyAsync(u => u.Email.ToLower() == cleanEmail || (u.Username != null && u.Username.ToLower() == cleanEmail));
        if (existingUser)
        {
            throw new InvalidOperationException("User with this email or username already exists.");
        }

        var user = new User
        {
            Id = Guid.NewGuid(),
            Email = cleanEmail,
            Username = cleanEmail.Contains('@') ? cleanEmail.Split('@')[0] : cleanEmail,
            PasswordHash = BCrypt.Net.BCrypt.HashPassword(request.Password),
            FullName = request.FullName.Trim(),
            PhoneNumber = request.PhoneNumber?.Trim(),
            Role = !string.IsNullOrWhiteSpace(request.Role) ? request.Role : "Caregiver",
            CreatedAt = DateTime.UtcNow,
            UpdatedAt = DateTime.UtcNow
        };

        var selfMember = new FamilyMember
        {
            Id = Guid.NewGuid(),
            UserId = user.Id,
            FullName = user.FullName,
            Relation = "Self",
            PreferredLanguage = "en",
            VoicePreference = "en-US-Standard-A",
            CreatedAt = DateTime.UtcNow
        };

        user.FamilyMembers.Add(selfMember);

        const string codeAlphabet = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
        var rndBytes = new byte[5];
        using (var rng = System.Security.Cryptography.RandomNumberGenerator.Create())
        {
            rng.GetBytes(rndBytes);
        }
        var code = "CV-" + new string(rndBytes.Select(b => codeAlphabet[b % codeAlphabet.Length]).ToArray());

        var familyGroup = new FamilyGroup
        {
            Id = Guid.NewGuid(),
            FamilyCode = code,
            Name = $"{user.FullName}'s Family",
            CreatorUserId = user.Id,
            CreatedAt = DateTime.UtcNow,
            UpdatedAt = DateTime.UtcNow
        };

        familyGroup.Members.Add(new FamilyGroupMember
        {
            Id = Guid.NewGuid(),
            FamilyGroupId = familyGroup.Id,
            UserId = user.Id,
            Role = "Creator",
            Status = "Approved",
            JoinedAt = DateTime.UtcNow
        });

        _dbContext.FamilyGroups.Add(familyGroup);

        var refreshToken = _tokenGenerator.GenerateRefreshToken();
        user.RefreshToken = refreshToken;
        user.RefreshTokenExpiryTime = DateTime.UtcNow.AddDays(7);

        _dbContext.Users.Add(user);
        await _dbContext.SaveChangesAsync();

        var accessToken = _tokenGenerator.GenerateAccessToken(user, selfMember.Id);
        var expiresAt = DateTime.UtcNow.AddHours(1);

        return new AuthResponseDto(
            accessToken,
            refreshToken,
            expiresAt,
            new UserDto(user.Id, user.Email, user.FullName, user.PhoneNumber, selfMember.Id, user.Role, user.Username)
        );
    }

    public async Task<AuthResponseDto> LoginAsync(LoginRequestDto request)
    {
        var cleanLogin = request.Email.Trim().ToLower();
        var user = await _dbContext.Users
            .Include(u => u.FamilyMembers)
            .FirstOrDefaultAsync(u => u.Email.ToLower() == cleanLogin || (u.Username != null && u.Username.ToLower() == cleanLogin));

        if (user == null || !BCrypt.Net.BCrypt.Verify(request.Password, user.PasswordHash))
        {
            throw new UnauthorizedAccessException("Invalid email/username or password.");
        }

        var selfMember = user.FamilyMembers.FirstOrDefault(fm => fm.Relation == "Self") 
                         ?? user.FamilyMembers.First();

        var refreshToken = _tokenGenerator.GenerateRefreshToken();
        user.RefreshToken = refreshToken;
        user.RefreshTokenExpiryTime = DateTime.UtcNow.AddDays(7);
        user.UpdatedAt = DateTime.UtcNow;

        await _dbContext.SaveChangesAsync();

        var accessToken = _tokenGenerator.GenerateAccessToken(user, selfMember.Id);
        var expiresAt = DateTime.UtcNow.AddHours(1);

        return new AuthResponseDto(
            accessToken,
            refreshToken,
            expiresAt,
            new UserDto(user.Id, user.Email, user.FullName, user.PhoneNumber, selfMember.Id, user.Role, user.Username)
        );
    }

    public async Task<AuthResponseDto> RefreshTokenAsync(RefreshTokenRequestDto request)
    {
        var principal = _tokenGenerator.GetPrincipalFromExpiredToken(request.AccessToken);
        if (principal == null)
        {
            throw new UnauthorizedAccessException("Invalid access token.");
        }

        var userIdClaim = principal.FindFirst(ClaimTypes.NameIdentifier)?.Value;
        if (!Guid.TryParse(userIdClaim, out var userId))
        {
            throw new UnauthorizedAccessException("Invalid token claims.");
        }

        var user = await _dbContext.Users
            .Include(u => u.FamilyMembers)
            .FirstOrDefaultAsync(u => u.Id == userId);

        if (user == null || user.RefreshToken != request.RefreshToken || user.RefreshTokenExpiryTime <= DateTime.UtcNow)
        {
            throw new UnauthorizedAccessException("Invalid or expired refresh token.");
        }

        var selfMember = user.FamilyMembers.FirstOrDefault(fm => fm.Relation == "Self") 
                         ?? user.FamilyMembers.First();

        var newAccessToken = _tokenGenerator.GenerateAccessToken(user, selfMember.Id);
        var newRefreshToken = _tokenGenerator.GenerateRefreshToken();

        user.RefreshToken = newRefreshToken;
        user.RefreshTokenExpiryTime = DateTime.UtcNow.AddDays(7);
        user.UpdatedAt = DateTime.UtcNow;

        await _dbContext.SaveChangesAsync();

        return new AuthResponseDto(
            newAccessToken,
            newRefreshToken,
            DateTime.UtcNow.AddHours(1),
            new UserDto(user.Id, user.Email, user.FullName, user.PhoneNumber, selfMember.Id, user.Role, user.Username)
        );
    }

    public async Task<bool> IsEmailRegisteredAsync(string email)
    {
        if (string.IsNullOrWhiteSpace(email)) return false;
        var cleanEmail = email.Trim().ToLower();
        return await _dbContext.Users.AnyAsync(u => u.Email.ToLower() == cleanEmail);
    }
}
