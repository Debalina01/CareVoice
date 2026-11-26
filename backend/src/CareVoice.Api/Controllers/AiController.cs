using System;
using System.Net.Http;
using System.Security.Claims;
using System.Threading.Tasks;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.Configuration;
using CareVoice.Application.DTOs;
using CareVoice.Application.Interfaces;

namespace CareVoice.Api.Controllers;

[Authorize]
[ApiController]
[Route("api/ai/serbom")]
public class AiController : ControllerBase
{
    private readonly ISerbomAiService _serbomAiService;

    public AiController(ISerbomAiService serbomAiService)
    {
        _serbomAiService = serbomAiService;
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

    [HttpPost("process")]
    public async Task<IActionResult> ProcessCommand([FromBody] SerbomAiRequestDto request)
    {
        try
        {
            var response = await _serbomAiService.ProcessCommandAsync(GetCallerUserId(), request);
            return Ok(response);
        }
        catch (Exception ex)
        {
            return BadRequest(new { message = ex.Message });
        }
    }

    [HttpPost("confirm-schedule")]
    public async Task<IActionResult> ConfirmSchedule([FromBody] ConfirmScheduleDto dto)
    {
        try
        {
            var response = await _serbomAiService.ConfirmAndSaveScheduleAsync(GetCallerUserId(), dto);
            return Ok(response);
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

    [HttpDelete("schedule/{medicineName}")]
    public async Task<IActionResult> DeleteSchedule(string medicineName, [FromQuery] Guid? targetMemberId = null)
    {
        try
        {
            var success = await _serbomAiService.DeleteScheduleByMedicineNameAsync(GetCallerUserId(), medicineName, targetMemberId);
            if (!success)
            {
                return NotFound(new { message = $"No active schedule found for '{medicineName}'." });
            }
            return Ok(new { message = $"Schedule for '{medicineName}' deleted successfully." });
        }
        catch (Exception ex)
        {
            return BadRequest(new { message = ex.Message });
        }
    }

    [AllowAnonymous]
    [HttpGet("status")]
    public async Task<IActionResult> GetStatus()
    {
        try
        {
            var status = await _serbomAiService.GetStatusAsync();
            return Ok(status);
        }
        catch (Exception ex)
        {
            return BadRequest(new { message = ex.Message });
        }
    }

    [HttpPost("config")]
    public async Task<IActionResult> UpdateConfig([FromBody] UpdateAiConfigRequestDto request)
    {
        try
        {
            await _serbomAiService.UpdateConfigAsync(request);
            var status = await _serbomAiService.GetStatusAsync();
            return Ok(new { success = true, status, message = "Serbom AI configuration updated successfully." });
        }
        catch (Exception ex)
        {
            return BadRequest(new { message = ex.Message });
        }
    }

    [AllowAnonymous]
    [HttpPost("sarvam-tts")]
    public async Task<IActionResult> GenerateSarvamTts([FromBody] SarvamTtsRequestDto request, [FromServices] IConfiguration config, [FromServices] IHttpClientFactory httpClientFactory)
    {
        if (string.IsNullOrWhiteSpace(request.Text))
        {
            return BadRequest(new { message = "Text cannot be empty." });
        }

        var apiKey = config["SarvamAi:ApiKey"];
        var endpoint = config["SarvamAi:TtsEndpoint"] ?? "https://api.sarvam.ai/text-to-speech";

        if (!string.IsNullOrWhiteSpace(apiKey))
        {
            try
            {
                var client = httpClientFactory.CreateClient();
                client.DefaultRequestHeaders.Add("api-subscription-key", apiKey);

                var payload = new
                {
                    inputs = new[] { request.Text },
                    target_language_code = request.TargetLanguageCode ?? "bn-IN",
                    speaker = request.Speaker ?? "meera",
                    pitch = 0,
                    pace = 1.0,
                    loudness = 1.5,
                    speech_sample_rate = 16000,
                    enable_preprocessing = true,
                    model = "bulbul:v1"
                };

                var content = new StringContent(System.Text.Json.JsonSerializer.Serialize(payload), System.Text.Encoding.UTF8, "application/json");
                var response = await client.PostAsync(endpoint, content);

                if (response.IsSuccessStatusCode)
                {
                    var responseJson = await response.Content.ReadAsStringAsync();
                    return Content(responseJson, "application/json");
                }
            }
            catch
            {
            }
        }

        var cleanLang = (request.TargetLanguageCode ?? "bn-IN").Split('-')[0];
        var encoded = Uri.EscapeDataString(request.Text);
        var fallbackUrl = $"/api/ai/tts-audio?lang={cleanLang}&text={encoded}";

        return Ok(new
        {
            audios = new[] { fallbackUrl },
            provider = "CareVoiceTtsStream",
            language = request.TargetLanguageCode
        });
    }

    [AllowAnonymous]
    [HttpGet("tts-audio")]
    [HttpGet("/api/ai/tts-audio")]
    public async Task<IActionResult> GetTtsAudio(
        [FromQuery] string text,
        [FromQuery] string lang = "bn",
        [FromServices] IConfiguration config = null!,
        [FromServices] IHttpClientFactory httpClientFactory = null!)
    {
        if (string.IsNullOrWhiteSpace(text))
        {
            return BadRequest(new { message = "Text parameter is required." });
        }

        var cleanLang = (lang ?? "bn").Split('-')[0].ToLower();

        var sarvamKey = config?["SarvamAi:ApiKey"];
        if (!string.IsNullOrWhiteSpace(sarvamKey) && httpClientFactory != null)
        {
            try
            {
                var client = httpClientFactory.CreateClient();
                client.DefaultRequestHeaders.Add("api-subscription-key", sarvamKey);
                var payload = new
                {
                    inputs = new[] { text },
                    target_language_code = $"{cleanLang}-IN",
                    speaker = "meera",
                    model = "bulbul:v1"
                };
                var content = new StringContent(System.Text.Json.JsonSerializer.Serialize(payload), System.Text.Encoding.UTF8, "application/json");
                var res = await client.PostAsync(config["SarvamAi:TtsEndpoint"] ?? "https://api.sarvam.ai/text-to-speech", content);
                if (res.IsSuccessStatusCode)
                {
                    var json = await res.Content.ReadAsStringAsync();
                    using var doc = System.Text.Json.JsonDocument.Parse(json);
                    if (doc.RootElement.TryGetProperty("audios", out var audios) && audios.GetArrayLength() > 0)
                    {
                        var base64 = audios[0].GetString();
                        if (!string.IsNullOrEmpty(base64))
                        {
                            var bytes = Convert.FromBase64String(base64);
                            return File(bytes, "audio/wav");
                        }
                    }
                }
            }
            catch
            {
            }
        }

        try
        {
            var client = httpClientFactory != null ? httpClientFactory.CreateClient() : new System.Net.Http.HttpClient();
            client.DefaultRequestHeaders.UserAgent.ParseAdd("Mozilla/5.0 (Windows NT 10.0; Win64; x64)");
            var encoded = Uri.EscapeDataString(text);
            var url = $"https://translate.google.com/translate_tts?ie=UTF-8&tl={cleanLang}&client=tw-ob&q={encoded}";
            var audioBytes = await client.GetByteArrayAsync(url);
            return File(audioBytes, "audio/mpeg");
        }
        catch (Exception ex)
        {
            return BadRequest(new { message = $"TTS stream failed: {ex.Message}" });
        }
    }
}
