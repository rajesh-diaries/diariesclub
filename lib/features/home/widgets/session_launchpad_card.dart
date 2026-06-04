import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/providers/server_clock_provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';

/// Compact "Adventure Launchpad" banner that appears on idle home when the
/// family has a reserved pre-booking. Shows the child's hero, countdown to
/// the slot, and a one-tap "I'm here!" button that redeems the pre-booking
/// and jumps straight to the QR screen.
class SessionLaunchpadCard extends ConsumerStatefulWidget {
  final Map<String, dynamic> preBooking;

  const SessionLaunchpadCard({super.key, required this.preBooking});

  @override
  ConsumerState<SessionLaunchpadCard> createState() =>
      _SessionLaunchpadCardState();
}

class _SessionLaunchpadCardState extends ConsumerState<SessionLaunchpadCard>
    with SingleTickerProviderStateMixin {
  bool _busy = false;
  String? _errorText;

  late final AnimationController _bounceController;

  static const _heroAssets = <String, String>{
    'rafi': 'assets/hero/rafi.png',
    'ellie': 'assets/hero/ellie.png',
    'gerry': 'assets/hero/gerry.png',
    'zena': 'assets/hero/zena.png',
  };

  static const _heroColors = <String, Color>{
    'rafi': AppColors.rafiCoral,
    'ellie': AppColors.ellieBlue,
    'gerry': AppColors.gerryAmber,
    'zena': AppColors.zenaGreen,
  };

  @override
  void initState() {
    super.initState();
    _bounceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _bounceController.dispose();
    super.dispose();
  }

  String get _childName =>
      (widget.preBooking['child_name'] as String?) ?? 'Your little one';

  String get _heroKey =>
      (widget.preBooking['favourite_hero'] as String?) ?? 'rafi';

  String? get _heroAsset => _heroAssets[_heroKey];

  Color get _heroColor => _heroColors[_heroKey] ?? AppColors.rafiCoral;

  DateTime? get _scheduledStart {
    final raw = widget.preBooking['scheduled_start'];
    if (raw == null) return null;
    if (raw is DateTime) return raw;
    if (raw is String) return DateTime.tryParse(raw);
    return null;
  }

  String _countdownLabel(DateTime scheduled) {
    final serverNow = ref.read(serverClockProvider.notifier).serverNow;
    final diff = scheduled.difference(serverNow);

    if (diff.isNegative) {
      return 'Starting now!';
    }
    if (diff.inDays > 0) {
      return 'Starts in ${diff.inDays}d ${diff.inHours.remainder(24)}h';
    }
    if (diff.inHours > 0) {
      return 'Starts in ${diff.inHours}h ${diff.inMinutes.remainder(60)}m';
    }
    if (diff.inMinutes > 5) {
      return 'Starts in ${diff.inMinutes}m';
    }
    return 'Starting soon!';
  }

  String _timeLabel(DateTime scheduled) {
    final hour = scheduled.hour > 12 ? scheduled.hour - 12 : scheduled.hour;
    final ampm = scheduled.hour >= 12 ? 'PM' : 'AM';
    final min = scheduled.minute.toString().padLeft(2, '0');
    final day = _dayName(scheduled.weekday);
    return '$day at $hour:$min $ampm';
  }

  String _dayName(int weekday) {
    const names = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return names[weekday - 1];
  }

  Future<void> _onImHere() async {
    HapticFeedback.mediumImpact();
    setState(() {
      _busy = true;
      _errorText = null;
    });

    try {
      final preBookingId = widget.preBooking['id'] as String?;
      if (preBookingId == null) throw StateError('Missing pre_booking_id');

      final result = await Supabase.instance.client.rpc<Map<String, dynamic>>(
        'pre_booking_redeem',
        params: {
          'p_pre_booking_id': preBookingId,
        },
      );

      if (!mounted) return;

      final success = result['success'] == true;
      if (!success) {
        setState(() {
          _busy = false;
          _errorText = 'Could not start session. Please try again.';
        });
        return;
      }

      final session = result['session'] as Map<String, dynamic>?;
      final sessionId = session?['session_id'] as String?;
      if (sessionId == null) {
        setState(() {
          _busy = false;
          _errorText = 'Session started but ID missing. Please refresh.';
        });
        return;
      }

      HapticFeedback.heavyImpact();
      if (!mounted) return;
      context.push('/session/qr/$sessionId');
    } on PostgrestException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _errorText = e.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _errorText = 'Something went wrong. Try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheduled = _scheduledStart;
    final countdown = scheduled != null ? _countdownLabel(scheduled) : 'Soon';
    final timeLabel = scheduled != null ? _timeLabel(scheduled) : '';

    return AnimatedBuilder(
      animation: _bounceController,
      builder: (context, child) {
        final bounce = math.sin(_bounceController.value * math.pi * 2) * 4;
        return Container(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                AppColors.navy,
                Color(0xFF1E3A6F),
              ],
            ),
            border: Border.all(
              color: _heroColor.withValues(alpha: 0.35),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: AppColors.navy.withValues(alpha: 0.20),
                blurRadius: 16,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Hero avatar with gentle bounce
              Transform.translate(
                offset: Offset(0, bounce),
                child: Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: _heroColor.withValues(alpha: 0.18),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: _heroColor.withValues(alpha: 0.50),
                      width: 2,
                    ),
                  ),
                  child: _heroAsset != null
                      ? ClipOval(
                          child: Image.asset(
                            _heroAsset!,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Icon(
                              PhosphorIconsFill.sparkle,
                              color: _heroColor,
                              size: 28,
                            ),
                          ),
                        )
                      : Icon(
                          PhosphorIconsFill.sparkle,
                          color: _heroColor,
                          size: 28,
                        ),
                )
                    .animate(onPlay: (c) => c.repeat(reverse: true))
                    .scale(
                      begin: const Offset(1.0, 1.0),
                      end: const Offset(1.08, 1.08),
                      duration: 1800.ms,
                      curve: Curves.easeInOut,
                    ),
              ),
              const SizedBox(width: 14),
              // Text column
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$_childName\'s adventure',
                      style: AppTextStyles.bodyLarge(
                        context,
                        color: Colors.white,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      countdown,
                      style: TextStyle(
                        color: _heroColor,
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.3,
                      ),
                    ),
                    if (timeLabel.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        timeLabel,
                        style: AppTextStyles.caption(
                          context,
                          color: Colors.white.withValues(alpha: 0.65),
                        ),
                      ),
                    ],
                    if (_errorText != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        _errorText!,
                        style: const TextStyle(
                          color: AppColors.rafiCoral,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 10),
              // "I'm here!" button
              _busy
                  ? const SizedBox(
                      width: 44,
                      height: 44,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: AppColors.gold,
                      ),
                    )
                  : FilledButton(
                      onPressed: _onImHere,
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.gold,
                        foregroundColor: AppColors.navy,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                      child: const Text(
                        "I'm here!",
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
            ],
          ),
        );
      },
    );
  }
}
