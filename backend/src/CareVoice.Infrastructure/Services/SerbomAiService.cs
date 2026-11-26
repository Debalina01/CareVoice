using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;
using System.Net.Http;
using System.Text;
using System.Text.Json;
using System.Text.RegularExpressions;
using System.Threading.Tasks;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Configuration;
using CareVoice.Application.Common;
using CareVoice.Application.DTOs;
using CareVoice.Application.Interfaces;
using CareVoice.Domain.Entities;
using CareVoice.Domain.Enums;
using CareVoice.Infrastructure.Persistence;

namespace CareVoice.Infrastructure.Services;

public class SerbomAiService : ISerbomAiService
{
    private readonly CareVoiceDbContext _dbContext;
    private readonly IMedicineService _medicineService;
    private readonly IScheduleService _scheduleService;
    private readonly IPermissionService _permissionService;
    private readonly IConfiguration? _configuration;

    private static string? _overrideApiKey;
    private static string? _overrideModel;
    private static readonly HttpClient _httpClient = new HttpClient { Timeout = TimeSpan.FromSeconds(15) };

    public SerbomAiService(
        CareVoiceDbContext dbContext,
        IMedicineService medicineService,
        IScheduleService scheduleService,
        IPermissionService permissionService,
        IConfiguration? configuration = null)
    {
        _dbContext = dbContext;
        _medicineService = medicineService;
        _scheduleService = scheduleService;
        _permissionService = permissionService;
        _configuration = configuration;
    }

