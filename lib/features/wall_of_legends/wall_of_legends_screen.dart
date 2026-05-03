import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../shared/placeholder_screen.dart';

class WallOfLegendsScreen extends StatelessWidget {
  const WallOfLegendsScreen({super.key});
  @override
  Widget build(BuildContext context) => const PlaceholderScreen(
        featureName: 'Wall of Legends',
        subtitle: "Today's anonymised highlights. Session 8.",
        icon: PhosphorIconsFill.trophy,
      );
}
