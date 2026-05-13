import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/providers/auth_provider.dart';
import '../../../core/providers/notifications_provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';

/// Bottom sheet inbox triggered by the bell icon on HomeAppBar. Sectioned
/// (TODAY / EARLIER), filled-dot for unread, taps deep-link via the
/// notification's `deep_link` column and mark the row read.
class NotificationInboxSheet extends ConsumerWidget {
  const NotificationInboxSheet({super.key});

  Future<void> _markAllRead(WidgetRef ref) async {
    final familyId = ref.read(currentFamilyIdProvider);
    if (familyId == null) return;
    await Supabase.instance.client
        .from('notifications')
        .update({'is_read': true})
        .eq('family_id', familyId)
        .eq('is_read', false);
  }

  Future<void> _open(
    BuildContext context,
    Map<String, dynamic> n,
  ) async {
    if (n['is_read'] != true) {
      await Supabase.instance.client
          .from('notifications')
          .update({'is_read': true}).eq('id', n['id'] as String);
    }
    if (!context.mounted) return;
    Navigator.of(context).pop();
    final link = n['deep_link'] as String?;
    if (link == null || link.isEmpty) return;
    // Wrap the navigation so a stale/typo deep_link (e.g. an older
    // schema's route) doesn't leave the customer on a blank 404 page.
    // Falls back to Home with a non-blocking snackbar.
    try {
      context.push(link);
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('That link is no longer available.'),
        ),
      );
      context.go('/home');
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(notificationsProvider).valueOrNull ?? const [];

    final today = <Map<String, dynamic>>[];
    final earlier = <Map<String, dynamic>>[];
    final cutoff = DateTime.now().subtract(const Duration(hours: 24));
    for (final n in list) {
      final t = DateTime.parse(n['created_at'] as String);
      if (t.isAfter(cutoff)) {
        today.add(n);
      } else {
        earlier.add(n);
      }
    }

    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.4,
      maxChildSize: 0.9,
      expand: false,
      builder: (_, controller) => Container(
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 12),
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.lightBorder,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Notifications', style: AppTextStyles.h2(context)),
                  TextButton(
                    onPressed: list.any((n) => n['is_read'] != true)
                        ? () => _markAllRead(ref)
                        : null,
                    child: const Text('Mark all read'),
                  ),
                ],
              ),
            ),
            Expanded(
              child: list.isEmpty
                  ? Center(
                      child: Text(
                        'No notifications yet.',
                        style: AppTextStyles.body(
                          context,
                          color: AppColors.lightTextSecondary,
                        ),
                      ),
                    )
                  : ListView(
                      controller: controller,
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      children: [
                        if (today.isNotEmpty) ...[
                          const _Heading(text: 'TODAY'),
                          for (final n in today)
                            _NotificationTile(
                              n: n,
                              onTap: () => _open(context, n),
                            ),
                          const SizedBox(height: 16),
                        ],
                        if (earlier.isNotEmpty) ...[
                          const _Heading(text: 'EARLIER'),
                          for (final n in earlier)
                            _NotificationTile(
                              n: n,
                              onTap: () => _open(context, n),
                            ),
                        ],
                        const SizedBox(height: 32),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Heading extends StatelessWidget {
  final String text;
  const _Heading({required this.text});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Text(
          text,
          style: AppTextStyles.caption(
            context,
            color: AppColors.lightTextSecondary,
          ),
        ),
      );
}

class _NotificationTile extends StatelessWidget {
  final Map<String, dynamic> n;
  final VoidCallback onTap;
  const _NotificationTile({required this.n, required this.onTap});

  String _timeAgo(String iso) {
    final t = DateTime.parse(iso).toLocal();
    final diff = DateTime.now().difference(t);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
    if (diff.inHours < 24) return '${diff.inHours} hr ago';
    return '${diff.inDays}d ago';
  }

  @override
  Widget build(BuildContext context) {
    final unread = n['is_read'] != true;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 6, right: 12),
              child: Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: unread ? AppColors.gold : AppColors.lightBorder,
                  shape: BoxShape.circle,
                ),
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    (n['title'] as String?) ?? 'Notification',
                    style: AppTextStyles.bodyLarge(context),
                  ),
                  if ((n['body'] as String?)?.isNotEmpty == true) ...[
                    const SizedBox(height: 4),
                    Text(
                      n['body'] as String,
                      style: AppTextStyles.body(
                        context,
                        color: AppColors.lightTextSecondary,
                      ),
                    ),
                  ],
                  const SizedBox(height: 4),
                  Text(
                    _timeAgo(n['created_at'] as String),
                    style: AppTextStyles.caption(
                      context,
                      color: AppColors.lightTextSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
