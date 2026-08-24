// lib/features/notices/presentation/notices_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/widgets/appear_fade.dart';
import '../../../core/widgets/skeleton.dart';
import '../domain/notice_model.dart';
import '../domain/notices_notifier.dart';

const _bg = Color(0xFF080808);
const _white = Color(0xFFFFFFFF);
const _black = Color(0xFF0A0A0A);
const _grey = Color(0xFF888888);
const _red = Color(0xFFD02128);

class NoticesScreen extends ConsumerStatefulWidget {
  const NoticesScreen({super.key});

  @override
  ConsumerState<NoticesScreen> createState() => _NoticesScreenState();
}

class _NoticesScreenState extends ConsumerState<NoticesScreen> {
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    // Fresh fetch with the CURRENT user's token, then silently clear the unread
    // count + app-icon badge — opening the inbox counts as "seen", so the user
    // never has to tap each notice to mark it read. The red highlight stays
    // visible for this session.
    Future.microtask(() async {
      final n = ref.read(noticesNotifierProvider.notifier);
      await n.refresh();
      await n.markAllReadSilently();
    });
  }

  @override
  void dispose() {
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scroll.position.pixels >=
        _scroll.position.maxScrollExtent - 240) {
      ref.read(noticesNotifierProvider.notifier).loadMore();
    }
  }

  Future<void> _pickDate() async {
    final st = ref.read(noticesNotifierProvider);
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: st.selectedDate,
      firstDate: DateTime(now.year - 2),
      lastDate: DateTime(now.year, now.month, now.day),
      helpText: 'View notices from',
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.light(
            primary: _red,
            onPrimary: _white,
            onSurface: _black,
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null) {
      HapticFeedback.selectionClick();
      ref.read(noticesNotifierProvider.notifier).selectDate(picked);
    }
  }

  static String _dateLabel(DateTime d) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final diff = today.difference(DateTime(d.year, d.month, d.day)).inDays;
    if (diff == 0) return 'Today';
    if (diff == 1) return 'Yesterday';
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return '${d.day} ${months[d.month - 1]} ${d.year}';
  }

  @override
  Widget build(BuildContext context) {
    final st = ref.watch(noticesNotifierProvider);
    final notifier = ref.read(noticesNotifierProvider.notifier);

    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Top bar ──
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      height: 38,
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      decoration: BoxDecoration(
                        color: _white.withOpacity(0.07),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: _white.withOpacity(0.12)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.west_rounded,
                              size: 14, color: _white.withOpacity(0.9)),
                          const SizedBox(width: 6),
                          Text('Back',
                              style: GoogleFonts.inter(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: _white.withOpacity(0.9))),
                        ],
                      ),
                    ),
                  ),
                  const Spacer(),
                  if (!notifier.isToday)
                    TextButton(
                      onPressed: () {
                        HapticFeedback.selectionClick();
                        notifier.goToToday();
                      },
                      child: Text('Today',
                          style: GoogleFonts.inter(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              color: _white.withOpacity(0.7))),
                    ),
                ],
              ),
            ),
            // ── Title ──
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: RichText(
                text: TextSpan(
                  style: GoogleFonts.antonSc(
                      fontSize: 36, height: 0.95, letterSpacing: -0.5),
                  children: const [
                    TextSpan(text: 'N', style: TextStyle(color: _red)),
                    TextSpan(text: 'OTICES', style: TextStyle(color: _white)),
                  ],
                ),
              ),
            ),
            // ── Date selector chip ──
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
              child: GestureDetector(
                onTap: _pickDate,
                child: Container(
                  height: 40,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  decoration: BoxDecoration(
                    color: _white.withOpacity(0.07),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: _white.withOpacity(0.12)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.calendar_today_rounded,
                          size: 14, color: _white.withOpacity(0.85)),
                      const SizedBox(width: 8),
                      Text(_dateLabel(st.selectedDate),
                          style: GoogleFonts.inter(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: _white)),
                      const SizedBox(width: 6),
                      Icon(Icons.expand_more_rounded,
                          size: 16, color: _white.withOpacity(0.6)),
                    ],
                  ),
                ),
              ),
            ),
            // ── Body ──
            Expanded(
              child: Container(
                width: double.infinity,
                decoration: const BoxDecoration(
                  color: _white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
                ),
                child: RefreshIndicator(
                  color: _black,
                  onRefresh: notifier.refresh,
                  child: _buildBody(st),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(NoticesState st) {
    if (st.loading) {
      return const SkeletonList(dark: false, count: 6, tileHeight: 76);
    }
    if (st.error != null && st.notices.isEmpty) {
      return const Center(child: Text('Could not load notices'));
    }
    if (st.notices.isEmpty) {
      return _NoticesEmpty(label: _dateLabel(st.selectedDate));
    }

    return AppearFade(
      child: ListView.separated(
        controller: _scroll,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(
          20, 22, 20, MediaQuery.of(context).padding.bottom + 30),
        itemCount: st.notices.length + 1, // +1 footer
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (_, i) {
          if (i == st.notices.length) return _Footer(st: st);
          return _NoticeCard(notice: st.notices[i]);
        },
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  final NoticesState st;
  const _Footer({required this.st});

  @override
  Widget build(BuildContext context) {
    if (st.loadingMore) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 20),
        child: Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(color: _black, strokeWidth: 2),
          ),
        ),
      );
    }
    if (!st.hasMore) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 18),
        child: Center(
          child: Text("You're all caught up",
              style: GoogleFonts.inter(
                  fontSize: 12, fontWeight: FontWeight.w600, color: _grey)),
        ),
      );
    }
    return const SizedBox(height: 8);
  }
}

