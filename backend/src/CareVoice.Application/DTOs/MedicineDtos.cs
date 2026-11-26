using System;
using System.Collections.Generic;
using CareVoice.Domain.Enums;

namespace CareVoice.Application.DTOs;

public class MedicineDto
{
    public Guid Id { get; set; }
    public Guid OwnerMemberId { get; set; }
    public string OwnerMemberName { get; set; } = string.Empty;
    public string Name { get; set; } = string.Empty;
    public string Dosage { get; set; } = string.Empty;
    public string? Instructions { get; set; }
    public FoodRelation FoodRelation { get; set; }
    public DateTime StartDate { get; set; }
    public DateTime? EndDate { get; set; }
    public bool IsDeleted { get; set; }
    public DateTime CreatedAt { get; set; }
    public List<ScheduleDto> Schedules { get; set; } = new();
}

public class CreateMedicineDto
{
    public Guid OwnerMemberId { get; set; }
    public string Name { get; set; } = string.Empty;
    public string Dosage { get; set; } = string.Empty;
    public string? Instructions { get; set; }
    public FoodRelation FoodRelation { get; set; } = FoodRelation.NoRelation;
    public DateTime StartDate { get; set; } = DateTime.UtcNow;
    public DateTime? EndDate { get; set; }
}

public class UpdateMedicineDto
{
    public string Name { get; set; } = string.Empty;
    public string Dosage { get; set; } = string.Empty;
    public string? Instructions { get; set; }
    public FoodRelation FoodRelation { get; set; }
    public DateTime StartDate { get; set; }
    public DateTime? EndDate { get; set; }
}

public class ScheduleDto
{
    public Guid Id { get; set; }
    public Guid MedicineId { get; set; }
    public string MedicineName { get; set; } = string.Empty;
    public string Dosage { get; set; } = string.Empty;
    public string? Instructions { get; set; }
    public FoodRelation FoodRelation { get; set; }
    public Guid TargetMemberId { get; set; }
    public string TargetMemberName { get; set; } = string.Empty;
    public Guid CreatedByMemberId { get; set; }
    public string CreatedByName { get; set; } = string.Empty;
    public string TimeOfDay { get; set; } = "08:00";
    public int DaysOfWeekMask { get; set; } = 127;
    public bool IsActive { get; set; }
    public DateTime CreatedAt { get; set; }
}

public class CreateScheduleDto
{
    public Guid MedicineId { get; set; }
    public Guid TargetMemberId { get; set; }
    public string TimeOfDay { get; set; } = "08:00";
    public int DaysOfWeekMask { get; set; } = 127;
}

public class UpdateScheduleDto
{
    public string TimeOfDay { get; set; } = "08:00";
    public int DaysOfWeekMask { get; set; } = 127;
    public bool IsActive { get; set; } = true;
}

public class DoseSyncDto
{
    public Guid ScheduleId { get; set; }
    public Guid MedicineId { get; set; }
    public string MedicineName { get; set; } = string.Empty;
    public string Dosage { get; set; } = string.Empty;
    public string? Instructions { get; set; }
    public FoodRelation FoodRelation { get; set; }
    public Guid TargetMemberId { get; set; }
    public string TargetMemberName { get; set; } = string.Empty;
    public DateTime ScheduledTimeUtc { get; set; }
    public string TimeOfDay { get; set; } = string.Empty;
    public string PreferredLanguage { get; set; } = "en";
    public string VoicePreference { get; set; } = "en-US-Standard-A";
}

public class SyncActionRequestDto
{
    public Guid ClientLogId { get; set; }
    public Guid ScheduleId { get; set; }
    public Guid TargetMemberId { get; set; }
    public DateTime ScheduledTime { get; set; }
    public DateTime? ActionTime { get; set; }
    public LogStatus Status { get; set; }
}

public class SyncActionResponseDto
{
    public Guid ClientLogId { get; set; }
    public bool Success { get; set; }
    public string Message { get; set; } = string.Empty;
}

public class DoseHistoryDto
{
    public Guid LogId { get; set; }
    public Guid ClientLogId { get; set; }
    public Guid ScheduleId { get; set; }
    public string MedicineName { get; set; } = string.Empty;
    public string Dosage { get; set; } = string.Empty;
    public Guid TargetMemberId { get; set; }
    public string TargetMemberName { get; set; } = string.Empty;
    public DateTime ScheduledTime { get; set; }
    public DateTime? ActionTime { get; set; }
    public LogStatus Status { get; set; }
    public DateTime CreatedAt { get; set; }
}
