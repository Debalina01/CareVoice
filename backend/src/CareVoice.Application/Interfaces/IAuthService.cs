using System.Threading.Tasks;
using CareVoice.Application.DTOs;
using CareVoice.Domain.Entities;

namespace CareVoice.Application.Interfaces;

public interface IAuthService
{
    Task<AuthResponseDto> RegisterAsync(RegisterRequestDto request);
    Task<AuthResponseDto> LoginAsync(LoginRequestDto request);
    Task<AuthResponseDto> RefreshTokenAsync(RefreshTokenRequestDto request);
    Task<bool> IsEmailRegisteredAsync(string email);
}

public interface IJwtTokenGenerator
{
    string GenerateAccessToken(User user, System.Guid primaryFamilyMemberId);
    string GenerateRefreshToken();
    System.Security.Claims.ClaimsPrincipal? GetPrincipalFromExpiredToken(string token);
}
