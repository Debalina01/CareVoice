using System;
using CareVoice.Domain.Enums;

namespace CareVoice.Application.DTOs;

public class CreateInviteDto
{
    public string InvitedEmail { get; set; } = string.Empty;
    public bool CanSetReminders { get; set; } = true;
    public bool CanViewLogs { get; set; } = true;
}

public class InviteDto
{
    public Guid Id { get; set; }
    public Guid InviterMemberId { get; set; }
    public string InviterName { get; set; } = string.Empty;
    public string InvitedEmail { get; set; } = string.Empty;
    public string InviteToken { get; set; } = string.Empty;
    public InviteStatus Status { get; set; }
    public DateTime ExpiresAt { get; set; }
    public DateTime CreatedAt { get; set; }
}

public class AcceptInviteDto
{
    public string InviteToken { get; set; } = string.Empty;
}
