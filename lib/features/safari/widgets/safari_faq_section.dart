import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import 'safari_colors.dart';

class SafariFaqSection extends StatefulWidget {
  const SafariFaqSection({super.key});

  @override
  State<SafariFaqSection> createState() => _SafariFaqSectionState();
}

class _SafariFaqSectionState extends State<SafariFaqSection> {
  final List<bool> _expanded = [false, false, false, false];

  final List<Map<String, String>> _faqs = const [
    {
      'q': 'When will Safari Club open?',
      'a': 'We are preparing the space and will share the launch timeline with waitlisted families first. Add your name to get early access.',
    },
    {
      'q': 'What age is Safari Club for?',
      'a': 'Safari Club is open to children aged 2 to 5 years. Activities are adapted to each age group so every child stays engaged.',
    },
    {
      'q': 'What will a typical day look like?',
      'a': 'A mix of guided play, creative projects, music and movement, story time, and calm reflection — all woven around our four character traits.',
    },
    {
      'q': 'Will there be screens or devices?',
      'a': 'No screens. We keep the day tactile and social so children learn through doing, creating, and connecting with others.',
    },
  ];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Questions?',
            style: AppTextStyles.h3(
              context,
              color: SafariColors.jungleGreen,
            ),
          ),
          const SizedBox(height: 20),
          ...List.generate(_faqs.length, (index) {
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFEEEEEE)),
              ),
              child: ExpansionTile(
                title: Text(
                  _faqs[index]['q']!,
                  style: AppTextStyles.body(
                    context,
                    color: SafariColors.slate,
                  ).copyWith(fontWeight: FontWeight.w700),
                ),
                trailing: Icon(
                  _expanded[index]
                      ? PhosphorIconsRegular.caretUp
                      : PhosphorIconsRegular.caretDown,
                  color: SafariColors.jungleGreen,
                ),
                onExpansionChanged: (expanded) {
                  setState(() => _expanded[index] = expanded);
                },
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: Text(
                      _faqs[index]['a']!,
                      style: AppTextStyles.body(
                        context,
                        color: AppColors.lightTextSecondary,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}