    public async Task<SerbomAiResponseDto> ProcessCommandAsync(Guid callerUserId, SerbomAiRequestDto request)
    {
        var rawText = (request.Message ?? string.Empty).Trim();
        var isBengali = request.Language?.ToLower() == "bn" || ContainsBengaliCharacters(rawText);

        if (string.IsNullOrWhiteSpace(rawText))
        {
            return new SerbomAiResponseDto
            {
                Intent = "GeneralChat",
                Status = "Incomplete",
                ReplyMessage = "Hello! I am Serbom AI, your smart medicine scheduling assistant. How can I help you today?",
                ReplyMessageBn = "নমস্কার! আমি সেরবম এআই, আপনার স্মার্ট ওষুধ সময়সূচি সহায়ক। আজ আপনাকে কীভাবে সাহায্য করতে পারি?"
            };
        }

        var accessibleMembers = await _dbContext.FamilyMembers
            .AsNoTracking()
            .Where(fm => fm.UserId == callerUserId && !fm.IsDeleted)
            .ToListAsync();

        var primaryMemberId = await _permissionService.GetPrimaryMemberIdAsync(callerUserId);
        var primaryMember = accessibleMembers.FirstOrDefault(m => m.Id == primaryMemberId)
                            ?? accessibleMembers.FirstOrDefault();

        var enableCloud = _configuration?.GetValue<bool>("SerbomAi:EnableCloudLlm", true) ?? true;
        var apiKey = GetApiKey();
        if (enableCloud && !string.IsNullOrWhiteSpace(apiKey))
        {
            try
            {
                var cloudResponse = await CallGeminiLlmAsync(rawText, accessibleMembers, request.TargetMemberId, primaryMember, isBengali, request.AccumulatedSchedule);
                if (cloudResponse != null)
                {
                    return cloudResponse;
                }
            }
            catch
            {
            }
        }

        if (IsDeleteIntent(rawText))
        {
            return await HandleDeleteIntentAsync(callerUserId, rawText, accessibleMembers, isBengali);
        }

        if (IsQueryIntent(rawText))
        {
            return await HandleQueryIntentAsync(callerUserId, accessibleMembers, isBengali);
        }

        var extracted = ExtractScheduleDetails(rawText, accessibleMembers, request.TargetMemberId, primaryMember, request.AccumulatedSchedule);

        var missing = new List<string>();
        if (string.IsNullOrWhiteSpace(extracted.MedicineName)) missing.Add("medicineName");
        if (string.IsNullOrWhiteSpace(extracted.Dosage)) missing.Add("dosage");
        if (extracted.TimesOfDay == null || extracted.TimesOfDay.Count == 0) missing.Add("timeOfDay");

        if (missing.Contains("medicineName"))
        {
            var isSelf = (extracted.TargetMemberId == primaryMember?.Id) || (extracted.TargetMemberName == "Primary Caregiver" && primaryMember?.Relation == "Self");
            var targetDesc = (!string.IsNullOrEmpty(extracted.TargetMemberName) && !isSelf) ? $" for {extracted.TargetMemberName}" : "";
            var targetDescBn = (!string.IsNullOrEmpty(extracted.TargetMemberName) && !isSelf) ? $" ({extracted.TargetMemberName}-এর জন্য)" : "";

            return new SerbomAiResponseDto
            {
                Intent = "ClarificationNeeded",
                Status = "Incomplete",
                ExtractedSchedule = extracted,
                MissingFields = missing,
                ReplyMessage = $"I would be happy to schedule medicine{targetDesc}. Could you please specify the name of the medicine?",
                ReplyMessageBn = $"আমি ওষুধের সময়সূচি তৈরি করতে প্রস্তুত{targetDescBn}। অনুগ্রহ করে ওষুধের নাম বলুন?",
                FollowUpQuestion = "What is the medicine name?",
                FollowUpQuestionBn = "ওষুধের নাম কী?"
            };
        }

        if (missing.Contains("dosage"))
        {
            var isSelf = (extracted.TargetMemberId == primaryMember?.Id) || (extracted.TargetMemberName == "Primary Caregiver" && primaryMember?.Relation == "Self");
            var targetDesc = (!string.IsNullOrEmpty(extracted.TargetMemberName) && !isSelf) ? $" for {extracted.TargetMemberName}" : "";
            var targetDescBn = (!string.IsNullOrEmpty(extracted.TargetMemberName) && !isSelf) ? $" ({extracted.TargetMemberName}-এর জন্য)" : "";

            return new SerbomAiResponseDto
            {
                Intent = "ClarificationNeeded",
                Status = "Incomplete",
                ExtractedSchedule = extracted,
                MissingFields = missing,
                ReplyMessage = $"I noted the medicine '{extracted.MedicineName}'{targetDesc}. What is the prescribed dosage (e.g. 500mg, 1 tablet)?",
                ReplyMessageBn = $"আমি '{extracted.MedicineName}' ওষুধটি চিহ্নিত করেছি{targetDescBn}। এর নির্ধারিত মাত্রা (dosage) কত? (যেমন: ৫০০ মিলিগ্রাম বা ১টি ট্যাবলেট)",
                FollowUpQuestion = $"What is the dosage for {extracted.MedicineName}?",
                FollowUpQuestionBn = $"{extracted.MedicineName}-এর মাত্রা কত?"
            };
        }

        if (missing.Contains("timeOfDay"))
        {
            var isSelf = (extracted.TargetMemberId == primaryMember?.Id) || (extracted.TargetMemberName == "Primary Caregiver" && primaryMember?.Relation == "Self");
            var targetDesc = (!string.IsNullOrEmpty(extracted.TargetMemberName) && !isSelf) ? $" for {extracted.TargetMemberName}" : "";
            var targetDescBn = (!string.IsNullOrEmpty(extracted.TargetMemberName) && !isSelf) ? $" ({extracted.TargetMemberName}-এর জন্য)" : "";

            return new SerbomAiResponseDto
            {
                Intent = "ClarificationNeeded",
                Status = "Incomplete",
                ExtractedSchedule = extracted,
                MissingFields = missing,
                ReplyMessage = $"At what time(s) should '{extracted.MedicineName}' be taken{targetDesc}? (e.g. 08:00 AM, twice daily, or morning and night)",
                ReplyMessageBn = $"{extracted.MedicineName} কোন সময়ে গ্রহণ করতে হবে{targetDescBn}? (যেমন: সকাল ৮টা, দিনে ২ বার, বা সকালে ও রাতে)",
                FollowUpQuestion = $"What time should {extracted.MedicineName} be taken?",
                FollowUpQuestionBn = $"{extracted.MedicineName} কোন সময় নিতে হবে?"
            };
        }

        var targetName = extracted.TargetMemberName ?? "You";
        var foodNote = GetFoodRelationText(extracted.FoodRelation, isBengali);
        var timesStr = string.Join(", ", extracted.TimesOfDay ?? new List<string>());

        var englishReply = $"I have prepared the medicine schedule for {extracted.MedicineName} ({extracted.Dosage}) for {targetName} at {timesStr} ({foodNote}). Please review and confirm before saving.";
        var bengaliReply = $"{targetName}-এর জন্য {extracted.MedicineName} ({extracted.Dosage}) সময়সূচি প্রস্তুত করা হয়েছে: সময় {timesStr} ({foodNote})। সংরক্ষণের আগে অনুগ্রহ করে নিশ্চিত করুন।";

        return new SerbomAiResponseDto
        {
            Intent = "CreateSchedule",
            Status = "ReadyForConfirmation",
            ReplyMessage = englishReply,
            ReplyMessageBn = bengaliReply,
            ExtractedSchedule = extracted
        };
    }

