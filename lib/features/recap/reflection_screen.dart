import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../shared/placeholder_screen.dart';

class ReflectionScreen extends StatelessWidget {
  final String sessionId;
  const ReflectionScreen({super.key, required this.sessionId});
  @override
  Widget build(BuildContext context) => PlaceholderScreen(
        featureName: 'Hero recap',
        subtitle: 'Tap-the-moments for $sessionId. Session 6.',
        icon: PhosphorIconsFill.heart,
      );
}
