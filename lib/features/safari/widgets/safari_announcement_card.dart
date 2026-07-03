import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/providers/venue_config_provider.dart';
import '../../../core/theme/app_text_styles.dart';
import 'safari_colors.dart';

class SafariAnnouncementCard extends ConsumerWidget {
  const SafariAnnouncementCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cfg = ref.watch(venueConfigProvider).valueOrNull;
    final enabled = cfg?['safari_notice_enabled'] == true;
    final adminTitle = (cfg?['safari_notice_title'] as String?) ?? '';
    final adminBody = (cfg?['safari_notice_body'] as String?) ?? '';

    const defaultTitle = 'Coming soon';
    const defaultBody =
        'Safari Club is a brand-new morning experience for 2–5 year olds. Add your details below and we’ll reach out when enrollment opens.';

    final title = (enabled && adminTitle.isNotEmpty) ? adminTitle : defaultTitle;
    final body = (enabled && adminBody.isNotEmpty) ? adminBody : defaultBody;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: SafariColors.jungleGreen.withValues(alpha: 0.06),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: IntrinsicHeight(
          child: Row(
            children: [
              Container(width: 5, color: SafariColors.warmAmber),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: SafariColors.warmAmber.withValues(alpha: 0.12),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          PhosphorIconsRegular.info,
                          color: SafariColors.warmAmber,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              style: AppTextStyles.bodyLarge(
                                context,
                                color: SafariColors.jungleGreen,
                              ).copyWith(fontWeight: FontWeight.w800),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              body,
                              style: AppTextStyles.body(
                                context,
                                color: SafariColors.slate.withValues(alpha: 0.85),
                              ),
                            ),
                          ],
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
    );
  }
}
