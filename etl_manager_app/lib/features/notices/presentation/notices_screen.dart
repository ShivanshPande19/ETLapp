// lib/features/notices/presentation/notices_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

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
  @override
  void initState() {
    super.initState();
    // Always refetch with the CURRENT user's token on open — guards against
    // showing a previous session's cached notices (provider is keep-alive).
    Future.microtask(
      () => ref.read(noticesNotifierProvider.notifier).fetch(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(noticesNotifierProvider);

    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
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
                  TextButton(
                    onPressed: () {
                      HapticFeedback.selectionClick();
                      ref.read(noticesNotifierProvider.notifier).markAllRead();
                    },
                    child: Text('Mark all read',
                        style: GoogleFonts.inter(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: _white.withOpacity(0.7))),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
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
            Expanded(
              child: Container(
                decoration: const BoxDecoration(
                  color: _white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
                ),
                child: RefreshIndicator(
                  color: _black,
                  onRefresh: () =>
                      ref.read(noticesNotifierProvider.notifier).fetch(),
                  child: async.when(
                    loading: () => const SkeletonList(
                        dark: false, count: 6, tileHeight: 76),
                    error: (_, __) => const Center(
                        child: Text('Could not load notices')),
                    data: (res) {
                      if (res.notices.isEmpty) return const _NoticesEmpty();
                      return ListView.separated(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: EdgeInsets.fromLTRB(
                          20, 22, 20,
                          MediaQuery.of(context).padding.bottom + 30,
                        ),
                        itemCount: res.notices.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (_, i) => _NoticeCard(
                          notice: res.notices[i],
                          onTap: () {
                            if (!res.notices[i].isRead) {
                              ref
                                  .read(noticesNotifierProvider.notifier)
                                  .markRead(res.notices[i].id);
                            }
                          },
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NoticeCard extends StatelessWidget {
  final NoticeModel notice;
  final VoidCallback onTap;
  const _NoticeCard({required this.notice, required this.onTap});

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
    return GestureDetector(
      onTap: onTap,
      child: Container(
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
  const _NoticesEmpty();
  @override
  Widget build(BuildContext context) => ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          SizedBox(height: MediaQuery.of(context).size.height * 0.18),
          Icon(Icons.notifications_none_rounded,
              size: 48, color: _grey.withOpacity(0.4)),
          const SizedBox(height: 14),
          Center(
            child: Text('No notices yet',
                style: GoogleFonts.inter(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: _black)),
          ),
          const SizedBox(height: 6),
          Center(
            child: Text("You're all caught up",
                style: GoogleFonts.inter(fontSize: 13, color: _grey)),
          ),
        ],
      );
}
