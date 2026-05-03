import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../shared/placeholder_screen.dart';

class SessionPreBookScreen extends StatelessWidget {
  const SessionPreBookScreen({super.key});
  @override
  Widget build(BuildContext context) => const PlaceholderScreen(
        featureName: 'Pre-book a session',
        subtitle: 'Same time next Saturday? Session 5.',
        icon: PhosphorIconsFill.calendarCheck,
      );
}