class _NoticeCard extends StatelessWidget {
  final NoticeModel notice;
  const _NoticeCard({required this.notice});

  IconData get _icon {
    switch (notice.type) {
      case 'early_logout':
        return Icons.logout_rounded;
      case 'shift_changed':
        return Icons.schedule_rounded;
      default:
        return Icons.notifications_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final unread = !notice.isRead;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: unread ? _red.withOpacity(0.04) : _white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: unread ? _red.withOpacity(0.25) : const Color(0xFFE5E5E5),
          width: 1.5,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: (notice.type == 'early_logout' ? _red : _black)
                  .withOpacity(0.08),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(_icon,
                size: 18,
                color: notice.type == 'early_logout' ? _red : _black),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        notice.title,
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: _black,
                        ),
                      ),
                    ),
                    if (unread)
                      Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                            color: _red, shape: BoxShape.circle),
                      ),
                  ],
                ),
                if (notice.body != null && notice.body!.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    notice.body!,
                    style: GoogleFonts.inter(
                        fontSize: 12.5, color: _grey, height: 1.4),
                  ),
                ],
                const SizedBox(height: 6),
                Text(
                  _relativeTime(notice.createdAt),
                  style: GoogleFonts.inter(fontSize: 11, color: _grey),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _relativeTime(DateTime? dt) {
    if (dt == null) return '';
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${dt.day}/${dt.month}/${dt.year}';
  }
}

class _NoticesEmpty extends StatelessWidget {
  final String label;
  const _NoticesEmpty({required this.label});
  @override
  Widget build(BuildContext context) => ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          SizedBox(height: MediaQuery.of(context).size.height * 0.16),
          Icon(Icons.notifications_none_rounded,
              size: 48, color: _grey.withOpacity(0.4)),
          const SizedBox(height: 14),
          Center(
            child: Text('No notices for $label',
                style: GoogleFonts.inter(
                    fontSize: 16, fontWeight: FontWeight.w700, color: _black)),
          ),
          const SizedBox(height: 6),
          Center(
            child: Text('Pick another date to see older notices',
                style: GoogleFonts.inter(fontSize: 13, color: _grey)),
          ),
        ],
      );
}
