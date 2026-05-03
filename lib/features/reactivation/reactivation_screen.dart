import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../shared/placeholder_screen.dart';

class ReactivationWelcomeScreen extends StatelessWidget {
  const ReactivationWelcomeScreen({super.key});
  @override
  Widget build(BuildContext context) => const PlaceholderScreen(
        featureName: 'Welcome back!',
        subtitle: '₹200 credit awaits. Session 12.',
        icon: PhosphorIconsFill.gift,
      );
}
