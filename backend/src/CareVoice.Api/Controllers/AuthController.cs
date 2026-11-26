using System;
using System.Threading.Tasks;
using Microsoft.AspNetCore.Mvc;
using CareVoice.Application.DTOs;
using CareVoice.Application.Interfaces;

namespace CareVoice.Api.Controllers;

[ApiController]
[Route("api/[controller]")]
public class AuthController : ControllerBase
{
    private readonly IAuthService _authService;

    public AuthController(IAuthService authService)
    {
        _authService = authService;
    }

    [HttpGet("health")]
    [HttpGet("ping")]
    public IActionResult HealthCheck()
    {
        return Ok(new
        {
            status = "Healthy",
            service = "CareVoice.Api",
            timestamp = DateTime.UtcNow
        });
    }

    [HttpPost("register")]
    public async Task<IActionResult> Register([FromBody] RegisterRequestDto request)
    {
        try
        {
            var result = await _authService.RegisterAsync(request);
            return Ok(result);
        }
        catch (InvalidOperationException ex)
        {
            return BadRequest(new { message = ex.Message });
        }
    }

    [HttpPost("login")]
    public async Task<IActionResult> Login([FromBody] LoginRequestDto request)
    {
        try
        {
            var result = await _authService.LoginAsync(request);
            return Ok(result);
        }
        catch (UnauthorizedAccessException ex)
        {
            return Unauthorized(new { message = ex.Message });
        }
    }

    [HttpPost("refresh")]
    public async Task<IActionResult> RefreshToken([FromBody] RefreshTokenRequestDto request)
    {
        try
        {
            var result = await _authService.RefreshTokenAsync(request);
            return Ok(result);
        }
        catch (UnauthorizedAccessException ex)
        {
            return Unauthorized(new { message = ex.Message });
        }
    }

    [HttpGet("check-email")]
    public async Task<IActionResult> CheckEmail([FromQuery] string email)
    {
        if (string.IsNullOrWhiteSpace(email) || !email.Contains('@'))
        {
            return BadRequest(new { available = false, message = "Please provide a valid email address." });
        }

        var cleanEmail = email.Trim().ToLower();
        var isRegistered = await _authService.IsEmailRegisteredAsync(cleanEmail);
        if (isRegistered)
        {
            return Ok(new { available = false, message = "This email address is already registered. Please log in or use another email." });
        }

        return Ok(new { available = true, message = "Email address is available for registration." });
    }

    [HttpPost("send-otp")]
    public async Task<IActionResult> SendOtp([FromBody] SendOtpRequestDto request, [FromServices] IEmailOtpService otpService)
    {
        try
        {
            if (string.IsNullOrWhiteSpace(request.Email) || !request.Email.Contains('@'))
            {
                return BadRequest(new { success = false, message = "Please enter a valid email address." });
            }

            var cleanEmail = request.Email.Trim().ToLower();
            if (string.Equals(request.Purpose, "Registration", StringComparison.OrdinalIgnoreCase))
            {
                var isRegistered = await _authService.IsEmailRegisteredAsync(cleanEmail);
                if (isRegistered)
                {
                    return BadRequest(new { success = false, message = "This email address is already registered. Please log in or use another email." });
                }
            }

            var deliveryResult = await otpService.SendOtpDetailedAsync(cleanEmail, request.Purpose, request.Code);

            return Ok(new
            {
                success = true,
                message = deliveryResult.Message,
                isDeliveredViaSmtp = deliveryResult.IsDeliveredViaSmtp
            });
        }
        catch (ArgumentException ex)
        {
            return BadRequest(new { success = false, message = ex.Message });
        }
        catch (Exception ex)
        {
            return StatusCode(500, new { success = false, message = ex.Message });
        }
    }

    [HttpPost("verify-otp")]
    public async Task<IActionResult> VerifyOtp([FromBody] VerifyOtpRequestDto request, [FromServices] IEmailOtpService otpService)
    {
        var cleanEmail = request.Email.Trim().ToLower();
        var isValid = await otpService.VerifyOtpAsync(cleanEmail, request.Otp, request.Purpose);
        if (isValid)
        {
            return Ok(new VerifyOtpResponseDto
            {
                Success = true,
                Message = "Email OTP successfully verified.",
                VerificationToken = Convert.ToBase64String(System.Text.Encoding.UTF8.GetBytes($"{cleanEmail}:{DateTime.UtcNow:O}"))
            });
        }

        return BadRequest(new VerifyOtpResponseDto
        {
            Success = false,
            Message = "Invalid or expired verification OTP. Please try again or request a new code."
        });
    }

    [HttpPost("register-with-otp")]
    public async Task<IActionResult> RegisterWithOtp([FromBody] RegisterWithOtpRequestDto request, [FromServices] IEmailOtpService otpService)
    {
        var cleanEmail = request.Email.Trim().ToLower();
        var isVerified = await otpService.VerifyOtpAsync(cleanEmail, request.Otp, "Registration");
        if (!isVerified)
        {
            return BadRequest(new { message = "Invalid or expired OTP. Please verify your email before registering." });
        }

        try
        {
            var registerDto = new RegisterRequestDto(
                cleanEmail,
                request.Password,
                request.FullName,
                request.PhoneNumber,
                request.Role
            );
            var result = await _authService.RegisterAsync(registerDto);
            return Ok(result);
        }
        catch (InvalidOperationException ex)
        {
            return BadRequest(new { message = ex.Message });
        }
    }
}
