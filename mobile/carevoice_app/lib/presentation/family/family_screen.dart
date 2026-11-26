import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../../core/firebase_service.dart';
import '../../core/localization.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_tokens.dart';
import '../../data/auth_repository.dart';
import '../../data/family_repository.dart';
import '../../data/medicine_repository.dart';
import '../../domain/models.dart';
import '../widgets/avatar_badge.dart';
import '../widgets/empty_state.dart';
import '../widgets/icon_tile_button.dart';
import '../widgets/pill_button.dart';
import '../widgets/section_header.dart';
import '../widgets/soft_card.dart';
import '../widgets/soft_text_field.dart';
import 'family_group_screen.dart';

class FamilyScreen extends StatefulWidget {
  const FamilyScreen({super.key});

  @override
  State<FamilyScreen> createState() => _FamilyScreenState();
}

class _FamilyScreenState extends State<FamilyScreen> {
  final _familyRepo = FamilyRepository();
  final _authRepo = AuthRepository();
  List<FamilyMemberModel> _members = [];
  bool _isLoading = true;
  String? _errorMessage;
  Timer? _pollingTimer;

  @override
  void initState() {
    super.initState();
    _loadMembers();
    _pollingTimer = Timer.periodic(const Duration(seconds: 8), (_) {
      if (mounted) _loadMembers(silent: true);
    });
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadMembers({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });
    }

