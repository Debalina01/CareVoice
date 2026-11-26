using System;
using System.IO;
using System.Net;
using System.Security.Cryptography;
using System.Threading;
using System.Threading.Tasks;
using Amazon;
using Amazon.Runtime;
using Amazon.S3;
using Amazon.S3.Model;
using CareVoice.Application.Interfaces;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Logging;

namespace CareVoice.Infrastructure.Services;

public class S3ObjectStorageService : IObjectStorageService, IDisposable
{
    private readonly IAmazonS3? _s3Client;
    private readonly ILogger<S3ObjectStorageService> _logger;
    private readonly string _bucketName;
    private readonly bool _useSseS3;

    public bool IsConfigured => _s3Client != null && !string.IsNullOrWhiteSpace(_bucketName);
    public string ProviderName => "AmazonS3";
    public string BucketName => _bucketName;

    public S3ObjectStorageService(IConfiguration configuration, ILogger<S3ObjectStorageService> logger)
    {
        _logger = logger;

        var accessKey = FirstNonEmpty(
            configuration["ObjectStorage:AccessKey"],
            Environment.GetEnvironmentVariable("S3_ACCESS_KEY_ID"),
            Environment.GetEnvironmentVariable("AWS_ACCESS_KEY_ID"));

        var secretKey = FirstNonEmpty(
            configuration["ObjectStorage:SecretKey"],
            Environment.GetEnvironmentVariable("S3_SECRET_ACCESS_KEY"),
            Environment.GetEnvironmentVariable("AWS_SECRET_ACCESS_KEY"));

        _bucketName = FirstNonEmpty(
            configuration["ObjectStorage:BucketName"],
            Environment.GetEnvironmentVariable("S3_BUCKET_NAME"),
            Environment.GetEnvironmentVariable("AWS_S3_BUCKET_NAME")) ?? string.Empty;

        var region = FirstNonEmpty(
            configuration["ObjectStorage:Region"],
            Environment.GetEnvironmentVariable("S3_REGION"),
            Environment.GetEnvironmentVariable("AWS_REGION")) ?? "us-east-1";

        var serviceUrl = FirstNonEmpty(
            configuration["ObjectStorage:ServiceUrl"],
            Environment.GetEnvironmentVariable("S3_ENDPOINT_URL"));

        var forcePathStyle = bool.TryParse(
            FirstNonEmpty(configuration["ObjectStorage:ForcePathStyle"], Environment.GetEnvironmentVariable("S3_FORCE_PATH_STYLE")),
            out var pathStyle) && pathStyle;

        _useSseS3 = string.IsNullOrWhiteSpace(serviceUrl);

        if (!string.IsNullOrWhiteSpace(accessKey) &&
            !string.IsNullOrWhiteSpace(secretKey) &&
            !string.IsNullOrWhiteSpace(_bucketName))
        {
            var s3Config = new AmazonS3Config
            {
                ForcePathStyle = forcePathStyle || !string.IsNullOrWhiteSpace(serviceUrl)
            };

            if (!string.IsNullOrWhiteSpace(serviceUrl))
            {
                s3Config.ServiceURL = serviceUrl.Trim();
            }
            else
            {
                s3Config.RegionEndpoint = RegionEndpoint.GetBySystemName(region.Trim());
            }

            _s3Client = new AmazonS3Client(new BasicAWSCredentials(accessKey.Trim(), secretKey.Trim()), s3Config);
        }
    }

    public async Task<ObjectUploadResult> UploadPrivateAsync(
        Stream content,
        string objectKey,
        string contentType,
        long contentLength,
        CancellationToken cancellationToken = default)
    {
        if (!IsConfigured || _s3Client == null)
        {
            throw new InvalidOperationException(
                "Private cloud object storage is not configured. Please set S3_BUCKET_NAME, AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY, and AWS_REGION (or S3_ENDPOINT_URL).");
        }

        await using var memoryStream = new MemoryStream();
        await content.CopyToAsync(memoryStream, cancellationToken);
        memoryStream.Position = 0;

        string sha256Hex;
        using (var sha = SHA256.Create())
        {
            var hashBytes = await sha.ComputeHashAsync(memoryStream, cancellationToken);
            sha256Hex = Convert.ToHexString(hashBytes).ToLowerInvariant();
        }

        memoryStream.Position = 0;

        var request = new PutObjectRequest
        {
            BucketName = _bucketName,
            Key = objectKey,
            InputStream = memoryStream,
            ContentType = contentType,
            AutoCloseStream = false,
            CannedACL = S3CannedACL.Private
        };

        if (_useSseS3)
        {
            request.ServerSideEncryptionMethod = ServerSideEncryptionMethod.AES256;
        }

        await _s3Client.PutObjectAsync(request, cancellationToken);
        _logger.LogInformation("Stored private medical document in bucket {Bucket} under key {Key} ({Size} bytes).",
            _bucketName, objectKey, memoryStream.Length);

        return new ObjectUploadResult(ProviderName, _bucketName, objectKey, sha256Hex);
    }

    public async Task<ObjectDownloadResult?> DownloadPrivateAsync(
        string objectKey,
        CancellationToken cancellationToken = default)
    {
        if (!IsConfigured || _s3Client == null)
        {
            throw new InvalidOperationException("Private cloud object storage is not configured.");
        }

        try
        {
            using var response = await _s3Client.GetObjectAsync(_bucketName, objectKey, cancellationToken);
            var buffer = new MemoryStream();
            await response.ResponseStream.CopyToAsync(buffer, cancellationToken);
            buffer.Position = 0;

            return new ObjectDownloadResult(
                buffer,
                response.Headers.ContentType ?? "application/octet-stream",
                response.ContentLength);
        }
        catch (AmazonS3Exception ex) when (ex.StatusCode == HttpStatusCode.NotFound)
        {
            return null;
        }
    }

    public async Task DeleteAsync(string objectKey, CancellationToken cancellationToken = default)
    {
        if (!IsConfigured || _s3Client == null)
        {
            return;
        }

        await _s3Client.DeleteObjectAsync(_bucketName, objectKey, cancellationToken);
    }

    private static string? FirstNonEmpty(params string?[] values)
    {
        foreach (var value in values)
        {
            if (!string.IsNullOrWhiteSpace(value))
            {
                return value.Trim();
            }
        }
        return null;
    }

    public void Dispose()
    {
        _s3Client?.Dispose();
    }
}
