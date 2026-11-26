using System;
using System.Collections.Generic;
using System.IO;
using System.Threading;
using System.Threading.Tasks;
using CareVoice.Application.DTOs;

namespace CareVoice.Application.Interfaces;

public sealed record UploadMedicalDocumentInput(
    Guid OwnerMemberId,
    Guid? MedicineId,
    string Title,
    string Category,
    string? Notes,
    string OriginalFileName,
    string ContentType,
    long FileSizeBytes,
    Stream FileStream);

public sealed record MedicalDocumentFileResult(
    Stream Content,
    string ContentType,
    string FileName,
    long FileSizeBytes);

public interface IMedicalDocumentService
{
    Task<IEnumerable<MedicalDocumentDto>> GetDocumentsAsync(
        Guid callerUserId,
        Guid? memberId = null,
        Guid? medicineId = null,
        CancellationToken cancellationToken = default);

    Task<MedicalDocumentDto?> GetDocumentByIdAsync(
        Guid callerUserId,
        Guid documentId,
        CancellationToken cancellationToken = default);

    Task<MedicalDocumentDto> UploadDocumentAsync(
        Guid callerUserId,
        UploadMedicalDocumentInput input,
        CancellationToken cancellationToken = default);

    Task<MedicalDocumentFileResult?> GetDocumentFileAsync(
        Guid callerUserId,
        Guid documentId,
        bool isDownload,
        CancellationToken cancellationToken = default);

    Task<bool> DeleteDocumentAsync(
        Guid callerUserId,
        Guid documentId,
        CancellationToken cancellationToken = default);
}
