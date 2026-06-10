import 'package:flutter/material.dart';
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
      'a': 'We are finalizing our space and will share a timeline with waitlisted families first. Join the list to be the first to know.',
    },
    {
      'q': 'What age is Safari Club for?',
      'a': 'Safari Club is designed for children aged 2 to 4 years.',
    },
    {
      'q': 'What will a typical day look like?',
      'a': 'Free play, structured activities, outdoor exploration, story time, and healthy snacks — all designed around our four character traits.',
    },
    {
      'q': 'Will there be screens or devices?',
      'a': 'No. Safari Club is intentionally screen-free. We believe children learn best through hands-on play, nature, and social interaction.',
    },
  ];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Questions?',
            style: TextStyle(
              color: SafariColors.jungleGreen,
              fontSize: 22,
              fontWeight: FontWeight.w600,
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
                  style: const TextStyle(
                    color: SafariColors.slate,
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                trailing: Icon(
                  _expanded[index]
                      ? Icons.keyboard_arrow_up
                      : Icons.keyboard_arrow_down,
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
                      style: const TextStyle(
                        color: Color(0xFF666666),
                        fontSize: 14,
                        height: 1.5,
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
