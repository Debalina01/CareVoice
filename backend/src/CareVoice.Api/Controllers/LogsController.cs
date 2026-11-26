using System;
using System.Collections.Generic;
using System.Security.Claims;
using System.Threading.Tasks;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using CareVoice.Application.DTOs;
using CareVoice.Application.Interfaces;

namespace CareVoice.Api.Controllers;

[Authorize]
[ApiController]
[Route("api/logs")]
public class LogsController : ControllerBase
{
    private readonly ILogService _logService;

    public LogsController(ILogService logService)
    {
        _logService = logService;
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

    [HttpPost("sync")]
    public async Task<IActionResult> SyncLogs([FromBody] List<SyncActionRequestDto> actions)
    {
        try
        {
            var results = await _logService.SyncActionsAsync(GetCallerUserId(), actions);
            return Ok(results);
        }
        catch (Exception ex)
        {
            return BadRequest(new { message = ex.Message });
        }
    }

    [HttpGet("history")]
    public async Task<IActionResult> GetAdherenceHistory(
        [FromQuery] Guid? targetMemberId = null,
        [FromQuery] DateTime? date = null)
    {
        try
        {
            var history = await _logService.GetAdherenceHistoryAsync(GetCallerUserId(), targetMemberId, date);
            return Ok(history);
        }
        catch (Exception ex)
        {
            return BadRequest(new { message = ex.Message });
        }
    }
}