    public async Task<ConfirmScheduleResponseDto> ConfirmAndSaveScheduleAsync(Guid callerUserId, ConfirmScheduleDto dto)
    {
        if (dto.TargetMemberId == Guid.Empty)
        {
            dto.TargetMemberId = await _permissionService.GetPrimaryMemberIdAsync(callerUserId);
        }

        var createMedDto = new CreateMedicineDto
        {
            OwnerMemberId = dto.TargetMemberId,
            Name = dto.MedicineName.Trim(),
            Dosage = dto.Dosage.Trim(),
            Instructions = dto.Instructions,
            FoodRelation = dto.FoodRelation,
            StartDate = dto.StartDate ?? DateTime.UtcNow,
            EndDate = dto.EndDate
        };

        var createdMed = await _medicineService.CreateMedicineAsync(callerUserId, createMedDto);

        var scheduleIds = new List<Guid>();
        var times = dto.TimesOfDay != null && dto.TimesOfDay.Count > 0 ? dto.TimesOfDay : new List<string> { "08:00" };

        foreach (var time in times)
        {
            var normalizedTime = TimeOfDayParser.NormalizeToTimeString(time, "08:00");
            var createSched = new CreateScheduleDto
            {
                MedicineId = createdMed.Id,
                TargetMemberId = dto.TargetMemberId,
                TimeOfDay = normalizedTime,
                DaysOfWeekMask = dto.DaysOfWeekMask > 0 ? dto.DaysOfWeekMask : 127
            };

            var sched = await _scheduleService.CreateScheduleAsync(callerUserId, createSched);
            scheduleIds.Add(sched.Id);
        }

        return new ConfirmScheduleResponseDto
        {
            MedicineId = createdMed.Id,
            ScheduleIds = scheduleIds,
            Message = $"Schedule for {createdMed.Name} confirmed and activated with {scheduleIds.Count} reminder(s).",
            MessageBn = $"{createdMed.Name}-এর সময়সূচি নিশ্চিত করা হয়েছে এবং {scheduleIds.Count}টি রিমাইন্ডার সক্রিয় হয়েছে।"
        };
    }

    public async Task<bool> DeleteScheduleByMedicineNameAsync(Guid callerUserId, string medicineName, Guid? targetMemberId = null)
    {
        var medicines = await _dbContext.Medicines
            .Include(m => m.Schedules)
            .Where(m => !m.IsDeleted && m.Name.ToLower().Contains(medicineName.ToLower().Trim()))
            .ToListAsync();

        var affected = false;
        foreach (var med in medicines)
        {
            var isAuthorized = await _permissionService.IsAuthorizedForMemberAsync(callerUserId, med.OwnerMemberId);
            if (!isAuthorized) continue;

            if (targetMemberId.HasValue && med.OwnerMemberId != targetMemberId.Value) continue;

            med.IsDeleted = true;
            foreach (var s in med.Schedules)
            {
                s.IsActive = false;
            }
            affected = true;
        }

        if (affected)
        {
            await _dbContext.SaveChangesAsync();
        }
        return affected;
    }

    private static bool ContainsBengaliCharacters(string text)
    {
        return Regex.IsMatch(text, @"[\u0980-\u09FF]");
    }

    private static bool IsDeleteIntent(string text)
    {
        var lower = text.ToLower();
        return lower.Contains("delete") || lower.Contains("remove") || lower.Contains("cancel")
            || lower.Contains("মুছে") || lower.Contains("ডিলিট") || lower.Contains("বাতিল") || lower.Contains("বন্ধ");
    }

    private static bool IsQueryIntent(string text)
    {
        var lower = text.ToLower();
        return (lower.Contains("what") && lower.Contains("medicine"))
            || lower.Contains("show schedule") || lower.Contains("list medicine") || lower.Contains("list reminder")
            || (lower.Contains("ওষুধ") && lower.Contains("কী")) || lower.Contains("সময়সূচি দেখাও") || lower.Contains("তালিকা");
    }

    private async Task<SerbomAiResponseDto> HandleDeleteIntentAsync(
        Guid callerUserId, string text, List<FamilyMember> members, bool isBengali)
    {
        var clean = Regex.Replace(text, @"(?i)\b(delete|remove|cancel|schedule|for|the|medicine|মুছে|ফেলুন|ডিলিট|করুন|বাতিল|ওষুধ)\b", " ").Trim();
        if (string.IsNullOrWhiteSpace(clean)) clean = "medicine";

        var deleted = await DeleteScheduleByMedicineNameAsync(callerUserId, clean);
        if (deleted)
        {
            return new SerbomAiResponseDto
            {
                Intent = "DeleteSchedule",
                Status = "Executed",
                ReplyMessage = $"Successfully deleted the schedule for '{clean}'.",
                ReplyMessageBn = $"'{clean}'-এর সময়সূচি সফলভাবে মুছে ফেলা হয়েছে।"
            };
        }

        return new SerbomAiResponseDto
        {
            Intent = "DeleteSchedule",
            Status = "Error",
            ReplyMessage = $"Could not find any active schedule for '{clean}' to delete.",
            ReplyMessageBn = $"মুছে ফেলার জন্য '{clean}'-এর কোনো সক্রিয় সময়সূচি পাওয়া যায়নি।"
        };
    }

