import 'package:flutter/material.dart';
import '../../core/localization.dart';
import '../../core/tts_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_tokens.dart';
import 'pill_button.dart';

class VoiceSettingsDialog extends StatefulWidget {
  const VoiceSettingsDialog({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const VoiceSettingsDialog(),
    );
  }

  @override
  State<VoiceSettingsDialog> createState() => _VoiceSettingsDialogState();
}

class _VoiceSettingsDialogState extends State<VoiceSettingsDialog> {
  late String _selectedLanguage;
  late bool _isVoiceEnabled;
  bool _isPlayingSample = false;

  final List<Map<String, String>> _languageOptions = [
    {'code': 'auto', 'name': 'Auto (Follows Member / সিস্টেম)', 'native': 'Smart Context', 'flag': '🌐'},
    {'code': 'en', 'name': 'English', 'native': 'English (Indian / US)', 'flag': '🇮🇳'},
    {'code': 'bn', 'name': 'Bengali', 'native': 'বাংলা (Bengali AI)', 'flag': '🇧🇩'},
    {'code': 'hi', 'name': 'Hindi', 'native': 'हिन्दी (Hindi AI)', 'flag': '🇮🇳'},
    {'code': 'ta', 'name': 'Tamil', 'native': 'தமிழ் (Tamil AI)', 'flag': '🇮🇳'},
    {'code': 'te', 'name': 'Telugu', 'native': 'తెలుగు (Telugu AI)', 'flag': '🇮🇳'},
    {'code': 'kn', 'name': 'Kannada', 'native': 'ಕನ್ನಡ (Kannada AI)', 'flag': '🇮🇳'},
    {'code': 'ml', 'name': 'Malayalam', 'native': 'മലയാളം (Malayalam AI)', 'flag': '🇮🇳'},
    {'code': 'mr', 'name': 'Marathi', 'native': 'मराठी (Marathi AI)', 'flag': '🇮🇳'},
    {'code': 'gu', 'name': 'Gujarati', 'native': 'ગુજરાતી (Gujarati AI)', 'flag': '🇮🇳'},
    {'code': 'pa', 'name': 'Punjabi', 'native': 'ਪੰਜਾਬੀ (Punjabi AI)', 'flag': '🇮🇳'},
    {'code': 'or', 'name': 'Odia', 'native': 'ଓଡ଼ିଆ (Odia AI)', 'flag': '🇮🇳'},
  ];

  @override
  void initState() {
    super.initState();
    _selectedLanguage = TtsService.voiceLanguage;
    _isVoiceEnabled = TtsService.isVoiceReminderEnabled;
  }

  Future<void> _playSample() async {
    setState(() => _isPlayingSample = true);
    await TtsService.playSample(_selectedLanguage);
    if (mounted) {
      setState(() => _isPlayingSample = false);
    }
  }

