import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../core/localization.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_tokens.dart';

class DateRangePickerWidget extends StatelessWidget {
  final DateTime fromDate;
  final DateTime? toDate;
  final ValueChanged<DateTime> onFromDateChanged;
  final ValueChanged<DateTime?> onToDateChanged;
  final bool isRequired;
  final String? label;

  const DateRangePickerWidget({
    super.key,
    required this.fromDate,
    required this.toDate,
    required this.onFromDateChanged,
    required this.onToDateChanged,
    this.isRequired = false,
    this.label,
  });

  bool get isInvalid {
    if (toDate == null) return false;
    final fromDateOnly = DateTime(fromDate.year, fromDate.month, fromDate.day);
    final toDateOnly = DateTime(toDate!.year, toDate!.month, toDate!.day);
    return toDateOnly.isBefore(fromDateOnly);
  }

  String _formatDate(DateTime dt) {
    return DateFormat('dd MMM yyyy').format(dt);
  }

  Future<void> _selectFromDate(BuildContext context) async {
    final fromDateOnly = DateTime(fromDate.year, fromDate.month, fromDate.day);
    final picked = await showDatePicker(
      context: context,
      initialDate: fromDateOnly,
      firstDate: DateTime(2000),
      lastDate: DateTime(2040),
      helpText: AppLanguage.instance.translate('select_from_date'),
    );

    if (picked != null) {
      final pickedOnly = DateTime(picked.year, picked.month, picked.day);
      onFromDateChanged(pickedOnly);
      if (toDate != null) {
        final toDateOnly = DateTime(toDate!.year, toDate!.month, toDate!.day);
        if (toDateOnly.isBefore(pickedOnly)) {
          onToDateChanged(pickedOnly);
        }
      }
    }
  }

  Future<void> _selectToDate(BuildContext context) async {
    final fromDateOnly = DateTime(fromDate.year, fromDate.month, fromDate.day);
    final initial = toDate != null
        ? DateTime(toDate!.year, toDate!.month, toDate!.day)
        : fromDateOnly;

    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2000),
      lastDate: DateTime(2040),
      helpText: AppLanguage.instance.translate('select_to_date'),
    );

    if (picked != null) {
      final pickedOnly = DateTime(picked.year, picked.month, picked.day);
      onToDateChanged(pickedOnly);
      if (pickedOnly.isBefore(fromDateOnly)) {
        onFromDateChanged(pickedOnly);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final lang = AppLanguage.instance;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (label != null) ...[
          Text(
            label!,
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 13,
              color: AppColors.ink,
            ),
          ),
          const SizedBox(height: 8),
        ],
        Row(
          children: [
            Expanded(
              child: InkWell(
                onTap: () => _selectFromDate(context),
                borderRadius: BorderRadius.circular(AppRadius.control),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: AppColors.creamLight,
                    borderRadius: BorderRadius.circular(AppRadius.control),
                    boxShadow: AppShadows.subtle,
                    border: Border.all(
                      color: isInvalid ? AppColors.missed : AppColors.sage,
                      width: 1.5,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.calendar_today_rounded, size: 14, color: AppColors.forest),
                          const SizedBox(width: 6),
                          Text(
                            lang.translate('from_date'),
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              color: AppColors.forest,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _formatDate(fromDate),
                        style: const TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w800,
                          color: AppColors.ink,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 10.0),
              child: Icon(Icons.arrow_forward_rounded, size: 18, color: AppColors.muted),
            ),

            Expanded(
              child: InkWell(
                onTap: () => _selectToDate(context),
                borderRadius: BorderRadius.circular(AppRadius.control),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: AppColors.creamLight,
                    borderRadius: BorderRadius.circular(AppRadius.control),
                    boxShadow: AppShadows.subtle,
                    border: Border.all(
                      color: isInvalid
                          ? AppColors.missed
                          : (toDate != null ? AppColors.sage : AppColors.softBorder),
                      width: 1.5,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.event_available_rounded,
                                size: 14,
                                color: toDate != null ? AppColors.forest : AppColors.muted,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                lang.translate('to_date'),
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                  color: toDate != null ? AppColors.forest : AppColors.muted,
                                ),
                              ),
                            ],
                          ),
                          if (toDate != null && !isRequired)
                            InkWell(
                              onTap: () => onToDateChanged(null),
                              borderRadius: BorderRadius.circular(999),
                              child: const Padding(
                                padding: EdgeInsets.all(2.0),
                                child: Icon(Icons.close_rounded, size: 14, color: AppColors.muted),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        toDate != null ? _formatDate(toDate!) : (lang.isBengali ? 'ঐচ্ছিক' : 'Ongoing / Optional'),
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w800,
                          color: toDate != null ? AppColors.ink : AppColors.muted,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
        if (isInvalid) ...[
          const SizedBox(height: 6),
          Text(
            lang.translate('invalid_date_range'),
            style: const TextStyle(color: AppColors.missed, fontSize: 11, fontWeight: FontWeight.bold),
          ),
        ],
      ],
    );
  }
}
