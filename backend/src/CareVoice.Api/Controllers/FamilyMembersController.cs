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
[Route("api/family-members")]
public class FamilyMembersController : ControllerBase
{
    private readonly IFamilyMemberService _familyMemberService;

    public FamilyMembersController(IFamilyMemberService familyMemberService)
    {
        _familyMemberService = familyMemberService;
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
    public async Task<IActionResult> GetAll()
    {
        try
        {
            var members = await _familyMemberService.GetFamilyMembersAsync(GetCallerUserId());
            return Ok(members);
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
            var member = await _familyMemberService.GetFamilyMemberByIdAsync(GetCallerUserId(), id);
            if (member == null)
            {
                return NotFound(new { message = "Family member not found or access denied." });
            }
            return Ok(member);
        }
        catch (Exception ex)
        {
            return BadRequest(new { message = ex.Message });
        }
    }

    [HttpPost]
    public async Task<IActionResult> Create([FromBody] CreateFamilyMemberDto dto)
    {
        try
        {
            var created = await _familyMemberService.CreateFamilyMemberAsync(GetCallerUserId(), dto);
            return CreatedAtAction(nameof(GetById), new { id = created.Id }, created);
        }
        catch (ArgumentException ex)
        {
            return BadRequest(new { message = ex.Message });
        }
        catch (InvalidOperationException ex)
        {
            return BadRequest(new { message = ex.Message });
        }
        catch (Exception ex)
        {
            return StatusCode(500, new { message = ex.Message });
        }
    }

    [HttpPut("{id:guid}")]
    public async Task<IActionResult> Update(Guid id, [FromBody] UpdateFamilyMemberDto dto)
    {
        try
        {
            var updated = await _familyMemberService.UpdateFamilyMemberAsync(GetCallerUserId(), id, dto);
            if (updated == null)
            {
                return NotFound(new { message = "Family member not found or access denied." });
            }
            return Ok(updated);
        }
        catch (Exception ex)
        {
            return BadRequest(new { message = ex.Message });
        }
    }

    [HttpDelete("{id:guid}")]
    public async Task<IActionResult> Delete(Guid id)
    {
        try
        {
            var deleted = await _familyMemberService.DeleteFamilyMemberAsync(GetCallerUserId(), id);
            if (!deleted)
            {
                return NotFound(new { message = "Family member not found or access denied." });
            }
            return NoContent();
        }
        catch (InvalidOperationException ex)
        {
            return BadRequest(new { message = ex.Message });
        }
        catch (Exception ex)
        {
            return StatusCode(500, new { message = ex.Message });
        }
    }
}