  Future<void> _savePreference() async {
    await TtsService.setVoiceReminderEnabled(_isVoiceEnabled);
    await TtsService.setVoiceLanguage(_selectedLanguage);
    if (!mounted) return;
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                _isVoiceEnabled
                    ? '${AppLanguage.instance.translate('voice_pref_saved')} (Voice: ON)'
                    : 'Voice reminders muted globally (Voice: OFF)',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
        backgroundColor: _isVoiceEnabled ? AppColors.forest : AppColors.coral,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppLanguage.instance,
      builder: (context, _) {
        final lang = AppLanguage.instance;

        return Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.82,
            maxWidth: 540,
          ),
          decoration: const BoxDecoration(
            color: AppColors.creamLight,
            borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.modal)),
            boxShadow: AppShadows.clay,
          ),
          padding: EdgeInsets.only(
            left: 24,
            right: 24,
            top: 22,
            bottom: MediaQuery.of(context).viewInsets.bottom + 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 44,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.softBorder,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: AppColors.sage.withValues(alpha: 0.4),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.record_voice_over_rounded, color: AppColors.forest, size: 22),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          lang.translate('voice_reminder_language'),
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                            color: AppColors.ink,
                          ),
                        ),
                        const SizedBox(height: 2),
                        const Text(
                          'Multilingual Indian AI Voice Reminders',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppColors.muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, color: AppColors.muted),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 14),

              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: _isVoiceEnabled ? AppColors.sage.withValues(alpha: 0.35) : AppColors.cream,
                  borderRadius: BorderRadius.circular(AppRadius.control),
                  border: Border.all(
                    color: _isVoiceEnabled ? AppColors.forest : AppColors.softBorder,
                    width: 1.5,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      _isVoiceEnabled ? Icons.volume_up_rounded : Icons.volume_off_rounded,
                      color: _isVoiceEnabled ? AppColors.forest : AppColors.coral,
                      size: 26,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                lang.isBengali ? 'ভয়েস রিমাইন্ডার' : 'Voice Reminders',
                                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5, color: AppColors.ink),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: _isVoiceEnabled ? AppColors.forest : AppColors.coral,
                                  borderRadius: BorderRadius.circular(AppRadius.pill),
                                ),
                                child: Text(
                                  _isVoiceEnabled ? 'ON' : 'OFF',
                                  style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w900),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _isVoiceEnabled
                                ? (lang.isBengali ? 'ওষুধের সময়ে স্বয়ংক্রিয় ভয়েস ঘোষণা সক্রিয়' : 'Voice announcements play at reminder times')
                                : (lang.isBengali ? 'ভয়েস ঘোষণা বন্ধ (নোটিফিকেশন চালু থাকবে)' : 'Voice muted (Visual notifications remain active)'),
                            style: const TextStyle(fontSize: 11.5, color: AppColors.muted),
                          ),
                        ],
                      ),
                    ),
                    Switch.adaptive(
                      value: _isVoiceEnabled,
                      activeThumbColor: AppColors.forest,
                      onChanged: (val) {
                        setState(() => _isVoiceEnabled = val);
                        TtsService.setVoiceReminderEnabled(val);
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),

              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: _languageOptions.length,
                  separatorBuilder: (context, index) => const SizedBox(height: 8),
                  itemBuilder: (context, idx) {
                    final item = _languageOptions[idx];
                    final code = item['code']!;
                    final isSelected = _selectedLanguage == code;

                    return InkWell(
                      onTap: () => setState(() => _selectedLanguage = code),
                      borderRadius: BorderRadius.circular(AppRadius.control),
                      child: AnimatedContainer(
                        duration: AppDurations.hover,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        decoration: BoxDecoration(
                          color: isSelected ? AppColors.sage.withValues(alpha: 0.45) : Colors.white,
                          borderRadius: BorderRadius.circular(AppRadius.control),
                          border: Border.all(
                            color: isSelected ? AppColors.forest : AppColors.softBorder.withValues(alpha: 0.15),
                            width: isSelected ? 1.8 : 1.0,
                          ),
                          boxShadow: isSelected ? AppShadows.subtle : null,
                        ),
                        child: Row(
                          children: [
                            Text(item['flag']!, style: const TextStyle(fontSize: 22)),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    item['name']!,
                                    style: TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 13.5,
                                      color: isSelected ? AppColors.forest : AppColors.ink,
                                    ),
                                  ),
                                  Text(
                                    item['native']!,
                                    style: const TextStyle(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w500,
                                      color: AppColors.muted,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (isSelected)
                              Container(
                                width: 22,
                                height: 22,
                                decoration: const BoxDecoration(
                                  color: AppColors.forest,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(Icons.check, size: 14, color: Colors.white),
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),

              const SizedBox(height: 18),

              Row(
                children: [
                  Expanded(
                    child: PillButton(
                      label: lang.translate('voice_test_btn'),
                      onPressed: _isPlayingSample ? null : _playSample,
                      icon: Icons.volume_up_rounded,
                      variant: PillButtonVariant.outlined,
                      isLoading: _isPlayingSample,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: PillButton(
                      label: lang.translate('save'),
                      onPressed: _savePreference,
                      icon: Icons.check_rounded,
                      variant: PillButtonVariant.primary,
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}
