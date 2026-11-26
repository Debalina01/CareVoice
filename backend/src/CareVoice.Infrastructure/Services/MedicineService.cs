using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;
using Microsoft.EntityFrameworkCore;
using CareVoice.Application.DTOs;
using CareVoice.Application.Interfaces;
using CareVoice.Domain.Entities;
using CareVoice.Infrastructure.Persistence;

namespace CareVoice.Infrastructure.Services;

public class MedicineService : IMedicineService
{
    private readonly CareVoiceDbContext _dbContext;
    private readonly IPermissionService _permissionService;

    public MedicineService(CareVoiceDbContext dbContext, IPermissionService permissionService)
    {
        _dbContext = dbContext;
        _permissionService = permissionService;
    }

    public async Task<IEnumerable<MedicineDto>> GetMedicinesAsync(Guid callerUserId, Guid? memberId = null)
    {
        var callerPrimaryMemberId = await _permissionService.GetPrimaryMemberIdAsync(callerUserId);

        IQueryable<Medicine> query = _dbContext.Medicines
            .AsNoTracking()
            .Include(m => m.OwnerMember)
            .Include(m => m.Schedules.Where(s => s.IsActive))
                .ThenInclude(s => s.TargetMember)
            .Where(m => !m.IsDeleted);

        if (memberId.HasValue)
        {
            var isAuthorized = await _permissionService.IsAuthorizedForMemberAsync(callerUserId, memberId.Value);
            if (!isAuthorized) return Enumerable.Empty<MedicineDto>();
            query = query.Where(m => m.OwnerMemberId == memberId.Value);
        }
        else
        {
            query = query.Where(m => m.OwnerMember.UserId == callerUserId ||
                                     _dbContext.FamilyPermissions.Any(fp => fp.GranterMemberId == m.OwnerMemberId &&
                                                                            fp.GranteeMemberId == callerPrimaryMemberId));
        }

        var medicines = await query.OrderBy(m => m.Name).ToListAsync();

        return medicines.Select(m => new MedicineDto
        {
            Id = m.Id,
            OwnerMemberId = m.OwnerMemberId,
            OwnerMemberName = m.OwnerMember.FullName,
            Name = m.Name,
            Dosage = m.Dosage,
            Instructions = m.Instructions,
            FoodRelation = m.FoodRelation,
            StartDate = m.StartDate,
            EndDate = m.EndDate,
            IsDeleted = m.IsDeleted,
            CreatedAt = m.CreatedAt,
            Schedules = m.Schedules.Select(s => new ScheduleDto
            {
                Id = s.Id,
                MedicineId = s.MedicineId,
                MedicineName = m.Name,
                Dosage = m.Dosage,
                Instructions = m.Instructions,
                FoodRelation = m.FoodRelation,
                TargetMemberId = s.TargetMemberId,
                TargetMemberName = s.TargetMember.FullName,
                CreatedByMemberId = s.CreatedByMemberId,
                TimeOfDay = s.TimeOfDay.ToString(@"hh\:mm"),
                DaysOfWeekMask = s.DaysOfWeekMask,
                IsActive = s.IsActive,
                CreatedAt = s.CreatedAt
            }).ToList()
        }).ToList();
    }

    public async Task<MedicineDto?> GetMedicineByIdAsync(Guid callerUserId, Guid id)
    {
        var medicine = await _dbContext.Medicines
            .AsNoTracking()
            .Include(m => m.OwnerMember)
            .Include(m => m.Schedules.Where(s => s.IsActive))
                .ThenInclude(s => s.TargetMember)
            .FirstOrDefaultAsync(m => m.Id == id && !m.IsDeleted);

        if (medicine == null) return null;

        var isAuthorized = await _permissionService.IsAuthorizedForMemberAsync(callerUserId, medicine.OwnerMemberId);
        if (!isAuthorized) return null;

        return new MedicineDto
        {
            Id = medicine.Id,
            OwnerMemberId = medicine.OwnerMemberId,
            OwnerMemberName = medicine.OwnerMember.FullName,
            Name = medicine.Name,
            Dosage = medicine.Dosage,
            Instructions = medicine.Instructions,
            FoodRelation = medicine.FoodRelation,
            StartDate = medicine.StartDate,
            EndDate = medicine.EndDate,
            IsDeleted = medicine.IsDeleted,
            CreatedAt = medicine.CreatedAt,
            Schedules = medicine.Schedules.Select(s => new ScheduleDto
            {
                Id = s.Id,
                MedicineId = s.MedicineId,
                MedicineName = medicine.Name,
                Dosage = medicine.Dosage,
                Instructions = medicine.Instructions,
                FoodRelation = medicine.FoodRelation,
                TargetMemberId = s.TargetMemberId,
                TargetMemberName = s.TargetMember.FullName,
                CreatedByMemberId = s.CreatedByMemberId,
                TimeOfDay = s.TimeOfDay.ToString(@"hh\:mm"),
                DaysOfWeekMask = s.DaysOfWeekMask,
                IsActive = s.IsActive,
                CreatedAt = s.CreatedAt
            }).ToList()
        };
    }