    private async Task<SerbomAiResponseDto> HandleQueryIntentAsync(Guid callerUserId, List<FamilyMember> members, bool isBengali)
    {
        var schedules = await _scheduleService.GetSchedulesAsync(callerUserId);
        var active = schedules.Where(s => s.IsActive).ToList();

        if (active.Count == 0)
        {
            return new SerbomAiResponseDto
            {
                Intent = "QuerySchedule",
                Status = "Executed",
                ReplyMessage = "There are currently no active medicine schedules.",
                ReplyMessageBn = "বর্তমানে কোনো সক্রিয় ওষুধের সময়সূচি নেই।"
            };
        }

        var lines = active.Select(s => $"- {s.MedicineName} ({s.Dosage}) for {s.TargetMemberName} at {s.TimeOfDay}");
        var replyEn = "Here are your active schedules:\n" + string.Join("\n", lines);
        var replyBn = "আপনার সক্রিয় সময়সূচিসমূহ:\n" + string.Join("\n", lines);

        return new SerbomAiResponseDto
        {
            Intent = "QuerySchedule",
            Status = "Executed",
            ReplyMessage = replyEn,
            ReplyMessageBn = replyBn
        };
    }

    private ExtractedScheduleDto ExtractScheduleDetails(
        string text,
        List<FamilyMember> members,
        Guid? explicitTargetMemberId,
        FamilyMember? primaryMember,
        ExtractedScheduleDto? accumulated = null)
    {
        var result = new ExtractedScheduleDto
        {
            DaysOfWeekMask = accumulated?.DaysOfWeekMask ?? 127,
            MedicineName = accumulated?.MedicineName ?? string.Empty,
            Dosage = accumulated?.Dosage ?? string.Empty,
            FoodRelation = accumulated?.FoodRelation ?? FoodRelation.NoRelation,
            Instructions = accumulated?.Instructions,
            TimesOfDay = accumulated?.TimesOfDay != null ? new List<string>(accumulated.TimesOfDay) : new List<string>(),
            DurationDays = accumulated?.DurationDays,
            TargetMemberId = accumulated?.TargetMemberId,
            TargetMemberName = accumulated?.TargetMemberName,
        };

        var textLower = text.ToLower();
        var isBengali = ContainsBengaliCharacters(text);

        FamilyMember? matchedMember = null;

        foreach (var member in members)
        {
            var name = member.FullName.ToLower();
            var rel = member.Relation.ToLower();

            if (Regex.IsMatch(textLower, $@"\b{Regex.Escape(name)}\b"))
            {
                matchedMember = member;
                break;
            }

            if (rel == "parent" && Regex.IsMatch(textLower, @"\b(papa|father|dad|baba|বাবা|ma|maa|mom|mother|মা)\b"))
            {
                matchedMember = member;
                break;
            }

            if (rel == "spouse" && Regex.IsMatch(textLower, @"\b(husband|wife|spouse|বউ|স্ত্রী|স্বামী)\b"))
            {
                matchedMember = member;
                break;
            }

            if (rel == "child" && Regex.IsMatch(textLower, @"\b(son|daughter|child|kid|ছেলে|মেয়ে|সন্তান)\b"))
            {
                matchedMember = member;
                break;
            }

            if (rel == "sibling" && Regex.IsMatch(textLower, @"\b(brother|sister|bhai|bon|ভাই|বোন)\b"))
            {
                matchedMember = member;
                break;
            }

            if (member.Relation == "Self" && Regex.IsMatch(textLower, @"\b(for me|myself|i need|my medicine|আমার জন্য|আমাকে)\b"))
            {
                matchedMember = member;
                break;
            }
        }

        if (matchedMember == null && accumulated?.TargetMemberId != null)
        {
            matchedMember = members.FirstOrDefault(m => m.Id == accumulated.TargetMemberId.Value);
        }

        if (matchedMember == null && explicitTargetMemberId.HasValue)
        {
            matchedMember = members.FirstOrDefault(m => m.Id == explicitTargetMemberId.Value);
        }

        if (matchedMember == null)
        {
            matchedMember = primaryMember ?? members.FirstOrDefault(m => m.Relation == "Self") ?? members.FirstOrDefault();
        }

        if (matchedMember != null)
        {
            result.TargetMemberId = matchedMember.Id;
            result.TargetMemberName = matchedMember.FullName;
        }

        var doseMatchEn = Regex.Match(text, @"\b(\d+(?:\.\d+)?\s*(?:mg|ml|g|mcg|tablets?|pills?|capsules?|drops?|puffs?))\b", RegexOptions.IgnoreCase);
        var doseMatchBn = Regex.Match(text, @"([\d০-৯]+(?:\.[\d০-৯]+)?\s*(?:মিলিগ্রাম|মিলি|গ্রাম|ট্যাবলেট|ক্যাপসুল|চামচ|ড্রপ))");

        if (doseMatchEn.Success)
        {
            result.Dosage = doseMatchEn.Groups[1].Value.Trim();
        }
        else if (doseMatchBn.Success)
        {
            result.Dosage = ConvertBengaliDigitsToAscii(doseMatchBn.Groups[1].Value.Trim());
        }
        else if (!string.IsNullOrEmpty(accumulated?.Dosage))
        {
            result.Dosage = accumulated.Dosage;
        }

        if (textLower.Contains("before food") || textLower.Contains("before meal") || textLower.Contains("before breakfast")
            || textLower.Contains("before lunch") || textLower.Contains("before dinner") || textLower.Contains("empty stomach")
            || textLower.Contains("খাওয়ার আগে") || textLower.Contains("খাবার আগে") || textLower.Contains("নাস্তার আগে") || textLower.Contains("খালি পেটে"))
        {
            result.FoodRelation = FoodRelation.BeforeFood;
            result.Instructions = isBengali ? "খাওয়ার আগে গ্রহণ করুন" : "Take before meal";
        }
        else if (textLower.Contains("after food") || textLower.Contains("after meal") || textLower.Contains("after meals")
                 || textLower.Contains("after breakfast") || textLower.Contains("after lunch") || textLower.Contains("after dinner")
                 || textLower.Contains("খাওয়ার পর") || textLower.Contains("খাওয়ার পরে") || textLower.Contains("খাবার পর")
                 || textLower.Contains("খাবার পরে") || textLower.Contains("নাস্তার পর") || textLower.Contains("নাস্তার পরে"))
        {
            result.FoodRelation = FoodRelation.AfterFood;
            result.Instructions = isBengali ? "খাওয়ার পরে গ্রহণ করুন" : "Take after meal";
        }
        else if (textLower.Contains("with food") || textLower.Contains("with meal") || textLower.Contains("with breakfast")
                 || textLower.Contains("with lunch") || textLower.Contains("with dinner") || textLower.Contains("খাবারের সাথে"))
        {
            result.FoodRelation = FoodRelation.WithFood;
            result.Instructions = isBengali ? "খাবারের সাথে গ্রহণ করুন" : "Take with food";
        }
        else if (accumulated != null && accumulated.FoodRelation != FoodRelation.NoRelation)
        {
            result.FoodRelation = accumulated.FoodRelation;
            result.Instructions = accumulated.Instructions;
        }
        else
        {
            result.FoodRelation = FoodRelation.NoRelation;
            result.Instructions = isBengali ? "পানির সাথে গ্রহণ করুন" : "Take with water";
        }

        var extractedTimes = new List<string>();

        var timeMatches = Regex.Matches(text, @"\b(\d{1,2})(?::(\d{2}))?\s*(am|pm)\b", RegexOptions.IgnoreCase);
        foreach (Match tm in timeMatches)
        {
            var h = int.Parse(tm.Groups[1].Value);
            var m = tm.Groups[2].Success ? int.Parse(tm.Groups[2].Value) : 0;
            var ampm = tm.Groups[3].Value.ToLower();
            if (ampm == "pm" && h < 12) h += 12;
            if (ampm == "am" && h == 12) h = 0;
            extractedTimes.Add($"{h:D2}:{m:D2}");
        }

        var time24Matches = Regex.Matches(text, @"\b([01]?\d|2[0-3]):([0-5]\d)\b");
        foreach (Match tm in time24Matches)
        {
            var t = $"{int.Parse(tm.Groups[1].Value):D2}:{int.Parse(tm.Groups[2].Value):D2}";
            if (!extractedTimes.Contains(t)) extractedTimes.Add(t);
        }

        var bnTimeMatches = Regex.Matches(text, @"(সকাল|দুপুর|সন্ধ্যা|রাত)\s*([\d০-৯]+)(?::([\d০-৯]+))?\s*টা");
        foreach (Match btm in bnTimeMatches)
        {
            var period = btm.Groups[1].Value;
            var h = int.Parse(ConvertBengaliDigitsToAscii(btm.Groups[2].Value));
            var m = btm.Groups[3].Success ? int.Parse(ConvertBengaliDigitsToAscii(btm.Groups[3].Value)) : 0;
            if ((period == "রাত" || period == "সন্ধ্যা") && h < 12) h += 12;
            if (period == "দুপুর" && h < 12 && h >= 1) h += 12;
            extractedTimes.Add($"{h:D2}:{m:D2}");
        }

        if (extractedTimes.Count == 0)
        {
            if (textLower.Contains("twice") || textLower.Contains("২ বার") || textLower.Contains("দুবার") || textLower.Contains("সকালে ও রাতে"))
            {
                extractedTimes.Add("08:00");
                extractedTimes.Add("20:00");
            }
            else if (textLower.Contains("thrice") || textLower.Contains("৩ বার") || textLower.Contains("তিনবার"))
            {
                extractedTimes.Add("08:00");
                extractedTimes.Add("14:00");
                extractedTimes.Add("20:00");
            }
            else if (textLower.Contains("morning") || textLower.Contains("সকালে"))
            {
                extractedTimes.Add("08:00");
            }
            else if (textLower.Contains("night") || textLower.Contains("রাতে"))
            {
                extractedTimes.Add("21:00");
            }
            else if (textLower.Contains("once") || textLower.Contains("১ বার") || textLower.Contains("একবার"))
            {
                extractedTimes.Add("09:00");
            }
        }

        if (extractedTimes.Count > 0)
        {
            result.TimesOfDay = extractedTimes
                .Select(t => TimeOfDayParser.NormalizeToTimeString(t, t))
                .Distinct()
                .OrderBy(t => t)
                .ToList();
        }
        else if (accumulated?.TimesOfDay != null && accumulated.TimesOfDay.Count > 0)
        {
            result.TimesOfDay = accumulated.TimesOfDay
                .Select(t => TimeOfDayParser.NormalizeToTimeString(t, t))
                .Distinct()
                .OrderBy(t => t)
                .ToList();
        }
        else
        {
            result.TimesOfDay = new List<string>();
        }

        var durMatchEn = Regex.Match(text, @"\b(?:for\s+)?(\d+)\s*(days?|weeks?|months?)\b", RegexOptions.IgnoreCase);
        var durMatchBn = Regex.Match(text, @"([\d০-৯]+)\s*(?:দিনের?|সপ্তাহের?|মাসের?)\s*(?:জন্য)?");

        int durationDays = 30;
        if (durMatchEn.Success)
        {
            var count = int.Parse(durMatchEn.Groups[1].Value);
            var unit = durMatchEn.Groups[2].Value.ToLower();
            durationDays = unit.StartsWith("week") ? count * 7 : unit.StartsWith("month") ? count * 30 : count;
            result.DurationDays = durationDays;
        }
        else if (durMatchBn.Success)
        {
            var count = int.Parse(ConvertBengaliDigitsToAscii(durMatchBn.Groups[1].Value));
            durationDays = durMatchBn.Value.Contains("সপ্তাহ") ? count * 7 : durMatchBn.Value.Contains("মাস") ? count * 30 : count;
            result.DurationDays = durationDays;
        }
        else if (accumulated?.DurationDays != null)
        {
            durationDays = accumulated.DurationDays.Value;
            result.DurationDays = durationDays;
        }
        else
        {
            result.DurationDays = 30;
        }

        result.StartDate = DateTime.UtcNow.Date;
        result.EndDate = DateTime.UtcNow.Date.AddDays(durationDays);

        var extractedMed = ExtractMedicineName(text, result.Dosage, accumulated?.MedicineName);
        if (!string.IsNullOrEmpty(extractedMed))
        {
            result.MedicineName = extractedMed;
        }
        else if (!string.IsNullOrEmpty(accumulated?.MedicineName))
        {
            result.MedicineName = accumulated.MedicineName;
        }

        return result;
    }

