import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../shared/placeholder_screen.dart';

class OnboardingNameScreen extends StatelessWidget {
  const OnboardingNameScreen({super.key});
  @override
  Widget build(BuildContext context) => const PlaceholderScreen(
        featureName: "What's your name?",
        subtitle: 'Session 4.',
        icon: PhosphorIconsFill.user,
      );
}

class OnboardingChildScreen extends StatelessWidget {
  const OnboardingChildScreen({super.key});
  @override
  Widget build(BuildContext context) => const PlaceholderScreen(
        featureName: 'Tell us about your child',
        subtitle: 'Session 4.',
        icon: PhosphorIconsFill.babyCarriage,
      );
}
