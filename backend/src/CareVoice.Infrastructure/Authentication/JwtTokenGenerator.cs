using System;
using System.IdentityModel.Tokens.Jwt;
using System.Security.Claims;
using System.Security.Cryptography;
using System.Text;
using Microsoft.Extensions.Configuration;
using Microsoft.IdentityModel.Tokens;
using CareVoice.Application.Interfaces;
using CareVoice.Domain.Entities;

namespace CareVoice.Infrastructure.Authentication;

public class JwtTokenGenerator : IJwtTokenGenerator
{
    private readonly IConfiguration _configuration;
    private static readonly string ProcessFallbackSecret =
        Convert.ToBase64String(RandomNumberGenerator.GetBytes(32));

    public JwtTokenGenerator(IConfiguration configuration)
    {
        _configuration = configuration;
    }

    public static string ResolveSigningSecret(IConfiguration configuration)
    {
        var configured = configuration["JwtSettings:Secret"];
        if (!string.IsNullOrWhiteSpace(configured)) return configured;

        var envSecret = Environment.GetEnvironmentVariable("JwtSettings__Secret")
            ?? Environment.GetEnvironmentVariable("JWT_SECRET");
        if (!string.IsNullOrWhiteSpace(envSecret)) return envSecret;

        return ProcessFallbackSecret;
    }

    public string GenerateAccessToken(User user, Guid primaryFamilyMemberId)
    {
        var key = new SymmetricSecurityKey(Encoding.UTF8.GetBytes(ResolveSigningSecret(_configuration)));
        var creds = new SigningCredentials(key, SecurityAlgorithms.HmacSha256);

        var claims = new[]
        {
            new Claim(ClaimTypes.NameIdentifier, user.Id.ToString()),
            new Claim(ClaimTypes.Email, user.Email),
            new Claim(ClaimTypes.Name, user.FullName),
            new Claim("PrimaryMemberId", primaryFamilyMemberId.ToString())
        };

        var expires = DateTime.UtcNow.AddMinutes(
            double.TryParse(_configuration["JwtSettings:AccessTokenExpiryMinutes"], out var mins) ? mins : 60);

        var token = new JwtSecurityToken(
            issuer: _configuration["JwtSettings:Issuer"] ?? "CareVoiceApi",
            audience: _configuration["JwtSettings:Audience"] ?? "CareVoiceClient",
            claims: claims,
            expires: expires,
            signingCredentials: creds
        );

        return new JwtSecurityTokenHandler().WriteToken(token);
    }

    public string GenerateRefreshToken()
    {
        var randomNumber = new byte[64];
        using var rng = RandomNumberGenerator.Create();
        rng.GetBytes(randomNumber);
        return Convert.ToBase64String(randomNumber);
    }

    public ClaimsPrincipal? GetPrincipalFromExpiredToken(string token)
    {
        var tokenValidationParameters = new TokenValidationParameters
        {
            ValidateAudience = true,
            ValidAudience = _configuration["JwtSettings:Audience"] ?? "CareVoiceClient",
            ValidateIssuer = true,
            ValidIssuer = _configuration["JwtSettings:Issuer"] ?? "CareVoiceApi",
            ValidateIssuerSigningKey = true,
            IssuerSigningKey = new SymmetricSecurityKey(Encoding.UTF8.GetBytes(
                ResolveSigningSecret(_configuration))),
            ValidateLifetime = false
        };

        var tokenHandler = new JwtSecurityTokenHandler();
        var principal = tokenHandler.ValidateToken(token, tokenValidationParameters, out var securityToken);

        if (securityToken is not JwtSecurityToken jwtSecurityToken ||
            !jwtSecurityToken.Header.Alg.Equals(SecurityAlgorithms.HmacSha256, StringComparison.InvariantCultureIgnoreCase))
        {
            throw new SecurityTokenException("Invalid token algorithm");
        }

        return principal;
    }
}
