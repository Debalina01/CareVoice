using System;

namespace CareVoice.Application.DTOs;

public class RegisterRequestDto
{
    public string Email { get; set; } = string.Empty;
    public string Password { get; set; } = string.Empty;
    public string FullName { get; set; } = string.Empty;
    public string? PhoneNumber { get; set; }
    public string Role { get; set; } = "Caregiver";

    public RegisterRequestDto() { }

    public RegisterRequestDto(string email, string password, string fullName, string? phoneNumber = null, string role = "Caregiver")
    {
        Email = email;
        Password = password;
        FullName = fullName;
        PhoneNumber = phoneNumber;
        Role = role;
    }
}

public class LoginRequestDto
{
    public string Email { get; set; } = string.Empty;
    public string Password { get; set; } = string.Empty;

    public LoginRequestDto() { }

    public LoginRequestDto(string email, string password)
    {
        Email = email;
        Password = password;
    }
}

public class RefreshTokenRequestDto
{
    public string AccessToken { get; set; } = string.Empty;
    public string RefreshToken { get; set; } = string.Empty;
}

public class AuthResponseDto
{
    public string AccessToken { get; set; } = string.Empty;
    public string RefreshToken { get; set; } = string.Empty;
    public DateTime ExpiresAt { get; set; }
    public UserDto User { get; set; } = null!;

    public AuthResponseDto() { }

    public AuthResponseDto(string accessToken, string refreshToken, DateTime expiresAt, UserDto user)
    {
        AccessToken = accessToken;
        RefreshToken = refreshToken;
        ExpiresAt = expiresAt;
        User = user;
    }
}

public class UserDto
{
    public Guid Id { get; set; }
    public string Email { get; set; } = string.Empty;
    public string? Username { get; set; }
    public string FullName { get; set; } = string.Empty;
    public string? PhoneNumber { get; set; }
    public string Role { get; set; } = "Caregiver";
    public Guid DefaultFamilyMemberId { get; set; }

    public UserDto() { }

    public UserDto(Guid id, string email, string fullName, string? phoneNumber, Guid defaultFamilyMemberId, string role = "Caregiver", string? username = null)
    {
        Id = id;
        Email = email;
        Username = username;
        FullName = fullName;
        PhoneNumber = phoneNumber;
        DefaultFamilyMemberId = defaultFamilyMemberId;
        Role = role;
    }
}

public class SendOtpRequestDto
{
    public string Email { get; set; } = string.Empty;
    public string Purpose { get; set; } = "Registration";
    public string? Code { get; set; }
}

public class VerifyOtpRequestDto
{
    public string Email { get; set; } = string.Empty;
    public string Otp { get; set; } = string.Empty;
    public string Purpose { get; set; } = "Registration";
}

public class VerifyOtpResponseDto
{
    public bool Success { get; set; }
    public string Message { get; set; } = string.Empty;
    public string? VerificationToken { get; set; }
}

public class RegisterWithOtpRequestDto
{
    public string Email { get; set; } = string.Empty;
    public string Password { get; set; } = string.Empty;
    public string FullName { get; set; } = string.Empty;
    public string? PhoneNumber { get; set; }
    public string Role { get; set; } = "Caregiver";
    public string Otp { get; set; } = string.Empty;
}
