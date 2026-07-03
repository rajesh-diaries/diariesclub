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
  final List<bool> _expanded = [false, false, false, false, false];

  final List<Map<String, String>> _faqs = const [
    {
      'q': 'Is this a school or Montessori program?',
      'a': 'No. Safari Club is a play-based morning club using The Safari Method. We focus on character traits and life skills, not academics.',
    },
    {
      'q': 'How is this different from activity classes?',
      'a': 'Most activity classes teach one skill. Safari Club uses play to build the four traits that help in every part of life.',
    },
    {
      'q': 'What should my child bring?',
      'a': 'A water bottle is plenty. Healthy snacks or meals can be provided, or you’re welcome to send your own snack box.',
    },
    {
      'q': 'Can we visit before enrolling?',
      'a': 'Yes. We’ll invite interested families for a visit once enrollment opens.',
    },
    {
      'q': 'When does Safari Club start?',
      'a': 'We’re preparing to launch soon. Tap “I’m interested” to be the first to know.',
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
