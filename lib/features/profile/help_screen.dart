// TODO: founder to wordsmith — placeholder copy for v1.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/providers/current_family_provider.dart';
import '../../core/providers/venue_config_provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/utils/phone.dart';

/// Help screen with a quick-contact bar at the top, an FAQ accordion, and
/// a "Report an issue" CTA that pre-fills WhatsApp with diagnostic context.
/// All FAQ copy is intentional placeholder — flagged with a TODO at the
/// top of the file so the founder can wordsmith without searching.
class HelpScreen extends ConsumerStatefulWidget {
  const HelpScreen({super.key});

  @override
  ConsumerState<HelpScreen> createState() => _HelpScreenState();
}

class _HelpScreenState extends ConsumerState<HelpScreen> {
  String _versionLine = '';

  @override
  void initState() {
    super.initState();
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    final info = await PackageInfo.fromPlatform();
    if (!mounted) return;
    setState(() => _versionLine = '${info.version}+${info.buildNumber}');
  }

  Future<void> _openWhatsApp({String? prefilled}) async {
    final cfg = ref.read(venueConfigProvider).valueOrNull ?? const {};
    final phone = (cfg['whatsapp_support_phone'] as String?) ?? '';
    final num = phone.replaceAll(RegExp(r'[^\d]'), '');
    final body = prefilled ?? 'Hi, I need help with Play Diaries.';
    final uri = Uri.parse('https://wa.me/$num?text=${Uri.encodeComponent(body)}');
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _call() async {
    final cfg = ref.read(venueConfigProvider).valueOrNull ?? const {};
    final phone = (cfg['whatsapp_support_phone'] as String?) ?? '';
    if (phone.isEmpty) return;
    await launchUrl(Uri.parse('tel:$phone'),
        mode: LaunchMode.externalApplication);
  }

  String _reportContext() {
    final family = ref.read(currentFamilyProvider).valueOrNull ?? const {};
    final phone = (family['phone'] as String?) ?? '';
    final phoneFmt =
        phone.isEmpty ? '—' : PhoneNormalizer.forDisplay(phone);
    return 'I need help with: \n\n'
        'My phone: $phoneFmt\n'
        'App version: $_versionLine';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Help'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(vertical: 16),
          children: [
            _QuickContactBar(
              onWhatsApp: () => _openWhatsApp(),
              onCall: _call,
            ),
            const SizedBox(height: 16),
            const _FaqAccordion(),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: OutlinedButton.icon(
                onPressed: () => _openWhatsApp(prefilled: _reportContext()),
                icon: const Icon(PhosphorIconsRegular.warningCircle),
                label: const Text('Report an issue'),
              ),
            ),
            const SizedBox(height: 24),
            _StillStuckCard(
              onWhatsApp: () => _openWhatsApp(),
              onCall: _call,
            ),
            const SizedBox(height: 16),
            const _PolicyFooter(),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

/// Privacy / Terms / Refund policy links — hosted externally (see
/// venue_config.*_url). Lives at the bottom of every Help screen so the
/// App Store reviewer and any parent can reach them in one tap from the
/// app's main support surface.
class _PolicyFooter extends ConsumerWidget {
  const _PolicyFooter();

  Future<void> _open(String? url) async {
    if (url == null || url.isEmpty) return;
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cfg = ref.watch(venueConfigProvider).valueOrNull ?? const {};
    final privacy = cfg['privacy_policy_url'] as String?;
    final terms = cfg['terms_of_service_url'] as String?;
    final refund = cfg['refund_policy_url'] as String?;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (privacy != null && privacy.isNotEmpty)
            TextButton.icon(
              onPressed: () => _open(privacy),
              icon: const Icon(PhosphorIconsRegular.shieldCheck, size: 18),
              label: const Text('Privacy Policy'),
              style: TextButton.styleFrom(
                alignment: Alignment.centerLeft,
                foregroundColor: AppColors.lightTextSecondary,
              ),
            ),
          if (terms != null && terms.isNotEmpty)
            TextButton.icon(
              onPressed: () => _open(terms),
              icon: const Icon(PhosphorIconsRegular.fileText, size: 18),
              label: const Text('Terms of Service'),
              style: TextButton.styleFrom(
                alignment: Alignment.centerLeft,
                foregroundColor: AppColors.lightTextSecondary,
              ),
            ),
          if (refund != null && refund.isNotEmpty)
            TextButton.icon(
              onPressed: () => _open(refund),
              icon: const Icon(PhosphorIconsRegular.receipt, size: 18),
              label: const Text('Refund Policy'),
              style: TextButton.styleFrom(
                alignment: Alignment.centerLeft,
                foregroundColor: AppColors.lightTextSecondary,
              ),
            ),
        ],
      ),
    );
  }
}

