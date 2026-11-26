using System;
using System.Collections.Generic;
using CareVoice.Domain.Enums;

namespace CareVoice.Domain.Entities;

public class User
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public string Email { get; set; } = string.Empty;
    public string? Username { get; set; }
    public string PasswordHash { get; set; } = string.Empty;
    public string FullName { get; set; } = string.Empty;
    public string? PhoneNumber { get; set; }
    public string Role { get; set; } = "Caregiver";
    public string? RefreshToken { get; set; }
    public DateTime? RefreshTokenExpiryTime { get; set; }
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
    public DateTime UpdatedAt { get; set; } = DateTime.UtcNow;

    public ICollection<FamilyMember> FamilyMembers { get; set; } = new List<FamilyMember>();
    public ICollection<FamilyGroupMember> GroupMemberships { get; set; } = new List<FamilyGroupMember>();
    public ICollection<Device> Devices { get; set; } = new List<Device>();
    public ICollection<Notification> Notifications { get; set; } = new List<Notification>();
}

public class FamilyGroup
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public string FamilyCode { get; set; } = string.Empty;
    public string Name { get; set; } = string.Empty;
    public Guid CreatorUserId { get; set; }
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
    public DateTime UpdatedAt { get; set; } = DateTime.UtcNow;

    public User CreatorUser { get; set; } = null!;
    public ICollection<FamilyGroupMember> Members { get; set; } = new List<FamilyGroupMember>();
}

public class FamilyGroupMember
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public Guid FamilyGroupId { get; set; }
    public Guid UserId { get; set; }
    public string Role { get; set; } = "Member";
    public string Status { get; set; } = "Approved";
    public DateTime JoinedAt { get; set; } = DateTime.UtcNow;

    public FamilyGroup FamilyGroup { get; set; } = null!;
    public User User { get; set; } = null!;
}

public class FamilyMember
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public Guid UserId { get; set; }
    public Guid? LinkedUserId { get; set; }
    public string FullName { get; set; } = string.Empty;
    public string Relation { get; set; } = string.Empty;
    public string PreferredLanguage { get; set; } = "en";
    public string VoicePreference { get; set; } = "en-US-Standard-A";
    public bool IsDeleted { get; set; } = false;
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;

    public User User { get; set; } = null!;
    public User? LinkedUser { get; set; }
    public ICollection<FamilyPermission> GrantedPermissions { get; set; } = new List<FamilyPermission>();
    public ICollection<FamilyPermission> ReceivedPermissions { get; set; } = new List<FamilyPermission>();
    public ICollection<Medicine> Medicines { get; set; } = new List<Medicine>();
    public ICollection<MedicalDocument> MedicalDocuments { get; set; } = new List<MedicalDocument>();
}

public class FamilyPermission
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public Guid GranterMemberId { get; set; }
    public Guid GranteeMemberId { get; set; }
    public bool CanSetReminders { get; set; } = true;
    public bool CanViewLogs { get; set; } = true;
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;

    public FamilyMember GranterMember { get; set; } = null!;
    public FamilyMember GranteeMember { get; set; } = null!;
}

public class Invite
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public Guid InviterMemberId { get; set; }
    public string InvitedEmail { get; set; } = string.Empty;
    public string InviteToken { get; set; } = Guid.NewGuid().ToString("N");
    public InviteStatus Status { get; set; } = InviteStatus.Pending;
    public DateTime ExpiresAt { get; set; } = DateTime.UtcNow.AddDays(7);
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;

    public FamilyMember InviterMember { get; set; } = null!;
}

public class Device
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public Guid UserId { get; set; }
    public string DeviceToken { get; set; } = string.Empty;
    public DevicePlatform Platform { get; set; }
    public DateTime LastActiveAt { get; set; } = DateTime.UtcNow;

    public User User { get; set; } = null!;
}

public class Medicine
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public Guid OwnerMemberId { get; set; }
    public string Name { get; set; } = string.Empty;
    public string Dosage { get; set; } = string.Empty;
    public string? Instructions { get; set; }
    public FoodRelation FoodRelation { get; set; } = FoodRelation.NoRelation;
    public DateTime StartDate { get; set; }
    public DateTime? EndDate { get; set; }
    public bool IsDeleted { get; set; } = false;
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;

    public FamilyMember OwnerMember { get; set; } = null!;
    public ICollection<MedicineSchedule> Schedules { get; set; } = new List<MedicineSchedule>();
}

public class MedicineSchedule
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public Guid MedicineId { get; set; }
    public Guid TargetMemberId { get; set; }
    public Guid CreatedByMemberId { get; set; }
    public TimeSpan TimeOfDay { get; set; }
    public int DaysOfWeekMask { get; set; } = 127;
    public bool IsActive { get; set; } = true;
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;

    public Medicine Medicine { get; set; } = null!;
    public FamilyMember TargetMember { get; set; } = null!;
    public FamilyMember CreatedByMember { get; set; } = null!;
    public ICollection<MedicineLog> Logs { get; set; } = new List<MedicineLog>();
}

public class MedicineLog
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public Guid ScheduleId { get; set; }
    public Guid TargetMemberId { get; set; }
    public DateTime ScheduledTime { get; set; }
    public DateTime? ActionTime { get; set; }
    public LogStatus Status { get; set; }
    public Guid ClientLogId { get; set; }
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;

    public MedicineSchedule Schedule { get; set; } = null!;
    public FamilyMember TargetMember { get; set; } = null!;
}

public class Notification
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public Guid RecipientUserId { get; set; }
    public string Title { get; set; } = string.Empty;
    public string Body { get; set; } = string.Empty;
    public string? PayloadJson { get; set; }
    public bool IsRead { get; set; } = false;
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;

    public User RecipientUser { get; set; } = null!;
}

public class AuditLog
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public Guid? ActorUserId { get; set; }
    public string Action { get; set; } = string.Empty;
    public string EntityName { get; set; } = string.Empty;
    public string EntityId { get; set; } = string.Empty;
    public string? ChangesJson { get; set; }
    public DateTime Timestamp { get; set; } = DateTime.UtcNow;
}

public class MedicalDocument
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public Guid OwnerMemberId { get; set; }
    public Guid UploadedByUserId { get; set; }
    public Guid? MedicineId { get; set; }
    public string Title { get; set; } = string.Empty;
    public string Category { get; set; } = "Prescription";
    public string? Notes { get; set; }
    public string OriginalFileName { get; set; } = string.Empty;
    public string ContentType { get; set; } = "application/octet-stream";
    public long FileSizeBytes { get; set; }
    public string StorageProvider { get; set; } = "S3";
    public string StorageBucket { get; set; } = string.Empty;
    public string StorageObjectKey { get; set; } = string.Empty;
    public string Sha256Hash { get; set; } = string.Empty;
    public bool IsDeleted { get; set; } = false;
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
    public DateTime UpdatedAt { get; set; } = DateTime.UtcNow;

    public FamilyMember OwnerMember { get; set; } = null!;
    public User UploadedByUser { get; set; } = null!;
    public Medicine? Medicine { get; set; }
}
