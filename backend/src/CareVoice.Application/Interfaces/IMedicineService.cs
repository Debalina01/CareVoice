using System;
using System.Collections.Generic;
using System.Threading.Tasks;
using CareVoice.Application.DTOs;

namespace CareVoice.Application.Interfaces;

public interface IMedicineService
{
    Task<IEnumerable<MedicineDto>> GetMedicinesAsync(Guid callerUserId, Guid? memberId = null);
    Task<MedicineDto?> GetMedicineByIdAsync(Guid callerUserId, Guid id);
    Task<MedicineDto> CreateMedicineAsync(Guid callerUserId, CreateMedicineDto dto);
    Task<MedicineDto?> UpdateMedicineAsync(Guid callerUserId, Guid id, UpdateMedicineDto dto);
    Task<bool> DeactivateMedicineAsync(Guid callerUserId, Guid id);
}
