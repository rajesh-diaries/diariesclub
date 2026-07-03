import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/theme/app_text_styles.dart';
import 'safari_colors.dart';

class SafariTypicalMorning extends StatelessWidget {
  const SafariTypicalMorning({super.key});

  final List<Map<String, String>> _slots = const [
    {'time': '9:30 AM', 'label': 'Arrival & free play'},
    {'time': '10:00 AM', 'label': 'Guided play activity (sensory, creative, or social)'},
    {'time': '11:00 AM', 'label': 'Snack & story circle'},
    {'time': '11:30 AM', 'label': 'Movement & character-trait games'},
    {'time': '12:15 PM', 'label': 'Wind-down'},
    {'time': '12:30 PM', 'label': 'Pickup'},
  ];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'A typical morning',
            style: AppTextStyles.h3(
              context,
              color: SafariColors.jungleGreen,
            ),
          ),
          const SizedBox(height: 20),
          ..._slots.map((slot) => Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      PhosphorIconsRegular.clock,
                      color: SafariColors.warmAmber,
                      size: 18,
                    ),
                    const SizedBox(width: 12),
                    Text(
                      slot['time']!,
                      style: AppTextStyles.body(
                        context,
                        color: SafariColors.jungleGreen,
                      ).copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        slot['label']!,
                        style: AppTextStyles.body(
                          context,
                          color: SafariColors.slate,
                        ),
                      ),
                    ),
                  ],
                ),
              )),
        ],
      ),
    );
  }
}
