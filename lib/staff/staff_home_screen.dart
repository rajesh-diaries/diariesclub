import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme/app_colors.dart';
import 'providers/staff_auth_provider.dart';
import 'widgets/staff_app_bar.dart';

/// Staff home — v1 fallback (BUG-031 deferred to v1.1).
///
/// Background: across 10+ fix attempts on 2026-05-06 (Material+InkWell
/// variants, Card+InkWell, GestureDetector with HitTestBehavior.opaque,
/// SafeArea drops, Padding+Column wraps, ListTile fallback, etc.) the
/// staff home consistently absorbed taps on Flutter web with
/// `mouse_tracker.dart:199` and `box.dart:251` assertions firing every
/// frame on entry. Bisect proved every interactive widget shape failed,
/// while bare Text bodies + plain AppBar worked. Root cause is a deep
/// Flutter-web hit-test interaction with this app shell that needs
/// dedicated investigation, not more incremental patches.
///
/// v1 ship policy: staff signs in successfully, lands here, sees a
/// list of available routes + paths. Navigation is via URL bar /
/// bookmarks until v1.1 lands the polished interactive home.
///
/// The original interactive widgets (`_StatsBar`, `_ActionsGrid`,
/// `_ActionCard`, `_ActionTile`, `_EndShiftCta`) are kept in git
/// history (last working render shape: commit `d37391d`); restore
/// when BUG-031 is properly investigated.
class StaffHomeScreen extends ConsumerWidget {
  const StaffHomeScreen({super.key});

  static const _routes = <(String, String)>[
    ('Scan QR', '/staff/qr'),
    ('Manual session', '/staff/manual'),
    ('Active sessions', '/staff/sessions'),
    ('Kitchen (KDS)', '/staff/kds'),
    ('Healthy Bite', '/staff/healthy-bite'),
    ('Refund', '/staff/refund'),
    ('Walk-in POS', '/staff/walkin'),
    ('Menu availability', '/staff/menu'),
    ('Audit log', '/staff/audit'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final device = ref.watch(currentTabletDeviceProvider).valueOrNull;
    final deviceLabel = device?['device_label'] as String?;

    return Scaffold(
      appBar: StaffAppBar(deviceLabel: deviceLabel),
      body: const Padding(
        padding: EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'v1 — manual navigation',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: AppColors.navy,
              ),
            ),
            SizedBox(height: 8),
            Text(
              'The polished home is shipping in v1.1 (BUG-031 — Flutter web '
              'hit-test issue under investigation). For v1, navigate to '
              'each feature by typing the path in the URL bar or using '
              'bookmarks.',
              style: TextStyle(fontSize: 14, color: AppColors.lightTextSecondary),
            ),
            SizedBox(height: 24),
            Text(
              'Available routes',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: AppColors.lightTextPrimary,
              ),
            ),
            SizedBox(height: 8),
            _RoutesList(),
          ],
        ),
      ),
    );
  }
}

class _RoutesList extends StatelessWidget {
  const _RoutesList();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final (label, path) in StaffHomeScreen._routes)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    label,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: AppColors.lightTextPrimary,
                    ),
                  ),
                ),
                Text(
                  path,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 13,
                    color: AppColors.lightTextSecondary,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
