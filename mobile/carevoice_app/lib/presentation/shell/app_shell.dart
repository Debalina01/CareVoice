import 'package:flutter/material.dart';
import '../../core/localization.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_tokens.dart';
import '../../domain/models.dart';
import '../widgets/avatar_badge.dart';
import '../widgets/icon_tile_button.dart';
import '../widgets/pill_button.dart';

class AppShell extends StatelessWidget {
  final UserModel user;
  final int currentIndex;
  final ValueChanged<int> onIndexChanged;
  final Widget body;
  final String title;
  final VoidCallback onNotificationTap;
  final int notificationCount;
  final VoidCallback onLogout;
  final Widget? searchBar;
  final List<Widget>? extraHeaderActions;
  final VoidCallback? onVoiceSettingsTap;
  final VoidCallback? onSerbomAiTap;

  const AppShell({
    super.key,
    required this.user,
    required this.currentIndex,
    required this.onIndexChanged,
    required this.body,
    required this.title,
    required this.onNotificationTap,
    this.notificationCount = 0,
    required this.onLogout,
    this.searchBar,
    this.extraHeaderActions,
    this.onVoiceSettingsTap,
    this.onSerbomAiTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppLanguage.instance,
      builder: (context, _) {
        final lang = AppLanguage.instance;
        final screenWidth = MediaQuery.of(context).size.width;

        if (screenWidth >= AppBreakpoints.desktop) {
          return _buildDesktopLayout(context, lang);
        } else if (screenWidth >= AppBreakpoints.mobile) {
          return _buildTabletLayout(context, lang);
        } else {
          return _buildMobileLayout(context, lang);
        }
      },
    );
  }

