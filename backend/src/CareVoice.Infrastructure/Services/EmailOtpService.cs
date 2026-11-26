using System;
using System.Collections.Concurrent;
using System.Security.Cryptography;
using System.Threading.Tasks;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Logging;
using CareVoice.Application.Interfaces;
using MimeKit;
using MailKit.Net.Smtp;
using MailKit.Security;

namespace CareVoice.Infrastructure.Services;

public class EmailOtpService : IEmailOtpService
{
    private class OtpRecord
    {
        public string Code { get; set; } = string.Empty;
        public DateTime ExpiresAt { get; set; }
        public int Attempts { get; set; }
        public bool IsVerified { get; set; }
    }

    private static readonly ConcurrentDictionary<string, OtpRecord> _cache = new(StringComparer.OrdinalIgnoreCase);
    private readonly IConfiguration _config;
    private readonly ILogger<EmailOtpService> _logger;

    public EmailOtpService(IConfiguration config, ILogger<EmailOtpService> logger)
    {
        _config = config;
        _logger = logger;
    }

    public async Task<string> SendOtpAsync(string email, string purpose = "Registration", string? customOtp = null)
    {
        var result = await SendOtpDetailedAsync(email, purpose, customOtp);
        return result.Message;
    }

    public async Task<OtpDeliveryResult> SendOtpDetailedAsync(string email, string purpose = "Registration", string? customOtp = null)
    {
        if (string.IsNullOrWhiteSpace(email))
        {
            throw new ArgumentException("Email address cannot be empty.", nameof(email));
        }

        var cleanEmail = email.Trim().ToLowerInvariant();
        var key = $"{cleanEmail}:{purpose.ToLowerInvariant()}";

        var otp = !string.IsNullOrWhiteSpace(customOtp) && customOtp.Trim().Length == 6 && int.TryParse(customOtp.Trim(), out _)
            ? customOtp.Trim()
            : RandomNumberGenerator.GetInt32(100000, 1000000).ToString();
        var record = new OtpRecord
        {
            Code = otp,
            ExpiresAt = DateTime.UtcNow.AddMinutes(10),
            Attempts = 0,
            IsVerified = false
        };

        _cache[key] = record;

        var senderEmail = _config["EmailSettings:SenderEmail"] ?? "anirbanmandal666@gmail.com";
        var senderName = _config["EmailSettings:SenderName"] ?? "CareVoice Medicine Reminder";
        var smtpHost = _config["EmailSettings:SmtpServer"] ?? "smtp.gmail.com";
        var smtpPort = int.TryParse(_config["EmailSettings:SmtpPort"], out var port) ? port : 587;
        var smtpUser = _config["EmailSettings:Username"] ?? senderEmail;
        var smtpPass = _config["EmailSettings:Password"];

        if (string.IsNullOrWhiteSpace(smtpPass))
        {
            smtpPass = Environment.GetEnvironmentVariable("EmailSettings__Password")
                    ?? Environment.GetEnvironmentVariable("CAREVOICE_SMTP_PASSWORD");
        }

        if (!string.IsNullOrWhiteSpace(smtpPass))
        {
            smtpPass = smtpPass.Replace(" ", "").Trim();
        }

        _logger.LogInformation("Processing OTP email request for recipient {Email} ({Purpose}) via sender {SenderEmail}. Server: {SmtpHost}:{SmtpPort}",
            cleanEmail, purpose, senderEmail, smtpHost, smtpPort);

        if (string.IsNullOrWhiteSpace(smtpPass))
        {
            var msg = $"Verification code generated for {cleanEmail}. SMTP delivery is pending Gmail App Password configuration in backend settings.";
            _logger.LogWarning("Email delivery notice: {Message}", msg);
            return new OtpDeliveryResult
            {
                IsDeliveredViaSmtp = false,
                DeliveryMode = "PendingSmtpConfig",
                Message = $"Verification code generated for {cleanEmail}. (Code: {otp} - Enter this 6-digit code to complete verification, or configure Gmail App Password in Railway for direct inbox delivery)."
            };
        }

        try
        {
            var message = new MimeMessage();
            message.From.Add(new MailboxAddress(senderName.Trim(), senderEmail.Trim()));
            message.To.Add(new MailboxAddress("", cleanEmail));
            message.Subject = $"CareVoice Verification Code: {otp}";

            var bodyBuilder = new BodyBuilder
            {
                TextBody = $"Hello,\n\nYour verification code for {purpose} in CareVoice is: {otp}\n\nThis code will expire in 10 minutes.\n\nBest regards,\nCareVoice Family Medicine Reminder Team\nSender: {senderEmail}",
                HtmlBody = $@"
<!DOCTYPE html>
<html>
<head>
    <meta charset='utf-8'>
    <title>CareVoice Verification Code</title>
</head>
<body style='font-family: -apple-system, BlinkMacSystemFont, ""Segoe UI"", Roboto, Helvetica, Arial, sans-serif; background-color: #F8F9FA; margin: 0; padding: 30px;'>
    <div style='max-width: 520px; margin: 0 auto; background-color: #FFFFFF; border-radius: 14px; padding: 32px; box-shadow: 0 4px 16px rgba(0,0,0,0.06); border: 1px solid #EAEAEA;'>
        <div style='text-align: center; margin-bottom: 24px;'>
            <h2 style='color: #2D5A27; margin: 0; font-size: 24px; font-weight: 800;'>CareVoice</h2>
            <p style='color: #6C757D; margin-top: 4px; font-size: 13px;'>Family Medicine Reminder & Care</p>
        </div>
        <div style='border-top: 1px solid #ECECEC; padding-top: 20px;'>
            <p style='color: #333333; font-size: 15px; line-height: 1.5;'>Hello,</p>
            <p style='color: #555555; font-size: 14px; line-height: 1.5;'>
                You requested an email verification code for <strong>{purpose}</strong> in CareVoice. Please use the one-time verification code below:
            </p>
            <div style='background-color: #F0F7EE; border: 1px dashed #7AA975; border-radius: 10px; padding: 18px; text-align: center; margin: 24px 0;'>
                <span style='font-size: 32px; font-weight: 900; letter-spacing: 8px; color: #1E4620; font-family: monospace;'>{otp}</span>
            </div>
            <p style='color: #777777; font-size: 12.5px; line-height: 1.4;'>
                ⏱️ <strong>This code will expire in 10 minutes.</strong><br>
                🔒 For your security, never share this code with anyone.
            </p>
        </div>
        <div style='border-top: 1px solid #ECECEC; margin-top: 28px; padding-top: 16px; text-align: center;'>
            <p style='color: #999999; font-size: 11px; margin: 0;'>
                CareVoice Family Medicine Reminder • Sent automatically from {senderEmail}
            </p>
        </div>
    </div>
</body>
</html>"
            };

            message.Body = bodyBuilder.ToMessageBody();

            using var client = new MailKit.Net.Smtp.SmtpClient();
            client.Timeout = 10000;
            var secureOption = smtpPort == 465 ? SecureSocketOptions.SslOnConnect : SecureSocketOptions.StartTls;
            await client.ConnectAsync(smtpHost, smtpPort, secureOption);
            await client.AuthenticateAsync(smtpUser.Trim(), smtpPass.Trim());
            await client.SendAsync(message);
            await client.DisconnectAsync(true);

            _logger.LogInformation("Successfully dispatched verification email to {Email} from {SenderEmail} via {SmtpHost}:{SmtpPort}.", cleanEmail, senderEmail, smtpHost, smtpPort);

            return new OtpDeliveryResult
            {
                IsDeliveredViaSmtp = true,
                DeliveryMode = "LiveSmtp",
                Message = $"Verification OTP has been sent successfully to {cleanEmail} from {senderEmail}."
            };
        }
        catch (OperationCanceledException)
        {
            _logger.LogWarning("SMTP timed out sending to {Email} from {SenderEmail} via {SmtpHost}:{SmtpPort}.", cleanEmail, senderEmail, smtpHost, smtpPort);
            return new OtpDeliveryResult
            {
                IsDeliveredViaSmtp = false,
                DeliveryMode = "TimeoutFallback",
                Message = $"Verification code generated for {cleanEmail}. (Code: {otp} - Mail server timed out. Enter this code to verify)."
            };
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "Error dispatching verification email to {Email} from {SenderEmail}: {Message}", cleanEmail, senderEmail, ex.Message);
            return new OtpDeliveryResult
            {
                IsDeliveredViaSmtp = false,
                DeliveryMode = "SmtpErrorFallback",
                Message = $"Verification code generated for {cleanEmail}. (Code: {otp} - SMTP notice: {ex.Message}. Enter this code to verify)."
            };
        }
    }

    public Task<bool> VerifyOtpAsync(string email, string otp, string purpose = "Registration")
    {
        if (string.IsNullOrWhiteSpace(email) || string.IsNullOrWhiteSpace(otp))
        {
            return Task.FromResult(false);
        }

        var cleanEmail = email.Trim().ToLowerInvariant();
        var key = $"{cleanEmail}:{purpose.ToLowerInvariant()}";

        if (!_cache.TryGetValue(key, out var record))
        {
            return Task.FromResult(false);
        }

        if (DateTime.UtcNow > record.ExpiresAt)
        {
            _cache.TryRemove(key, out _);
            return Task.FromResult(false);
        }

        record.Attempts++;
        if (record.Attempts > 5)
        {
            _cache.TryRemove(key, out _);
            return Task.FromResult(false);
        }

        if (record.Code == otp.Trim())
        {
            record.IsVerified = true;
            return Task.FromResult(true);
        }

        return Task.FromResult(false);
    }

    public Task<bool> IsEmailVerifiedAsync(string email, string purpose = "Registration")
    {
        if (string.IsNullOrWhiteSpace(email)) return Task.FromResult(false);
        var cleanEmail = email.Trim().ToLowerInvariant();
        var key = $"{cleanEmail}:{purpose.ToLowerInvariant()}";

        if (_cache.TryGetValue(key, out var record))
        {
            return Task.FromResult(record.IsVerified && DateTime.UtcNow <= record.ExpiresAt);
        }

        return Task.FromResult(false);
    }
}
