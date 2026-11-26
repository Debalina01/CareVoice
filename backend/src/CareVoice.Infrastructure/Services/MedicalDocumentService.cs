using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text.RegularExpressions;
using System.Threading;
using System.Threading.Tasks;
using CareVoice.Application.DTOs;
using CareVoice.Application.Interfaces;
using CareVoice.Domain.Entities;
using CareVoice.Infrastructure.Persistence;
using Microsoft.EntityFrameworkCore;

namespace CareVoice.Infrastructure.Services;

public class MedicalDocumentService : IMedicalDocumentService
{
    public const long MaxFileSizeBytes = 10 * 1024 * 1024;

    private static readonly Dictionary<string, string> AllowedExtensionMimeTypes = new(StringComparer.OrdinalIgnoreCase)
    {
        [".pdf"] = "application/pdf",
        [".png"] = "image/png",
        [".jpg"] = "image/jpeg",
        [".jpeg"] = "image/jpeg",
        [".webp"] = "image/webp"
    };

    private static readonly HashSet<string> AllowedCategories = new(StringComparer.OrdinalIgnoreCase)
    {
        "Prescription",
        "Lab Report",
        "Doctor Note",
        "Vaccination Record",
        "Other"
    };

    private readonly CareVoiceDbContext _dbContext;
    private readonly IPermissionService _permissionService;
    private readonly IObjectStorageService _objectStorage;

    public MedicalDocumentService(
        CareVoiceDbContext dbContext,
        IPermissionService permissionService,
        IObjectStorageService objectStorage)
    {
        _dbContext = dbContext;
        _permissionService = permissionService;
        _objectStorage = objectStorage;
    }

    public async Task<IEnumerable<MedicalDocumentDto>> GetDocumentsAsync(
        Guid callerUserId,
        Guid? memberId = null,
        Guid? medicineId = null,
        CancellationToken cancellationToken = default)
    {
        if (memberId.HasValue)
        {
            var canView = await _permissionService.CanViewLogsAsync(callerUserId, memberId.Value);
            if (!canView)
            {
                throw new UnauthorizedAccessException("You do not have permission to view files for this family member.");
            }
        }

        var query = _dbContext.MedicalDocuments
            .AsNoTracking()
            .Include(d => d.OwnerMember)
            .Include(d => d.UploadedByUser)
            .Include(d => d.Medicine)
            .Where(d => !d.IsDeleted);

        if (memberId.HasValue)
        {
            query = query.Where(d => d.OwnerMemberId == memberId.Value);
        }

        if (medicineId.HasValue)
        {
            query = query.Where(d => d.MedicineId == medicineId.Value);
        }

        var candidates = await query
            .OrderByDescending(d => d.CreatedAt)
            .ToListAsync(cancellationToken);

        var authorized = new List<MedicalDocumentDto>();
        var permissionCache = new Dictionary<Guid, bool>();

        foreach (var doc in candidates)
        {
            if (!permissionCache.TryGetValue(doc.OwnerMemberId, out var allowed))
            {
                allowed = await _permissionService.CanViewLogsAsync(callerUserId, doc.OwnerMemberId);
                permissionCache[doc.OwnerMemberId] = allowed;
            }

            if (allowed)
            {
                authorized.Add(MapToDto(doc));
            }
        }

        return authorized;
    }

    public async Task<MedicalDocumentDto?> GetDocumentByIdAsync(
        Guid callerUserId,
        Guid documentId,
        CancellationToken cancellationToken = default)
    {
        var doc = await _dbContext.MedicalDocuments
            .AsNoTracking()
            .Include(d => d.OwnerMember)
            .Include(d => d.UploadedByUser)
            .Include(d => d.Medicine)
            .FirstOrDefaultAsync(d => d.Id == documentId && !d.IsDeleted, cancellationToken);

        if (doc == null) return null;

        var allowed = await _permissionService.CanViewLogsAsync(callerUserId, doc.OwnerMemberId);
        if (!allowed)
        {
            throw new UnauthorizedAccessException("You do not have permission to access this medical document.");
        }

        return MapToDto(doc);
    }

