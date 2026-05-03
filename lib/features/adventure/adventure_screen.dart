import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../shared/placeholder_screen.dart';

class AdventureScreen extends StatelessWidget {
  const AdventureScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const PlaceholderScreen(
      featureName: 'Adventure',
      subtitle: 'Heroes, traits, hero cards, gift ladder. Session 8.',
      icon: PhosphorIconsFill.compass,
    );
  }
}
