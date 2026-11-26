using System;
using System.Globalization;
using System.Text.RegularExpressions;

namespace CareVoice.Application.Common;

/// <summary>
/// Resilient parser for TimeOfDay strings across 12-hour AM/PM, 24-hour, dot-separated,
/// Bengali numerals, and localized time phrases.
/// </summary>
public static class TimeOfDayParser
{
    private static readonly string[] ExactFormats = new[]
    {
        "h:mm tt", "hh:mm tt", "h:mmtt", "hh:mmtt",
        "h:mm:ss tt", "hh:mm:ss tt", "h tt", "hh tt", "htt", "hhtt",
        "H:mm", "HH:mm", "H:mm:ss", "HH:mm:ss", "H:m", "HH:m",
        "h.mm tt", "hh.mm tt", "h.mmtt", "hh.mmtt",
        "H.mm", "HH.mm", "H.mm.ss", "HH.mm.ss"
    };

    /// <summary>
    /// Attempts to parse a time string into a TimeSpan representing time of day.
    /// Supports 12-hour AM/PM, 24-hour, Bengali numerals, and common variations.
    /// </summary>
    public static bool TryParse(string? input, out TimeSpan timeSpan)
    {
        timeSpan = TimeSpan.Zero;
        if (string.IsNullOrWhiteSpace(input))
        {
            return false;
        }

        var clean = NormalizeBengaliDigits(input.Trim());

        if (TimeSpan.TryParse(clean, CultureInfo.InvariantCulture, out timeSpan))
        {
            if (timeSpan >= TimeSpan.Zero && timeSpan < TimeSpan.FromDays(1))
            {
                return true;
            }
        }

        if (DateTime.TryParseExact(clean, ExactFormats, CultureInfo.InvariantCulture, DateTimeStyles.None, out var dtExact))
        {
            timeSpan = dtExact.TimeOfDay;
            return true;
        }

        if (DateTime.TryParse(clean, CultureInfo.InvariantCulture, DateTimeStyles.NoCurrentDateDefault, out var dt))
        {
            timeSpan = dt.TimeOfDay;
            return true;
        }

        var match = Regex.Match(
            clean,
            @"^\s*(?:(সকাল|ভোর|দুপুর|সন্ধ্যা|বিকাল|রাত)\s*)?(\d{1,2})(?:[:.](\d{1,2}))?(?::(\d{1,2}))?\s*(am|pm|a\.m\.|p\.m\.|টা)?(?:\s*(সকাল|ভোর|দুপুর|সন্ধ্যা|বিকাল|রাত))?\s*$",
            RegexOptions.IgnoreCase);

        if (match.Success)
        {
            if (ExtractTimeFromRegexMatch(match, out timeSpan))
            {
                return true;
            }
        }

        var embeddedMatch = Regex.Match(
            clean,
            @"(?:(সকাল|ভোর|দুপুর|সন্ধ্যা|বিকাল|রাত)\s*)?(\d{1,2})(?:[:.](\d{1,2}))?(?::(\d{1,2}))?\s*(am|pm|a\.m\.|p\.m\.|টা)",
            RegexOptions.IgnoreCase);

        if (embeddedMatch.Success)
        {
            if (ExtractTimeFromRegexMatch(embeddedMatch, out timeSpan))
            {
                return true;
            }
        }

        return false;
    }

    /// <summary>
    /// Parses the time or throws an ArgumentException with a helpful description if invalid.
    /// </summary>
    public static TimeSpan Parse(string? input)
    {
        if (TryParse(input, out var ts))
        {
            return ts;
        }

        throw new ArgumentException($"Invalid TimeOfDay format: '{input}'. Expected format e.g. '08:30' or '8:00 AM'.");
    }

    /// <summary>
    /// Normalizes any recognized time string into standard 24-hour 'HH:mm' string format.
    /// </summary>
    public static string NormalizeToTimeString(string? input, string fallback = "08:00")
    {
        if (TryParse(input, out var ts))
        {
            return ts.ToString(@"hh\:mm");
        }

        return fallback;
    }

    private static bool ExtractTimeFromRegexMatch(Match match, out TimeSpan timeSpan)
    {
        timeSpan = TimeSpan.Zero;

        if (!int.TryParse(match.Groups[2].Value, out var h))
        {
            return false;
        }

        var m = match.Groups[3].Success ? int.Parse(match.Groups[3].Value) : 0;
        var s = match.Groups[4].Success ? int.Parse(match.Groups[4].Value) : 0;

        var periodBn = (match.Groups[1].Success ? match.Groups[1].Value : "") +
                       (match.Groups[6].Success ? match.Groups[6].Value : "");
        var ampm = match.Groups[5].Success ? match.Groups[5].Value.ToLowerInvariant().Replace(".", "") : "";

        var isPm = ampm == "pm" || periodBn == "রাত" || periodBn == "সন্ধ্যা" || periodBn == "বিকাল";
        var isAm = ampm == "am" || periodBn == "সকাল" || periodBn == "ভোর";

        if (periodBn == "দুপুর" && h >= 1 && h < 12)
        {
            isPm = true;
        }

        if (isPm && h < 12)
        {
            h += 12;
        }
        else if (isAm && h == 12)
        {
            h = 0;
        }

        if (h >= 0 && h < 24 && m >= 0 && m < 60 && s >= 0 && s < 60)
        {
            timeSpan = new TimeSpan(h, m, s);
            return true;
        }

        return false;
    }

    public static string NormalizeBengaliDigits(string input)
    {
        const string bnDigits = "০১২৩৪৫৬৭৮৯";
        const string enDigits = "0123456789";
        var chars = input.ToCharArray();
        for (int i = 0; i < chars.Length; i++)
        {
            var idx = bnDigits.IndexOf(chars[i]);
            if (idx >= 0)
            {
                chars[i] = enDigits[idx];
            }
        }
        return new string(chars);
    }
}
