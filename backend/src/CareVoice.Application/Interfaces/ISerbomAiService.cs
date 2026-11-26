using System;
using System.Threading.Tasks;
using CareVoice.Application.DTOs;

namespace CareVoice.Application.Interfaces;

public interface ISerbomAiService
{
    Task<SerbomAiResponseDto> ProcessCommandAsync(Guid callerUserId, SerbomAiRequestDto request);
    Task<ConfirmScheduleResponseDto> ConfirmAndSaveScheduleAsync(Guid callerUserId, ConfirmScheduleDto dto);
    Task<bool> DeleteScheduleByMedicineNameAsync(Guid callerUserId, string medicineName, Guid? targetMemberId = null);
    Task<SerbomAiStatusDto> GetStatusAsync();
    Task<bool> UpdateConfigAsync(UpdateAiConfigRequestDto request);
}