    public async Task<MedicalDocumentDto> UploadDocumentAsync(
        Guid callerUserId,
        UploadMedicalDocumentInput input,
        CancellationToken cancellationToken = default)
    {
        if (input.FileSizeBytes <= 0)
        {
            throw new ArgumentException("Please choose a non-empty file to upload.");
        }

        if (input.FileSizeBytes > MaxFileSizeBytes)
        {
            throw new ArgumentException("The selected file is larger than the 10 MB limit.");
        }

        var canUpload = await _permissionService.CanSetRemindersAsync(callerUserId, input.OwnerMemberId);
        if (!canUpload)
        {
            throw new UnauthorizedAccessException("You do not have permission to upload documents for this family member.");
        }

        var ownerMember = await _dbContext.FamilyMembers
            .FirstOrDefaultAsync(fm => fm.Id == input.OwnerMemberId && !fm.IsDeleted, cancellationToken);
        if (ownerMember == null)
        {
            throw new ArgumentException("Selected family member could not be found.");
        }

        if (input.MedicineId.HasValue)
        {
            var medicineExists = await _dbContext.Medicines
                .AnyAsync(m => m.Id == input.MedicineId.Value && !m.IsDeleted, cancellationToken);
            if (!medicineExists)
            {
                throw new ArgumentException("Selected medicine could not be found.");
            }
        }

        var safeOriginalName = Path.GetFileName(input.OriginalFileName ?? string.Empty).Trim();
        if (string.IsNullOrWhiteSpace(safeOriginalName))
        {
            throw new ArgumentException("File name is required.");
        }

        var extension = Path.GetExtension(safeOriginalName);
        if (string.IsNullOrWhiteSpace(extension) || !AllowedExtensionMimeTypes.TryGetValue(extension, out var canonicalMime))
        {
            throw new ArgumentException("Only PDF, PNG, JPG, JPEG, and WEBP files are supported.");
        }

        var normalizedCategory = AllowedCategories.FirstOrDefault(
            c => c.Equals(input.Category?.Trim(), StringComparison.OrdinalIgnoreCase)) ?? "Prescription";

        var documentId = Guid.NewGuid();
        var cleanTitle = string.IsNullOrWhiteSpace(input.Title)
            ? Path.GetFileNameWithoutExtension(safeOriginalName)
            : input.Title.Trim();

        var sanitizedSlug = Regex.Replace(Path.GetFileNameWithoutExtension(safeOriginalName), @"[^a-zA-Z0-9_-]+", "-").Trim('-');
        if (string.IsNullOrWhiteSpace(sanitizedSlug)) sanitizedSlug = "document";
        if (sanitizedSlug.Length > 40) sanitizedSlug = sanitizedSlug[..40];

        var objectKey = $"medical-documents/{ownerMember.Id:N}/{documentId:N}_{sanitizedSlug}{extension.ToLowerInvariant()}";

        var uploadResult = await _objectStorage.UploadPrivateAsync(
            input.FileStream,
            objectKey,
            canonicalMime,
            input.FileSizeBytes,
            cancellationToken);

        var entity = new MedicalDocument
        {
            Id = documentId,
            OwnerMemberId = ownerMember.Id,
            UploadedByUserId = callerUserId,
            MedicineId = input.MedicineId,
            Title = cleanTitle,
            Category = normalizedCategory,
            Notes = string.IsNullOrWhiteSpace(input.Notes) ? null : input.Notes.Trim(),
            OriginalFileName = safeOriginalName,
            ContentType = canonicalMime,
            FileSizeBytes = input.FileSizeBytes,
            StorageProvider = uploadResult.Provider,
            StorageBucket = uploadResult.BucketName,
            StorageObjectKey = uploadResult.ObjectKey,
            Sha256Hash = uploadResult.Sha256Hash,
            IsDeleted = false,
            CreatedAt = DateTime.UtcNow,
            UpdatedAt = DateTime.UtcNow
        };

        _dbContext.MedicalDocuments.Add(entity);
        _dbContext.AuditLogs.Add(new AuditLog
        {
            Id = Guid.NewGuid(),
            ActorUserId = callerUserId,
            Action = "UploadMedicalDocument",
            EntityName = nameof(MedicalDocument),
            EntityId = entity.Id.ToString(),
            ChangesJson = $"{{\"ownerMemberId\":\"{ownerMember.Id}\",\"category\":\"{normalizedCategory}\",\"fileSize\":{input.FileSizeBytes}}}",
            Timestamp = DateTime.UtcNow
        });

        await _dbContext.SaveChangesAsync(cancellationToken);

        var loaded = await _dbContext.MedicalDocuments
            .AsNoTracking()
            .Include(d => d.OwnerMember)
            .Include(d => d.UploadedByUser)
            .Include(d => d.Medicine)
            .FirstAsync(d => d.Id == entity.Id, cancellationToken);

        return MapToDto(loaded);
    }

