import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../shared/placeholder_screen.dart';

class ClubScreen extends StatelessWidget {
  const ClubScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const PlaceholderScreen(
      featureName: 'Club',
      subtitle: 'Café & FIT menu, combos, while-you-wait food. Session 7.',
      icon: PhosphorIconsFill.martini,
    );
  }
}