    try {
      final members = await _familyRepo.getFamilyMembers();
      if (mounted) {
        setState(() {
          _members = members;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted && !silent) {
        setState(() {
          _errorMessage = e.toString().replaceAll('Exception: ', '');
          _isLoading = false;
        });
      }
    }
  }

  void _showAddMemberDialog() {
    final nameCtrl = TextEditingController();
    final usernameCtrl = TextEditingController();
    final passwordCtrl = TextEditingController();
    bool createCredentials = true;
    bool addToCurrentFamily = false;
    bool obscurePassword = true;
    String relation = 'Parent';
    String lang = 'en';
    String voice = 'en-US-Standard-A';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final appLang = AppLanguage.instance;
          return Dialog(
            backgroundColor: Colors.transparent,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480, maxHeight: 600),
              child: SoftCard(
                backgroundColor: AppColors.creamLight,
                padding: const EdgeInsets.all(24),
                radius: AppRadius.modal,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: const BoxDecoration(
                              color: AppColors.sage,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.person_add_alt_1_rounded, color: AppColors.forest, size: 24),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              appLang.translate('add_member'),
                              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: AppColors.ink),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      SoftTextField(
                        controller: nameCtrl,
                        labelText: '${appLang.translate('full_name')} *',
                        prefixIcon: Icons.person_rounded,
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        isExpanded: true,
                        initialValue: relation,
                        decoration: const InputDecoration(
                          labelText: 'Relationship',
                          prefixIcon: Icon(Icons.group_rounded, color: AppColors.forest),
                        ),
                        items: const [
                          DropdownMenuItem(value: 'Parent', child: Text('Parent', overflow: TextOverflow.ellipsis)),
                          DropdownMenuItem(value: 'Grandmother', child: Text('Grandmother', overflow: TextOverflow.ellipsis)),
                          DropdownMenuItem(value: 'Grandfather', child: Text('Grandfather', overflow: TextOverflow.ellipsis)),
                          DropdownMenuItem(value: 'Spouse', child: Text('Spouse', overflow: TextOverflow.ellipsis)),
                          DropdownMenuItem(value: 'Child', child: Text('Child', overflow: TextOverflow.ellipsis)),
                          DropdownMenuItem(value: 'Sibling', child: Text('Sibling', overflow: TextOverflow.ellipsis)),
                          DropdownMenuItem(value: 'Other', child: Text('Other', overflow: TextOverflow.ellipsis)),
                        ],
                        onChanged: (val) {
                          if (val != null) setDialogState(() => relation = val);
                        },
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        isExpanded: true,
                        initialValue: lang,
                        decoration: const InputDecoration(
                          labelText: 'Preferred Language',
                          prefixIcon: Icon(Icons.language_rounded, color: AppColors.forest),
                        ),
                        items: const [
                          DropdownMenuItem(value: 'en', child: Text('English (en)', overflow: TextOverflow.ellipsis)),
                          DropdownMenuItem(value: 'bn', child: Text('বাংলা (Bengali - bn)', overflow: TextOverflow.ellipsis)),
                          DropdownMenuItem(value: 'hi', child: Text('Hindi (hi)', overflow: TextOverflow.ellipsis)),
                          DropdownMenuItem(value: 'es', child: Text('Spanish (es)', overflow: TextOverflow.ellipsis)),
                          DropdownMenuItem(value: 'fr', child: Text('French (fr)', overflow: TextOverflow.ellipsis)),
                        ],
                        onChanged: (val) {
                          if (val != null) {
                            setDialogState(() {
                              lang = val;
                              if (val == 'bn') voice = 'bn-IN-Standard-A';
                              if (val == 'en') voice = 'en-US-Standard-A';
                            });
                          }
                        },
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        isExpanded: true,
                        initialValue: voice,
                        decoration: const InputDecoration(
                          labelText: 'Voice Alert Preference',
                          prefixIcon: Icon(Icons.record_voice_over_rounded, color: AppColors.forest),
                        ),
                        items: const [
                          DropdownMenuItem(value: 'bn-IN-Standard-A', child: Text('বাংলা (Bengali Voice Alert)', overflow: TextOverflow.ellipsis)),
                          DropdownMenuItem(value: 'en-US-Standard-A', child: Text('English (US Female)', overflow: TextOverflow.ellipsis)),
                          DropdownMenuItem(value: 'en-US-Standard-B', child: Text('English (US Male)', overflow: TextOverflow.ellipsis)),
                          DropdownMenuItem(value: 'es-ES-Standard-A', child: Text('Spanish (Standard)', overflow: TextOverflow.ellipsis)),
                        ],
                        onChanged: (val) {
                          if (val != null) setDialogState(() => voice = val);
                        },
                      ),
                      const SizedBox(height: 16),

                      Container(
                        decoration: BoxDecoration(
                          color: createCredentials ? AppColors.mint.withValues(alpha: 0.4) : AppColors.cream,
                          borderRadius: BorderRadius.circular(AppRadius.control),
                          border: Border.all(
                            color: createCredentials ? AppColors.forest.withValues(alpha: 0.3) : AppColors.muted.withValues(alpha: 0.2),
                          ),
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            SwitchListTile(
                              contentPadding: EdgeInsets.zero,
                              title: Text(
                                appLang.translate('create_member_credentials'),
                                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5, color: AppColors.ink),
                              ),
                              subtitle: Text(
                                appLang.translate('create_credentials_subtitle'),
                                style: const TextStyle(fontSize: 11.5, color: AppColors.muted),
                              ),
                              value: createCredentials,
                              activeThumbColor: AppColors.forest,
                              onChanged: (val) {
                                setDialogState(() => createCredentials = val);
                              },
                            ),
                            if (createCredentials) ...[
                              const Divider(height: 16),
                              SoftTextField(
                                controller: usernameCtrl,
                                labelText: 'Member Email / Login ID *',
                                hintText: 'e.g. member@carevoice.app or papa123',
                                prefixIcon: Icons.alternate_email_rounded,
                              ),
                              const SizedBox(height: 10),
                              SoftTextField(
                                controller: passwordCtrl,
                                obscureText: obscurePassword,
                                labelText: '${appLang.translate('member_password')} *',
                                hintText: appLang.translate('member_password_hint'),
                                prefixIcon: Icons.lock_outline_rounded,
                                suffixIcon: IconButton(
                                  icon: Icon(
                                    obscurePassword ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                                    size: 20,
                                    color: AppColors.forest,
                                  ),
                                  onPressed: () {
                                    setDialogState(() => obscurePassword = !obscurePassword);
                                  },
                                ),
                              ),
                              const SizedBox(height: 10),

                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: addToCurrentFamily ? AppColors.mint.withValues(alpha: 0.6) : AppColors.cream,
                                  borderRadius: BorderRadius.circular(AppRadius.control),
                                  border: Border.all(
                                    color: addToCurrentFamily ? AppColors.forest : AppColors.muted.withValues(alpha: 0.3),
                                  ),
                                ),
                                child: SwitchListTile(
                                  contentPadding: EdgeInsets.zero,
                                  dense: true,
                                  title: Text(
                                    appLang.isBengali ? 'বর্তমান পরিবারে সদস্য হিসেবে যুক্ত করুন' : 'Add to Current Family',
                                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: AppColors.ink),
                                  ),
                                  subtitle: Text(
                                    appLang.isBengali
                                        ? (addToCurrentFamily
                                            ? 'সদস্যটি এই পরিবারের অধীনে যুক্ত হবে।'
                                            : 'স্বতন্ত্র অ্যাকাউন্ট তৈরি হবে। পরিবারে যুক্ত হবে না।')
                                        : (addToCurrentFamily
                                            ? 'Member will be added to this family upon creation.'
                                            : 'Account created independently without family assignment.'),
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: addToCurrentFamily ? AppColors.forest : AppColors.muted,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  value: addToCurrentFamily,
                                  activeThumbColor: AppColors.forest,
                                  onChanged: (val) => setDialogState(() => addToCurrentFamily = val),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                      Row(
                        children: [
                          Expanded(
                            child: PillButton(
                              label: appLang.translate('cancel'),
                              variant: PillButtonVariant.subtle,
                              onPressed: () => Navigator.pop(ctx),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: PillButton(
                              label: appLang.translate('add_member'),
                              variant: PillButtonVariant.primary,
                              customColor: AppColors.forest,
                              onPressed: () async {
                                if (nameCtrl.text.trim().isEmpty) return;
                                if (createCredentials) {
                                  if (usernameCtrl.text.trim().isEmpty) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text(appLang.translate('username_required'))),
                                    );
                                    return;
                                  }
                                  if (passwordCtrl.text.length < 6) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text(appLang.translate('password_min_length'))),
                                    );
                                    return;
                                  }
                                }

                                Navigator.pop(ctx);
                                final storage = const FlutterSecureStorage();
                                final activeFamilyId = await storage.read(key: 'carevoice_active_family_id') ?? 'family_default';

                                try {
                                  if (createCredentials) {
                                    if (!addToCurrentFamily) {
                                      await _authRepo.createMemberAccount(
                                        email: usernameCtrl.text.trim(),
                                        password: passwordCtrl.text,
                                        fullName: nameCtrl.text.trim(),
                                        role: 'Family Member',
                                        assignToFamilyId: null,
                                        isEmailVerified: true,
                                      );
                                      if (mounted) {
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(
                                            content: Text(appLang.isBengali
                                                ? 'স্বতন্ত্র লগইন অ্যাকাউন্ট তৈরি হয়েছে (পরিবারে যুক্ত করা হয়নি)'
                                                : 'Login account created independently. User was not added to family.'),
                                            backgroundColor: AppColors.forest,
                                          ),
                                        );
                                      }
                                    } else {
                                      await _authRepo.createMemberAccount(
                                        email: usernameCtrl.text.trim(),
                                        password: passwordCtrl.text,
                                        fullName: nameCtrl.text.trim(),
                                        role: 'Family Member',
                                        assignToFamilyId: activeFamilyId,
                                        isEmailVerified: true,
                                      );
                                      await _familyRepo.createFamilyMember(
                                        fullName: nameCtrl.text.trim(),
                                        relation: relation,
                                        preferredLanguage: lang,
                                        voicePreference: voice,
                                        username: usernameCtrl.text.trim(),
                                        password: passwordCtrl.text,
                                        familyId: activeFamilyId,
                                      );
                                      _loadMembers();
                                      if (mounted) {
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(
                                            content: Text(appLang.isBengali 
                                                ? 'পারিবারিক সদস্য এবং লগইন অ্যাকাউন্ট সফলভাবে তৈরি হয়েছে!' 
                                                : 'Family member and login account created successfully!'),
                                            backgroundColor: AppColors.forest,
                                          ),
                                        );
                                      }
                                    }
                                  } else {
                                    await _familyRepo.createFamilyMember(
                                      fullName: nameCtrl.text.trim(),
                                      relation: relation,
                                      preferredLanguage: lang,
                                      voicePreference: voice,
                                      familyId: activeFamilyId,
                                    );
                                    _loadMembers();
                                    if (mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(
                                          content: Text(appLang.isBengali 
                                              ? 'পারিবারিক সদস্য সফলভাবে যুক্ত হয়েছে!' 
                                              : 'Family member added successfully!'),
                                          backgroundColor: AppColors.forest,
                                        ),
                                      );
                                    }
                                  }
                                } catch (e) {
                                  if (mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(e.toString().replaceAll('Exception: ', '')),
                                        backgroundColor: AppColors.missed,
                                      ),
                                    );
                                  }
                                }
                              },
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  void _showEditMemberDialog(FamilyMemberModel member) {
    final nameCtrl = TextEditingController(text: member.fullName);
    String relation = member.relation;
    const allowedLangs = ['en', 'bn', 'hi', 'es', 'fr'];
    const allowedVoices = ['bn-IN-Standard-A', 'en-US-Standard-A', 'en-US-Standard-B', 'es-ES-Standard-A'];
    String lang = allowedLangs.contains(member.preferredLanguage) ? member.preferredLanguage : 'en';
    String voice = allowedVoices.contains(member.voicePreference) ? member.voicePreference : 'en-US-Standard-A';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => Dialog(
          backgroundColor: Colors.transparent,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: SoftCard(
              backgroundColor: AppColors.creamLight,
              padding: const EdgeInsets.all(24),
              radius: AppRadius.modal,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Edit ${member.fullName}',
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: AppColors.ink),
                    ),
                    const SizedBox(height: 16),
                    SoftTextField(
                      controller: nameCtrl,
                      labelText: 'Full Name *',
                      prefixIcon: Icons.person_rounded,
                    ),
                    const SizedBox(height: 12),
                    if (!member.isSelf) ...[
                      SoftTextField(
                        controller: TextEditingController(text: relation),
                        labelText: 'Relationship',
                        prefixIcon: Icons.group_rounded,
                        onChanged: (val) => relation = val,
                      ),
                      const SizedBox(height: 12),
                    ],
                    DropdownButtonFormField<String>(
                      isExpanded: true,
                      initialValue: lang,
                      decoration: const InputDecoration(
                        labelText: 'Preferred Language',
                        prefixIcon: Icon(Icons.language_rounded, color: AppColors.forest),
                      ),
                      items: const [
                        DropdownMenuItem(value: 'en', child: Text('English (en)', overflow: TextOverflow.ellipsis)),
                        DropdownMenuItem(value: 'bn', child: Text('বাংলা (Bengali - bn)', overflow: TextOverflow.ellipsis)),
                        DropdownMenuItem(value: 'hi', child: Text('Hindi (hi)', overflow: TextOverflow.ellipsis)),
                        DropdownMenuItem(value: 'es', child: Text('Spanish (es)', overflow: TextOverflow.ellipsis)),
                        DropdownMenuItem(value: 'fr', child: Text('French (fr)', overflow: TextOverflow.ellipsis)),
                      ],
                      onChanged: (val) {
                        if (val != null) {
                          setDialogState(() {
                            lang = val;
                            if (val == 'bn') voice = 'bn-IN-Standard-A';
                            if (val == 'en') voice = 'en-US-Standard-A';
                          });
                        }
                      },
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      isExpanded: true,
                      initialValue: voice,
                      decoration: const InputDecoration(
                        labelText: 'Voice Alert Preference',
                        prefixIcon: Icon(Icons.record_voice_over_rounded, color: AppColors.forest),
                      ),
                      items: const [
                        DropdownMenuItem(value: 'bn-IN-Standard-A', child: Text('বাংলা (Bengali Voice Alert)', overflow: TextOverflow.ellipsis)),
                        DropdownMenuItem(value: 'en-US-Standard-A', child: Text('English (US Female)', overflow: TextOverflow.ellipsis)),
                        DropdownMenuItem(value: 'en-US-Standard-B', child: Text('English (US Male)', overflow: TextOverflow.ellipsis)),
                        DropdownMenuItem(value: 'es-ES-Standard-A', child: Text('Spanish (Standard)', overflow: TextOverflow.ellipsis)),
                      ],
                      onChanged: (val) {
                        if (val != null) setDialogState(() => voice = val);
                      },
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Expanded(
                          child: PillButton(
                            label: 'Cancel',
                            variant: PillButtonVariant.subtle,
                            onPressed: () => Navigator.pop(ctx),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: PillButton(
                            label: 'Save Changes',
                            variant: PillButtonVariant.primary,
                            customColor: AppColors.forest,
                            onPressed: () async {
                              Navigator.pop(ctx);
                              try {
                                await _familyRepo.updateFamilyMember(
                                  id: member.id,
                                  fullName: nameCtrl.text.trim(),
                                  relation: relation,
                                  preferredLanguage: lang,
                                  voicePreference: voice,
                                );
                                _loadMembers();
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('Member updated successfully!'), backgroundColor: AppColors.forest),
                                  );
                                }
                              } catch (e) {
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text(e.toString().replaceAll('Exception: ', ''))),
                                  );
                                }
                              }
                            },
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showDeleteDialog(FamilyMemberModel member) {
    if (member.isSelf) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cannot delete default Self profile.')),
      );
      return;
    }

    final lang = AppLanguage.instance;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.control)),
        backgroundColor: AppColors.creamLight,
        title: Row(
          children: [
            const Icon(Icons.person_remove_rounded, color: AppColors.missed, size: 24),
            const SizedBox(width: 8),
            Text(
              lang.isBengali ? 'সদস্য অপসারণ নিশ্চিত করুন' : 'Remove from Family',
              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: AppColors.ink),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              lang.isBengali
                  ? 'আপনি কি নিশ্চিত যে "${member.fullName}"-কে এই পরিবার থেকে সরিয়ে দিতে চান?'
                  : 'Are you sure you want to remove "${member.fullName}" from this family?',
              style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: AppColors.ink),
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.sage.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(AppRadius.control),
              ),
              child: Text(
                lang.isBengali
                    ? 'নোট: ব্যবহারকারীর কেয়ারভয়েস অ্যাকাউন্ট মুছে যাবে না এবং তাদের অন্যান্য পরিবারের সদস্যপদ অক্ষুণ্ণ থাকবে।'
                    : 'Note: Their CareVoice account will NOT be deleted, and their membership in other families remains unchanged.',
                style: const TextStyle(fontSize: 11.5, color: AppColors.forest, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(lang.translate('cancel'), style: const TextStyle(color: AppColors.muted, fontWeight: FontWeight.bold)),
          ),
          PillButton(
            label: lang.isBengali ? 'পরিবার থেকে সরান' : 'Remove Member',
            variant: PillButtonVariant.primary,
            customColor: AppColors.missed,
            height: 36,
            onPressed: () async {
              Navigator.pop(ctx);
              final deletedId = member.id;
              final deletedName = member.fullName;
              final memberEmail = member.username;

              setState(() {
                _members.removeWhere((m) => m.id == deletedId);
              });

              try {
                await _familyRepo.deleteFamilyMember(deletedId, memberEmail: memberEmail);
                try {
                  final activeGroups = await MedicineRepository().getAllMyFamilyGroups();
                  for (final g in activeGroups) {
                    FirebaseService.instance.broadcastFamilyUpdate(
                      familyId: g.id,
                      type: 'member_removed',
                      title: 'Member removed: $deletedName',
                      titleBn: 'সদস্য সরানো হয়েছে: $deletedName',
                      description: '$deletedName was removed from the family group.',
                      descriptionBn: '$deletedName-কে পরিবার থেকে সরানো হয়েছে।',
                      actorName: 'Family Admin',
                    );
                  }
                } catch (_) {}

                await _loadMembers(silent: true);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(lang.isBengali
                          ? '$deletedName-কে এই পরিবার থেকে সফলভাবে সরানো হয়েছে।'
                          : '$deletedName removed from this family group.'),
                      backgroundColor: AppColors.forest,
                    ),
                  );
                }
              } catch (e) {
                await _loadMembers();
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(e.toString().replaceAll('Exception: ', ''))),
                  );
                }
              }
            },
          ),
        ],
      ),
    );
  }

  void _showAddExistingMemberDialog() {
    final emailCtrl = TextEditingController();
    String relation = 'Parent';
    bool isSubmitting = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final lang = AppLanguage.instance;
          return Dialog(
            backgroundColor: Colors.transparent,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: SoftCard(
                backgroundColor: AppColors.creamLight,
                padding: const EdgeInsets.all(24),
                radius: AppRadius.modal,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: const BoxDecoration(
                            color: AppColors.mint,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.person_add_alt_rounded, color: AppColors.forest, size: 22),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            lang.isBengali ? 'বিদ্যমান সদস্য যোগ করুন' : 'Add Existing User by Email',
                            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 17, color: AppColors.ink),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      lang.isBengali
                          ? 'পূর্বে নিবন্ধিত ব্যবহারকারীর ইমেল দিয়ে এই পরিবারে যুক্ত করুন।'
                          : 'Add a previously registered user into this family using their email address.',
                      style: const TextStyle(fontSize: 12, color: AppColors.muted),
                    ),
                    const SizedBox(height: 16),
                    SoftTextField(
                      controller: emailCtrl,
                      labelText: '${lang.translate('email_address')} *',
                      hintText: 'e.g. member@carevoice.app',
                      prefixIcon: Icons.email_rounded,
                      keyboardType: TextInputType.emailAddress,
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      isExpanded: true,
                      initialValue: relation,
                      decoration: const InputDecoration(
                        labelText: 'Relationship in Family',
                        prefixIcon: Icon(Icons.group_rounded, color: AppColors.forest),
                      ),
                      items: const [
                        DropdownMenuItem(value: 'Parent', child: Text('Parent')),
                        DropdownMenuItem(value: 'Grandmother', child: Text('Grandmother')),
                        DropdownMenuItem(value: 'Grandfather', child: Text('Grandfather')),
                        DropdownMenuItem(value: 'Spouse', child: Text('Spouse')),
                        DropdownMenuItem(value: 'Child', child: Text('Child')),
                        DropdownMenuItem(value: 'Sibling', child: Text('Sibling')),
                        DropdownMenuItem(value: 'Other', child: Text('Other')),
                      ],
                      onChanged: (val) {
                        if (val != null) setDialogState(() => relation = val);
                      },
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Expanded(
                          child: PillButton(
                            label: lang.translate('cancel'),
                            variant: PillButtonVariant.subtle,
                            onPressed: () => Navigator.pop(ctx),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: PillButton(
                            label: lang.isBengali ? 'যোগ করুন' : 'Add to Family',
                            variant: PillButtonVariant.primary,
                            customColor: AppColors.forest,
                            isLoading: isSubmitting,
                            onPressed: () async {
                              final email = emailCtrl.text.trim();
                              if (email.isEmpty) return;
                              setDialogState(() => isSubmitting = true);
                              try {
                                final member = await _familyRepo.addExistingUserToFamily(
                                  email: email,
                                  relation: relation,
                                );
                                if (ctx.mounted) Navigator.pop(ctx);
                                _loadMembers();
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(lang.isBengali
                                          ? '${member.fullName} (${member.username})-কে পরিবারে সফলভাবে যুক্ত করা হয়েছে!'
                                          : '${member.fullName} added to family successfully!'),
                                      backgroundColor: AppColors.forest,
                                    ),
                                  );
                                }
                              } catch (e) {
                                setDialogState(() => isSubmitting = false);
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(e.toString().replaceAll('Exception: ', '')),
                                      backgroundColor: AppColors.missed,
                                    ),
                                  );
                                }
                              }
                            },
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  void _showInviteDialog() {
    final emailCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: SoftCard(
            backgroundColor: AppColors.creamLight,
            padding: const EdgeInsets.all(24),
            radius: AppRadius.modal,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Invite External Contact',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: AppColors.ink),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Send a secure invitation to link another CareVoice account (e.g. Elderly parent or relative).',
                  style: TextStyle(fontSize: 12.5, color: AppColors.muted),
                ),
                const SizedBox(height: 16),
                SoftTextField(
                  controller: emailCtrl,
                  labelText: 'Recipient Email Address *',
                  prefixIcon: Icons.email_rounded,
                  keyboardType: TextInputType.emailAddress,
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: PillButton(
                        label: 'Cancel',
                        variant: PillButtonVariant.subtle,
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: PillButton(
                        label: 'Create Invitation',
                        variant: PillButtonVariant.primary,
                        customColor: AppColors.coral,
                        onPressed: () async {
                          final email = emailCtrl.text.trim();
                          if (email.isEmpty) return;
                          Navigator.pop(ctx);
                          try {
                            final invite = await _familyRepo.createInvite(email);
                            if (mounted) {
                              _showGeneratedTokenDialog(invite);
                            }
                          } catch (e) {
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text(e.toString().replaceAll('Exception: ', ''))),
                              );
                            }
                          }
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showGeneratedTokenDialog(InviteModel invite) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.control)),
        title: const Row(
          children: [
            Icon(Icons.check_circle_rounded, color: AppColors.taken),
            SizedBox(width: 8),
            Text('Invitation Created'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Sent To: ${invite.invitedEmail}', style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            const Text('Share this secure invitation token with the recipient:'),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.cream,
                borderRadius: BorderRadius.circular(AppRadius.control),
              ),
              child: SelectableText(
                invite.inviteToken,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 13, fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(height: 8),
            const Text('Expires in 7 days', style: TextStyle(fontSize: 12, color: AppColors.muted)),
          ],
        ),
        actions: [
          PillButton(
            label: 'Copy Token',
            icon: Icons.copy_rounded,
            variant: PillButtonVariant.primary,
            customColor: AppColors.forest,
            height: 36,
            onPressed: () {
              Clipboard.setData(ClipboardData(text: invite.inviteToken));
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Token copied to clipboard!'), backgroundColor: AppColors.forest),
              );
            },
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void _showAcceptInviteDialog() {
    final tokenCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: SoftCard(
            backgroundColor: AppColors.creamLight,
            padding: const EdgeInsets.all(24),
            radius: AppRadius.modal,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Accept Caregiver Invitation',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: AppColors.ink),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Enter the invitation token received from your caregiver to link accounts and grant reminder permissions.',
                  style: TextStyle(fontSize: 12.5, color: AppColors.muted),
                ),
                const SizedBox(height: 16),
                SoftTextField(
                  controller: tokenCtrl,
                  labelText: 'Invite Token *',
                  prefixIcon: Icons.vpn_key_rounded,
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: PillButton(
                        label: 'Cancel',
                        variant: PillButtonVariant.subtle,
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: PillButton(
                        label: 'Accept & Link',
                        variant: PillButtonVariant.primary,
                        customColor: AppColors.forest,
                        onPressed: () async {
                          final token = tokenCtrl.text.trim();
                          if (token.isEmpty) return;
                          Navigator.pop(ctx);
                          try {
                            await _familyRepo.acceptInvite(token);
                            _loadMembers();
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Invitation accepted! Linked successfully.'), backgroundColor: AppColors.forest),
                              );
                            }
                          } catch (e) {
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text(e.toString().replaceAll('Exception: ', ''))),
                              );
                            }
                          }
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.cream,
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppColors.coral))
          : _errorMessage != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.error_outline_rounded, size: 48, color: AppColors.missed),
                        const SizedBox(height: 12),
                        Text(_errorMessage!, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.missed)),
                        const SizedBox(height: 16),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            PillButton(
                              label: 'Retry',
                              variant: PillButtonVariant.primary,
                              icon: Icons.refresh_rounded,
                              onPressed: _loadMembers,
                            ),
                            const SizedBox(width: 12),
                            PillButton(
                              label: 'Log In Again',
                              variant: PillButtonVariant.outlined,
                              icon: Icons.login_rounded,
                              onPressed: () async {
                                final nav = Navigator.of(context);
                                final storage = const FlutterSecureStorage();
                                await storage.deleteAll();
                                if (mounted) {
                                  nav.pushNamedAndRemoveUntil('/login', (route) => false);
                                }
                              },
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                )
              : RefreshIndicator(
                  color: AppColors.forest,
                  backgroundColor: AppColors.creamLight,
                  onRefresh: _loadMembers,
                  child: ListView(
                    padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 20.0),
                    children: [
                      SoftCard(
                        backgroundColor: AppColors.mint,
                        radius: AppRadius.card,
                        padding: const EdgeInsets.all(18),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => const FamilyGroupScreen()),
                          );
                        },
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: const BoxDecoration(
                                color: Colors.white,
                                shape: BoxShape.circle,
                                boxShadow: AppShadows.subtle,
                              ),
                              child: const Icon(Icons.groups_3_rounded, color: AppColors.forest, size: 28),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    AppLanguage.instance.translate('family_group_title'),
                                    style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16.5, color: AppColors.ink),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    AppLanguage.instance.isBengali
                                        ? 'ইউনিক কোড দিয়ে পরিবার পরিচালনা ও রিয়েল-টাইম আপডেট'
                                        : 'Manage Unique Code, Member Approvals & Shared Updates',
                                    style: const TextStyle(fontSize: 12, color: AppColors.muted, fontWeight: FontWeight.w600),
                                  ),
                                ],
                              ),
                            ),
                            const Icon(Icons.arrow_forward_ios_rounded, size: 16, color: AppColors.forest),
                          ],
                        ),
                      ),
                      const SizedBox(height: 18),

                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          PillButton(
                            label: AppLanguage.instance.isBengali ? 'ফ্যামিলি কোর্ট (কোড/আবিষ্কার)' : 'Family Court / Code',
                            icon: Icons.hub_rounded,
                            variant: PillButtonVariant.tinted,
                            customColor: AppColors.butter,
                            customTextColor: AppColors.forest,
                            height: 44,
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(builder: (_) => const FamilyGroupScreen()),
                              );
                            },
                          ),
                          PillButton(
                            label: 'Add Member',
                            icon: Icons.person_add_rounded,
                            variant: PillButtonVariant.primary,
                            customColor: AppColors.coral,
                            height: 44,
                            onPressed: _showAddMemberDialog,
                          ),
                          PillButton(
                            label: AppLanguage.instance.isBengali ? 'ইমেল দিয়ে সদস্য যোগ' : 'Add by Email',
                            icon: Icons.person_search_rounded,
                            variant: PillButtonVariant.tinted,
                            customColor: AppColors.mint,
                            customTextColor: AppColors.forest,
                            height: 44,
                            onPressed: _showAddExistingMemberDialog,
                          ),
                          PillButton(
                            label: 'Invite Contact',
                            icon: Icons.mail_outline_rounded,
                            variant: PillButtonVariant.tinted,
                            customColor: AppColors.sage,
                            customTextColor: AppColors.forest,
                            height: 44,
                            onPressed: _showInviteDialog,
                          ),
                          PillButton(
                            label: 'Accept Invitation',
                            icon: Icons.link_rounded,
                            variant: PillButtonVariant.subtle,
                            height: 44,
                            onPressed: _showAcceptInviteDialog,
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),

                      SectionHeader(
                        title: 'Monitored Members (${_members.length})',
                        subtitle: 'Care recipients and linked family members',
                        icon: Icons.people_alt_rounded,
                        iconColor: AppColors.forest,
                      ),
                      const SizedBox(height: 10),

                      if (_members.isEmpty)
                        EmptyState(
                          icon: Icons.people_outline_rounded,
                          title: 'No Members Yet',
                          message: 'Add family members to monitor and share medication schedules.',
                          actionLabel: 'Add Member',
                          onAction: _showAddMemberDialog,
                        ),

                      ..._members.map((member) => Padding(
                            padding: const EdgeInsets.only(bottom: 12.0),
                            child: SoftCard(
                              backgroundColor: AppColors.creamLight,
                              radius: AppRadius.card,
                              padding: const EdgeInsets.all(16),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  AvatarBadge(
                                    name: member.fullName,
                                    relation: member.relation,
                                    size: 46,
                                    showRelationBadge: false,
                                  ),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Text(
                                              member.fullName,
                                              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: AppColors.ink),
                                            ),
                                            const SizedBox(width: 8),
                                            if (member.isSelf)
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                                decoration: BoxDecoration(
                                                  color: AppColors.mint,
                                                  borderRadius: BorderRadius.circular(AppRadius.pill),
                                                ),
                                                child: const Text('Self', style: TextStyle(color: AppColors.forest, fontSize: 10.5, fontWeight: FontWeight.w900)),
                                              ),
                                            if (member.hasLoginCredentials && member.username != null) ...[
                                              const SizedBox(width: 6),
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                                decoration: BoxDecoration(
                                                  color: AppColors.powder,
                                                  borderRadius: BorderRadius.circular(AppRadius.pill),
                                                ),
                                                child: Row(
                                                  mainAxisSize: MainAxisSize.min,
                                                  children: [
                                                    const Icon(Icons.account_circle_rounded, size: 12, color: AppColors.forest),
                                                    const SizedBox(width: 4),
                                                    Text(
                                                      member.username!,
                                                      style: const TextStyle(color: AppColors.forest, fontSize: 10.5, fontWeight: FontWeight.w800),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ],
                                          ],
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          'Relation: ${member.relation} • Voice: ${member.voicePreference} (${member.preferredLanguage})',
                                          style: const TextStyle(fontSize: 12, color: AppColors.muted),
                                        ),
                                        const SizedBox(height: 8),
                                        Wrap(
                                          spacing: 8,
                                          runSpacing: 4,
                                          children: [
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                              decoration: BoxDecoration(
                                                color: member.canSetReminders ? AppColors.mint : AppColors.cream,
                                                borderRadius: BorderRadius.circular(AppRadius.pill),
                                              ),
                                              child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Icon(
                                                    member.canSetReminders ? Icons.check_circle_rounded : Icons.cancel_rounded,
                                                    size: 13,
                                                    color: member.canSetReminders ? AppColors.taken : AppColors.muted,
                                                  ),
                                                  const SizedBox(width: 4),
                                                  Text(
                                                    'Can Set Reminders',
                                                    style: TextStyle(
                                                      fontSize: 10.5,
                                                      fontWeight: FontWeight.w700,
                                                      color: member.canSetReminders ? AppColors.forest : AppColors.muted,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                              decoration: BoxDecoration(
                                                color: member.canViewLogs ? AppColors.mint : AppColors.cream,
                                                borderRadius: BorderRadius.circular(AppRadius.pill),
                                              ),
                                              child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Icon(
                                                    member.canViewLogs ? Icons.check_circle_rounded : Icons.cancel_rounded,
                                                    size: 13,
                                                    color: member.canViewLogs ? AppColors.taken : AppColors.muted,
                                                  ),
                                                  const SizedBox(width: 4),
                                                  Text(
                                                    'Can View Logs',
                                                    style: TextStyle(
                                                      fontSize: 10.5,
                                                      fontWeight: FontWeight.w700,
                                                      color: member.canViewLogs ? AppColors.forest : AppColors.muted,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                  Row(
                                    children: [
                                      IconTileButton(
                                        icon: Icons.edit_rounded,
                                        tooltip: 'Edit Member',
                                        iconColor: AppColors.forest,
                                        backgroundColor: AppColors.sage,
                                        size: 32,
                                        onPressed: () => _showEditMemberDialog(member),
                                      ),
                                      if (!member.isSelf) ...[
                                        const SizedBox(width: 6),
                                        IconTileButton(
                                          icon: Icons.delete_outline_rounded,
                                          tooltip: 'Delete Member',
                                          iconColor: AppColors.missed,
                                          backgroundColor: AppColors.peach.withValues(alpha: 0.4),
                                          size: 32,
                                          onPressed: () => _showDeleteDialog(member),
                                        ),
                                      ],
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          )),
                    ],
                  ),
                ),
    );
  }
}
