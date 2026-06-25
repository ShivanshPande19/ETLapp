// lib/features/settings/presentation/settings_screen.dart

import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/services/biometric_service.dart';
import '../../auth/domain/auth_notifier.dart';
import '../../courts/domain/courts_notifier.dart'; // NEW IMPORT
import '../../home/presentation/home_providers.dart' show currentOutletNameProvider;
import '../presentation/manage_courts_screen.dart';
import 'outlet_staff_management_screen.dart';
import '../../notices/domain/notices_notifier.dart';
import '../../notices/presentation/notices_screen.dart';
import '../../attendance_calendar/presentation/manager_attendance_screen.dart';

const _bg = Color(0xFF080808);
const _white = Color(0xFFFFFFFF);
const _black = Color(0xFF0A0A0A);
const _grey = Color(0xFF888888);
const _red = Color(0xFFD02128);

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});
  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen>
    with TickerProviderStateMixin {
  late final AnimationController _fadeCtrl;
  late final AnimationController _heroCtrl;
  late final AnimationController _listCtrl;
  late final Animation<double> _fadeAnim;
  late final Animation<double> _heroFade;
  late final Animation<Offset> _heroSlide;

  bool _biometricLock = false;
  bool _biometricAvailable = false;
  bool _backPressed = false;

  SharedPreferences? _prefs;

  @override
  void initState() {
    super.initState();
    SystemChrome.setSystemUIOverlayStyle(
      SystemUiOverlayStyle.light.copyWith(statusBarColor: Colors.transparent),
    );

    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _heroCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 550),
    );
    _listCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );

    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOutCubic);
    _heroFade = CurvedAnimation(parent: _heroCtrl, curve: Curves.easeOutCubic);
    _heroSlide = Tween<Offset>(
      begin: const Offset(0, 0.10),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _heroCtrl, curve: Curves.easeOutCubic));

    _fadeCtrl.forward();
    Future.delayed(const Duration(milliseconds: 60), () {
      if (mounted) _heroCtrl.forward();
    });
    Future.delayed(const Duration(milliseconds: 160), () {
      if (mounted) _listCtrl.forward();
    });

    _loadPrefs();
  }

  Future<void> _loadPrefs() async {
    _prefs = await SharedPreferences.getInstance();
    final email = ref.read(authNotifierProvider).managerEmail ?? 'default';
    final key = 'biometric_lock_$email';
    final saved = _prefs!.getBool(key) ?? false;
    final available = await BiometricService.isAvailable();
    if (mounted) {
      setState(() {
        _biometricLock = saved;
        _biometricAvailable = available;
      });
    }
  }

  Future<void> _onBiometricToggle(bool v) async {
    HapticFeedback.selectionClick();
    if (v) {
      final passed = await BiometricService.authenticate();
      if (!passed) {
        _showBiometricError();
        return;
      }
    }
    final email = ref.read(authNotifierProvider).managerEmail ?? 'default';
    final key = 'biometric_lock_$email';
    await _prefs?.setBool(key, v);
    if (mounted) setState(() => _biometricLock = v);
  }

  void _showBiometricError() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Authentication failed. Biometric lock not enabled.',
          style: GoogleFonts.inter(fontSize: 13, color: _white),
        ),
        backgroundColor: _black,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    _heroCtrl.dispose();
    _listCtrl.dispose();
    super.dispose();
  }

  Animation<double> _itemAnim(int i) => CurvedAnimation(
    parent: _listCtrl,
    curve: Interval(
      (i * 0.08).clamp(0.0, 0.7),
      ((i * 0.08) + 0.4).clamp(0.0, 1.0),
      curve: Curves.easeOutCubic,
    ),
  );

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authNotifierProvider);
    final courtsAsync = ref.watch(courtsNotifierProvider); // NEW WATCH
    final name = auth.managerName ?? 'Manager';
    final email = auth.managerEmail ?? 'manager@etl.com';
    final roleLabel = auth.isEtlManager
        ? 'Admin Access'
        : auth.isOutletManager
            ? 'Outlet Manager'
            : 'Staff Access';
    final outletName =
        ref.watch(currentOutletNameProvider).value ?? 'Your Outlet';

    return Scaffold(
      backgroundColor: _bg,
      body: FadeTransition(
        opacity: _fadeAnim,
        child: SafeArea(
          bottom: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    GestureDetector(
                      onTapDown: (_) {
                        HapticFeedback.selectionClick();
                        setState(() => _backPressed = true);
                      },
                      onTapUp: (_) {
                        setState(() => _backPressed = false);
                        Navigator.of(context).pop();
                      },
                      onTapCancel: () => setState(() => _backPressed = false),
                      child: AnimatedScale(
                        scale: _backPressed ? 0.92 : 1.0,
                        duration: const Duration(milliseconds: 120),
                        curve: Curves.easeOutCubic,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          curve: Curves.easeOutCubic,
                          height: 38,
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          decoration: BoxDecoration(
                            color: _backPressed
                                ? _white.withOpacity(0.14)
                                : _white.withOpacity(0.07),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(
                              color: _white.withOpacity(
                                _backPressed ? 0.22 : 0.12,
                              ),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.west_rounded,
                                size: 14,
                                color: _white.withOpacity(0.9),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                'Back',
                                style: GoogleFonts.inter(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: _white.withOpacity(0.9),
                                  height: 1,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    FadeTransition(
                      opacity: _heroFade,
                      child: SlideTransition(
                        position: _heroSlide,
                        child: RichText(
                          text: TextSpan(
                            style: GoogleFonts.antonSc(
                              fontSize: 42,
                              height: 0.95,
                              letterSpacing: -0.5,
                            ),
                            children: const [
                              TextSpan(
                                text: 'S',
                                style: TextStyle(color: _red),
                              ),
                              TextSpan(
                                text: 'ETTINGS',
                                style: TextStyle(color: _white),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    FadeTransition(
                      opacity: _heroFade,
                      child: Row(
                        children: [
                          Container(
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(
                              color: AppTheme.success,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: AppTheme.success.withOpacity(0.6),
                                  blurRadius: 6,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'ETL Management App',
                            style: GoogleFonts.inter(
                              fontSize: 13,
                              color: _white.withOpacity(0.45),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Container(
                  decoration: const BoxDecoration(
                    color: _white,
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(28),
                    ),
                  ),
                  child: SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    padding: EdgeInsets.fromLTRB(
                      20,
                      24,
                      20,
                      MediaQuery.of(context).padding.bottom + 40,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _StaggerItem(
                          anim: _itemAnim(0),
                          child: _ProfileCard(
                              name: name, email: email, roleLabel: roleLabel),
                        ),
                        const SizedBox(height: 28),
                        _StaggerItem(
                          anim: _itemAnim(1),
                          child: const _SectionLabel('APP SETTINGS'),
                        ),
                        const SizedBox(height: 10),
                        _StaggerItem(
                          anim: _itemAnim(2),
                          child: _SettingsGroup(
                            children: [
                              _ToggleTile(
                                icon: Icons.fingerprint_rounded,
                                label: 'Biometric Lock',
                                subtitle: _biometricAvailable
                                    ? 'Use Face ID / fingerprint to unlock app'
                                    : 'Not available on this device',
                                value: _biometricLock,
                                enabled: _biometricAvailable,
                                onChanged: _biometricAvailable
                                    ? _onBiometricToggle
                                    : null,
                              ),
                              if (auth.isManager) ...[
                                _GroupDivider(),
                                _InfoTile(
                                  icon: Icons.schedule_rounded,
                                  label: 'Sales Data Sync',
                                  value: 'Daily · 12:00 AM',
                                  valueColor: _grey,
                                ),
                              ],
                            ],
                          ),
                        ),
                        // ── Role-specific section ─────────────────────
                        if (auth.isEtlManager) ...[
                          const SizedBox(height: 24),
                          _StaggerItem(
                            anim: _itemAnim(3),
                            child: const _SectionLabel('COURTS'),
                          ),
                          const SizedBox(height: 10),
                          _StaggerItem(
                            anim: _itemAnim(4),
                            child: _SettingsGroup(
                              children: [
                                _NavTile(
                                  icon: Icons.store_rounded,
                                  label: 'Manage Courts',
                                  subtitle: courtsAsync.when(
                                    loading: () => 'Loading courts...',
                                    error: (_, __) => 'ETL Courts',
                                    data: (list) =>
                                        'ETL · ${list.length} active ${list.length == 1 ? 'court' : 'courts'}',
                                  ),
                                  onTap: () => Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) =>
                                          const ManageCourtsScreen(),
                                    ),
                                  ),
                                ),
                                _GroupDivider(),
                                _NavTile(
                                  icon: Icons.event_available_rounded,
                                  label: 'Staff Attendance',
                                  subtitle: 'Monthly calendar · all courts',
                                  onTap: () => Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) =>
                                          const ManagerAttendanceScreen(),
                                    ),
                                  ),
                                ),
                                _GroupDivider(),
                                _NavTile(
                                  icon: Icons.point_of_sale_rounded,
                                  label: 'POS Integrations',
                                  subtitle: 'GoFrugal, Petpooja, Vyapar',
                                  onTap: () {},
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 24),
                          _StaggerItem(
                            anim: _itemAnim(5),
                            child: const _SectionLabel('NOTIFICATIONS'),
                          ),
                          const SizedBox(height: 10),
                          _StaggerItem(
                            anim: _itemAnim(5),
                            child: _SettingsGroup(
                              children: [
                                Consumer(
                                  builder: (context, ref, _) {
                                    final unread = ref
                                            .watch(unreadCountProvider)
                                            .value ??
                                        0;
                                    return _NavTile(
                                      icon: Icons.notifications_rounded,
                                      label: 'Notices',
                                      subtitle: unread > 0
                                          ? '$unread unread'
                                          : 'Early logouts & alerts',
                                      onTap: () {
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (_) =>
                                                const NoticesScreen(),
                                          ),
                                        ).then((_) => ref.invalidate(
                                            unreadCountProvider));
                                      },
                                    );
                                  },
                                ),
                              ],
                            ),
                          ),
                        ] else if (auth.isOutletManager) ...[
                          const SizedBox(height: 24),
                          _StaggerItem(
                            anim: _itemAnim(3),
                            child: const _SectionLabel('MY OUTLET'),
                          ),
                          const SizedBox(height: 10),
                          _StaggerItem(
                            anim: _itemAnim(4),
                            child: _SettingsGroup(
                              children: [
                                _NavTile(
                                  icon: Icons.people_alt_rounded,
                                  label: 'Manage Staff',
                                  subtitle: 'Add & manage your outlet staff',
                                  onTap: () => Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) =>
                                          OutletStaffManagementScreen(
                                        outletId: auth.outletId ?? 0,
                                        outletName: outletName,
                                      ),
                                    ),
                                  ),
                                ),
                                _GroupDivider(),
                                _InfoTile(
                                  icon: Icons.storefront_rounded,
                                  label: 'Outlet',
                                  value: outletName,
                                  valueColor: _black,
                                ),
                              ],
                            ),
                          ),
                        ],
                        const SizedBox(height: 24),
                        _StaggerItem(
                          anim: _itemAnim(5),
                          child: const _SectionLabel('ABOUT'),
                        ),
                        const SizedBox(height: 10),
                        _StaggerItem(
                          anim: _itemAnim(6),
                          child: _SettingsGroup(
                            children: [
                              _InfoTile(
                                icon: Icons.verified_rounded,
                                label: 'App Version',
                                value: '1.0.0 (Phase 1)',
                                valueColor: AppTheme.success,
                              ),
                              _GroupDivider(),
                              _InfoTile(
                                icon: Icons.business_rounded,
                                label: 'Organisation',
                                value: 'ETL Food Courts',
                              ),
                              _GroupDivider(),
                              _InfoTile(
                                icon: Icons.cloud_done_rounded,
                                label: 'Environment',
                                value: 'Production',
                                valueColor: _black,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 32),
                        _StaggerItem(
                          anim: _itemAnim(7),
                          child: _LogoutButton(
                            onConfirm: () {
                              ref.read(authNotifierProvider.notifier).logout();
                              context.go('/login');
                            },
                          ),
                        ),
                        const SizedBox(height: 24),
                        _StaggerItem(
                          anim: _itemAnim(8),
                          child: Center(
                            child: Column(
                              children: [
                                Container(
                                  width: 32,
                                  height: 1,
                                  color: const Color(0xFFE5E5E5),
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  'ETL Management App · Phase 1',
                                  style: GoogleFonts.inter(
                                    fontSize: 11,
                                    color: _grey,
                                    fontWeight: FontWeight.w500,
                                    letterSpacing: 0.3,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  'For internal use only',
                                  style: GoogleFonts.inter(
                                    fontSize: 10,
                                    color: _grey.withOpacity(0.6),
                                  ),
                                ),
                              ],
                            ),
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

class _StaggerItem extends StatelessWidget {
  final Animation<double> anim;
  final Widget child;
  const _StaggerItem({required this.anim, required this.child});

  @override
  Widget build(BuildContext context) => FadeTransition(
    opacity: anim,
    child: SlideTransition(
      position: Tween<Offset>(
        begin: const Offset(0, 0.06),
        end: Offset.zero,
      ).animate(anim),
      child: child,
    ),
  );
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Container(
        width: 3,
        height: 12,
        decoration: BoxDecoration(
          color: _red,
          borderRadius: BorderRadius.circular(999),
        ),
      ),
      const SizedBox(width: 8),
      Text(
        text,
        style: GoogleFonts.inter(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: _grey,
          letterSpacing: 1.4,
        ),
      ),
    ],
  );
}

class _ProfileCard extends StatelessWidget {
  final String name, email, roleLabel;
  const _ProfileCard({
    required this.name,
    required this.email,
    required this.roleLabel,
  });

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: _black,
      borderRadius: BorderRadius.circular(20),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withOpacity(0.12),
          blurRadius: 16,
          offset: const Offset(0, 4),
        ),
      ],
    ),
    child: Row(
      children: [
        Container(
          width: 54,
          height: 54,
          decoration: BoxDecoration(
            color: _red.withOpacity(0.15),
            shape: BoxShape.circle,
            border: Border.all(color: _red.withOpacity(0.4), width: 1.5),
          ),
          child: Center(
            child: Text(
              name[0].toUpperCase(),
              style: GoogleFonts.antonSc(fontSize: 22, color: _white),
            ),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name,
                style: GoogleFonts.inter(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: _white,
                  letterSpacing: -0.2,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                email,
                style: GoogleFonts.inter(
                  fontSize: 12,
                  color: _white.withOpacity(0.45),
                ),
              ),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: _white.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: _white.withOpacity(0.15)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.shield_rounded, size: 11, color: _white),
                    const SizedBox(width: 5),
                    Text(
                      roleLabel,
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: _white,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _SettingsGroup extends StatelessWidget {
  final List<Widget> children;
  const _SettingsGroup({required this.children});

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: _white,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: const Color(0xFFE5E5E5), width: 1.5),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withOpacity(0.04),
          blurRadius: 8,
          offset: const Offset(0, 2),
        ),
      ],
    ),
    child: Column(children: children),
  );
}

class _GroupDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
    height: 1,
    margin: const EdgeInsets.only(left: 60),
    color: const Color(0xFFE5E5E5),
  );
}

class _IconBox extends StatelessWidget {
  final IconData icon;
  final Color color;
  const _IconBox({required this.icon, this.color = _black});

  @override
  Widget build(BuildContext context) => Container(
    width: 36,
    height: 36,
    decoration: BoxDecoration(
      color: color.withOpacity(0.08),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: color.withOpacity(0.12)),
    ),
    child: Icon(icon, size: 17, color: color),
  );
}

class _ToggleTile extends StatelessWidget {
  final IconData icon;
  final String label, subtitle;
  final bool value;
  final bool enabled;
  final ValueChanged<bool>? onChanged;

  const _ToggleTile({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.value,
    this.enabled = true,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    child: Row(
      children: [
        _IconBox(
          icon: icon,
          color: !enabled
              ? _grey
              : value
              ? _black
              : _grey,
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: GoogleFonts.inter(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: enabled ? _black : _grey,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                subtitle,
                style: GoogleFonts.inter(fontSize: 12, color: _grey),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        GestureDetector(
          onTap: enabled && onChanged != null ? () => onChanged!(!value) : null,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            width: 46,
            height: 26,
            decoration: BoxDecoration(
              color: !enabled
                  ? const Color(0xFFE5E5E5)
                  : value
                  ? _black
                  : const Color(0xFFE5E5E5),
              borderRadius: BorderRadius.circular(999),
              boxShadow: value && enabled
                  ? [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.2),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ]
                  : null,
            ),
            child: Padding(
              padding: const EdgeInsets.all(3),
              child: AnimatedAlign(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                alignment: value ? Alignment.centerRight : Alignment.centerLeft,
                child: Container(
                  width: 20,
                  height: 20,
                  decoration: const BoxDecoration(
                    color: _white,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    ),
  );
}

class _NavTile extends StatefulWidget {
  final IconData icon;
  final String label, subtitle;
  final VoidCallback onTap;
  const _NavTile({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.onTap,
  });
  @override
  State<_NavTile> createState() => _NavTileState();
}

class _NavTileState extends State<_NavTile> {
  bool _pressed = false;
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: widget.onTap,
    onTapDown: (_) {
      HapticFeedback.selectionClick();
      setState(() => _pressed = true);
    },
    onTapUp: (_) => setState(() => _pressed = false),
    onTapCancel: () => setState(() => _pressed = false),
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      color: _pressed ? _black.withOpacity(0.04) : Colors.transparent,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          _IconBox(icon: widget.icon),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.label,
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: _black,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  widget.subtitle,
                  style: GoogleFonts.inter(fontSize: 12, color: _grey),
                ),
              ],
            ),
          ),
          AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            transform: Matrix4.translationValues(_pressed ? 3 : 0, 0, 0),
            child: Icon(
              Icons.chevron_right_rounded,
              size: 18,
              color: _grey.withOpacity(0.5),
            ),
          ),
        ],
      ),
    ),
  );
}

class _InfoTile extends StatelessWidget {
  final IconData icon;
  final String label, value;
  final Color valueColor;
  const _InfoTile({
    required this.icon,
    required this.label,
    required this.value,
    this.valueColor = _grey,
  });

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    child: Row(
      children: [
        _IconBox(icon: icon),
        const SizedBox(width: 14),
        Expanded(
          child: Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: _black,
            ),
          ),
        ),
        Text(
          value,
          style: GoogleFonts.inter(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: valueColor,
          ),
        ),
      ],
    ),
  );
}

class _LogoutButton extends StatefulWidget {
  final VoidCallback onConfirm;
  const _LogoutButton({required this.onConfirm});
  @override
  State<_LogoutButton> createState() => _LogoutButtonState();
}

class _LogoutButtonState extends State<_LogoutButton> {
  bool _pressed = false;
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: () => _showDialog(context),
    onTapDown: (_) {
      HapticFeedback.mediumImpact();
      setState(() => _pressed = true);
    },
    onTapUp: (_) => setState(() => _pressed = false),
    onTapCancel: () => setState(() => _pressed = false),
    child: AnimatedScale(
      scale: _pressed ? 0.97 : 1.0,
      duration: const Duration(milliseconds: 120),
      curve: Curves.easeOutCubic,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: _white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: AppTheme.danger.withOpacity(0.35),
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: AppTheme.danger.withOpacity(0.08),
              blurRadius: 12,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.logout_rounded, color: AppTheme.danger, size: 17),
            const SizedBox(width: 10),
            Text(
              'Log Out',
              style: GoogleFonts.inter(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: AppTheme.danger,
              ),
            ),
          ],
        ),
      ),
    ),
  );

  void _showDialog(BuildContext context) {
    showDialog(
      context: context,
      barrierColor: Colors.black.withOpacity(0.6),
      builder: (_) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: AlertDialog(
          backgroundColor: Colors.transparent,
          elevation: 0,
          contentPadding: EdgeInsets.zero,
          insetPadding: const EdgeInsets.symmetric(horizontal: 32),
          content: Container(
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              color: _white,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.18),
                  blurRadius: 40,
                  offset: const Offset(0, 16),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: AppTheme.danger.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppTheme.danger.withOpacity(0.2)),
                  ),
                  child: Icon(
                    Icons.logout_rounded,
                    color: AppTheme.danger,
                    size: 22,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Log Out?',
                  style: GoogleFonts.antonSc(
                    fontSize: 22,
                    color: _black,
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'You will need to log in again to access the ETL Management App.',
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    color: _grey,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: () => Navigator.pop(context),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF5F5F5),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFFE5E5E5)),
                          ),
                          child: Center(
                            child: Text(
                              'Cancel',
                              style: GoogleFonts.inter(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: _grey,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: GestureDetector(
                        onTap: () {
                          Navigator.pop(context);
                          widget.onConfirm();
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          decoration: BoxDecoration(
                            color: AppTheme.danger.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: AppTheme.danger.withOpacity(0.3),
                            ),
                          ),
                          child: Center(
                            child: Text(
                              'Log Out',
                              style: GoogleFonts.inter(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: AppTheme.danger,
                              ),
                            ),
                          ),
                        ),
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
}