    private static string ExtractMedicineName(string text, string knownDosage, string? existingMedicineName = null)
    {
        var knownMeds = new[]
        {
            "Paracetamol", "Aspirin", "Metformin", "Amoxicillin", "Pantoprazole",
            "Omeprazole", "Atorvastatin", "Losartan", "Azithromycin", "Ciprofloxacin",
            "Cetirizine", "Ibuprofen", "Vitamin C", "Vitamin D", "Insulin", "Lisinopril",
            "Dolo", "Napa", "Calpol", "Augmentin", "Thyronorm", "Ecosprin", "Gliclazide",
            "Telmisartan", "Monas", "Seclo", "Maxpro", "Finix", "Lipitor", "Crocin",
            "প্যারাসিটামল", "মেটফর্মিন", "অ্যাসপিরিন", "এমোক্সিসিলিন", "প্যান্টোপ্রাজল",
            "ওমেপ্রাজল", "এটোরভাস্ট্যাটিন", "লোসার্টান", "সিপ্রোফ্লক্সাসিন", "সেটিরিজিন", "আইবুপ্রোফেন"
        };

        foreach (var med in knownMeds)
        {
            if (Regex.IsMatch(text, $@"\b{Regex.Escape(med)}\b", RegexOptions.IgnoreCase))
            {
                return med;
            }
        }

        if (!string.IsNullOrEmpty(knownDosage))
        {
            var matchBefore = Regex.Match(text, $@"\b([A-Za-z\u0980-\u09FF]{{3,25}})\s+{Regex.Escape(knownDosage)}", RegexOptions.IgnoreCase);
            if (matchBefore.Success)
            {
                var candidate = matchBefore.Groups[1].Value.Trim();
                if (!IsStopWord(candidate) && !IsFamilyRelationWord(candidate)) return candidate;
            }
        }

        var actionMatch = Regex.Match(text, @"(?i)\b(?:take|add|schedule|prescribe|give|ওষুধ|নিন|দিন)\s+([A-Za-z\u0980-\u09FF]{3,25})");
        if (actionMatch.Success)
        {
            var candidate = actionMatch.Groups[1].Value.Trim();
            if (!IsStopWord(candidate) && !IsFamilyRelationWord(candidate)) return candidate;
        }

        var suffixMatch = Regex.Match(text, @"\b([A-Za-z]{3,20}(?:cillin|mycin|statin|olol|pril|sartan|zole|pam|pine|ide|ine|tin|one|fen|vir|mab))\b", RegexOptions.IgnoreCase);
        if (suffixMatch.Success)
        {
            var candidate = suffixMatch.Groups[1].Value.Trim();
            if (!IsStopWord(candidate) && !IsFamilyRelationWord(candidate)) return candidate;
        }

        if (!string.IsNullOrWhiteSpace(existingMedicineName))
        {
            return existingMedicineName;
        }

        var cleaned = Regex.Replace(text, @"(?i)\b(the medicine is|its|it's|medicine|named|called|ওষুধের নাম|হলো|নাম|হল)\b", " ").Trim();
        var words = cleaned.Split(new[] { ' ', ',', '.' }, StringSplitOptions.RemoveEmptyEntries);
        if (words.Length >= 1 && words.Length <= 3)
        {
            var candidate = string.Join(" ", words);
            if (!Regex.IsMatch(candidate, @"\d")
                && !Regex.IsMatch(candidate, @"(?i)(mg|ml|mcg|tablet|pill|capsule|drop|am|pm|morning|night|daily|twice|once|food|meal|breakfast|lunch|dinner|after|before|with|সকাল|রাত|খাবার|নাস্তা)")
                && !IsStopWord(candidate)
                && !IsFamilyRelationWord(candidate)
                && candidate.Length >= 3)
            {
                return candidate;
            }
        }

        return string.Empty;
    }

