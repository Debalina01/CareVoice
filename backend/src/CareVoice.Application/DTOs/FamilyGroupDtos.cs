using System;
using System.Collections.Generic;

namespace CareVoice.Application.DTOs;

public class CreateFamilyGroupDto
{
    public string Name { get; set; } = string.Empty;
}

public class JoinFamilyGroupDto
{
    public string FamilyCode { get; set; } = string.Empty;
}

public class JoinFamilyGroupWithOtpDto
{
    public string FamilyCode { get; set; } = string.Empty;
    public string? Otp { get; set; }
}

public class FamilyGroupMemberDto
{
    public Guid Id { get; set; }
    public Guid UserId { get; set; }
    public string FullName { get; set; } = string.Empty;
    public string Email { get; set; } = string.Empty;
    public string Role { get; set; } = "Member";
    public string Status { get; set; } = "Approved";
    public DateTime JoinedAt { get; set; }
}

public class FamilyGroupDto
{
    public Guid Id { get; set; }
    public string FamilyCode { get; set; } = string.Empty;
    public string Name { get; set; } = string.Empty;
    public Guid CreatorUserId { get; set; }
    public string CreatorName { get; set; } = string.Empty;
    public bool IsCreator { get; set; }
    public int MembersCount { get; set; }
    public string UserMembershipStatus { get; set; } = "Approved";
    public DateTime CreatedAt { get; set; }
    public List<FamilyGroupMemberDto> Members { get; set; } = new();
    public List<FamilyGroupMemberDto> PendingRequests { get; set; } = new();
}

public class SharedFamilyUpdateDto
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public Guid FamilyGroupId { get; set; }
    public string Type { get; set; } = "ScheduleUpdate";
    public string Title { get; set; } = string.Empty;
    public string TitleBn { get; set; } = string.Empty;
    public string Description { get; set; } = string.Empty;
    public string DescriptionBn { get; set; } = string.Empty;
    public string ActorName { get; set; } = string.Empty;
    public DateTime Timestamp { get; set; } = DateTime.UtcNow;
}
