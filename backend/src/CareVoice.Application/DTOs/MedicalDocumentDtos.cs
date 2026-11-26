using System;

namespace CareVoice.Application.DTOs;

public class MedicalDocumentDto
{
    public Guid Id { get; set; }
    public Guid OwnerMemberId { get; set; }
    public string OwnerMemberName { get; set; } = string.Empty;
    public Guid UploadedByUserId { get; set; }
    public string UploadedByName { get; set; } = string.Empty;
    public Guid? MedicineId { get; set; }
    public string? MedicineName { get; set; }
    public string Title { get; set; } = string.Empty;
    public string Category { get; set; } = "Prescription";
    public string? Notes { get; set; }
    public string OriginalFileName { get; set; } = string.Empty;
    public string ContentType { get; set; } = string.Empty;
    public long FileSizeBytes { get; set; }
    public DateTime CreatedAt { get; set; }
}
