using System;
using System.Collections.Generic;
using System.Threading.Tasks;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Logging.Abstractions;
using Xunit;
using CareVoice.Infrastructure.Services;

namespace CareVoice.Tests;

public class EmailOtpServiceTests
{
    private IConfiguration CreateConfig(Dictionary<string, string?> values)
    {
        return new ConfigurationBuilder()
            .AddInMemoryCollection(values)
            .Build();
    }

    [Fact]
    public async Task SendOtpDetailedAsync_WithLiveCredentials_ConnectsToSmtp()
    {
        var config = CreateConfig(new Dictionary<string, string?>
        {
            { "EmailSettings:SenderEmail", "anirbanmandal666@gmail.com" },
            { "EmailSettings:Password", "oheujnmltgvwfyjo" },
            { "EmailSettings:SmtpServer", "smtp.gmail.com" },
            { "EmailSettings:SmtpPort", "465" }
        });

        var service = new EmailOtpService(config, NullLogger<EmailOtpService>.Instance);
        var result = await service.SendOtpDetailedAsync("anirbanmandal666@gmail.com", "RegistrationTest");

        Assert.NotNull(result);
        Assert.NotNull(result.Message);
        Console.WriteLine($"Live SMTP Test Result: Delivered={result.IsDeliveredViaSmtp}, Mode={result.DeliveryMode}, Message={result.Message}");
    }

    [Fact]
    public async Task VerifyOtpAsync_WhenCodeMatches_ReturnsTrue()
    {
        var config = CreateConfig(new Dictionary<string, string?>
        {
            { "EmailSettings:SenderEmail", "anirbanmandal666@gmail.com" },
            { "EmailSettings:Password", "" }
        });

        var service = new EmailOtpService(config, NullLogger<EmailOtpService>.Instance);
        const string testEmail = "verifytest@example.com";
        const string testOtp = "123456";

        await service.SendOtpDetailedAsync(testEmail, "Registration", testOtp);

        var isVerified = await service.VerifyOtpAsync(testEmail, testOtp, "Registration");
        Assert.True(isVerified);

        var checkVerified = await service.IsEmailVerifiedAsync(testEmail, "Registration");
        Assert.True(checkVerified);
    }

    [Fact]
    public async Task VerifyOtpAsync_WhenCodeIncorrect_ReturnsFalse()
    {
        var config = CreateConfig(new Dictionary<string, string?>
        {
            { "EmailSettings:SenderEmail", "anirbanmandal666@gmail.com" },
            { "EmailSettings:Password", "" }
        });

        var service = new EmailOtpService(config, NullLogger<EmailOtpService>.Instance);
        const string testEmail = "wrongcode@example.com";
        const string testOtp = "654321";

        await service.SendOtpDetailedAsync(testEmail, "Registration", testOtp);

        var isVerified = await service.VerifyOtpAsync(testEmail, "000000", "Registration");
        Assert.False(isVerified);
    }

    [Fact]
    public async Task VerifyOtpAsync_WhenAttemptsExceedFive_InvalidatesCode()
    {
        var config = CreateConfig(new Dictionary<string, string?>
        {
            { "EmailSettings:SenderEmail", "anirbanmandal666@gmail.com" },
            { "EmailSettings:Password", "" }
        });

        var service = new EmailOtpService(config, NullLogger<EmailOtpService>.Instance);
        const string testEmail = "rate_limit@example.com";
        const string testOtp = "777888";

        await service.SendOtpDetailedAsync(testEmail, "Registration", testOtp);

        for (int i = 0; i < 5; i++)
        {
            var failed = await service.VerifyOtpAsync(testEmail, "999999", "Registration");
            Assert.False(failed);
        }

        var sixthAttempt = await service.VerifyOtpAsync(testEmail, testOtp, "Registration");
        Assert.False(sixthAttempt);
    }
}
