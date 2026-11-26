using System;
using System.IO;
using System.Security.Claims;
using System.Threading;
using System.Threading.Tasks;
using CareVoice.Application.Interfaces;
using CareVoice.Infrastructure.Services;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Net.Http.Headers;

namespace CareVoice.Api.Controllers;

[Authorize]
[ApiController]
[Route("api/medical-documents")]
public class MedicalDocumentsController : ControllerBase
{
    private readonly IMedicalDocumentService _documentService;
    private readonly IObjectStorageService _objectStorage;

    public MedicalDocumentsController(
        IMedicalDocumentService documentService,
        IObjectStorageService objectStorage)
    {
        _documentService = documentService;
        _objectStorage = objectStorage;
    }

    private Guid GetCallerUserId()
    {
        var claim = User.FindFirst(ClaimTypes.NameIdentifier)?.Value;
        if (!Guid.TryParse(claim, out var userId))
        {
            throw new UnauthorizedAccessException("Missing or invalid user identifier in authentication token.");
        }
        return userId;
    }

    [HttpGet("storage-status")]
    public IActionResult GetStorageStatus()
    {
        return Ok(new
        {
            configured = _objectStorage.IsConfigured,
            provider = _objectStorage.ProviderName
        });
    }

    [HttpGet]
    public async Task<IActionResult> GetAll(
        [FromQuery] Guid? memberId = null,
        [FromQuery] Guid? medicineId = null,
        CancellationToken cancellationToken = default)
    {
        try
        {
            var docs = await _documentService.GetDocumentsAsync(GetCallerUserId(), memberId, medicineId, cancellationToken);
            return Ok(docs);
        }
        catch (UnauthorizedAccessException ex)
        {
            return StatusCode(403, new { message = ex.Message });
        }
        catch (Exception ex)
        {
            return BadRequest(new { message = ex.Message });
        }
    }

    [HttpGet("{id:guid}")]
    public async Task<IActionResult> GetById(Guid id, CancellationToken cancellationToken = default)
    {
        try
        {
            var doc = await _documentService.GetDocumentByIdAsync(GetCallerUserId(), id, cancellationToken);
            if (doc == null)
            {
                return NotFound(new { message = "Medical document not found." });
            }
            return Ok(doc);
        }
        catch (UnauthorizedAccessException ex)
        {
            return StatusCode(403, new { message = ex.Message });
        }
        catch (Exception ex)
        {
            return BadRequest(new { message = ex.Message });
        }
    }

    [HttpPost]
    [RequestSizeLimit(12 * 1024 * 1024)]
    [Consumes("multipart/form-data")]
    public async Task<IActionResult> Upload(
        [FromForm] IFormFile file,
        [FromForm] Guid ownerMemberId,
        [FromForm] Guid? medicineId = null,
        [FromForm] string title = "",
        [FromForm] string category = "Prescription",
        [FromForm] string? notes = null,
        CancellationToken cancellationToken = default)
    {
        if (file == null || file.Length <= 0)
        {
            return BadRequest(new { message = "Please choose a file to upload." });
        }

        if (file.Length > MedicalDocumentService.MaxFileSizeBytes)
        {
            return BadRequest(new { message = "The selected file exceeds the 10 MB size limit." });
        }

        try
        {
            await using var stream = file.OpenReadStream();
            var input = new UploadMedicalDocumentInput(
                ownerMemberId,
                medicineId,
                title,
                category,
                notes,
                file.FileName,
                file.ContentType,
                file.Length,
                stream);

            var created = await _documentService.UploadDocumentAsync(GetCallerUserId(), input, cancellationToken);
            return CreatedAtAction(nameof(GetById), new { id = created.Id }, created);
        }
        catch (UnauthorizedAccessException ex)
        {
            return StatusCode(403, new { message = ex.Message });
        }
        catch (ArgumentException ex)
        {
            return BadRequest(new { message = ex.Message });
        }
        catch (InvalidOperationException ex)
        {
            return StatusCode(503, new { message = ex.Message });
        }
        catch (Exception ex)
        {
            return StatusCode(500, new { message = $"Unable to upload medical document: {ex.Message}" });
        }
    }

    [HttpGet("{id:guid}/file")]
    public async Task<IActionResult> GetFile(
        Guid id,
        [FromQuery] bool download = false,
        CancellationToken cancellationToken = default)
    {
        try
        {
            var result = await _documentService.GetDocumentFileAsync(GetCallerUserId(), id, download, cancellationToken);
            if (result == null)
            {
                return NotFound(new { message = "Medical document file not found." });
            }

            Response.Headers["Cache-Control"] = "no-store, no-cache, private, max-age=0";
            Response.Headers["X-Content-Type-Options"] = "nosniff";

            var safeFileName = Path.GetFileName(result.FileName);
            if (download)
            {
                return File(result.Content, result.ContentType, safeFileName);
            }

            var contentDisposition = new ContentDispositionHeaderValue("inline");
            contentDisposition.SetHttpFileName(safeFileName);
            Response.Headers[HeaderNames.ContentDisposition] = contentDisposition.ToString();
            return File(result.Content, result.ContentType);
        }
        catch (UnauthorizedAccessException ex)
        {
            return StatusCode(403, new { message = ex.Message });
        }
        catch (InvalidOperationException ex)
        {
            return StatusCode(503, new { message = ex.Message });
        }
        catch (Exception ex)
        {
            return StatusCode(500, new { message = $"Unable to retrieve medical document: {ex.Message}" });
        }
    }

    [HttpDelete("{id:guid}")]
    public async Task<IActionResult> Delete(Guid id, CancellationToken cancellationToken = default)
    {
        try
        {
            var deleted = await _documentService.DeleteDocumentAsync(GetCallerUserId(), id, cancellationToken);
            if (!deleted)
            {
                return NotFound(new { message = "Medical document not found." });
            }
            return NoContent();
        }
        catch (UnauthorizedAccessException ex)
        {
            return StatusCode(403, new { message = ex.Message });
        }
        catch (Exception ex)
        {
            return StatusCode(500, new { message = ex.Message });
        }
    }
}