    private static bool IsFamilyRelationWord(string word)
    {
        var lower = word.ToLower();
        var relations = new[]
        {
            "papa", "father", "dad", "daddy", "mom", "mother", "mommy", "parent", "parents",
            "brother", "sister", "bhai", "bon", "son", "daughter", "child", "kid",
            "husband", "wife", "spouse", "grandpa", "grandma", "baba", "maa", "ma",
            "বাবা", "মা", "ভাই", "বোন", "ছেলে", "মেয়ে", "স্বামী", "স্ত্রী", "দাদু", "দিদা"
        };
        return relations.Contains(lower);
    }

    private static bool IsStopWord(string word)
    {
        var lower = word.ToLower();
        var stops = new[]
        {
            "medicine", "pill", "pills", "tablet", "tablets", "daily", "twice", "once",
            "after", "before", "meal", "meals", "food", "papa", "father", "mom", "mother",
            "for", "the", "give", "take", "set", "reminder", "reminders", "schedule", "please",
            "yes", "no", "ok", "okay", "জন্য", "ওষুধ", "খাবার", "সকালে", "রাতে", "বাবা", "মা"
        };
        return stops.Contains(lower);
    }

    private static string ConvertBengaliDigitsToAscii(string input)
    {
        var bnDigits = "০১২৩৪৫৬৭৮৯";
        var enDigits = "0123456789";
        var chars = input.ToCharArray();
        for (int i = 0; i < chars.Length; i++)
        {
            int idx = bnDigits.IndexOf(chars[i]);
            if (idx != -1) chars[i] = enDigits[idx];
        }
        return new string(chars);
    }

