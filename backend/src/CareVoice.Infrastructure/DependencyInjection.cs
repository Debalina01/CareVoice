using System;
using System.Text;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.IdentityModel.Tokens;
using CareVoice.Application.Interfaces;
using CareVoice.Infrastructure.Authentication;
using CareVoice.Infrastructure.Persistence;
using CareVoice.Infrastructure.Services;

namespace CareVoice.Infrastructure;

public static class DependencyInjection
{
    public static string NormalizePostgresConnectionString(string raw)
    {
        if (string.IsNullOrWhiteSpace(raw)) return raw;
        var trimmed = raw.Trim();
        if (!trimmed.StartsWith("postgres://", StringComparison.OrdinalIgnoreCase) &&
            !trimmed.StartsWith("postgresql://", StringComparison.OrdinalIgnoreCase))
        {
            return trimmed;
        }

        var uri = new Uri(trimmed);
        var userInfo = uri.UserInfo.Split(':', 2);
        var username = Uri.UnescapeDataString(userInfo[0]);
        var password = userInfo.Length > 1 ? Uri.UnescapeDataString(userInfo[1]) : string.Empty;
        var database = uri.AbsolutePath.TrimStart('/');
        var port = uri.Port > 0 ? uri.Port : 5432;
        var isLocal = uri.Host.Equals("localhost", StringComparison.OrdinalIgnoreCase) ||
                      uri.Host.Equals("127.0.0.1", StringComparison.OrdinalIgnoreCase) ||
                      uri.Host.EndsWith(".railway.internal", StringComparison.OrdinalIgnoreCase);

        var sslMode = isLocal ? "Prefer" : "Require";
        return $"Host={uri.Host};Port={port};Database={database};Username={username};Password={password};SSL Mode={sslMode};Trust Server Certificate=true";
    }

    public static IServiceCollection AddInfrastructure(this IServiceCollection services, IConfiguration configuration)
    {
        AppContext.SetSwitch("Npgsql.EnableLegacyTimestampBehavior", true);

        var databaseUrl = Environment.GetEnvironmentVariable("DATABASE_URL")
            ?? configuration["DATABASE_URL"];
        var defaultConnection = configuration.GetConnectionString("DefaultConnection");
        var useInMemory = string.IsNullOrWhiteSpace(databaseUrl) &&
            configuration.GetValue<bool>("UseInMemoryDatabase", false);

        var rawConnection = !string.IsNullOrWhiteSpace(databaseUrl)
            ? databaseUrl
            : (defaultConnection ?? string.Empty);

        services.AddDbContext<CareVoiceDbContext>(options =>
        {
            if (useInMemory)
            {
                options.UseInMemoryDatabase("CareVoiceDevDb");
            }
            else
            {
                var pgConn = NormalizePostgresConnectionString(rawConnection);
                options.UseNpgsql(pgConn, b => b.MigrationsAssembly(typeof(CareVoiceDbContext).Assembly.FullName));
            }
        });

        services.AddScoped<IJwtTokenGenerator, JwtTokenGenerator>();
        services.AddScoped<IAuthService, AuthService>();
        services.AddScoped<IPermissionService, PermissionService>();
        services.AddScoped<IFamilyMemberService, FamilyMemberService>();
        services.AddScoped<IFamilyGroupService, FamilyGroupService>();
        services.AddScoped<IInviteService, InviteService>();
        services.AddScoped<IMedicineService, MedicineService>();
        services.AddScoped<IScheduleService, ScheduleService>();
        services.AddScoped<ILogService, LogService>();
        services.AddScoped<IMissedReminderRelayService, MissedReminderRelayService>();
        services.AddScoped<ISerbomAiService, SerbomAiService>();
        services.AddScoped<IMedicalDocumentService, MedicalDocumentService>();
        services.AddSingleton<IObjectStorageService, S3ObjectStorageService>();
        services.AddSingleton<IEmailOtpService, EmailOtpService>();

        var secret = Authentication.JwtTokenGenerator.ResolveSigningSecret(configuration);
        var issuer = configuration["JwtSettings:Issuer"] ?? "CareVoiceApi";
        var audience = configuration["JwtSettings:Audience"] ?? "CareVoiceClient";

        services.AddAuthentication(options =>
        {
            options.DefaultAuthenticateScheme = JwtBearerDefaults.AuthenticationScheme;
            options.DefaultChallengeScheme = JwtBearerDefaults.AuthenticationScheme;
        })
        .AddJwtBearer(options =>
        {
            options.RequireHttpsMetadata = false;
            options.SaveToken = true;
            options.TokenValidationParameters = new TokenValidationParameters
            {
                ValidateIssuer = true,
                ValidIssuer = issuer,
                ValidateAudience = true,
                ValidAudience = audience,
                ValidateIssuerSigningKey = true,
                IssuerSigningKey = new SymmetricSecurityKey(Encoding.UTF8.GetBytes(secret)),
                ClockSkew = System.TimeSpan.Zero
            };
        });

        return services;
    }
}
