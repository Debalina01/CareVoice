using System.Threading.Tasks;
using CareVoice.Application.DTOs;

namespace CareVoice.Application.Interfaces;

public class OtpDeliveryResult
{
    public bool IsDeliveredViaSmtp { get; set; }
    public string DeliveryMode { get; set; } = "LiveSmtp";
    public string Message { get; set; } = string.Empty;
}

public interface IEmailOtpService
{
    Task<string> SendOtpAsync(string email, string purpose = "Registration", string? customOtp = null);
    Task<OtpDeliveryResult> SendOtpDetailedAsync(string email, string purpose = "Registration", string? customOtp = null);
    Task<bool> VerifyOtpAsync(string email, string otp, string purpose = "Registration");
    Task<bool> IsEmailVerifiedAsync(string email, string purpose = "Registration");
}
