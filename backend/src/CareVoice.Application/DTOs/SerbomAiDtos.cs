using System;
using System.Collections.Generic;
using CareVoice.Domain.Enums;

namespace CareVoice.Application.DTOs;

public class SerbomAiRequestDto
{
    public string Message { get; set; } = string.Empty;
    public string Language { get; set; } = "en";
    public Guid? TargetMemberId { get; set; }
    public ExtractedScheduleDto? AccumulatedSchedule { get; set; }
}

public class ExtractedScheduleDto
{
    public string MedicineName { get; set; } = string.Empty;
    public string Dosage { get; set; } = string.Empty;
    public FoodRelation FoodRelation { get; set; } = FoodRelation.NoRelation;
    public string? Instructions { get; set; }
    public List<string> TimesOfDay { get; set; } = new();
    public int DaysOfWeekMask { get; set; } = 127;
    public int? DurationDays { get; set; }
    public DateTime? StartDate { get; set; }
    public DateTime? EndDate { get; set; }
    public Guid? TargetMemberId { get; set; }
    public string? TargetMemberName { get; set; }
}

public class SerbomAiResponseDto
{
    public string Intent { get; set; } = "CreateSchedule";
    public string Status { get; set; } = "ReadyForConfirmation";
    public string ReplyMessage { get; set; } = string.Empty;
    public string ReplyMessageBn { get; set; } = string.Empty;
    public ExtractedScheduleDto? ExtractedSchedule { get; set; }
    public Guid? ExistingMedicineId { get; set; }
    public Guid? ExistingScheduleId { get; set; }
    public List<string> MissingFields { get; set; } = new();
    public string? FollowUpQuestion { get; set; }
    public string? FollowUpQuestionBn { get; set; }
}

public class ConfirmScheduleDto
{
    public Guid TargetMemberId { get; set; }
    public string MedicineName { get; set; } = string.Empty;
    public string Dosage { get; set; } = string.Empty;
    public string? Instructions { get; set; }
    public FoodRelation FoodRelation { get; set; } = FoodRelation.NoRelation;
    public List<string> TimesOfDay { get; set; } = new();
    public int DaysOfWeekMask { get; set; } = 127;
    public DateTime? StartDate { get; set; }
    public DateTime? EndDate { get; set; }
}

public class ConfirmScheduleResponseDto
{
    public Guid MedicineId { get; set; }
    public List<Guid> ScheduleIds { get; set; } = new();
    public string Message { get; set; } = string.Empty;
    public string MessageBn { get; set; } = string.Empty;
}

public class SerbomAiStatusDto
{
    public string Status { get; set; } = "Online";
    public string ActiveEngine { get; set; } = "LocalNlu";
    public bool HasApiKey { get; set; }
    public string Model { get; set; } = "gemini-1.5-flash";
    public List<string> SupportedLanguages { get; set; } = new() { "en", "bn" };
    public string Description { get; set; } = "Serbom AI bilingual medical scheduling and reminder assistant";
}

public class UpdateAiConfigRequestDto
{
    public string? ApiKey { get; set; }
    public string? Provider { get; set; } = "Gemini";
    public string? Model { get; set; } = "gemini-1.5-flash";
}

public class SarvamTtsRequestDto
{
    public string Text { get; set; } = string.Empty;
    public string TargetLanguageCode { get; set; } = "bn-IN";
    public string Speaker { get; set; } = "meera";
}
