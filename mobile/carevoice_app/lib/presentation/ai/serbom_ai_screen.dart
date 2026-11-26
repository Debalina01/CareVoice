import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import '../../core/localization.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/tts_service.dart';
import '../../data/medicine_repository.dart';
import '../../domain/models.dart';
import '../widgets/avatar_badge.dart';
import '../widgets/date_range_picker_widget.dart';
import '../widgets/icon_tile_button.dart';
import '../widgets/pill_button.dart';
import '../widgets/soft_card.dart';
import '../widgets/voice_settings_dialog.dart';

class SerbomAiScreen extends StatefulWidget {
  final List<FamilyMemberModel> members;
  final String? initialMemberId;

  const SerbomAiScreen({
    super.key,
    required this.members,
    this.initialMemberId,
  });

  @override
  State<SerbomAiScreen> createState() => _SerbomAiScreenState();
}

class _ChatMessage {
  final bool isUser;
  final String text;
  final String? timestamp;
  final ExtractedScheduleModel? pendingConfirmation;
  final bool isFollowUp;

  _ChatMessage({
    required this.isUser,
    required this.text,
    this.timestamp,
    this.pendingConfirmation,
    this.isFollowUp = false,
  });
}

class _SerbomAiScreenState extends State<SerbomAiScreen> {
  final _medicineRepo = MedicineRepository();
  final _textController = TextEditingController();
  final _scrollController = ScrollController();
  final List<_ChatMessage> _messages = [];
  bool _isLoading = false;
  String? _selectedMemberId;
  ExtractedScheduleModel? _accumulatedSchedule;

  @override
  void initState() {
    super.initState();
    _selectedMemberId = widget.initialMemberId ?? (widget.members.isNotEmpty ? widget.members.first.id : null);

    final lang = AppLanguage.instance;
    _messages.add(_ChatMessage(
      isUser: false,
      text: lang.isBengali
          ? 'নমস্কার! আমি আপনার কেয়ারভয়েস সহকারী। নিচের যেকোনো উদাহরণে ট্যাপ করুন অথবা কোন ওষুধ কখন খেতে হবে তা লিখে জানান—আমি সুন্দরভাবে রিমাইন্ডার তৈরি করে দেব।'
          : 'Hello! I am your CareVoice Helper. Tap a quick example below, speak, or type what medicine someone needs to take and when—I will set up the reminder for you.',
      timestamp: _nowTime(),
    ));
  }