  Widget _buildDesktopLayout(BuildContext context, AppLanguage lang) {
    return Scaffold(
      backgroundColor: AppColors.cream,
      body: Row(
        children: [
          Container(
            width: AppDimensions.sidebarWidth,
            height: double.infinity,
            decoration: const BoxDecoration(
              color: AppColors.sage,
              boxShadow: [
                BoxShadow(
                  color: Color(0x144A3B2F),
                  blurRadius: 16,
                  offset: Offset(4, 0),
                ),
              ],
            ),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: const BoxDecoration(
                        color: AppColors.creamLight,
                        shape: BoxShape.circle,
                        boxShadow: AppShadows.subtle,
                      ),
                      child: const Icon(Icons.medication_liquid_rounded, color: AppColors.forest, size: 24),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            lang.translate('app_title'),
                            style: const TextStyle(
                              fontSize: 19,
                              fontWeight: FontWeight.w900,
                              color: AppColors.forest,
                              letterSpacing: -0.3,
                            ),
                          ),
                          Text(
                            user.role == 'Caregiver'
                                ? lang.translate('role_caretaker')
                                : lang.translate('role_individual'),
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: AppColors.ink,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 28),

                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.creamLight.withValues(alpha: 0.65),
                    borderRadius: BorderRadius.circular(AppRadius.control),
                  ),
                  child: Row(
                    children: [
                      AvatarBadge(
                        name: user.fullName,
                        relation: user.role == 'Caregiver' ? 'Care' : 'Self',
                        size: 38,
                        showRelationBadge: false,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              user.fullName,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                                color: AppColors.ink,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              user.email,
                              style: const TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w500,
                                color: AppColors.muted,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                Expanded(
                  child: ListView(
                    padding: EdgeInsets.zero,
                    children: [
                      _buildSidebarNavItem(
                        icon: Icons.grid_view_rounded,
                        label: lang.translate('nav_dashboard'),
                        index: 0,
                      ),
                      const SizedBox(height: 8),
                      _buildSidebarNavItem(
                        icon: Icons.people_alt_rounded,
                        label: lang.translate('nav_family'),
                        index: 1,
                      ),
                      const SizedBox(height: 8),
                      _buildSidebarNavItem(
                        icon: Icons.medication_rounded,
                        label: lang.translate('nav_medicines'),
                        index: 2,
                      ),
                      const SizedBox(height: 8),
                      _buildSidebarNavItem(
                        icon: Icons.folder_shared_rounded,
                        label: lang.translate('nav_documents'),
                        index: 3,
                      ),
                      if (onSerbomAiTap != null) ...[
                        const SizedBox(height: 18),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: PillButton(
                            label: lang.translate('serbom_ai_title'),
                            icon: Icons.auto_awesome_rounded,
                            onPressed: onSerbomAiTap,
                            variant: PillButtonVariant.subtle,
                            customColor: AppColors.butter,
                            height: 44,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),

                if (onVoiceSettingsTap != null) ...[
                  InkWell(
                    onTap: onVoiceSettingsTap,
                    borderRadius: BorderRadius.circular(AppRadius.control),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
                      child: Row(
                        children: [
                          const Icon(Icons.record_voice_over_rounded, size: 18, color: AppColors.forest),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              lang.translate('voice_settings'),
                              style: const TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w700,
                                color: AppColors.ink,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                ],

                PillButton(
                  label: lang.translate('logout'),
                  icon: Icons.logout_rounded,
                  onPressed: onLogout,
                  variant: PillButtonVariant.outlined,
                  height: 42,
                ),
              ],
            ),
          ),

          Expanded(
            child: Column(
              children: [
                _buildTopHeader(context, lang, isDesktop: true),
                Expanded(child: body),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSidebarNavItem({
    required IconData icon,
    required String label,
    required int index,
  }) {
    final isSelected = currentIndex == index;

    return InkWell(
      onTap: () => onIndexChanged(index),
      borderRadius: BorderRadius.circular(AppRadius.pill),
      child: AnimatedContainer(
        duration: AppDurations.hover,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.creamLight : Colors.transparent,
          borderRadius: BorderRadius.circular(AppRadius.pill),
          boxShadow: isSelected ? AppShadows.subtle : null,
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 20,
              color: isSelected ? AppColors.coral : AppColors.forest,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: isSelected ? FontWeight.w900 : FontWeight.w700,
                  color: isSelected ? AppColors.forest : AppColors.ink,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTabletLayout(BuildContext context, AppLanguage lang) {
    return Scaffold(
      backgroundColor: AppColors.cream,
      body: Row(
        children: [
          Container(
            width: AppDimensions.railWidth,
            height: double.infinity,
            decoration: const BoxDecoration(
              color: AppColors.sage,
              boxShadow: [
                BoxShadow(
                  color: Color(0x144A3B2F),
                  blurRadius: 12,
                  offset: Offset(3, 0),
                ),
              ],
            ),
            padding: const EdgeInsets.symmetric(vertical: 20),
            child: Column(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: const BoxDecoration(
                    color: AppColors.creamLight,
                    shape: BoxShape.circle,
                    boxShadow: AppShadows.subtle,
                  ),
                  child: const Icon(Icons.medication_liquid_rounded, color: AppColors.forest, size: 24),
                ),
                const SizedBox(height: 32),
                _buildRailNavItem(icon: Icons.grid_view_rounded, tooltip: lang.translate('nav_dashboard'), index: 0),
                const SizedBox(height: 12),
                _buildRailNavItem(icon: Icons.people_alt_rounded, tooltip: lang.translate('nav_family'), index: 1),
                const SizedBox(height: 12),
                _buildRailNavItem(icon: Icons.medication_rounded, tooltip: lang.translate('nav_medicines'), index: 2),
                const SizedBox(height: 12),
                _buildRailNavItem(icon: Icons.folder_shared_rounded, tooltip: lang.translate('nav_documents'), index: 3),
                const Spacer(),
                if (onSerbomAiTap != null) ...[
                  IconTileButton(
                    icon: Icons.auto_awesome_rounded,
                    tooltip: lang.translate('serbom_ai_title'),
                    backgroundColor: AppColors.butter,
                    iconColor: AppColors.ink,
                    onPressed: onSerbomAiTap,
                  ),
                  const SizedBox(height: 12),
                ],
                IconTileButton(
                  icon: Icons.logout_rounded,
                  tooltip: lang.translate('logout'),
                  onPressed: onLogout,
                ),
              ],
            ),
          ),
          Expanded(
            child: Column(
              children: [
                _buildTopHeader(context, lang, isDesktop: false),
                Expanded(child: body),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRailNavItem({
    required IconData icon,
    required String tooltip,
    required int index,
  }) {
    final isSelected = currentIndex == index;

    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: () => onIndexChanged(index),
        borderRadius: BorderRadius.circular(AppRadius.circular),
        child: AnimatedContainer(
          duration: AppDurations.hover,
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: isSelected ? AppColors.creamLight : Colors.transparent,
            shape: BoxShape.circle,
            boxShadow: isSelected ? AppShadows.subtle : null,
          ),
          child: Icon(
            icon,
            size: 22,
            color: isSelected ? AppColors.coral : AppColors.forest,
          ),
        ),
      ),
    );
  }

  Widget _buildMobileLayout(BuildContext context, AppLanguage lang) {
    return Scaffold(
      backgroundColor: AppColors.cream,
      appBar: AppBar(
        title: Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
        ),
        actions: [
          _buildNotificationButton(),
          const SizedBox(width: 8),
          _buildLanguageTogglePill(lang),
          const SizedBox(width: 12),
        ],
      ),
      drawer: _buildMobileDrawer(context, lang),
      body: body,
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          boxShadow: [
            BoxShadow(
              color: Color(0x144A3B2F),
              blurRadius: 16,
              offset: Offset(0, -4),
            ),
          ],
        ),
        child: NavigationBar(
          selectedIndex: currentIndex,
          onDestinationSelected: onIndexChanged,
          backgroundColor: AppColors.sage,
          indicatorColor: AppColors.creamLight,
          destinations: [
            NavigationDestination(
              icon: const Icon(Icons.grid_view_outlined),
              selectedIcon: const Icon(Icons.grid_view_rounded, color: AppColors.coral),
              label: lang.translate('nav_dashboard'),
            ),
            NavigationDestination(
              icon: const Icon(Icons.people_outline_rounded),
              selectedIcon: const Icon(Icons.people_alt_rounded, color: AppColors.coral),
              label: lang.translate('nav_family'),
            ),
            NavigationDestination(
              icon: const Icon(Icons.medication_outlined),
              selectedIcon: const Icon(Icons.medication_rounded, color: AppColors.coral),
              label: lang.translate('nav_medicines'),
            ),
            NavigationDestination(
              icon: const Icon(Icons.folder_shared_outlined),
              selectedIcon: const Icon(Icons.folder_shared_rounded, color: AppColors.coral),
              label: lang.translate('nav_documents'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMobileDrawer(BuildContext context, AppLanguage lang) {
    return Drawer(
      backgroundColor: AppColors.sage,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  AvatarBadge(name: user.fullName, size: 48),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          user.fullName,
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: AppColors.ink),
                        ),
                        Text(
                          user.email,
                          style: const TextStyle(fontSize: 11, color: AppColors.muted),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              const Divider(color: AppColors.softBorder),
              ListTile(
                leading: const Icon(Icons.grid_view_rounded, color: AppColors.forest),
                title: Text(lang.translate('nav_dashboard'), style: const TextStyle(fontWeight: FontWeight.w800)),
                selected: currentIndex == 0,
                onTap: () {
                  Navigator.pop(context);
                  onIndexChanged(0);
                },
              ),
              ListTile(
                leading: const Icon(Icons.people_alt_rounded, color: AppColors.forest),
                title: Text(lang.translate('nav_family'), style: const TextStyle(fontWeight: FontWeight.w800)),
                selected: currentIndex == 1,
                onTap: () {
                  Navigator.pop(context);
                  onIndexChanged(1);
                },
              ),
              ListTile(
                leading: const Icon(Icons.medication_rounded, color: AppColors.forest),
                title: Text(lang.translate('nav_medicines'), style: const TextStyle(fontWeight: FontWeight.w800)),
                selected: currentIndex == 2,
                onTap: () {
                  Navigator.pop(context);
                  onIndexChanged(2);
                },
              ),
              ListTile(
                leading: const Icon(Icons.folder_shared_rounded, color: AppColors.forest),
                title: Text(lang.translate('nav_documents'), style: const TextStyle(fontWeight: FontWeight.w800)),
                selected: currentIndex == 3,
                onTap: () {
                  Navigator.pop(context);
                  onIndexChanged(3);
                },
              ),
              if (onSerbomAiTap != null)
                ListTile(
                  leading: const Icon(Icons.auto_awesome_rounded, color: AppColors.coral),
                  title: Text(lang.translate('serbom_ai_title'), style: const TextStyle(fontWeight: FontWeight.w800)),
                  onTap: () {
                    Navigator.pop(context);
                    onSerbomAiTap!();
                  },
                ),
              if (onVoiceSettingsTap != null)
                ListTile(
                  leading: const Icon(Icons.record_voice_over_rounded, color: AppColors.forest),
                  title: Text(lang.translate('voice_settings'), style: const TextStyle(fontWeight: FontWeight.w800)),
                  onTap: () {
                    Navigator.pop(context);
                    onVoiceSettingsTap!();
                  },
                ),
              const Spacer(),
              PillButton(
                label: lang.translate('logout'),
                icon: Icons.logout_rounded,
                onPressed: onLogout,
                variant: PillButtonVariant.outlined,
                height: 44,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTopHeader(BuildContext context, AppLanguage lang, {required bool isDesktop}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    color: AppColors.ink,
                    letterSpacing: -0.4,
                  ),
                ),
              ],
            ),
          ),
          if (searchBar != null) ...[
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 260),
              child: searchBar!,
            ),
            const SizedBox(width: 14),
          ],
          _buildNotificationButton(),
          const SizedBox(width: 10),
          _buildLanguageTogglePill(lang),
          const SizedBox(width: 12),
          AvatarBadge(name: user.fullName, size: 38),
          if (extraHeaderActions != null) ...[
            const SizedBox(width: 8),
            ...extraHeaderActions!,
          ],
        ],
      ),
    );
  }

  Widget _buildNotificationButton() {
    return IconTileButton(
      icon: Icons.notifications_active_rounded,
      tooltip: 'Notifications',
      onPressed: onNotificationTap,
      badge: notificationCount > 0
          ? Container(
              padding: const EdgeInsets.all(4),
              decoration: const BoxDecoration(
                color: AppColors.missed,
                shape: BoxShape.circle,
              ),
              child: Text(
                '$notificationCount',
                style: const TextStyle(color: Colors.white, fontSize: 9.5, fontWeight: FontWeight.w900),
              ),
            )
          : null,
    );
  }

  Widget _buildLanguageTogglePill(AppLanguage lang) {
    return InkWell(
      onTap: () => lang.toggleLanguage(),
      borderRadius: BorderRadius.circular(AppRadius.pill),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.creamLight,
          borderRadius: BorderRadius.circular(AppRadius.pill),
          boxShadow: AppShadows.subtle,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.language_rounded, size: 16, color: AppColors.forest),
            const SizedBox(width: 6),
            Text(
              lang.isBengali ? 'English' : 'বাংলা',
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w800,
                color: AppColors.forest,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