    public async Task<MedicalDocumentFileResult?> GetDocumentFileAsync(
        Guid callerUserId,
        Guid documentId,
        bool isDownload,
        CancellationToken cancellationToken = default)
    {
        var doc = await _dbContext.MedicalDocuments
            .AsNoTracking()
            .FirstOrDefaultAsync(d => d.Id == documentId && !d.IsDeleted, cancellationToken);

        if (doc == null) return null;

        var allowed = await _permissionService.CanViewLogsAsync(callerUserId, doc.OwnerMemberId);
        if (!allowed)
        {
            throw new UnauthorizedAccessException("You do not have permission to access this medical document.");
        }

        var downloaded = await _objectStorage.DownloadPrivateAsync(doc.StorageObjectKey, cancellationToken);
        if (downloaded == null) return null;

        _dbContext.AuditLogs.Add(new AuditLog
        {
            Id = Guid.NewGuid(),
            ActorUserId = callerUserId,
            Action = isDownload ? "DownloadMedicalDocument" : "ViewMedicalDocument",
            EntityName = nameof(MedicalDocument),
            EntityId = doc.Id.ToString(),
            Timestamp = DateTime.UtcNow
        });
        await _dbContext.SaveChangesAsync(cancellationToken);

        return new MedicalDocumentFileResult(
            downloaded.Content,
            doc.ContentType,
            doc.OriginalFileName,
            doc.FileSizeBytes);
    }

    public async Task<bool> DeleteDocumentAsync(
        Guid callerUserId,
        Guid documentId,
        CancellationToken cancellationToken = default)
    {
        var doc = await _dbContext.MedicalDocuments
            .FirstOrDefaultAsync(d => d.Id == documentId && !d.IsDeleted, cancellationToken);

        if (doc == null) return false;

        var canModify = doc.UploadedByUserId == callerUserId ||
                        await _permissionService.CanSetRemindersAsync(callerUserId, doc.OwnerMemberId);
        if (!canModify)
        {
            throw new UnauthorizedAccessException("You do not have permission to remove this medical document.");
        }

        await _objectStorage.DeleteAsync(doc.StorageObjectKey, cancellationToken);
        doc.IsDeleted = true;
        doc.UpdatedAt = DateTime.UtcNow;

        _dbContext.AuditLogs.Add(new AuditLog
        {
            Id = Guid.NewGuid(),
            ActorUserId = callerUserId,
            Action = "DeleteMedicalDocument",
            EntityName = nameof(MedicalDocument),
            EntityId = doc.Id.ToString(),
            Timestamp = DateTime.UtcNow
        });

        await _dbContext.SaveChangesAsync(cancellationToken);
        return true;
    }

    private static MedicalDocumentDto MapToDto(MedicalDocument doc)
    {
        return new MedicalDocumentDto
        {
            Id = doc.Id,
            OwnerMemberId = doc.OwnerMemberId,
            OwnerMemberName = doc.OwnerMember?.FullName ?? string.Empty,
            UploadedByUserId = doc.UploadedByUserId,
            UploadedByName = doc.UploadedByUser?.FullName ?? string.Empty,
            MedicineId = doc.MedicineId,
            MedicineName = doc.Medicine?.Name,
            Title = doc.Title,
            Category = doc.Category,
            Notes = doc.Notes,
            OriginalFileName = doc.OriginalFileName,
            ContentType = doc.ContentType,
            FileSizeBytes = doc.FileSizeBytes,
            CreatedAt = doc.CreatedAt
        };
    }
}
