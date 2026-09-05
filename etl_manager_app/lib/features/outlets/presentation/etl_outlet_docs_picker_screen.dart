// lib/features/outlets/presentation/etl_outlet_docs_picker_screen.dart
//
// ETL-manager entry point to outlet documents: pick any outlet, then manage its
// documents (the backend allows an ETL manager to manage any outlet's docs).

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/network/api_client.dart'; // dioProvider
import '../../../core/widgets/skeleton.dart';
import 'outlet_documents_screen.dart';

const _bg = Color(0xFF080808);
const _white = Color(0xFFFFFFFF);
const _black = Color(0xFF0A0A0A);
const _grey = Color(0xFF888888);
const _red = Color(0xFFD02128);

class _OutletRow {
  final int id;
  final String name;
  const _OutletRow(this.id, this.name);
}

class EtlOutletDocsPickerScreen extends ConsumerStatefulWidget {
  const EtlOutletDocsPickerScreen({super.key});

  @override
  ConsumerState<EtlOutletDocsPickerScreen> createState() =>
      _EtlOutletDocsPickerScreenState();
}

class _EtlOutletDocsPickerScreenState
    extends ConsumerState<EtlOutletDocsPickerScreen> {
  bool _loading = true;
  String? _error;
  List<_OutletRow> _outlets = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await ref.read(dioProvider).get('/outlets/');
      final data = res.data;
      final List list = data is List
          ? data
          : (data is Map ? (data['outlets'] ?? data['data'] ?? []) : []);
      final rows = <_OutletRow>[];
      for (final o in list) {
        if (o is Map && o['id'] != null) {
          rows.add(_OutletRow(
            o['id'] as int,
            (o['vendor_name'] ?? o['name'] ?? 'Outlet ${o['id']}').toString(),
          ));
        }
      }
      rows.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      if (!mounted) return;
      setState(() {
        _outlets = rows;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not load outlets. Pull to refresh.';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
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
                    onTap: () {
                      HapticFeedback.selectionClick();
                      Navigator.of(context).pop();
                    },
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
                                color: _white.withOpacity(0.9),
                              )),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  RichText(
                    text: TextSpan(
                      style: GoogleFonts.antonSc(
                          fontSize: 34, height: 0.95, letterSpacing: -0.5),
                      children: const [
                        TextSpan(text: 'O', style: TextStyle(color: _red)),
                        TextSpan(
                            text: 'UTLET DOCS', style: TextStyle(color: _white)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text('Pick an outlet to manage its documents',
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        color: _white.withOpacity(0.45),
                        fontWeight: FontWeight.w500,
                      )),
                ],
              ),
            ),
            Expanded(
              child: Container(
                width: double.infinity,
                decoration: const BoxDecoration(
                  color: _white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
                ),
                child: _loading
                    ? const SkeletonList(dark: false, count: 6, tileHeight: 64)
                    : _error != null
                        ? Center(
                            child: Text(_error!,
                                style: GoogleFonts.inter(color: _grey)))
                        : RefreshIndicator(
                            onRefresh: _load,
                            color: _black,
                            backgroundColor: _white,
                            child: ListView.separated(
                              padding: EdgeInsets.fromLTRB(
                                20,
                                22,
                                20,
                                MediaQuery.of(context).padding.bottom + 30,
                              ),
                              physics: const AlwaysScrollableScrollPhysics(
                                parent: BouncingScrollPhysics(),
                              ),
                              itemCount: _outlets.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 10),
                              itemBuilder: (_, i) {
                                final o = _outlets[i];
                                return GestureDetector(
                                  onTap: () {
                                    HapticFeedback.selectionClick();
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => OutletDocumentsScreen(
                                          outletId: o.id,
                                          outletName: o.name,
                                        ),
                                      ),
                                    );
                                  },
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 14, vertical: 14),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFFAFAFA),
                                      borderRadius: BorderRadius.circular(16),
                                      border: Border.all(
                                          color: Colors.grey.shade200,
                                          width: 1.5),
                                    ),
                                    child: Row(
                                      children: [
                                        Container(
                                          width: 40,
                                          height: 40,
                                          decoration: BoxDecoration(
                                            color: _red.withOpacity(0.08),
                                            borderRadius:
                                                BorderRadius.circular(12),
                                          ),
                                          child: const Icon(
                                              Icons.storefront_rounded,
                                              size: 18,
                                              color: _red),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Text(o.name,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: GoogleFonts.inter(
                                                  color: _black,
                                                  fontWeight: FontWeight.w700,
                                                  fontSize: 14)),
                                        ),
                                        const Icon(Icons.chevron_right_rounded,
                                            color: _grey),
                                      ],
                                    ),
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
