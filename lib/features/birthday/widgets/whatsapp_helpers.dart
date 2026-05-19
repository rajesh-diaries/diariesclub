import 'dart:async';

import 'package:url_launcher/url_launcher.dart';

/// Strip non-digits and "+" so we can pass a clean number to wa.me.
String _waNumber(String phone) =>
    phone.replaceAll(RegExp(r'[^0-9]'), '');

Uri _waUri(String phone, String message) {
  return Uri.parse(
    'https://wa.me/${_waNumber(phone)}?text=${Uri.encodeComponent(message)}',
  );
}

/// "Send me the brochure" CTA on each package card.
///
/// Greets the team's WhatsApp on behalf of the parent so the message is
/// warm + actionable. The PDF link is appended so the team can grab the
/// exact brochure to send back, and we leave a clean signature so the
/// parent's intent (package + child) is explicit.
Future<bool> openBrochureWhatsapp({
  required String teamPhone,
  required String packageName,
  required String? childName,
  required String? parentName,
  required String? brochurePdfUrl,
}) {
  final greeting = parentName != null && parentName.isNotEmpty
      ? 'Hi! This is $parentName.'
      : 'Hi from the Play Diaries app.';
  final forChild = childName != null && childName.isNotEmpty
      ? ' We\'re planning $childName\'s birthday'
      : ' We\'re planning a birthday';
  final pdfLine = brochurePdfUrl != null && brochurePdfUrl.isNotEmpty
      ? '\n\nBrochure: $brochurePdfUrl'
      : '';
  final message =
      '$greeting$forChild and would love the brochure for $packageName, please.$pdfLine';
  return launchUrl(
    _waUri(teamPhone, message),
    mode: LaunchMode.externalApplication,
  );
}

/// Floating "Talk to our team" CTA at the bottom of the packages screen.
/// Opens WhatsApp with a soft opener so the team isn't guessing what the
/// parent's question is about.
Future<bool> openTalkToTeamWhatsapp({
  required String teamPhone,
  required String? childName,
  required String? parentName,
}) {
  final greeting = parentName != null && parentName.isNotEmpty
      ? 'Hi! This is $parentName.'
      : 'Hi from the Play Diaries app.';
  final forChild = childName != null && childName.isNotEmpty
      ? ' Looking at birthday packages for $childName.'
      : ' Looking at birthday packages.';
  final message = '$greeting$forChild Could you help me with a few questions?';
  return launchUrl(
    _waUri(teamPhone, message),
    mode: LaunchMode.externalApplication,
  );
}
