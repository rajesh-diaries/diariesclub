import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../widgets/admin_app_bar.dart';
import '../widgets/admin_buttons.dart';

/// Compose and send a broadcast push notification to every active family.
///
/// Calls `admin_notification_broadcast` (migration 0141) which fans out
/// one row per family into the `notifications` table. The customer
/// inbox is realtime-subscribed to that table, so the message + unread
/// badge appear the moment the broadcast lands.
///
/// Deep links are optional; when set, tapping the inbox row routes the
/// customer to that path. We expose the same route options as
/// announcement editor for consistency.
class BroadcastNotificationScreen extends ConsumerStatefulWidget {
  const BroadcastNotificationScreen({super.key});

  @override
  ConsumerState<BroadcastNotificationScreen> createState() =>
      _BroadcastNotificationScreenState();
}

const _deepLinkOptions = <String, String>{
  '': '— None —',
  '/home': 'Home',
  '/club': 'Club tab',
  '/club/workshops': 'Workshops',
  '/birthday': 'Birthday discovery',
  '/profile/wallet-history': 'Wallet history',
  '/adventure': 'Adventure tab',
};

class _BroadcastNotificationScreenState
    extends ConsumerState<BroadcastNotificationScreen> {
  final _titleCtrl = TextEditingController();
  final _bodyCtrl = TextEditingController();
  String _deepLink = '';
  bool _busy = false;
  String? _errorText;

  @override
  void dispose() {
    _titleCtrl.dispose();
    _bodyCtrl.dispose();
    super.dispose();
  }

  Future<void> _confirmAndSend() async {
    if (_busy) return;
    final title = _titleCtrl.text.trim();
    final body = _bodyCtrl.text.trim();
    if (title.isEmpty || body.isEmpty) {
      setState(() => _errorText = 'Title and body are required.');
      return;
    }
    if (title.length > 80) {
      setState(() => _errorText = 'Title must be 80 chars or less.');
      return;
    }
    if (body.length > 240) {
      setState(() => _errorText = 'Body must be 240 chars or less.');
      return;
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Send to every family?'),
        content: Text(
          'This broadcast will land in the inbox of every active '
          'family. It cannot be unsent.\n\n'
          'Title: $title\n\n'
          'Body: $body',
        ),
        actions: [
          AdminSecondaryButton(
            label: 'Cancel',
            ghost: true,
            onPressed: () => Navigator.pop(c, false),
          ),
          const SizedBox(width: 8),
          AdminPrimaryButton(
            label: 'Send broadcast',
            onPressed: () => Navigator.pop(c, true),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    setState(() {
      _busy = true;
      _errorText = null;
    });
    try {
      final res = await Supabase.instance.client
          .rpc<Map<String, dynamic>>('admin_notification_broadcast', params: {
        'p_title': title,
        'p_body': body,
        'p_deep_link': _deepLink.isEmpty ? null : _deepLink,
      });
      if (!mounted) return;
      final count = res['recipient_count'] as int? ?? 0;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppColors.activeGreen,
          content: Text('Broadcast sent to $count famil${count == 1 ? 'y' : 'ies'}.'),
        ),
      );
      setState(() {
        _busy = false;
        _titleCtrl.clear();
        _bodyCtrl.clear();
        _deepLink = '';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _errorText = 'Could not send: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const AdminAppBar(
        title: 'Push Notifications',
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(
                      PhosphorIconsRegular.bellRinging,
                      color: AppColors.navy,
                      size: 22,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Broadcast to all families',
                      style: AppTextStyles.h2(context, color: AppColors.navy),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  'Drops a notification into every active family\'s inbox '
                  'right away. The customer\'s bell badge ticks up, and '
                  'tapping the row deep-links them to the optional route below.',
                  style: AppTextStyles.body(
                    context,
                    color: AppColors.lightTextSecondary,
                  ),
                ),
                const SizedBox(height: 24),

                Text('Title', style: AppTextStyles.bodyLarge(context)),
                const SizedBox(height: 6),
                TextField(
                  controller: _titleCtrl,
                  enabled: !_busy,
                  maxLength: 80,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    isDense: true,
                    hintText: 'e.g. New workshop just dropped',
                  ),
                ),

                const SizedBox(height: 8),
                Text('Body', style: AppTextStyles.bodyLarge(context)),
                const SizedBox(height: 6),
                TextField(
                  controller: _bodyCtrl,
                  enabled: !_busy,
                  maxLength: 240,
                  maxLines: 4,
                  minLines: 3,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    hintText:
                        'e.g. Saturday slime-making with Zena. Spots fill fast — tap to register.',
                  ),
                ),

                const SizedBox(height: 8),
                Text('Tap action (optional)',
                    style: AppTextStyles.bodyLarge(context)),
                const SizedBox(height: 6),
                DropdownButtonFormField<String>(
                  initialValue: _deepLink,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: [
                    for (final entry in _deepLinkOptions.entries)
                      DropdownMenuItem<String>(
                        value: entry.key,
                        child: Text(entry.value),
                      ),
                  ],
                  onChanged: _busy
                      ? null
                      : (v) => setState(() => _deepLink = v ?? ''),
                ),

                if (_errorText != null) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.adminRed.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: AppColors.adminRed.withValues(alpha: 0.35),
                      ),
                    ),
                    child: Text(
                      _errorText!,
                      style: AppTextStyles.body(
                        context,
                        color: AppColors.adminRed,
                      ),
                    ),
                  ),
                ],

                const SizedBox(height: 24),
                Row(
                  children: [
                    AdminPrimaryButton(
                      icon: PhosphorIconsRegular.paperPlaneTilt,
                      label: _busy ? 'Sending…' : 'Send broadcast',
                      onPressed: _busy ? null : _confirmAndSend,
                    ),
                    const SizedBox(width: 12),
                    Text(
                      'No undo. Sent immediately.',
                      style: AppTextStyles.caption(
                        context,
                        color: AppColors.lightTextSecondary,
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
