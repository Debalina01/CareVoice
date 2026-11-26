import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../../core/file_saver.dart';
import '../../core/localization.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_tokens.dart';
import '../../data/api_client.dart';
import '../../data/family_repository.dart';
import '../../data/medical_document_repository.dart';
import '../../domain/models.dart';
import '../widgets/empty_state.dart';
import '../widgets/pill_button.dart';
import '../widgets/section_header.dart';
import '../widgets/soft_card.dart';
import '../widgets/soft_text_field.dart';

class MedicalDocumentsScreen extends StatefulWidget {
  const MedicalDocumentsScreen({super.key});

  @override
  State<MedicalDocumentsScreen> createState() => _MedicalDocumentsScreenState();
}

class _MedicalDocumentsScreenState extends State<MedicalDocumentsScreen> {
  final _docRepo = MedicalDocumentRepository();
  final _familyRepo = FamilyRepository();

  List<MedicalDocumentModel> _documents = [];
  List<FamilyMemberModel> _members = [];
  bool _isLoading = true;
  bool _storageReady = true;
  String? _errorMessage;
  String? _selectedMemberId;
  String _selectedCategory = 'All';

  static const List<String> _categories = [
    'All',
    'Prescription',
    'Lab Report',
    'Doctor Note',
    'Vaccination Record',
    'Other',
  ];

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  Future<void> _loadAll() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final members = await _familyRepo.getFamilyMembers();
      final storageReady = await _docRepo.isCloudStorageReady();
      List<MedicalDocumentModel> docs = [];

      if (await ApiClient.instance.hasJwtToken()) {
        docs = await _docRepo.getDocuments(memberId: _selectedMemberId);
      } else {
        _errorMessage = AppLanguage.instance.isBengali
            ? 'আপনার নিরাপদ নথিপত্র দেখতে অনলাইন অ্যাকাউন্ট দিয়ে লগইন করুন।'
            : 'Please sign in with an internet connection to access your private medical documents.';
      }