    private static string GetFoodRelationText(FoodRelation relation, bool isBengali)
    {
        return relation switch
        {
            FoodRelation.BeforeFood => isBengali ? "খাওয়ার আগে" : "Before Food",
            FoodRelation.AfterFood => isBengali ? "খাওয়ার পরে" : "After Food",
            FoodRelation.WithFood => isBengali ? "খাবারের সাথে" : "With Food",
            _ => isBengali ? "কোনো খাবারের নিয়ম নেই" : "No Food Relation"
        };
    }

    public Task<SerbomAiStatusDto> GetStatusAsync()
    {
        var apiKey = GetApiKey();
        var hasApiKey = !string.IsNullOrWhiteSpace(apiKey);
        var activeEngine = hasApiKey ? "GeminiLlm" : "LocalNlu";

        return Task.FromResult(new SerbomAiStatusDto
        {
            Status = "Online",
            ActiveEngine = activeEngine,
            HasApiKey = hasApiKey,
            Model = _overrideModel ?? _configuration?["SerbomAi:Model"] ?? "gemini-1.5-flash",
            SupportedLanguages = new List<string> { "en", "bn" },
            Description = hasApiKey
                ? "Serbom AI powered by Google Gemini with local NLU fallback"
                : "Serbom AI powered by built-in bilingual Natural Language Understanding (NLU)"
        });
    }

    public Task<bool> UpdateConfigAsync(UpdateAiConfigRequestDto request)
    {
        if (request.ApiKey != null)
        {
            _overrideApiKey = request.ApiKey.Trim();
        }
        if (!string.IsNullOrWhiteSpace(request.Model))
        {
            _overrideModel = request.Model.Trim();
        }
        return Task.FromResult(true);
    }

    private string? GetApiKey()
    {
        return _overrideApiKey
            ?? Environment.GetEnvironmentVariable("GEMINI_API_KEY")
            ?? Environment.GetEnvironmentVariable("SERBOM_API_KEY")
            ?? _configuration?["SerbomAi:ApiKey"];
    }

