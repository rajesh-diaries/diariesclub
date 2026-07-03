import 'package:flutter/material.dart';

import '../../../core/theme/app_text_styles.dart';
import 'safari_colors.dart';

class SafariWhatItIs extends StatelessWidget {
  const SafariWhatItIs({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'What is it?',
            style: AppTextStyles.h3(
              context,
              color: SafariColors.jungleGreen,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Safari Club is not a school, not a Montessori, and not an activity class.\n\n'
            'It is a trait-first play space for 2–5 year olds inside Play Diaries.\n\n'
            'It follows The Safari Method — a play-first approach where children grow the four life traits they need most: Brave, Curious, Kind, and Creative.\n\n'
            'In a world where knowledge is one click away, we believe children need relationships, confidence, and character far more than another worksheet.',
            style: AppTextStyles.body(
              context,
              color: SafariColors.slate,
            ),
          ),
        ],
      ),
    );
  }
}