      if (mounted) {
        setState(() {
          _members = members;
          _storageReady = storageReady;
          _documents = docs;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = ApiClient.friendlyError(
            e,
            fallback: AppLanguage.instance.translate('error_load_documents'),
          );
          _isLoading = false;
        });
      }
    }
  }

  List<MedicalDocumentModel> get _filteredDocuments {
    return _documents.where((doc) {
      if (_selectedMemberId != null && doc.ownerMemberId != _selectedMemberId) {
        return false;
      }
      if (_selectedCategory != 'All' && doc.category.toLowerCase() != _selectedCategory.toLowerCase()) {
        return false;
      }
      return true;
    }).toList();
  }

  Future<void> _openUploadDialog() async {
    final lang = AppLanguage.instance;
    if (_members.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(lang.isBengali
              ? 'প্রথমে পরিবার ট্যাবে গিয়ে একজন সদস্য যোগ করুন।'
              : 'Please add a family member first before uploading a document.'),
          backgroundColor: AppColors.coral,
        ),
      );
      return;
    }

    final titleCtrl = TextEditingController();
    final notesCtrl = TextEditingController();
    String selectedMemberId = _selectedMemberId ?? _members.first.id;
    String selectedCategory = 'Prescription';
    String? pickedFileName;
    Uint8List? pickedBytes;
    String? dialogError;
    bool isUploading = false;

    await showDialog(
      context: context,
      barrierDismissible: !isUploading,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          return Dialog(
            backgroundColor: Colors.transparent,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480, maxHeight: 640),
              child: SoftCard(
                backgroundColor: AppColors.creamLight,
                padding: const EdgeInsets.all(22),
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
                              color: AppColors.mint,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.upload_file_rounded, color: AppColors.forest, size: 22),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              lang.translate('upload_document'),
                              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: AppColors.ink),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close_rounded, color: AppColors.muted),
                            onPressed: isUploading ? null : () => Navigator.pop(ctx),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        lang.translate('upload_document_hint'),
                        style: const TextStyle(fontSize: 12.5, color: AppColors.muted, height: 1.35),
                      ),
                      const SizedBox(height: 16),

                      if (dialogError != null) ...[
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: AppColors.missed.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(AppRadius.control),
                          ),
                          child: Text(
                            dialogError!,
                            style: const TextStyle(color: AppColors.missed, fontSize: 12.5, fontWeight: FontWeight.w600),
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],

                      InkWell(
                        onTap: isUploading
                            ? null
                            : () async {
                                final file = await FilePicker.pickFile(
                                  type: FileType.custom,
                                  allowedExtensions: ['pdf', 'png', 'jpg', 'jpeg', 'webp'],
                                );
                                if (file != null) {
                                  final bytes = await file.readAsBytes();
                                  if (bytes.isEmpty) {
                                    setDialogState(() {
                                      dialogError = lang.isBengali
                                          ? 'ফাইলটি পড়া যায়নি। অনুগ্রহ করে আবার চেষ্টা করুন।'
                                          : 'Could not read that file. Please choose another file.';
                                    });
                                    return;
                                  }
                                  if (bytes.length > 10 * 1024 * 1024) {
                                    setDialogState(() {
                                      dialogError = lang.isBengali
                                          ? 'ফাইলের আকার ১০ মেগাবাইটের বেশি হতে পারবে না।'
                                          : 'Please select a file smaller than 10 MB.';
                                    });
                                    return;
                                  }
                                  setDialogState(() {
                                    pickedFileName = file.name;
                                    pickedBytes = bytes;
                                    dialogError = null;
                                    if (titleCtrl.text.trim().isEmpty) {
                                      final dot = file.name.lastIndexOf('.');
                                      titleCtrl.text = dot > 0 ? file.name.substring(0, dot) : file.name;
                                    }
                                  });
                                }
                              },
                        borderRadius: BorderRadius.circular(AppRadius.control),
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: pickedBytes != null ? AppColors.mint.withValues(alpha: 0.35) : Colors.white,
                            borderRadius: BorderRadius.circular(AppRadius.control),
                            border: Border.all(
                              color: pickedBytes != null ? AppColors.forest : AppColors.softBorder,
                              width: 1.5,
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                pickedBytes != null ? Icons.check_circle_rounded : Icons.attach_file_rounded,
                                color: AppColors.forest,
                                size: 24,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      pickedFileName ?? lang.translate('select_file'),
                                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5, color: AppColors.ink),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      pickedBytes != null
                                          ? '${(pickedBytes!.length / 1024).toStringAsFixed(1)} KB'
                                          : (lang.isBengali ? 'PDF বা ছবি (সর্বোচ্চ ১০ MB)' : 'PDF or Photo (PNG, JPG up to 10 MB)'),
                                      style: const TextStyle(fontSize: 11.5, color: AppColors.muted),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),

                      Text(
                        lang.translate('target_person'),
                        style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: AppColors.ink),
                      ),
                      const SizedBox(height: 6),
                      DropdownButtonFormField<String>(
                        initialValue: _members.any((m) => m.id == selectedMemberId) ? selectedMemberId : _members.first.id,
                        decoration: InputDecoration(
                          filled: true,
                          fillColor: Colors.white,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.control)),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        ),
                        items: _members
                            .map((m) => DropdownMenuItem(
                                  value: m.id,
                                  child: Text('${m.fullName} (${m.relation})'),
                                ))
                            .toList(),
                        onChanged: isUploading
                            ? null
                            : (val) {
                                if (val != null) setDialogState(() => selectedMemberId = val);
                              },
                      ),
                      const SizedBox(height: 14),

                      Text(
                        lang.translate('document_category'),
                        style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: AppColors.ink),
                      ),
                      const SizedBox(height: 6),
                      DropdownButtonFormField<String>(
                        initialValue: selectedCategory,
                        decoration: InputDecoration(
                          filled: true,
                          fillColor: Colors.white,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.control)),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        ),
                        items: _categories
                            .where((c) => c != 'All')
                            .map((c) => DropdownMenuItem(value: c, child: Text(_translateCategory(c, lang))))
                            .toList(),
                        onChanged: isUploading
                            ? null
                            : (val) {
                                if (val != null) setDialogState(() => selectedCategory = val);
                              },
                      ),
                      const SizedBox(height: 14),

                      SoftTextField(
                        controller: titleCtrl,
                        labelText: lang.translate('document_title'),
                        hintText: lang.isBengali ? 'যেমন: বাবার ব্লাড প্রেসারের প্রেসক্রিপশন' : 'e.g. Papa BP Prescription',
                        prefixIcon: Icons.title_rounded,
                      ),
                      const SizedBox(height: 12),
                      SoftTextField(
                        controller: notesCtrl,
                        labelText: lang.isBengali ? 'সংক্ষিপ্ত নোট (ঐচ্ছিক)' : 'Notes (Optional)',
                        hintText: lang.isBengali ? 'যেমন: ডাঃ সেন দিয়েছেন' : 'e.g. From Dr. Sen clinic visit',
                        prefixIcon: Icons.notes_rounded,
                      ),
                      const SizedBox(height: 20),

                      Row(
                        children: [
                          Expanded(
                            child: PillButton(
                              label: lang.translate('cancel'),
                              variant: PillButtonVariant.subtle,
                              onPressed: isUploading ? null : () => Navigator.pop(ctx),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            flex: 2,
                            child: PillButton(
                              label: lang.translate('save'),
                              icon: Icons.cloud_upload_rounded,
                              variant: PillButtonVariant.primary,
                              isLoading: isUploading,
                              onPressed: () async {
                                if (pickedBytes == null || pickedFileName == null) {
                                  setDialogState(() {
                                    dialogError = lang.isBengali
                                        ? 'অনুগ্রহ করে প্রথমে একটি ফাইল বেছে নিন।'
                                        : 'Please choose a PDF or image file first.';
                                  });
                                  return;
                                }
                                setDialogState(() {
                                  isUploading = true;
                                  dialogError = null;
                                });
                                try {
                                  await _docRepo.uploadDocument(
                                    ownerMemberId: selectedMemberId,
                                    title: titleCtrl.text.trim().isEmpty ? pickedFileName! : titleCtrl.text.trim(),
                                    category: selectedCategory,
                                    notes: notesCtrl.text.trim(),
                                    fileName: pickedFileName!,
                                    bytes: pickedBytes!,
                                  );
                                  if (ctx.mounted) Navigator.pop(ctx);
                                  await _loadAll();
                                  if (mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(lang.isBengali
                                            ? 'নথিটি নিরাপদে সংরক্ষণ করা হয়েছে!'
                                            : 'Document saved safely!'),
                                        backgroundColor: AppColors.forest,
                                      ),
                                    );
                                  }
                                } catch (e) {
                                  setDialogState(() {
                                    isUploading = false;
                                    dialogError = ApiClient.friendlyError(e);
                                  });
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

  Future<void> _viewDocument(MedicalDocumentModel doc) async {
    final lang = AppLanguage.instance;
    try {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(lang.isBengali ? 'নথি খোলা হচ্ছে...' : 'Opening document...'),
          duration: const Duration(seconds: 1),
        ),
      );
      final bytes = await _docRepo.downloadDocumentBytes(doc.id, download: false);
      if (!mounted) return;

      if (doc.isImage) {
        showDialog(
          context: context,
          builder: (ctx) => Dialog(
            backgroundColor: AppColors.creamLight,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.modal)),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720, maxHeight: 680),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            doc.title,
                            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: AppColors.ink),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.download_rounded, color: AppColors.forest),
                          tooltip: lang.translate('download_file'),
                          onPressed: () => _downloadDocument(doc),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close_rounded, color: AppColors.muted),
                          onPressed: () => Navigator.pop(ctx),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(AppRadius.control),
                        child: InteractiveViewer(
                          child: Image.memory(bytes, fit: BoxFit.contain),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      } else {
        await FileSaver.saveAndOpenFile(
          bytes: bytes,
          fileName: doc.originalFileName,
          mimeType: doc.contentType,
          openAfterSave: true,
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(ApiClient.friendlyError(e)), backgroundColor: AppColors.missed),
      );
    }
  }

  Future<void> _downloadDocument(MedicalDocumentModel doc) async {
    final lang = AppLanguage.instance;
    try {
      final bytes = await _docRepo.downloadDocumentBytes(doc.id, download: true);
      final savedPath = await FileSaver.saveAndOpenFile(
        bytes: bytes,
        fileName: doc.originalFileName,
        mimeType: doc.contentType,
        openAfterSave: false,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            savedPath != null && savedPath.contains('/')
                ? '${lang.translate('download_complete')}: ${doc.originalFileName}'
                : '${lang.translate('download_complete')}: ${doc.originalFileName}',
          ),
          backgroundColor: AppColors.forest,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(ApiClient.friendlyError(e)), backgroundColor: AppColors.missed),
      );
    }
  }

  Future<void> _confirmDelete(MedicalDocumentModel doc) async {
    final lang = AppLanguage.instance;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.creamLight,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.control)),
        title: Text(
          lang.isBengali ? 'নথি মুছে ফেলবেন?' : 'Delete this document?',
          style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.ink),
        ),
        content: Text(
          lang.isBengali
              ? '"${doc.title}" স্থায়ীভাবে মুছে ফেলা হবে।'
              : '"${doc.title}" will be permanently removed from your private storage.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(lang.translate('cancel'), style: const TextStyle(color: AppColors.muted)),
          ),
          PillButton(
            label: lang.translate('delete'),
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
        await _docRepo.deleteDocument(doc.id);
        await _loadAll();
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(ApiClient.friendlyError(e)), backgroundColor: AppColors.missed),
        );
      }
    }
  }

  String _translateCategory(String cat, AppLanguage lang) {
    switch (cat.toLowerCase()) {
      case 'all':
        return lang.translate('filter_all');
      case 'prescription':
        return lang.translate('prescription');
      case 'lab report':
        return lang.translate('lab_report');
      case 'doctor note':
        return lang.translate('doctor_note');
      case 'vaccination record':
        return lang.translate('vaccination_record');
      default:
        return lang.translate('other');
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppLanguage.instance,
      builder: (context, _) {
        final lang = AppLanguage.instance;
        final docs = _filteredDocuments;

        return RefreshIndicator(
          onRefresh: _loadAll,
          color: AppColors.forest,
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              SoftCard(
                backgroundColor: AppColors.mint.withValues(alpha: 0.4),
                radius: AppRadius.card,
                padding: const EdgeInsets.all(18),
                child: Wrap(
                  spacing: 14,
                  runSpacing: 12,
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: const BoxDecoration(color: AppColors.creamLight, shape: BoxShape.circle),
                          child: const Icon(Icons.verified_user_rounded, color: AppColors.forest, size: 22),
                        ),
                        const SizedBox(width: 12),
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 460),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                lang.translate('documents_banner_title'),
                                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: AppColors.forest),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                lang.translate('documents_banner_subtitle'),
                                style: const TextStyle(fontSize: 12.5, color: AppColors.ink, height: 1.35),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    PillButton(
                      label: lang.translate('upload_document'),
                      icon: Icons.upload_file_rounded,
                      variant: PillButtonVariant.primary,
                      onPressed: _openUploadDialog,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              if (!_storageReady) ...[
                SoftCard(
                  backgroundColor: AppColors.butter.withValues(alpha: 0.45),
                  radius: AppRadius.control,
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline_rounded, color: AppColors.ink, size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          lang.isBengali
                              ? 'নিরাপদ ক্লাউড স্টোরেজ সক্রিয় করা হচ্ছে। এখনই ফাইল সংরক্ষণে অসুবিধা হতে পারে।'
                              : 'Private cloud file storage is waiting for server setup. Uploading will work as soon as storage credentials are added.',
                          style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppColors.ink),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],

              if (_members.isNotEmpty) ...[
                SectionHeader(title: lang.translate('filter_by_person')),
                const SizedBox(height: 8),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      ChoiceChip(
                        label: Text(lang.translate('filter_all')),
                        selected: _selectedMemberId == null,
                        selectedColor: AppColors.forest,
                        labelStyle: TextStyle(
                          color: _selectedMemberId == null ? Colors.white : AppColors.ink,
                          fontWeight: FontWeight.w700,
                        ),
                        onSelected: (_) => setState(() => _selectedMemberId = null),
                      ),
                      const SizedBox(width: 8),
                      ..._members.map((m) {
                        final selected = _selectedMemberId == m.id;
                        return Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ChoiceChip(
                            label: Text(m.isSelf ? '${m.fullName} (${lang.translate('filter_self')})' : m.fullName),
                            selected: selected,
                            selectedColor: AppColors.forest,
                            labelStyle: TextStyle(
                              color: selected ? Colors.white : AppColors.ink,
                              fontWeight: FontWeight.w700,
                            ),
                            onSelected: (_) => setState(() => _selectedMemberId = m.id),
                          ),
                        );
                      }),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
              ],

              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: _categories.map((c) {
                    final selected = _selectedCategory == c;
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: FilterChip(
                        label: Text(_translateCategory(c, lang)),
                        selected: selected,
                        selectedColor: AppColors.sage,
                        onSelected: (_) => setState(() => _selectedCategory = c),
                      ),
                    );
                  }).toList(),
                ),
              ),
              const SizedBox(height: 18),

              if (_isLoading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 48),
                  child: Center(child: CircularProgressIndicator(color: AppColors.coral)),
                )
              else if (_errorMessage != null)
                SoftCard(
                  backgroundColor: AppColors.creamLight,
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      const Icon(Icons.cloud_off_rounded, size: 36, color: AppColors.muted),
                      const SizedBox(height: 10),
                      Text(_errorMessage!, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.ink)),
                      const SizedBox(height: 12),
                      PillButton(label: lang.translate('retry'), onPressed: _loadAll, variant: PillButtonVariant.outlined),
                    ],
                  ),
                )
              else if (docs.isEmpty)
                EmptyState(
                  icon: Icons.folder_open_rounded,
                  title: lang.translate('no_documents'),
                  message: lang.translate('no_documents_subtitle'),
                  actionLabel: lang.translate('upload_document'),
                  onAction: _openUploadDialog,
                )
              else
                ...docs.map((doc) {
                  final dateText = doc.createdAt.length >= 10 ? doc.createdAt.substring(0, 10) : doc.createdAt;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: SoftCard(
                      backgroundColor: AppColors.creamLight,
                      radius: AppRadius.card,
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                  color: doc.isPdf
                                      ? AppColors.coral.withValues(alpha: 0.15)
                                      : AppColors.mint.withValues(alpha: 0.6),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Icon(
                                  doc.isPdf ? Icons.picture_as_pdf_rounded : Icons.image_rounded,
                                  color: doc.isPdf ? AppColors.coral : AppColors.forest,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      doc.title,
                                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: AppColors.ink),
                                    ),
                                    const SizedBox(height: 4),
                                    Wrap(
                                      spacing: 8,
                                      runSpacing: 4,
                                      children: [
                                        _chipTag(doc.ownerMemberName, Icons.person_rounded, AppColors.mint),
                                        _chipTag(_translateCategory(doc.category, lang), Icons.label_rounded, AppColors.sage.withValues(alpha: 0.5)),
                                        _chipTag('${doc.formattedSize} • $dateText', Icons.insert_drive_file_rounded, Colors.white),
                                      ],
                                    ),
                                    if (doc.notes != null && doc.notes!.isNotEmpty) ...[
                                      const SizedBox(height: 6),
                                      Text(doc.notes!, style: const TextStyle(fontSize: 12.5, color: AppColors.muted)),
                                    ],
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              PillButton(
                                label: lang.translate('view_file'),
                                icon: Icons.visibility_rounded,
                                height: 36,
                                variant: PillButtonVariant.outlined,
                                onPressed: () => _viewDocument(doc),
                              ),
                              PillButton(
                                label: lang.translate('download_file'),
                                icon: Icons.download_rounded,
                                height: 36,
                                variant: PillButtonVariant.primary,
                                onPressed: () => _downloadDocument(doc),
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete_outline_rounded, color: AppColors.missed),
                                tooltip: lang.translate('delete'),
                                onPressed: () => _confirmDelete(doc),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                }),
            ],
          ),
        );
      },
    );
  }

  Widget _chipTag(String label, IconData icon, Color bg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: AppColors.forest),
          const SizedBox(width: 4),
          Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.ink)),
        ],
      ),
    );
  }
}