    private async Task<SerbomAiResponseDto?> CallGeminiLlmAsync(
        string rawText,
        List<FamilyMember> accessibleMembers,
        Guid? targetMemberId,
        FamilyMember? primaryMember,
        bool isBengali,
        ExtractedScheduleDto? accumulated = null)
    {
        var apiKey = GetApiKey();
        if (string.IsNullOrWhiteSpace(apiKey)) return null;

        var model = _overrideModel ?? _configuration?["SerbomAi:Model"] ?? "gemini-1.5-flash";
        var url = $"https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent?key={apiKey}";

        var memberNames = string.Join(", ", accessibleMembers.Select(m => $"{m.FullName} ({m.Relation})"));
        var accumulatedContext = accumulated != null
            ? $"\nContext from previous conversational turns:\n- Medicine: {accumulated.MedicineName}\n- Dosage: {accumulated.Dosage}\n- Times: {string.Join(", ", accumulated.TimesOfDay ?? new List<string>())}\n- Target: {accumulated.TargetMemberName}\n- Food: {accumulated.FoodRelation}\nMerge this prior context with the user's latest input."
            : "";

        var prompt = $@"You are Serbom AI, an intelligent bilingual medical scheduling assistant for the CareVoice application.
Analyze the user's input in English or Bengali (বাংলা) and extract medicine scheduling details.
Accessible family members: [{memberNames}].
Default/Current user: {primaryMember?.FullName}.{accumulatedContext}

Return a JSON object conforming strictly to this structure:
{{
  ""intent"": ""CreateSchedule"",
  ""status"": ""ReadyForConfirmation"",
  ""replyMessage"": ""Natural conversational response in English confirming details"",
  ""replyMessageBn"": ""Natural conversational response in Bengali (বাংলা) confirming details"",
  ""extractedSchedule"": {{
    ""medicineName"": ""Medicine name"",
    ""dosage"": ""Dosage amount (e.g. 500mg, 1 tablet)"",
    ""foodRelation"": ""NoRelation"",
    ""instructions"": ""Special note or null"",
    ""timesOfDay"": [""08:00"", ""20:00""],
    ""daysOfWeekMask"": 127,
    ""durationDays"": 7,
    ""targetMemberName"": ""Recipient name""
  }},
  ""missingFields"": [],
  ""followUpQuestion"": null,
  ""followUpQuestionBn"": null
}}

Guidelines:
1. TimesOfDay must be in 24-hour 'HH:mm' format.
2. FoodRelation must be one of: 'NoRelation', 'BeforeFood', 'AfterFood', 'WithFood'.
3. If medicineName, dosage, or timesOfDay are missing, set status to 'Incomplete' and formulate followUpQuestion and followUpQuestionBn.
4. If the user asks to delete or remove a schedule, set intent to 'DeleteSchedule' and reply accordingly.
5. Provide high quality, natural Bengali (বাংলা) translation in replyMessageBn and followUpQuestionBn.

User text: ""{rawText}""";

        var payload = new
        {
            contents = new[]
            {
                new
                {
                    parts = new[]
                    {
                        new { text = prompt }
                    }
                }
            },
            generationConfig = new
            {
                temperature = 0.1,
                responseMimeType = "application/json"
            }
        };

        var json = JsonSerializer.Serialize(payload);
        var content = new StringContent(json, Encoding.UTF8, "application/json");

        var response = await _httpClient.PostAsync(url, content);
        if (!response.IsSuccessStatusCode) return null;

        var responseBody = await response.Content.ReadAsStringAsync();
        using var doc = JsonDocument.Parse(responseBody);
        if (!doc.RootElement.TryGetProperty("candidates", out var candidates) || candidates.GetArrayLength() == 0)
        {
            return null;
        }

        var textContent = candidates[0]
            .GetProperty("content")
            .GetProperty("parts")[0]
            .GetProperty("text")
            .GetString();

        if (string.IsNullOrWhiteSpace(textContent)) return null;

        var options = new JsonSerializerOptions { PropertyNameCaseInsensitive = true };
        var aiResult = JsonSerializer.Deserialize<SerbomAiResponseDto>(textContent, options);

        if (aiResult?.ExtractedSchedule != null)
        {
            if (aiResult.ExtractedSchedule.TimesOfDay != null)
            {
                aiResult.ExtractedSchedule.TimesOfDay = aiResult.ExtractedSchedule.TimesOfDay
                    .Select(t => TimeOfDayParser.NormalizeToTimeString(t, t))
                    .Distinct()
                    .OrderBy(t => t)
                    .ToList();
            }

            var targetName = aiResult.ExtractedSchedule.TargetMemberName;
            var matchedMember = accessibleMembers.FirstOrDefault(m =>
                !string.IsNullOrEmpty(targetName) &&
                (m.FullName.Contains(targetName, StringComparison.OrdinalIgnoreCase) ||
                 m.Relation.Contains(targetName, StringComparison.OrdinalIgnoreCase)))
                ?? accessibleMembers.FirstOrDefault(m => m.Id == targetMemberId)
                ?? primaryMember;

            if (matchedMember != null)
            {
                aiResult.ExtractedSchedule.TargetMemberId = matchedMember.Id;
                aiResult.ExtractedSchedule.TargetMemberName = matchedMember.FullName;
            }
        }

        return aiResult;
    }
}
