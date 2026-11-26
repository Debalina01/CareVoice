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
[Route("api/family-groups")]
public class FamilyGroupsController : ControllerBase
{
    private readonly IFamilyGroupService _familyGroupService;

    public FamilyGroupsController(IFamilyGroupService familyGroupService)
    {
        _familyGroupService = familyGroupService;
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

    [HttpGet("my")]
    public async Task<IActionResult> GetMyFamilyGroup()
    {
        try
        {
            var group = await _familyGroupService.GetMyFamilyGroupAsync(GetCallerUserId());
            return Ok(group);
        }
        catch (Exception ex)
        {
            return BadRequest(new { message = ex.Message });
        }
    }

    [HttpGet]
    public async Task<IActionResult> GetAllMyFamilyGroups()
    {
        try
        {
            var groups = await _familyGroupService.GetAllMyFamilyGroupsAsync(GetCallerUserId());
            return Ok(groups);
        }
        catch (Exception ex)
        {
            return BadRequest(new { message = ex.Message });
        }
    }

    [HttpGet("{id:guid}")]
    public async Task<IActionResult> GetFamilyGroupById(Guid id)
    {
        try
        {
            var group = await _familyGroupService.GetFamilyGroupByIdAsync(GetCallerUserId(), id);
            if (group == null) return NotFound(new { message = "Family group not found." });
            return Ok(group);
        }
        catch (UnauthorizedAccessException ex)
        {
            return Unauthorized(new { message = ex.Message });
        }
        catch (Exception ex)
        {
            return BadRequest(new { message = ex.Message });
        }
    }

    [HttpPost]
    public async Task<IActionResult> Create([FromBody] CreateFamilyGroupDto dto)
    {
        try
        {
            var group = await _familyGroupService.CreateFamilyGroupAsync(GetCallerUserId(), dto);
            return Ok(group);
        }
        catch (Exception ex)
        {
            return BadRequest(new { message = ex.Message });
        }
    }

    [HttpPost("join")]
    public async Task<IActionResult> Join([FromBody] JoinFamilyGroupDto dto)
    {
        try
        {
            var group = await _familyGroupService.JoinFamilyGroupByCodeAsync(GetCallerUserId(), dto.FamilyCode);
            return Ok(group);
        }
        catch (ArgumentException ex)
        {
            return BadRequest(new { message = ex.Message });
        }
        catch (InvalidOperationException ex)
        {
            return Conflict(new { message = ex.Message });
        }
    }

    [HttpPost("join-with-otp")]
    public async Task<IActionResult> JoinWithOtp([FromBody] JoinFamilyGroupWithOtpDto dto, [FromServices] IEmailOtpService otpService)
    {
        var callerUserId = GetCallerUserId();
        if (!string.IsNullOrWhiteSpace(dto.Otp))
        {
            var userClaim = User.FindFirst(ClaimTypes.Email)?.Value;
            if (!string.IsNullOrWhiteSpace(userClaim))
            {
                var isVerified = await otpService.VerifyOtpAsync(userClaim, dto.Otp, "JoinFamily");
                if (!isVerified)
                {
                    return BadRequest(new { message = "Invalid or expired OTP for joining family." });
                }
            }
        }

        try
        {
            var group = await _familyGroupService.JoinFamilyGroupByCodeAsync(callerUserId, dto.FamilyCode);
            return Ok(group);
        }
        catch (ArgumentException ex)
        {
            return BadRequest(new { message = ex.Message });
        }
        catch (InvalidOperationException ex)
        {
            return Conflict(new { message = ex.Message });
        }
        catch (Exception ex)
        {
            return StatusCode(500, new { message = ex.Message });
        }
    }

    [HttpPost("{id:guid}/approve/{targetUserId:guid}")]
    public async Task<IActionResult> ApproveMember(Guid id, Guid targetUserId)
    {
        try
        {
            var success = await _familyGroupService.ApproveMemberAsync(GetCallerUserId(), id, targetUserId);
            return Ok(new { success, message = "Member successfully approved and joined to the family." });
        }
        catch (UnauthorizedAccessException ex)
        {
            return Forbid();
        }
        catch (Exception ex)
        {
            return BadRequest(new { message = ex.Message });
        }
    }

    [HttpPost("{id:guid}/reject/{targetUserId:guid}")]
    public async Task<IActionResult> RejectMember(Guid id, Guid targetUserId)
    {
        try
        {
            var success = await _familyGroupService.RejectMemberAsync(GetCallerUserId(), id, targetUserId);
            return Ok(new { success, message = "Member request was rejected." });
        }
        catch (UnauthorizedAccessException ex)
        {
            return Forbid();
        }
        catch (Exception ex)
        {
            return BadRequest(new { message = ex.Message });
        }
    }

    [HttpDelete("{id:guid}/members/{targetUserId:guid}")]
    public async Task<IActionResult> RemoveMember(Guid id, Guid targetUserId)
    {
        try
        {
            var success = await _familyGroupService.RemoveMemberAsync(GetCallerUserId(), id, targetUserId);
            return Ok(new { success, message = "Member removed from the family." });
        }
        catch (UnauthorizedAccessException ex)
        {
            return Forbid();
        }
        catch (Exception ex)
        {
            return BadRequest(new { message = ex.Message });
        }
    }

    [HttpGet("{id:guid}/shared-updates")]
    public async Task<IActionResult> GetSharedUpdates(Guid id)
    {
        try
        {
            var updates = await _familyGroupService.GetSharedUpdatesAsync(GetCallerUserId(), id);
            return Ok(updates);
        }
        catch (Exception ex)
        {
            return BadRequest(new { message = ex.Message });
        }
    }
}
