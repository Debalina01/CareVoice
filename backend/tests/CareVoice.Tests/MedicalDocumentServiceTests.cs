using System;
using System.Collections.Concurrent;
using System.IO;
using System.Linq;
using System.Security.Cryptography;
using System.Text;
using System.Threading;
using System.Threading.Tasks;
using CareVoice.Application.Interfaces;
using CareVoice.Domain.Entities;
using CareVoice.Infrastructure.Persistence;
using CareVoice.Infrastructure.Services;
using Microsoft.EntityFrameworkCore;
using Xunit;

namespace CareVoice.Tests;

public class MedicalDocumentServiceTests
{
    private sealed class InMemoryFakeObjectStorage : IObjectStorageService
    {
        public ConcurrentDictionary<string, (byte[] Bytes, string ContentType)> Objects { get; } = new();
        public bool IsConfigured => true;
        public string ProviderName => "AmazonS3";
        public string BucketName => "carevoice-private-test";

        public async Task<ObjectUploadResult> UploadPrivateAsync(
            Stream content,
            string objectKey,
            string contentType,
            long contentLength,
            CancellationToken cancellationToken = default)
        {
            using var ms = new MemoryStream();
            await content.CopyToAsync(ms, cancellationToken);
            var bytes = ms.ToArray();
            Objects[objectKey] = (bytes, contentType);
            var sha = Convert.ToHexString(SHA256.HashData(bytes)).ToLowerInvariant();
            return new ObjectUploadResult(ProviderName, BucketName, objectKey, sha);
        }

        public Task<ObjectDownloadResult?> DownloadPrivateAsync(string objectKey, CancellationToken cancellationToken = default)
        {
            if (!Objects.TryGetValue(objectKey, out var entry))
            {
                return Task.FromResult<ObjectDownloadResult?>(null);
            }
            return Task.FromResult<ObjectDownloadResult?>(
                new ObjectDownloadResult(new MemoryStream(entry.Bytes), entry.ContentType, entry.Bytes.Length));
        }

        public Task DeleteAsync(string objectKey, CancellationToken cancellationToken = default)
        {
            Objects.TryRemove(objectKey, out _);
            return Task.CompletedTask;
        }
    }

    private static CareVoiceDbContext CreateDbContext(string dbName)
    {
        var options = new DbContextOptionsBuilder<CareVoiceDbContext>()
            .UseInMemoryDatabase(databaseName: dbName)
            .Options;
        return new CareVoiceDbContext(options);
    }

    [Fact]
    public async Task UploadAndDownloadDocument_ShouldStorePrivatelyInObjectStorage_AndEnforcePermissions()
    {
        var db = CreateDbContext($"MedDocAuthDb_{Guid.NewGuid()}");
        var storage = new InMemoryFakeObjectStorage();
        var perm = new PermissionService(db);
        var docService = new MedicalDocumentService(db, perm, storage);

        var ownerUserId = Guid.NewGuid();
        var strangerUserId = Guid.NewGuid();

        db.Users.Add(new User { Id = ownerUserId, Email = "owner@carevoice.app", FullName = "Caregiver Owner", PasswordHash = "x" });
        db.Users.Add(new User { Id = strangerUserId, Email = "stranger@carevoice.app", FullName = "Stranger", PasswordHash = "x" });

        var ownerMember = new FamilyMember { Id = Guid.NewGuid(), UserId = ownerUserId, FullName = "Papa", Relation = "Parent" };
        db.FamilyMembers.Add(ownerMember);
        db.FamilyMembers.Add(new FamilyMember { Id = Guid.NewGuid(), UserId = strangerUserId, FullName = "Stranger Self", Relation = "Self" });
        await db.SaveChangesAsync();

        var sampleBytes = Encoding.UTF8.GetBytes("%PDF-1.4 Sample Prescription");
        await using var uploadStream = new MemoryStream(sampleBytes);

        var uploaded = await docService.UploadDocumentAsync(ownerUserId, new UploadMedicalDocumentInput(
            OwnerMemberId: ownerMember.Id,
            MedicineId: null,
            Title: "BP Prescription",
            Category: "Prescription",
            Notes: "Take after breakfast",
            OriginalFileName: "rx_papa.pdf",
            ContentType: "application/pdf",
            FileSizeBytes: sampleBytes.Length,
            FileStream: uploadStream));

        Assert.Equal("BP Prescription", uploaded.Title);
        Assert.Equal("rx_papa.pdf", uploaded.OriginalFileName);
        Assert.Single(storage.Objects);

        var ownerDocs = (await docService.GetDocumentsAsync(ownerUserId, ownerMember.Id)).ToList();
        Assert.Single(ownerDocs);

        var fileRes = await docService.GetDocumentFileAsync(ownerUserId, uploaded.Id, isDownload: true);
        Assert.NotNull(fileRes);
        Assert.Equal("application/pdf", fileRes!.ContentType);

        await Assert.ThrowsAsync<UnauthorizedAccessException>(() =>
            docService.GetDocumentsAsync(strangerUserId, ownerMember.Id));
        await Assert.ThrowsAsync<UnauthorizedAccessException>(() =>
            docService.GetDocumentFileAsync(strangerUserId, uploaded.Id, isDownload: false));
        await Assert.ThrowsAsync<UnauthorizedAccessException>(() =>
            docService.DeleteDocumentAsync(strangerUserId, uploaded.Id));

        var deleted = await docService.DeleteDocumentAsync(ownerUserId, uploaded.Id);
        Assert.True(deleted);
        Assert.Empty(storage.Objects);
        Assert.Empty(await docService.GetDocumentsAsync(ownerUserId, ownerMember.Id));
    }

    [Fact]
    public async Task UploadDocument_ShouldRejectUnsupportedExtensions_AndOversizedFiles()
    {
        var db = CreateDbContext($"MedDocValidationDb_{Guid.NewGuid()}");
        var storage = new InMemoryFakeObjectStorage();
        var perm = new PermissionService(db);
        var docService = new MedicalDocumentService(db, perm, storage);

        var userId = Guid.NewGuid();
        db.Users.Add(new User { Id = userId, Email = "user@carevoice.app", FullName = "User", PasswordHash = "x" });
        var member = new FamilyMember { Id = Guid.NewGuid(), UserId = userId, FullName = "Self", Relation = "Self" };
        db.FamilyMembers.Add(member);
        await db.SaveChangesAsync();

        await using var exeStream = new MemoryStream(new byte[] { 1, 2, 3 });
        await Assert.ThrowsAsync<ArgumentException>(() =>
            docService.UploadDocumentAsync(userId, new UploadMedicalDocumentInput(
                member.Id, null, "Bad File", "Other", null, "payload.exe", "application/octet-stream", 3, exeStream)));

        await using var bigStream = new MemoryStream(new byte[] { 1 });
        await Assert.ThrowsAsync<ArgumentException>(() =>
            docService.UploadDocumentAsync(userId, new UploadMedicalDocumentInput(
                member.Id, null, "Huge File", "Prescription", null, "scan.pdf", "application/pdf", 11 * 1024 * 1024, bigStream)));
    }
}