  String _nowTime() {
    final now = DateTime.now();
    return '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutCubic,
        );
      }
    });
  }

  Future<void> _handleSendMessage([String? overrideText]) async {
    final text = overrideText ?? _textController.text.trim();
    if (text.isEmpty || _isLoading) return;

    _textController.clear();
    setState(() {
      _messages.add(_ChatMessage(
        isUser: true,
        text: text,
        timestamp: _nowTime(),
      ));
      _isLoading = true;
    });
    _scrollToBottom();

    final currentLang = AppLanguage.instance.currentLanguage;

    try {
      final response = await _medicineRepo.processSerbomAi(
        message: text,
        language: currentLang,
        targetMemberId: _selectedMemberId,
        accumulatedSchedule: _accumulatedSchedule,
      );

      if (response.extractedSchedule != null) {
        _accumulatedSchedule = response.extractedSchedule;
        if (response.extractedSchedule!.targetMemberId != null &&
            response.extractedSchedule!.targetMemberId!.isNotEmpty) {
          _selectedMemberId = response.extractedSchedule!.targetMemberId;
        }
      }

      final reply = AppLanguage.instance.isBengali ? response.replyMessageBn : response.replyMessage;
      TtsService.speak(reply, language: currentLang);

      setState(() {
        _messages.add(_ChatMessage(
          isUser: false,
          text: reply,
          timestamp: _nowTime(),
          pendingConfirmation: response.status == 'ReadyForConfirmation' ? response.extractedSchedule : null,
          isFollowUp: response.status == 'Incomplete' || response.status == 'NeedsClarification',
        ));
      });
    } catch (e) {
      final errorMsg = AppLanguage.instance.isBengali
          ? 'সারবম এআই অনুরোধ প্রক্রিয়া করতে ব্যর্থ হয়েছে: ${e.toString().replaceAll('Exception: ', '')}'
          : 'Serbom AI error: ${e.toString().replaceAll('Exception: ', '')}';
      setState(() {
        _messages.add(_ChatMessage(
          isUser: false,
          text: errorMsg,
          timestamp: _nowTime(),
        ));
      });
    } finally {
      setState(() => _isLoading = false);
      _scrollToBottom();
    }
  }

  Future<void> _confirmSchedule(ExtractedScheduleModel schedule, int msgIndex) async {
    if (schedule.endDate != null && schedule.startDate != null && schedule.endDate!.isBefore(schedule.startDate!)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLanguage.instance.translate('invalid_date_range')),
          backgroundColor: AppColors.missed,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final result = await _medicineRepo.confirmSerbomSchedule(schedule);
      final successMsg = AppLanguage.instance.isBengali
          ? (result['messageBn'] ?? 'সময়সূচী সফলভাবে সংরক্ষিত হয়েছে!')
          : (result['message'] ?? 'Medicine schedule successfully saved and active!');

      TtsService.speak(successMsg, language: AppLanguage.instance.currentLanguage);

      setState(() {
        _accumulatedSchedule = null;
        final oldMsg = _messages[msgIndex];
        _messages[msgIndex] = _ChatMessage(
          isUser: oldMsg.isUser,
          text: oldMsg.text,
          timestamp: oldMsg.timestamp,
          pendingConfirmation: null,
        );
        _messages.add(_ChatMessage(
          isUser: false,
          text: '✅ $successMsg',
          timestamp: _nowTime(),
        ));
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(successMsg), backgroundColor: AppColors.forest),
        );
      }
    } catch (e) {
      final err = e.toString().replaceAll('Exception: ', '');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $err'), backgroundColor: AppColors.missed),
        );
      }
    } finally {
      setState(() => _isLoading = false);
      _scrollToBottom();
    }
  }

  void _cancelSchedule(int msgIndex) {
    setState(() {
      _accumulatedSchedule = null;
      final oldMsg = _messages[msgIndex];
      _messages[msgIndex] = _ChatMessage(
        isUser: oldMsg.isUser,
        text: oldMsg.text,
        timestamp: oldMsg.timestamp,
        pendingConfirmation: null,
      );
      _messages.add(_ChatMessage(
        isUser: false,
        text: AppLanguage.instance.isBengali
            ? 'রিমাইন্ডার তৈরি বাতিল করা হয়েছে। আপনি চাইলে নিচের উদাহরণ থেকে বেছে নিতে পারেন।'
            : 'No problem—we cancelled that reminder. Feel free to tap a quick example below or type another medicine.',
        timestamp: _nowTime(),
      ));
    });
    _scrollToBottom();
  }

  void _showVoiceInputDialog() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _SarvamVoiceInputSheet(
        onRecognized: (text) {
          _handleSendMessage(text);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppLanguage.instance,
      builder: (context, _) {
        final lang = AppLanguage.instance;

        return Scaffold(
          backgroundColor: AppColors.cream,
          appBar: AppBar(
            backgroundColor: AppColors.cream,
            foregroundColor: AppColors.ink,
            elevation: 0,
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: const BoxDecoration(
                    color: AppColors.butter,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.auto_awesome_rounded, color: AppColors.ink, size: 18),
                ),
                const SizedBox(width: 10),
                Text(
                  lang.translate('serbom_ai_title'),
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
              ],
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.record_voice_over_rounded),
                tooltip: lang.translate('voice_settings'),
                onPressed: () => VoiceSettingsDialog.show(context),
              ),
              TextButton.icon(
                icon: const Icon(Icons.language_rounded, size: 16, color: AppColors.forest),
                label: Text(
                  lang.isBengali ? 'English' : 'বাংলা',
                  style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.forest),
                ),
                onPressed: () => lang.toggleLanguage(),
              ),
            ],
          ),
          body: Column(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                color: AppColors.sage.withValues(alpha: 0.35),
                child: Row(
                  children: [
                    const Icon(Icons.person_rounded, size: 16, color: AppColors.forest),
                    const SizedBox(width: 6),
                    Text(
                      '${lang.translate('target_person')}:',
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: AppColors.forest),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: widget.members.map((m) {
                            final isSelected = _selectedMemberId?.toLowerCase() == m.id.toLowerCase();
                            return Padding(
                              padding: const EdgeInsets.only(right: 6),
                              child: ChoiceChip(
                                avatar: AvatarBadge(
                                  name: m.fullName,
                                  size: 22,
                                  showRelationBadge: false,
                                ),
                                label: Text(
                                  '${m.fullName}${m.isSelf ? ' (${lang.translate('filter_self')})' : ''}',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: isSelected ? FontWeight.w900 : FontWeight.w600,
                                    color: isSelected ? Colors.white : AppColors.ink,
                                  ),
                                ),
                                selected: isSelected,
                                selectedColor: AppColors.forest,
                                backgroundColor: AppColors.creamLight,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(AppRadius.pill),
                                  side: BorderSide(
                                    color: isSelected ? Colors.transparent : AppColors.muted.withValues(alpha: 0.2),
                                  ),
                                ),
                                onSelected: (val) {
                                  if (val) {
                                    setState(() {
                                      _selectedMemberId = m.id;
                                      if (_accumulatedSchedule != null) {
                                        _accumulatedSchedule!.targetMemberId = m.id;
                                        _accumulatedSchedule!.targetMemberName = m.fullName;
                                      }
                                    });
                                  }
                                },
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              Expanded(
                child: ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                  itemCount: _messages.length,
                  itemBuilder: (context, index) {
                    final msg = _messages[index];
                    return _buildMessageItem(msg, index, lang);
                  },
                ),
              ),

              if (_isLoading)
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.coral),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        lang.isBengali ? 'সারবম এআই চিন্তা করছে...' : 'Serbom AI is analyzing...',
                        style: const TextStyle(fontSize: 12, color: AppColors.muted, fontStyle: FontStyle.italic),
                      ),
                    ],
                  ),
                ),

                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  color: AppColors.creamLight,
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: (lang.isBengali
                              ? [
                                  'সকাল ৮টায় খাওয়ার পর প্যারাসিটামল ৫০০ এমজি',
                                  'রাত ৯টায় ভিটামিন ডি ১টি ট্যাবলেট',
                                  'আজকের ওষুধের তালিকা দেখাও',
                                ]
                              : [
                                  'Paracetamol 500mg at 8:00 AM after food',
                                  'Vitamin D 1 tablet at 9:00 PM after dinner',
                                  'Show my upcoming medicines',
                                ])
                          .map((sample) => Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: ActionChip(
                                  avatar: const Icon(Icons.bolt_rounded, size: 15, color: AppColors.forest),
                                  label: Text(
                                    sample,
                                    style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: AppColors.ink),
                                  ),
                                  backgroundColor: AppColors.mint.withValues(alpha: 0.45),
                                  onPressed: () => _handleSendMessage(sample),
                                ),
                              ))
                          .toList(),
                    ),
                  ),
                ),

              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: const BoxDecoration(
                  color: AppColors.creamLight,
                  boxShadow: [
                    BoxShadow(
                      color: Color(0x0F4A3B2F),
                      blurRadius: 8,
                      offset: Offset(0, -2),
                    ),
                  ],
                ),
                child: SafeArea(
                  child: Row(
                    children: [
                      IconTileButton(
                        icon: Icons.mic_rounded,
                        tooltip: lang.translate('serbom_voice_input'),
                        iconColor: AppColors.forest,
                        backgroundColor: AppColors.mint,
                        size: 42,
                        onPressed: _showVoiceInputDialog,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: _textController,
                          decoration: InputDecoration(
                            hintText: lang.translate('serbom_placeholder'),
                            hintStyle: const TextStyle(fontSize: 13, color: AppColors.muted),
                            filled: true,
                            fillColor: Colors.white,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(AppRadius.pill),
                              borderSide: BorderSide(color: AppColors.muted.withValues(alpha: 0.2)),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(AppRadius.pill),
                              borderSide: BorderSide(color: AppColors.muted.withValues(alpha: 0.2)),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(AppRadius.pill),
                              borderSide: const BorderSide(color: AppColors.forest, width: 1.5),
                            ),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                          ),
                          onSubmitted: (_) => _handleSendMessage(),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconTileButton(
                        icon: Icons.send_rounded,
                        tooltip: 'Send',
                        iconColor: Colors.white,
                        backgroundColor: AppColors.coral,
                        size: 42,
                        onPressed: () => _handleSendMessage(),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildMessageItem(_ChatMessage msg, int index, AppLanguage lang) {
    if (msg.isUser) {
      return Align(
        alignment: Alignment.centerRight,
        child: Container(
          margin: const EdgeInsets.only(bottom: 12, left: 48),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: const BoxDecoration(
            color: AppColors.forest,
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(20),
              topRight: Radius.circular(20),
              bottomLeft: Radius.circular(20),
              bottomRight: Radius.circular(4),
            ),
            boxShadow: AppShadows.subtle,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                msg.text,
                style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500, height: 1.35),
              ),
              if (msg.timestamp != null) ...[
                const SizedBox(height: 4),
                Text(
                  msg.timestamp!,
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 10),
                ),
              ],
            ],
          ),
        ),
      );
    }

    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 16, right: 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 26,
                  height: 26,
                  decoration: const BoxDecoration(
                    color: AppColors.mint,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.auto_awesome_rounded, size: 14, color: AppColors.forest),
                ),
                const SizedBox(width: 8),
                const Text(
                  'CareVoice Helper',
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 12.5, color: AppColors.forest),
                ),
                if (msg.timestamp != null) ...[
                  const SizedBox(width: 8),
                  Text(
                    msg.timestamp!,
                    style: const TextStyle(fontSize: 10, color: AppColors.muted),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: msg.isFollowUp ? AppColors.butter.withValues(alpha: 0.3) : AppColors.creamLight,
                borderRadius: const BorderRadius.only(
                  topRight: Radius.circular(20),
                  bottomLeft: Radius.circular(4),
                  bottomRight: Radius.circular(20),
                ),
                boxShadow: AppShadows.subtle,
              ),
              child: Text(
                msg.text,
                style: const TextStyle(fontSize: 14, color: AppColors.ink, height: 1.4),
              ),
            ),
            if (msg.pendingConfirmation != null)
              _buildConfirmationCard(msg.pendingConfirmation!, index, lang),
          ],
        ),
      ),
    );
  }

  Widget _buildConfirmationCard(ExtractedScheduleModel schedule, int msgIndex, AppLanguage lang) {
    return Container(
      margin: const EdgeInsets.only(top: 12),
      child: SoftCard(
        backgroundColor: Colors.white,
        radius: AppRadius.card,
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.fact_check_rounded, color: AppColors.forest, size: 22),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    lang.translate('confirm_schedule_title'),
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: AppColors.forest),
                  ),
                ),
              ],
            ),
            const Divider(height: 20),

            _buildDetailRow(lang.translate('medicine_name'), schedule.medicineName, Icons.medication_rounded),
            if (schedule.targetMemberName != null)
              _buildDetailRow(lang.translate('target_person'), schedule.targetMemberName!, Icons.person_rounded),
            _buildDetailRow(lang.translate('dosage'), schedule.dosage, Icons.colorize_rounded),
            _buildDetailRow(lang.translate('times_of_day'), schedule.timesOfDay.join(', '), Icons.access_time_rounded),
            _buildDetailRow(lang.translate('food_relation'), _getFoodRelationLabel(schedule.foodRelation, lang), Icons.restaurant_rounded),
            if (schedule.durationDays != null)
              _buildDetailRow(lang.translate('duration'), '${schedule.durationDays} ${lang.translate('days')}', Icons.date_range_rounded),

            Padding(
              padding: const EdgeInsets.only(bottom: 12, top: 4),
              child: DateRangePickerWidget(
                label: '${lang.translate('course_duration')} (${lang.translate('from_date')} - ${lang.translate('to_date')})',
                fromDate: schedule.startDate ?? DateTime.now(),
                toDate: schedule.endDate ?? (schedule.startDate ?? DateTime.now()).add(Duration(days: schedule.durationDays ?? 7)),
                onFromDateChanged: (dt) {
                  setState(() => schedule.startDate = dt);
                },
                onToDateChanged: (dt) {
                  setState(() => schedule.endDate = dt);
                },
              ),
            ),

            Row(
              children: [
                const Icon(Icons.record_voice_over_rounded, size: 16, color: AppColors.forest),
                const SizedBox(width: 8),
                Text(
                  '${lang.translate('voice_reminder_language')}: ',
                  style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: AppColors.ink),
                ),
                InkWell(
                  onTap: () => VoiceSettingsDialog.show(context),
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppColors.mint,
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                    ),
                    child: Text(
                      TtsService.voiceLanguage == 'bn'
                          ? 'বাংলা (Bengali)'
                          : (TtsService.voiceLanguage == 'en' ? 'English' : lang.translate('voice_lang_auto')),
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: AppColors.forest),
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: PillButton(
                    label: lang.translate('cancel'),
                    variant: PillButtonVariant.subtle,
                    onPressed: () => _cancelSchedule(msgIndex),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: PillButton(
                    label: lang.translate('confirm_and_save'),
                    icon: Icons.check_rounded,
                    variant: PillButtonVariant.primary,
                    customColor: AppColors.coral,
                    onPressed: () => _confirmSchedule(schedule, msgIndex),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: AppColors.forest),
          const SizedBox(width: 8),
          Text(
            '$label: ',
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: AppColors.ink),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 13, color: AppColors.muted, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  String _getFoodRelationLabel(String relation, AppLanguage lang) {
    switch (relation) {
      case 'BeforeMeal':
      case 'BeforeFood':
        return lang.translate('before_meal');
      case 'AfterMeal':
      case 'AfterFood':
        return lang.translate('after_meal');
      case 'WithMeal':
      case 'WithFood':
        return lang.translate('with_meal');
      default:
        return lang.translate('no_relation');
    }
  }
}

class _SarvamVoiceInputSheet extends StatefulWidget {
  final Function(String text) onRecognized;

  const _SarvamVoiceInputSheet({required this.onRecognized});

  @override
  State<_SarvamVoiceInputSheet> createState() => _SarvamVoiceInputSheetState();
}

class _SarvamVoiceInputSheetState extends State<_SarvamVoiceInputSheet>
    with SingleTickerProviderStateMixin {
  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _isListening = false;
  String _recognizedText = '';
  String? _errorMessage;
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);
    _initializeAndStartListening();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _speech.stop();
    super.dispose();
  }

  Future<void> _initializeAndStartListening() async {
    setState(() {
      _errorMessage = null;
      _recognizedText = '';
    });

    try {
      final available = await _speech.initialize(
        onStatus: (status) {
          if (status == 'done' || status == 'notListening') {
            if (mounted) {
              setState(() => _isListening = false);
            }
          }
        },
        onError: (err) {
          if (mounted) {
            setState(() {
              _isListening = false;
              if (err.errorMsg != 'error_no_match') {
                _errorMessage = err.errorMsg;
              }
            });
          }
        },
      );

      if (!available) {
        if (mounted) {
          setState(() {
            _errorMessage = AppLanguage.instance.isBengali
                ? 'মাইক্রোফোন বা স্পিচ সার্ভিস পাওয়া যায়নি। অনুগ্রহ করে সেটিংস থেকে মাইক্রোফোনের অনুমতি দিন।'
                : 'Microphone permission or speech recognition is not available. Please grant permission in settings.';
          });
        }
        return;
      }

      _startListening();
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString();
        });
      }
    }
  }

  Future<void> _startListening() async {
    final lang = AppLanguage.instance;
    final isBn = lang.isBengali;

    String localeId = isBn ? 'bn_IN' : 'en_IN';
    try {
      final locales = await _speech.locales();
      final hasBn = locales.any((l) => l.localeId.toLowerCase().startsWith('bn'));
      final hasEn = locales.any((l) => l.localeId.toLowerCase().startsWith('en'));
      if (isBn && hasBn) {
        localeId = locales.firstWhere((l) => l.localeId.toLowerCase().startsWith('bn')).localeId;
      } else if (!isBn && hasEn) {
        localeId = locales.firstWhere((l) => l.localeId.toLowerCase().startsWith('en')).localeId;
      }
    } catch (_) {}

    setState(() {
      _isListening = true;
      _errorMessage = null;
    });

    try {
      await _speech.listen(
        onResult: (result) {
          if (mounted) {
            setState(() {
              _recognizedText = result.recognizedWords;
            });
            if (result.finalResult && _recognizedText.trim().isNotEmpty) {
              _sendText(_recognizedText);
            }
          }
        },
        listenOptions: stt.SpeechListenOptions(
          listenMode: stt.ListenMode.confirmation,
          partialResults: true,
          cancelOnError: false,
          localeId: localeId,
        ),
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _isListening = false;
          _errorMessage = e.toString();
        });
      }
    }
  }

  Future<void> _stopListening() async {
    await _speech.stop();
    setState(() => _isListening = false);
  }

  void _sendText(String text) {
    final clean = text.trim();
    if (clean.isEmpty) return;
    _speech.stop();
    Navigator.pop(context);
    widget.onRecognized(clean);
  }

  @override
  Widget build(BuildContext context) {
    final lang = AppLanguage.instance;
    final englishPrompts = [
      'Take Paracetamol 500mg twice daily at 8:00 AM and 8:00 PM after food',
      'Give Papa Metformin 500mg at 9:00 AM after breakfast for 14 days',
      'Take Vitamin D 1000IU once daily at 10:00 AM before food',
    ];
    final bengaliPrompts = [
      'বাবাকে প্রতিদিন সকাল ৮টা এবং রাত ৯টায় খাওয়ার পর মেটফর্মিন ৫০০ এমজি দিতে হবে ৭ দিন',
      'প্রতিদিন দুপুর ২টায় খাওয়ার পর প্যারাসিটামল ৫০০ এমজি খাও',
      'প্রতিদিন সকাল ১০টায় খালি পেটে প্যান্টোপ্রাজল ৪০ এমজি দিতে হবে',
    ];
    final suggestions = lang.isBengali ? bengaliPrompts : englishPrompts;

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.creamLight,
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.modal)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      child: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: const BoxDecoration(
                          color: AppColors.mint,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.mic_rounded, color: AppColors.forest, size: 24),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        lang.translate('serbom_voice_input'),
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: AppColors.ink),
                      ),
                    ],
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, color: AppColors.muted),
                    onPressed: () {
                      _speech.stop();
                      Navigator.pop(context);
                    },
                  ),
                ],
              ),
              const SizedBox(height: 20),

              Center(
                child: GestureDetector(
                  onTap: () {
                    if (_isListening) {
                      _stopListening();
                    } else {
                      _startListening();
                    }
                  },
                  child: AnimatedBuilder(
                    animation: _pulseController,
                    builder: (context, child) {
                      final scale = _isListening ? 1.0 + (_pulseController.value * 0.15) : 1.0;
                      return Transform.scale(
                        scale: scale,
                        child: Container(
                          width: 80,
                          height: 80,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: _isListening ? AppColors.coral : AppColors.forest,
                            boxShadow: [
                              BoxShadow(
                                color: (_isListening ? AppColors.coral : AppColors.forest).withValues(alpha: 0.35),
                                blurRadius: _isListening ? 20 : 10,
                                spreadRadius: _isListening ? 6 : 2,
                              ),
                            ],
                          ),
                          child: Icon(
                            _isListening ? Icons.mic_rounded : Icons.mic_none_rounded,
                            color: Colors.white,
                            size: 38,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
              const SizedBox(height: 14),

              Center(
                child: Text(
                  _isListening
                      ? (lang.isBengali ? '🎙️ কথা বলুন... আমি শুনছি' : '🎙️ Listening... Speak now')
                      : (_recognizedText.isNotEmpty
                          ? (lang.isBengali ? '✓ কণ্ঠ শনাক্ত হয়েছে' : '✓ Speech Captured')
                          : (lang.isBengali ? 'মাইক্রোফোনে ট্যাপ করে কথা বলুন' : 'Tap microphone to speak')),
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: _isListening ? AppColors.coral : AppColors.forest,
                  ),
                ),
              ),
              const SizedBox(height: 12),

              if (_recognizedText.isNotEmpty) ...[
                SoftCard(
                  backgroundColor: Colors.white,
                  radius: AppRadius.control,
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            lang.isBengali ? 'শনাক্তকৃত বক্তব্য:' : 'Recognized Speech:',
                            style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: AppColors.muted),
                          ),
                          InkWell(
                            onTap: () => _sendText(_recognizedText),
                            child: Row(
                              children: [
                                Text(
                                  lang.isBengali ? 'পাঠান' : 'Send',
                                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: AppColors.forest),
                                ),
                                const SizedBox(width: 4),
                                const Icon(Icons.send_rounded, size: 14, color: AppColors.forest),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _recognizedText,
                        style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, color: AppColors.ink),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                PillButton(
                  label: lang.isBengali ? 'রিমাইন্ডার তৈরি করুন' : 'Create Reminder',
                  icon: Icons.check_circle_rounded,
                  variant: PillButtonVariant.primary,
                  customColor: AppColors.coral,
                  onPressed: () => _sendText(_recognizedText),
                ),
                const SizedBox(height: 16),
              ],

              if (_errorMessage != null) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.peach.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(AppRadius.control),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline_rounded, color: AppColors.missed, size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _errorMessage!,
                          style: const TextStyle(fontSize: 12, color: AppColors.missed, fontWeight: FontWeight.w600),
                        ),
                      ),
                      TextButton(
                        onPressed: _initializeAndStartListening,
                        child: Text(lang.isBengali ? 'পুনরায় চেষ্টা' : 'Retry'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
              ],

              const Divider(color: AppColors.softBorder),
              const SizedBox(height: 8),
              Text(
                lang.isBengali
                    ? 'অথবা নিচের যেকোনো উদাহরণে ট্যাপ করুন:'
                    : 'Or tap a quick example below:',
                style: const TextStyle(fontSize: 12, color: AppColors.muted, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 10),
              ...suggestions.map(
                (prompt) => Padding(
                  padding: const EdgeInsets.only(bottom: 8.0),
                  child: SoftCard(
                    backgroundColor: Colors.white,
                    radius: AppRadius.control,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    onTap: () => _sendText(prompt),
                    child: Row(
                      children: [
                        const Icon(Icons.record_voice_over_rounded, color: AppColors.forest, size: 18),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            prompt,
                            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppColors.ink),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