    public async Task<MedicineDto> CreateMedicineAsync(Guid callerUserId, CreateMedicineDto dto)
    {
        if (string.IsNullOrWhiteSpace(dto.Name))
        {
            throw new ArgumentException("Medicine name is required.", nameof(dto.Name));
        }

        var canSet = await _permissionService.CanSetRemindersAsync(callerUserId, dto.OwnerMemberId);
        if (!canSet)
        {
            throw new UnauthorizedAccessException("You do not have permission to manage medicines for this member.");
        }

        var ownerMember = await _dbContext.FamilyMembers.FindAsync(dto.OwnerMemberId);
        if (ownerMember == null || ownerMember.IsDeleted)
        {
            throw new ArgumentException("Target owner member does not exist.");
        }

        var medicine = new Medicine
        {
            Id = Guid.NewGuid(),
            OwnerMemberId = dto.OwnerMemberId,
            Name = dto.Name.Trim(),
            Dosage = dto.Dosage.Trim(),
            Instructions = dto.Instructions?.Trim(),
            FoodRelation = dto.FoodRelation,
            StartDate = dto.StartDate,
            EndDate = dto.EndDate,
            IsDeleted = false,
            CreatedAt = DateTime.UtcNow
        };

        _dbContext.Medicines.Add(medicine);
        await _dbContext.SaveChangesAsync();

        return new MedicineDto
        {
            Id = medicine.Id,
            OwnerMemberId = medicine.OwnerMemberId,
            OwnerMemberName = ownerMember.FullName,
            Name = medicine.Name,
            Dosage = medicine.Dosage,
            Instructions = medicine.Instructions,
            FoodRelation = medicine.FoodRelation,
            StartDate = medicine.StartDate,
            EndDate = medicine.EndDate,
            IsDeleted = medicine.IsDeleted,
            CreatedAt = medicine.CreatedAt
        };
    }

    public async Task<MedicineDto?> UpdateMedicineAsync(Guid callerUserId, Guid id, UpdateMedicineDto dto)
    {
        var medicine = await _dbContext.Medicines
            .Include(m => m.OwnerMember)
            .FirstOrDefaultAsync(m => m.Id == id && !m.IsDeleted);

        if (medicine == null) return null;

        var canSet = await _permissionService.CanSetRemindersAsync(callerUserId, medicine.OwnerMemberId);
        if (!canSet)
        {
            throw new UnauthorizedAccessException("You do not have permission to update medicines for this member.");
        }

        if (!string.IsNullOrWhiteSpace(dto.Name)) medicine.Name = dto.Name.Trim();
        if (!string.IsNullOrWhiteSpace(dto.Dosage)) medicine.Dosage = dto.Dosage.Trim();
        medicine.Instructions = dto.Instructions?.Trim();
        medicine.FoodRelation = dto.FoodRelation;
        medicine.StartDate = dto.StartDate;
        medicine.EndDate = dto.EndDate;

        await _dbContext.SaveChangesAsync();

        return new MedicineDto
        {
            Id = medicine.Id,
            OwnerMemberId = medicine.OwnerMemberId,
            OwnerMemberName = medicine.OwnerMember.FullName,
            Name = medicine.Name,
            Dosage = medicine.Dosage,
            Instructions = medicine.Instructions,
            FoodRelation = medicine.FoodRelation,
            StartDate = medicine.StartDate,
            EndDate = medicine.EndDate,
            IsDeleted = medicine.IsDeleted,
            CreatedAt = medicine.CreatedAt
        };
    }

    public async Task<bool> DeactivateMedicineAsync(Guid callerUserId, Guid id)
    {
        var medicine = await _dbContext.Medicines
            .FirstOrDefaultAsync(m => m.Id == id && !m.IsDeleted);

        if (medicine == null) return false;

        var canSet = await _permissionService.CanSetRemindersAsync(callerUserId, medicine.OwnerMemberId);
        if (!canSet)
        {
            throw new UnauthorizedAccessException("You do not have permission to deactivate medicines for this member.");
        }

        medicine.IsDeleted = true;
        await _dbContext.SaveChangesAsync();
        return true;
    }
}
