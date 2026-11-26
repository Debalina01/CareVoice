import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/firebase_service.dart';
import '../../core/localization.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_tokens.dart';
import '../../data/medicine_repository.dart';
import '../../domain/models.dart';
import '../widgets/avatar_badge.dart';
import '../widgets/icon_tile_button.dart';
import '../widgets/pill_button.dart';
import '../widgets/section_header.dart';
import '../widgets/soft_card.dart';
import '../widgets/soft_text_field.dart';

class FamilyGroupScreen extends StatefulWidget {
  const FamilyGroupScreen({super.key});

  @override
  State<FamilyGroupScreen> createState() => _FamilyGroupScreenState();
}

class _FamilyGroupScreenState extends State<FamilyGroupScreen> {
  final _repository = MedicineRepository();
  final _joinCodeController = TextEditingController();

  FamilyGroupModel? _familyGroup;
  List<FamilyGroupModel> _allFamilies = [];
  List<SharedFamilyUpdateModel> _sharedUpdates = [];
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadFamilyGroup();
  }

  @override
  void dispose() {
    _joinCodeController.dispose();
    super.dispose();
  }

  Future<void> _loadFamilyGroup() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final group = await _repository.getMyFamilyGroup();
      List<FamilyGroupModel> allFams = [];
      try {
        allFams = await _repository.getAllMyFamilyGroups();
      } catch (_) {}

      List<SharedFamilyUpdateModel> updates = [];
      if (group != null) {
        updates = await _repository.getSharedFamilyUpdates(group.id);
        FirebaseService.instance.syncFamilyGroupToFirestore(
          familyId: group.id,
          familyCode: group.familyCode,
          familyName: group.name,
          creatorUserId: group.creatorUserId,
          creatorName: group.creatorName,
        );
      }

      setState(() {
        _familyGroup = group;
        _allFamilies = allFams;
        _sharedUpdates = updates;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = e.toString().replaceAll('Exception: ', '');
        _isLoading = false;
      });
    }
  }

  Future<void> _handleSwitchFamily(FamilyGroupModel fam) async {
    setState(() => _isLoading = true);
    await _repository.switchActiveFamily(fam.id);
    await _loadFamilyGroup();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLanguage.instance.isBengali
              ? 'সক্রিয় পরিবার পরিবর্তন করা হয়েছে: ${fam.name}'
              : 'Switched active family to "${fam.name}".'),
          backgroundColor: AppColors.forest,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _handleLeaveFamily(FamilyGroupModel fam) async {
    final lang = AppLanguage.instance;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.control)),
        backgroundColor: AppColors.creamLight,
        title: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, color: AppColors.coral, size: 24),
            const SizedBox(width: 8),
            Text(
              lang.isBengali ? 'পরিবার ত্যাগ করুন' : 'Leave Family',
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17, color: AppColors.ink),
            ),
          ],
        ),
        content: Text(
          lang.isBengali
              ? 'আপনি কি নিশ্চিত যে "${fam.name}" পরিবারটি ত্যাগ করতে চান? আপনি এই পরিবারের ওষুধের অনুস্মারক আর পাবেন না।'
              : 'Are you sure you want to leave "${fam.name}" (${fam.familyCode})? You will no longer receive medicine reminders for this family.',
          style: const TextStyle(fontSize: 13, color: AppColors.ink),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(lang.translate('cancel'), style: const TextStyle(color: AppColors.muted, fontWeight: FontWeight.bold)),
          ),
          PillButton(
            label: lang.isBengali ? 'ত্যাগ করুন' : 'Leave Family',
            variant: PillButtonVariant.primary,
            customColor: AppColors.coral,
            height: 36,
            onPressed: () => Navigator.pop(ctx, true),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      setState(() => _isLoading = true);
      try {
        await _repository.leaveFamily(fam.id);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(lang.isBengali
                  ? '"${fam.name}" পরিবার সফলভাবে ত্যাগ করা হয়েছে।'
                  : 'You have left "${fam.name}".'),
              backgroundColor: AppColors.forest,
            ),
          );
        }
        await _loadFamilyGroup();
      } catch (e) {
        setState(() => _isLoading = false);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: $e'), backgroundColor: AppColors.missed),
          );
        }
      }
    }
  }

  Future<void> _joinFamily() async {
    final code = _joinCodeController.text.trim();
    if (code.isEmpty) return;

    final lang = AppLanguage.instance;
    setState(() => _isLoading = true);

    try {
      final updated = await _repository.joinFamilyGroupByCode(code);
      _joinCodeController.clear();
      setState(() {
        _familyGroup = updated;
        _isLoading = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(lang.isBengali
                ? 'পরিবারে যুক্ত হওয়ার অনুরোধ সফলভাবে পাঠানো হয়েছে!'
                : 'Join request sent! Pending approval from family creator.'),
            backgroundColor: AppColors.forest,
          ),
        );
      }
      _loadFamilyGroup();
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString().replaceAll('Exception: ', '')),
            backgroundColor: AppColors.missed,
          ),
        );
      }
    }
  }

  Future<void> _approveMember(String targetUserId, String memberName) async {
    if (_familyGroup == null) return;
    final lang = AppLanguage.instance;

    try {
      final success = await _repository.approveFamilyMember(_familyGroup!.id, targetUserId);
      if (success) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(lang.isBengali
                  ? '$memberName-কে পরিবারে অনুমোদন করা হয়েছে!'
                  : '$memberName approved and added to the family!'),
              backgroundColor: AppColors.forest,
            ),
          );
        }
        _loadFamilyGroup();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: AppColors.missed),
        );
      }
    }
  }

  Future<void> _rejectMember(String targetUserId) async {
    if (_familyGroup == null) return;
    try {
      await _repository.rejectFamilyMember(_familyGroup!.id, targetUserId);
      _loadFamilyGroup();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: AppColors.missed),
        );
      }
    }
  }

  Future<void> _removeMember(String targetUserId, String memberName) async {
    if (_familyGroup == null) return;
    final lang = AppLanguage.instance;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.control)),
        title: Text(lang.translate('remove_member')),
        content: Text(lang.isBengali
            ? 'আপনি কি নিশ্চিত যে $memberName-কে পরিবার থেকে সরিয়ে দিতে চান?'
            : 'Are you sure you want to remove $memberName from the family group?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(lang.translate('cancel'))),
          PillButton(
            label: lang.translate('remove_member'),
            variant: PillButtonVariant.primary,
            customColor: AppColors.missed,
            height: 36,
            onPressed: () => Navigator.pop(ctx, true),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await _repository.removeFamilyMember(_familyGroup!.id, targetUserId);
        _loadFamilyGroup();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: $e'), backgroundColor: AppColors.missed),
          );
        }
      }
    }
  }

  void _copyFamilyCode() {
    if (_familyGroup == null) return;
    Clipboard.setData(ClipboardData(text: _familyGroup!.familyCode));
    final lang = AppLanguage.instance;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${lang.translate('code_copied')} (${_familyGroup!.familyCode})'),
        backgroundColor: AppColors.forest,
        duration: const Duration(seconds: 2),
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
            title: Text(
              lang.translate('family_group_title'),
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.refresh_rounded),
                onPressed: _loadFamilyGroup,
                tooltip: lang.translate('refresh'),
              ),
            ],
          ),
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
                            PillButton(
                              label: 'Retry',
                              variant: PillButtonVariant.primary,
                              onPressed: _loadFamilyGroup,
                            ),
                          ],
                        ),
                      ),
                    )
                  : RefreshIndicator(
                  color: AppColors.forest,
                  backgroundColor: AppColors.creamLight,
                  onRefresh: _loadFamilyGroup,
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _buildFamilyCodeCard(lang),
                        const SizedBox(height: 18),

                        if (_allFamilies.length > 1) ...[
                          _buildAssociatedFamiliesCard(lang),
                          const SizedBox(height: 18),
                        ],

                        _buildJoinFamilyCard(lang),
                        const SizedBox(height: 18),

                        if (_familyGroup != null && _familyGroup!.isCreator)
                          _buildPendingRequestsCard(lang),
                        if (_familyGroup != null && _familyGroup!.isCreator)
                          const SizedBox(height: 18),

                        if (_familyGroup != null)
                          _buildMembersListCard(lang),
                        if (_familyGroup != null)
                          const SizedBox(height: 18),

                        _buildSharedUpdatesCard(lang),
                      ],
                    ),
                  ),
                ),
        );
      },
    );
  }

  Widget _buildFamilyCodeCard(AppLanguage lang) {
    final code = _familyGroup?.familyCode ?? '---';
    final name = _familyGroup?.name ?? 'My Family';
    final isCreator = _familyGroup?.isCreator ?? false;

    return SoftCard(
      backgroundColor: AppColors.creamLight,
      radius: AppRadius.card,
      padding: const EdgeInsets.all(22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  name,
                  style: const TextStyle(
                    color: AppColors.ink,
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: isCreator ? AppColors.butter : AppColors.mint,
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                ),
                child: Text(
                  isCreator ? (lang.isBengali ? 'প্রশাসক' : 'Creator / Admin') : (lang.isBengali ? 'সদস্য' : 'Member'),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: isCreator ? AppColors.ink : AppColors.forest,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            lang.translate('unique_family_id'),
            style: const TextStyle(color: AppColors.muted, fontSize: 12.5, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),

          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: AppColors.mint.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(AppRadius.control),
                    border: Border.all(color: AppColors.forest.withValues(alpha: 0.2)),
                  ),
                  child: Text(
                    code,
                    style: const TextStyle(
                      color: AppColors.forest,
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 2,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              PillButton(
                onPressed: _copyFamilyCode,
                icon: Icons.copy_rounded,
                label: lang.translate('copy_code'),
                variant: PillButtonVariant.primary,
                customColor: AppColors.forest,
                height: 48,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            lang.translate('share_family_code'),
            style: const TextStyle(color: AppColors.muted, fontSize: 12),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Icon(Icons.cloud_done_rounded, color: AppColors.taken, size: 16),
              const SizedBox(width: 6),
              Text(
                lang.translate('firebase_sync_status'),
                style: const TextStyle(color: AppColors.taken, fontSize: 11, fontWeight: FontWeight.w800),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAssociatedFamiliesCard(AppLanguage lang) {
    return SoftCard(
      backgroundColor: AppColors.creamLight,
      radius: AppRadius.card,
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.hub_rounded, color: AppColors.forest, size: 20),
              const SizedBox(width: 8),
              Text(
                lang.isBengali ? 'আমার সংযুক্ত পরিবারসমূহ (${_allFamilies.length})' : 'My Associated Families (${_allFamilies.length})',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: AppColors.ink),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            lang.isBengali
                ? 'আপনি একাধিক পরিবারের সাথে যুক্ত থাকতে পারেন এবং পরিবার পরিবর্তন করতে পারেন।'
                : 'You belong to multiple families simultaneously. Switch active family or leave as needed.',
            style: const TextStyle(fontSize: 12, color: AppColors.muted),
          ),
          const SizedBox(height: 14),
          ..._allFamilies.map((fam) {
            final isActive = fam.id == _familyGroup?.id;
            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isActive ? AppColors.mint.withValues(alpha: 0.35) : Colors.white,
                borderRadius: BorderRadius.circular(AppRadius.control),
                border: Border.all(
                  color: isActive ? AppColors.forest : AppColors.softBorder.withValues(alpha: 0.2),
                  width: isActive ? 1.5 : 1.0,
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: isActive ? AppColors.forest : AppColors.sage.withValues(alpha: 0.4),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.family_restroom_rounded,
                      color: isActive ? Colors.white : AppColors.forest,
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                fam.name,
                                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5, color: AppColors.ink),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 6),
                            if (isActive)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: AppColors.forest,
                                  borderRadius: BorderRadius.circular(AppRadius.pill),
                                ),
                                child: Text(
                                  lang.isBengali ? 'সক্রিয়' : 'Active',
                                  style: const TextStyle(color: Colors.white, fontSize: 9.5, fontWeight: FontWeight.w800),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Text(
                              'Code: ${fam.familyCode}',
                              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.forest),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              '• ${fam.membersCount} ${lang.isBengali ? "সদস্য" : "members"}',
                              style: const TextStyle(fontSize: 11, color: AppColors.muted),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  if (!isActive)
                    PillButton(
                      label: lang.isBengali ? 'সক্রিয় করুন' : 'Switch',
                      variant: PillButtonVariant.tinted,
                      customColor: AppColors.mint,
                      customTextColor: AppColors.forest,
                      height: 32,
                      onPressed: () => _handleSwitchFamily(fam),
                    ),
                  const SizedBox(width: 4),
                  IconButton(
                    icon: const Icon(Icons.exit_to_app_rounded, color: AppColors.coral, size: 20),
                    tooltip: lang.isBengali ? 'পরিবার ত্যাগ করুন' : 'Leave family',
                    onPressed: () => _handleLeaveFamily(fam),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildJoinFamilyCard(AppLanguage lang) {
    return SoftCard(
      backgroundColor: AppColors.creamLight,
      radius: AppRadius.card,
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.group_add_rounded, color: AppColors.forest, size: 20),
              const SizedBox(width: 8),
              Text(
                lang.translate('join_family'),
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: AppColors.ink),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: SoftTextField(
                  controller: _joinCodeController,
                  hintText: lang.translate('join_family_hint'),
                  prefixIcon: Icons.vpn_key_rounded,
                ),
              ),
              const SizedBox(width: 10),
              PillButton(
                onPressed: _joinFamily,
                label: lang.translate('join_button'),
                variant: PillButtonVariant.primary,
                customColor: AppColors.coral,
                height: 48,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPendingRequestsCard(AppLanguage lang) {
    final pending = _familyGroup?.pendingRequests ?? [];

    return SoftCard(
      backgroundColor: pending.isNotEmpty ? AppColors.butter.withValues(alpha: 0.3) : AppColors.creamLight,
      radius: AppRadius.card,
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.notification_important_rounded, color: AppColors.coral),
              const SizedBox(width: 8),
              Text(
                lang.translate('pending_approvals'),
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: AppColors.ink),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                decoration: BoxDecoration(
                  color: pending.isNotEmpty ? AppColors.coral : AppColors.sage,
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                ),
                child: Text(
                  '${pending.length}',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 12,
                    color: pending.isNotEmpty ? Colors.white : AppColors.forest,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (pending.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text(
                lang.translate('no_pending_requests'),
                style: const TextStyle(color: AppColors.muted, fontSize: 13),
              ),
            )
          else
            ...pending.map((req) => Padding(
                  padding: const EdgeInsets.only(bottom: 8.0),
                  child: SoftCard(
                    backgroundColor: Colors.white,
                    radius: AppRadius.control,
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        AvatarBadge(name: req.fullName, size: 38, showRelationBadge: false),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(req.fullName, style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.ink)),
                              Text(req.email, style: const TextStyle(fontSize: 12, color: AppColors.muted)),
                            ],
                          ),
                        ),
                        PillButton(
                          label: lang.translate('reject'),
                          variant: PillButtonVariant.subtle,
                          height: 32,
                          onPressed: () => _rejectMember(req.userId),
                        ),
                        const SizedBox(width: 6),
                        PillButton(
                          label: lang.translate('approve'),
                          variant: PillButtonVariant.primary,
                          customColor: AppColors.forest,
                          height: 32,
                          onPressed: () => _approveMember(req.userId, req.fullName),
                        ),
                      ],
                    ),
                  ),
                )),
        ],
      ),
    );
  }

  Widget _buildMembersListCard(AppLanguage lang) {
    final members = _familyGroup?.members ?? [];
    final isCreator = _familyGroup?.isCreator ?? false;

    return SoftCard(
      backgroundColor: AppColors.creamLight,
      radius: AppRadius.card,
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeader(
            title: '${lang.translate('family_members')} (${members.length})',
            icon: Icons.people_rounded,
            iconColor: AppColors.forest,
          ),
          const SizedBox(height: 8),
          ...members.map((m) {
            final isMemberCreator = m.role == 'Creator';
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 6.0),
              child: Row(
                children: [
                  AvatarBadge(name: m.fullName, size: 40, showRelationBadge: false),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(m.fullName, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: AppColors.ink)),
                            if (isMemberCreator) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: AppColors.butter,
                                  borderRadius: BorderRadius.circular(AppRadius.pill),
                                ),
                                child: Text(
                                  lang.isBengali ? 'প্রশাসক' : 'Admin',
                                  style: const TextStyle(fontSize: 10, color: AppColors.ink, fontWeight: FontWeight.w900),
                                ),
                              ),
                            ],
                          ],
                        ),
                        Text(
                          m.email.isNotEmpty ? m.email : (lang.isBengali ? 'সক্রিয় সদস্য' : 'Active Member'),
                          style: const TextStyle(fontSize: 11.5, color: AppColors.muted),
                        ),
                      ],
                    ),
                  ),
                  if (isCreator && !isMemberCreator)
                    IconTileButton(
                      icon: Icons.person_remove_rounded,
                      tooltip: lang.translate('remove_member'),
                      iconColor: AppColors.missed,
                      backgroundColor: AppColors.peach.withValues(alpha: 0.4),
                      size: 32,
                      onPressed: () => _removeMember(m.userId, m.fullName),
                    ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildSharedUpdatesCard(AppLanguage lang) {
    return SoftCard(
      backgroundColor: AppColors.creamLight,
      radius: AppRadius.card,
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeader(
            title: lang.translate('shared_family_updates'),
            icon: Icons.dynamic_feed_rounded,
            iconColor: AppColors.forest,
          ),
          const SizedBox(height: 8),
          if (_sharedUpdates.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                lang.translate('no_shared_updates'),
                style: const TextStyle(color: AppColors.muted, fontSize: 13),
              ),
            )
          else
            ..._sharedUpdates.map((u) {
              final isTaken = u.type == 'DoseTaken';
              final isMissed = u.type == 'DoseMissed';
              final isJoined = u.type == 'MemberJoined';

              final iconColor = isTaken ? AppColors.taken : (isMissed ? AppColors.missed : AppColors.forest);
              final icon = isTaken
                  ? Icons.check_circle_rounded
                  : (isMissed
                      ? Icons.warning_amber_rounded
                      : (isJoined ? Icons.person_add_rounded : Icons.info_outline_rounded));

              return Padding(
                padding: const EdgeInsets.only(bottom: 8.0),
                child: SoftCard(
                  backgroundColor: Colors.white,
                  radius: AppRadius.control,
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: iconColor.withValues(alpha: 0.15),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(icon, color: iconColor, size: 20),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              lang.isBengali ? u.titleBn : u.title,
                              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: AppColors.ink),
                            ),
                            Text(
                              lang.isBengali ? u.descriptionBn : u.description,
                              style: const TextStyle(fontSize: 11.5, color: AppColors.muted),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }
}