class _QuickContactBar extends StatelessWidget {
  final VoidCallback onWhatsApp;
  final VoidCallback onCall;
  const _QuickContactBar({required this.onWhatsApp, required this.onCall});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.activeGreen.withValues(alpha: 0.15),
            AppColors.gold.withValues(alpha: 0.15),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.lightBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Need urgent help?',
            style: AppTextStyles.bodyLarge(context),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: onWhatsApp,
                  icon: const Icon(PhosphorIconsRegular.whatsappLogo),
                  label: const Text('WhatsApp'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.activeGreen,
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: onCall,
                  icon: const Icon(PhosphorIconsRegular.phone),
                  label: const Text('Call'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.navy,
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
//  FAQ — placeholder copy. Founder to wordsmith.
// ---------------------------------------------------------------------------
class _FaqAccordion extends StatelessWidget {
  const _FaqAccordion();

  static const _sections = <_FaqSection>[
    _FaqSection('About Play Diaries', [
      _FaqItem(
        'What is Play Diaries?',
        "A premium kids' play space + café where character grows through play.",
      ),
      _FaqItem(
        'What are Coins?',
        'Cashback you earn on Coffee Diaries and FIT Diaries purchases. They sit in their own balance — redeem to your wallet from Profile when you want, then spend the wallet on anything at Play Diaries. (XP is different — kids earn that through play sessions and workshops.)',
      ),
      _FaqItem(
        'Why have a wallet?',
        'One balance across Play Diaries — pay for sessions, FIT meals, café orders. Top it up via recharge, referral bonuses, or redeemed Coins.',
      ),
    ]),
    _FaqSection('Sessions', [
      _FaqItem(
        'How do play sessions work?',
        'Pick 1 hour or 2 hours, pay from wallet or cash, show the QR at the desk to start your timer.',
      ),
      _FaqItem(
        'What if my time runs out?',
        "When your time's up, you'll see a wrap-up screen. Tap Extend for a 30-min or 1-hour top-up, or wrap up to finish.",
      ),
      _FaqItem(
        'Can I extend?',
        'Yes — open the active session card on Home and tap Extend. Wallet or cash.',
      ),
    ]),
    _FaqSection('Wallet & Payments', [
      _FaqItem(
        'How do top-up offers work?',
        'Larger top-ups come with a bonus credit. Bonuses sit in the same wallet — there is no separate balance to track.',
      ),
      _FaqItem(
        'Are wallet credits refundable?',
        'Wallet top-ups are non-refundable but never expire. Use them on play, café, or workshops at any time.',
      ),
      _FaqItem(
        'Why is my balance not updating?',
        "Razorpay confirmations land within ~5 seconds. If it's been longer than a minute, message us on WhatsApp and we'll fix it.",
      ),
    ]),
    _FaqSection('The Adventure', [
      _FaqItem(
        'How do my kids earn XP?',
        'Every play session, workshop, and reflection awards XP. Different activities favour different traits.',
      ),
      _FaqItem(
        'What are character traits?',
        'Brave (Rafi), Kind (Ellie), Curious (Gerry), Creative (Zena). Each trait progresses through 5 stages.',
      ),
      _FaqItem(
        'How do reflections work?',
        'After a session you can pick a few moments — those moments split the XP between traits. If you skip, we split evenly.',
      ),
    ]),
    _FaqSection('Birthdays', [
      _FaqItem(
        'How do I book a birthday?',
        "It's a quick enquiry first — open the Birthday card on Home, browse the packages and tap Inquire on the one you like. Our team WhatsApps you within 24 hours to lock the date and customise.",
      ),
      _FaqItem(
        'Can I cancel or reschedule?',
        'Cancel up to 1 month before the event. Reschedule up to 10 days before. Inside the 10-day window we’ve already committed to preparations, so neither is possible.',
      ),
      _FaqItem(
        "What's included in every package?",
        'A dedicated host, full play-area access for your guests, your own private hall, and unlimited food per the package menu.',
      ),
      _FaqItem(
        'Are add-ons available?',
        'Yes — activities (entertainer, themed games), themed decor, photography (event coverage + edited album), and a wallet/bar service. Our team walks you through the options.',
      ),
    ]),
    _FaqSection('Account', [
      _FaqItem(
        'How do I edit my info?',
        'Tap the pencil at the top of Profile to change your family name and email.',
      ),
      _FaqItem(
        'Can I delete my account?',
        'Yes — at the bottom of Profile. Your data is anonymised and cannot be recovered.',
      ),
      _FaqItem(
        'Privacy and data',
        'Our Privacy Policy, Terms of Service, and Refund Policy are linked at the bottom of this screen.',
      ),
    ]),
  ];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          for (final s in _sections) _Section(section: s),
        ],
      ),
    );
  }
}

class _FaqSection {
  final String title;
  final List<_FaqItem> items;
  const _FaqSection(this.title, this.items);
}

class _FaqItem {
  final String q;
  final String a;
  const _FaqItem(this.q, this.a);
}

class _Section extends StatelessWidget {
  final _FaqSection section;
  const _Section({required this.section});

  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      title: Text(section.title, style: AppTextStyles.bodyLarge(context)),
      childrenPadding: const EdgeInsets.symmetric(horizontal: 16),
      children: [
        for (final i in section.items)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(i.q, style: AppTextStyles.bodyLarge(context)),
                const SizedBox(height: 2),
                Text(
                  i.a,
                  style: AppTextStyles.body(
                    context,
                    color: AppColors.lightTextSecondary,
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
      ],
    );
  }
}

class _StillStuckCard extends StatelessWidget {
  final VoidCallback onWhatsApp;
  final VoidCallback onCall;
  const _StillStuckCard({required this.onWhatsApp, required this.onCall});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.lightSurface,
        border: Border.all(color: AppColors.lightBorder),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Still stuck?', style: AppTextStyles.h3(context)),
          const SizedBox(height: 4),
          Text(
            'Reach our team directly. We usually reply within an hour during venue hours.',
            style: AppTextStyles.body(
              context,
              color: AppColors.lightTextSecondary,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onWhatsApp,
                  icon: const Icon(PhosphorIconsRegular.whatsappLogo),
                  label: const Text('WhatsApp'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onCall,
                  icon: const Icon(PhosphorIconsRegular.phone),
                  label: const Text('Call'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
