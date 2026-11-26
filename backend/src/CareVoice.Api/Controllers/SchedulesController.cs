using System;
using System.Security.Claims;
using System.Threading.Tasks;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using CareVoice.Application.DTOs;
using CareVoice.Application.Interfaces;

namespace CareVoice.Api.Controllers;

[Authorize]
[ApiController]
[Route("api/schedules")]
public class SchedulesController : ControllerBase
{
    private readonly IScheduleService _scheduleService;

    public SchedulesController(IScheduleService scheduleService)
    {
        _scheduleService = scheduleService;
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

    [HttpGet]
    public async Task<IActionResult> GetAll([FromQuery] Guid? targetMemberId = null)
    {
        try
        {
            var schedules = await _scheduleService.GetSchedulesAsync(GetCallerUserId(), targetMemberId);
            return Ok(schedules);
        }
        catch (Exception ex)
        {
            return BadRequest(new { message = ex.Message });
        }
    }

    [HttpGet("{id:guid}")]
    public async Task<IActionResult> GetById(Guid id)
    {
        try
        {
            var schedule = await _scheduleService.GetScheduleByIdAsync(GetCallerUserId(), id);
            if (schedule == null)
            {
                return NotFound(new { message = "Schedule not found or access denied." });
            }
            return Ok(schedule);
        }
        catch (Exception ex)
        {
            return BadRequest(new { message = ex.Message });
        }
    }

    [HttpPost]
    public async Task<IActionResult> Create([FromBody] CreateScheduleDto dto)
    {
        try
        {
            var created = await _scheduleService.CreateScheduleAsync(GetCallerUserId(), dto);
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
        catch (Exception ex)
        {
            return StatusCode(500, new { message = ex.Message });
        }
    }

    [HttpPut("{id:guid}")]
    public async Task<IActionResult> Update(Guid id, [FromBody] UpdateScheduleDto dto)
    {
        try
        {
            var updated = await _scheduleService.UpdateScheduleAsync(GetCallerUserId(), id, dto);
            if (updated == null)
            {
                return NotFound(new { message = "Schedule not found or access denied." });
            }
            return Ok(updated);
        }
        catch (UnauthorizedAccessException ex)
        {
            return StatusCode(403, new { message = ex.Message });
        }
        catch (ArgumentException ex)
        {
            return BadRequest(new { message = ex.Message });
        }
        catch (Exception ex)
        {
            return StatusCode(500, new { message = ex.Message });
        }
    }

    [HttpDelete("{id:guid}")]
    public async Task<IActionResult> Delete(Guid id)
    {
        try
        {
            var success = await _scheduleService.DeleteScheduleAsync(GetCallerUserId(), id);
            if (!success)
            {
                return NotFound(new { message = "Schedule not found or access denied." });
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

    [HttpGet("sync")]
    public async Task<IActionResult> Sync([FromQuery] Guid? targetMemberId = null)
    {
        try
        {
            var syncWindow = await _scheduleService.Get48HourSyncWindowAsync(GetCallerUserId(), targetMemberId);
            return Ok(syncWindow);
        }
        catch (Exception ex)
        {
            return BadRequest(new { message = ex.Message });
        }
    }
}
