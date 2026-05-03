import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../shared/placeholder_screen.dart';

class PhoneAuthScreen extends StatelessWidget {
  const PhoneAuthScreen({super.key});
  @override
  Widget build(BuildContext context) => const PlaceholderScreen(
        featureName: 'Sign in',
        subtitle: 'OTP-based phone auth. Session 4.',
        icon: PhosphorIconsFill.signIn,
      );
}

class OtpScreen extends StatelessWidget {
  const OtpScreen({super.key});
  @override
  Widget build(BuildContext context) => const PlaceholderScreen(
        featureName: 'Verify OTP',
        subtitle: 'Session 4.',
        icon: PhosphorIconsFill.shieldCheck,
      );
}
