import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/providers/profile_history_providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/utils/currency.dart';

/// Detail view for a single past session. Lists the immediately-available
/// fields (date, duration, payment, amount, status, child) and points to
/// the reflection screen for the Session-6 bits (XP per trait, hero card,
/// reflection moments).
class PastSessionDetailScreen extends ConsumerWidget {
  final String sessionId;
  const PastSessionDetailScreen({super.key, required this.sessionId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(pastSessionDetailProvider(sessionId));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Session detail'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      body: SafeArea(
        child: async.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                "Couldn't load this session.",
                style: AppTextStyles.body(context),
              ),
            ),
          ),
          data: (s) {
            if (s == null) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    'Session not found.',
                    style: AppTextStyles.body(context),
                  ),
                ),
              );
            }
            return _Body(session: s);
          },
        ),
      ),
    );
  }
}

class _Body extends StatelessWidget {
  final Map<String, dynamic> session;
  const _Body({required this.session});

  @override
  Widget build(BuildContext context) {
    final childName =
        ((session['children'] as Map?)?['name'] as String?) ?? 'Your child';
    final duration = session['duration_minutes'] as int? ?? 0;
    final amount = session['amount_paise'] as int? ?? 0;
    final paymentMethod =
        (session['payment_method'] as String?) ?? '—';
    final status = session['status'] as String? ?? 'completed';
    final startedAt = DateTime.parse(session['started_at'] as String).toLocal();
    final completedAt = session['completed_at'] != null
        ? DateTime.parse(session['completed_at'] as String).toLocal()
        : null;
    final reflectionStatus =
        (session['reflection_status'] as String?) ?? 'pending';
    final isGuest = session['is_guest'] == true;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            childName,
            style: AppTextStyles.h2(context),
          ),
          const SizedBox(height: 4),
          Text(
            DateFormat('EEEE, MMM d · h:mm a').format(startedAt),
            style: AppTextStyles.body(
              context,
              color: AppColors.lightTextSecondary,
            ),
          ),
          const SizedBox(height: 16),
          _Fact(label: 'Duration',
              value: duration == 60 ? '1 hour' : '$duration minutes'),
          _Fact(label: 'Amount', value: Money.fromPaise(amount)),
          _Fact(label: 'Payment', value: _paymentLabel(paymentMethod)),
          _Fact(label: 'Status', value: _statusLabel(status)),
          if (completedAt != null)
            _Fact(
              label: 'Completed',
              value: DateFormat('MMM d · h:mm a').format(completedAt),
            ),
          if (isGuest)
            const _Fact(label: 'Guest session', value: 'Yes'),
          const SizedBox(height: 24),
          _ReflectionBlock(
            sessionId: session['id'] as String,
            reflectionStatus: reflectionStatus,
          ),
        ],
      ),
    );
  }

  String _paymentLabel(String method) => switch (method) {
        'wallet' => 'Diaries Wallet',
        'cash' => 'Cash at venue',
        'razorpay' => 'Razorpay',
        _ => method,
      };

  String _statusLabel(String status) => switch (status) {
        'active' => 'Active',
        'grace' => 'In grace',
        'completed' => 'Completed',
        'auto_closed' => 'Auto-closed',
        'void' => 'Cancelled',
        _ => status,
      };
}

class _Fact extends StatelessWidget {
  final String label;
  final String value;
  const _Fact({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: AppTextStyles.body(
              context,
              color: AppColors.lightTextSecondary,
            ),
          ),
          Text(value, style: AppTextStyles.body(context)),
        ],
      ),
    );
  }
}

class _ReflectionBlock extends StatelessWidget {
  final String sessionId;
  final String reflectionStatus;
  const _ReflectionBlock({
    required this.sessionId,
    required this.reflectionStatus,
  });

  @override
  Widget build(BuildContext context) {
    final tone = switch (reflectionStatus) {
      'reflected' => 'Reflected',
      'auto_split' => 'Auto-split (XP awarded automatically)',
      _ => 'Reflection pending',
    };
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.gold.withValues(alpha: 0.10),
        border: Border.all(color: AppColors.gold.withValues(alpha: 0.30)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                PhosphorIconsFill.medal,
                color: AppColors.navy,
                size: 22,
              ),
              const SizedBox(width: 8),
              Text('Hero Recap', style: AppTextStyles.h3(context)),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            tone,
            style: AppTextStyles.body(
              context,
              color: AppColors.lightTextSecondary,
            ),
          ),
          const SizedBox(height: 8),
          // Detail (XP-per-trait, moments tapped, hero card earned) lives in
          // Session 6's reflection screen — link out for now.
          OutlinedButton.icon(
            onPressed: () => context.push('/reflection/$sessionId'),
            icon: const Icon(PhosphorIconsRegular.heart),
            label: const Text('Open reflection'),
          ),
        ],
      ),
    );
  }
}
