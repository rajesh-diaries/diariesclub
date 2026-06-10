import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/providers/venue_config_provider.dart';
import 'safari_colors.dart';

class SafariAnnouncementCard extends ConsumerWidget {
  const SafariAnnouncementCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cfg = ref.watch(venueConfigProvider).valueOrNull;
    final enabled = cfg?['safari_notice_enabled'] == true;
    final title = (cfg?['safari_notice_title'] as String?) ?? '';
    final body = (cfg?['safari_notice_body'] as String?) ?? '';

    if (!enabled || (title.isEmpty && body.isEmpty)) {
      return const SizedBox.shrink();
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: SafariColors.warmAmber.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: SafariColors.warmAmber.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline, color: SafariColors.warmAmber, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (title.isNotEmpty)
                  Text(
                    title,
                    style: const TextStyle(
                      color: SafariColors.slate,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                if (body.isNotEmpty) ...[
                  if (title.isNotEmpty) const SizedBox(height: 2),
                  Text(
                    body,
                    style: const TextStyle(
                      color: SafariColors.slate,
                      fontSize: 13,
                      height: 1.4,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
