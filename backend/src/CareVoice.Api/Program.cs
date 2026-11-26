using System;
using System.Text.Json.Serialization;
using Microsoft.AspNetCore.Builder;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Microsoft.OpenApi.Models;
using CareVoice.Application.DTOs;
using CareVoice.Application.Interfaces;
using CareVoice.Domain.Entities;
using CareVoice.Domain.Enums;
using CareVoice.Infrastructure;
using CareVoice.Infrastructure.Persistence;

var builder = WebApplication.CreateBuilder(args);

builder.Services.AddCors(options =>
{
    options.AddPolicy("AllowAll", policy =>
    {
        policy.AllowAnyOrigin()
              .AllowAnyMethod()
              .AllowAnyHeader()
              .WithExposedHeaders("Content-Disposition");
    });
});

builder.Services.AddControllers()
    .AddJsonOptions(options =>
    {
        options.JsonSerializerOptions.PropertyNameCaseInsensitive = true;
        options.JsonSerializerOptions.Converters.Add(new JsonStringEnumConverter());
    });

builder.Services.AddHttpClient();

builder.Services.AddEndpointsApiExplorer();

builder.Services.AddSwaggerGen(c =>
{
    c.SwaggerDoc("v1", new OpenApiInfo { Title = "CareVoice API", Version = "v1" });
    
    c.AddSecurityDefinition("Bearer", new OpenApiSecurityScheme
    {
        Description = "JWT Authorization header using the Bearer scheme. Example: \"Authorization: Bearer {token}\"",
        Name = "Authorization",
        In = ParameterLocation.Header,
        Type = SecuritySchemeType.ApiKey,
        Scheme = "Bearer"
    });

    c.AddSecurityRequirement(new OpenApiSecurityRequirement
    {
        {
            new OpenApiSecurityScheme
            {
                Reference = new OpenApiReference
                {
                    Type = ReferenceType.SecurityScheme,
                    Id = "Bearer"
                }
            },
            new string[] {}
        }
    });
});

builder.Services.AddInfrastructure(builder.Configuration);

var app = builder.Build();

if (app.Environment.IsDevelopment())
{
    app.UseDeveloperExceptionPage();
    app.UseSwagger();
    app.UseSwaggerUI();
}

app.UseRouting();

app.UseCors("AllowAll");

app.UseAuthentication();
app.UseAuthorization();

app.MapControllers();

app.MapGet("/", () => Results.Ok(new
{
    service = "CareVoice API",
    status = "Healthy",
    version = "1.0.0",
    health = "/api/auth/health"
}));

if (!EF.IsDesignTime)
{
using (var scope = app.Services.CreateScope())
{
    var authService = scope.ServiceProvider.GetRequiredService<IAuthService>();
    var dbContext = scope.ServiceProvider.GetRequiredService<CareVoiceDbContext>();

    if (!dbContext.Database.IsInMemory())
    {
        await dbContext.Database.MigrateAsync();
    }

    if (app.Environment.IsDevelopment())
    {
        try
        {
            await authService.RegisterAsync(new RegisterRequestDto(
                "caregiver@carevoice.app",
                "Password123!",
                "Primary Caregiver",
                "+1234567890",
                "Caregiver"
            ));
        }
        catch (InvalidOperationException)
        {
        }

        try
        {
            await authService.RegisterAsync(new RegisterRequestDto(
                "patient@carevoice.app",
                "Password123!",
                "John Doe (Patient)",
                "+1987654321",
                "Individual"
            ));
        }
        catch (InvalidOperationException)
        {
        }

        var caregiver = await dbContext.Users.FirstOrDefaultAsync(u => u.Email == "caregiver@carevoice.app");
        if (caregiver != null && !await dbContext.FamilyMembers.AnyAsync(fm => fm.UserId == caregiver.Id && fm.Relation == "Parent"))
        {
            dbContext.FamilyMembers.Add(new FamilyMember
            {
                Id = Guid.NewGuid(),
                UserId = caregiver.Id,
                FullName = "Papa",
                Relation = "Parent",
                PreferredLanguage = "en",
                VoicePreference = "en-US-Standard-A",
                IsDeleted = false,
                CreatedAt = DateTime.UtcNow
            });
            await dbContext.SaveChangesAsync();
        }

        if (caregiver != null)
        {
            var caregiverSelf = await dbContext.FamilyMembers.FirstOrDefaultAsync(fm => fm.UserId == caregiver.Id && fm.Relation == "Self");
            var papaMember = await dbContext.FamilyMembers.FirstOrDefaultAsync(fm => fm.UserId == caregiver.Id && fm.Relation == "Parent");

            if (caregiverSelf != null && !await dbContext.Medicines.AnyAsync(m => m.OwnerMemberId == caregiverSelf.Id))
            {
                var bpMed = new Medicine
                {
                    Id = Guid.NewGuid(),
                    OwnerMemberId = caregiverSelf.Id,
                    Name = "bp",
                    Dosage = "1 tablet",
                    Instructions = "food",
                    FoodRelation = FoodRelation.NoRelation,
                    StartDate = DateTime.UtcNow.Date.AddDays(-7),
                    EndDate = DateTime.UtcNow.Date.AddDays(30),
                    IsDeleted = false,
                    CreatedAt = DateTime.UtcNow
                };
                dbContext.Medicines.Add(bpMed);
                await dbContext.SaveChangesAsync();

                dbContext.MedicineSchedules.Add(new MedicineSchedule
                {
                    Id = Guid.NewGuid(),
                    MedicineId = bpMed.Id,
                    TargetMemberId = caregiverSelf.Id,
                    CreatedByMemberId = caregiverSelf.Id,
                    TimeOfDay = new TimeSpan(16, 5, 0),
                    DaysOfWeekMask = 127,
                    IsActive = true,
                    CreatedAt = DateTime.UtcNow
                });

                dbContext.MedicineSchedules.Add(new MedicineSchedule
                {
                    Id = Guid.NewGuid(),
                    MedicineId = bpMed.Id,
                    TargetMemberId = caregiverSelf.Id,
                    CreatedByMemberId = caregiverSelf.Id,
                    TimeOfDay = new TimeSpan(DateTime.UtcNow.Hour, DateTime.UtcNow.Minute, 0),
                    DaysOfWeekMask = 127,
                    IsActive = true,
                    CreatedAt = DateTime.UtcNow
                });

                if (papaMember != null)
                {
                    dbContext.MedicineSchedules.Add(new MedicineSchedule
                    {
                        Id = Guid.NewGuid(),
                        MedicineId = bpMed.Id,
                        TargetMemberId = papaMember.Id,
                        CreatedByMemberId = caregiverSelf.Id,
                        TimeOfDay = new TimeSpan(9, 0, 0),
                        DaysOfWeekMask = 127,
                        IsActive = true,
                        CreatedAt = DateTime.UtcNow
                    });
                }

                await dbContext.SaveChangesAsync();
            }
        }
    }
}
}

var customPort = Environment.GetEnvironmentVariable("PORT");
if (!string.IsNullOrEmpty(customPort))
{
    app.Urls.Add($"http://0.0.0.0:{customPort}");
}

app.Run();
