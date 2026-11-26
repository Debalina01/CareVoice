using System.IO;
using System.Threading;
using System.Threading.Tasks;

namespace CareVoice.Application.Interfaces;

public sealed record ObjectUploadResult(
    string Provider,
    string BucketName,
    string ObjectKey,
    string Sha256Hash);

public sealed record ObjectDownloadResult(
    Stream Content,
    string ContentType,
    long? ContentLength);

public interface IObjectStorageService
{
    bool IsConfigured { get; }
    string ProviderName { get; }
    string BucketName { get; }

    Task<ObjectUploadResult> UploadPrivateAsync(
        Stream content,
        string objectKey,
        string contentType,
        long contentLength,
        CancellationToken cancellationToken = default);

    Task<ObjectDownloadResult?> DownloadPrivateAsync(
        string objectKey,
        CancellationToken cancellationToken = default);

    Task DeleteAsync(
        string objectKey,
        CancellationToken cancellationToken = default);
}
