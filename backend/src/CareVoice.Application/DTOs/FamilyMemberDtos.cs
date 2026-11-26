using System;

namespace CareVoice.Application.DTOs;

public class FamilyMemberDto
{
    public Guid Id { get; set; }
    public Guid UserId { get; set; }
    public Guid? LinkedUserId { get; set; }
    public string FullName { get; set; } = string.Empty;
    public string Relation { get; set; } = string.Empty;
    public string PreferredLanguage { get; set; } = "en";
    public string VoicePreference { get; set; } = "en-US-Standard-A";
    public bool IsSelf { get; set; }
    public bool CanSetReminders { get; set; } = true;
    public bool CanViewLogs { get; set; } = true;
    public DateTime CreatedAt { get; set; }
    public string? Username { get; set; }
    public bool HasLoginCredentials { get; set; }
}

public class CreateFamilyMemberDto
{
    public string FullName { get; set; } = string.Empty;
    public string Relation { get; set; } = string.Empty;
    public string PreferredLanguage { get; set; } = "en";
    public string VoicePreference { get; set; } = "en-US-Standard-A";
    public string? Username { get; set; }
    public string? Password { get; set; }
}

public class UpdateFamilyMemberDto
{
    public string FullName { get; set; } = string.Empty;
    public string Relation { get; set; } = string.Empty;
    public string PreferredLanguage { get; set; } = "en";
    public string VoicePreference { get; set; } = "en-US-Standard-A";
}
