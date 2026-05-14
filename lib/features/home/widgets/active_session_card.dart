import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/providers/family_children_provider.dart';
import '../../../core/theme/app_colors.dart';

/// Immersive "Playing now" card pinned at the top of multi-session home.
/// One card surface holds 1+ live sessions: each kid gets a ring timer
/// stroked in their favourite-character colour, with the remaining time
/// shown inside. Below the ring: kid's name + a status word
/// (Playing / Wrapping up / Awaiting check-in).
///
/// Single-kid → one big centred ring (120px) with a soft character-tinted
/// glow behind it. Multi-kid → a row of smaller rings (68px) on the same
/// navy gradient, each tappable into that session's detail.
class ActiveSessionsCard extends ConsumerStatefulWidget {
  final List<Map<String, dynamic>> sessions;
  const ActiveSessionsCard({super.key, required this.sessions});

  @override
  ConsumerState<ActiveSessionsCard> createState() =>
      _ActiveSessionsCardState();
}

class _ActiveSessionsCardState extends ConsumerState<ActiveSessionsCard> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final children = ref.watch(familyChildrenProvider).valueOrNull ?? const [];

    final entries = widget.sessions
        .map((s) => _Entry.from(s, children))
        .toList();
    if (entries.isEmpty) return const SizedBox.shrink();

    final singleKid = entries.length == 1;
    final glowColor = singleKid ? entries.first.heroColor : null;

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 22),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF2A4A92),
            AppColors.navy,
            Color(0xFF152C5C),
          ],
          stops: [0.0, 0.55, 1.0],
        ),
        border: Border.all(
          color: AppColors.gold.withValues(alpha: 0.28),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.navy.withValues(alpha: 0.28),
            blurRadius: 28,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(
                PhosphorIconsFill.sparkle,
                color: AppColors.gold,
                size: 16,
              ),
              const SizedBox(width: 8),
              Text(
                entries.length == 1
                    ? 'PLAYING NOW'
                    : '${entries.length} PLAYING NOW',
                style: const TextStyle(
                  color: AppColors.gold,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.6,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (singleKid)
            _SingleKidBody(entry: entries.first, glowColor: glowColor!)
          else
            _MultiKidBody(entries: entries),
        ],
      ),
    );
  }
}

class _Entry {
  final String sessionId;
  final String childName;
  final String status; // 'pending' | 'active' | 'grace' (or active-overrun)
  final DateTime? expiresAt;
  final DateTime? createdAt;
  final Color heroColor;

  _Entry({
    required this.sessionId,
    required this.childName,
    required this.status,
    required this.expiresAt,
    required this.createdAt,
    required this.heroColor,
  });

  /// Build an entry from a session row + the cached children list.
  /// `expires_at`/`created_at` are ISO strings that *can* be malformed in
  /// transient API states — we tryParse so a single bad row doesn't tank
  /// the Home tab; the timer just shows "—" until the next stream tick.
  static _Entry from(
    Map<String, dynamic> s,
    List<Map<String, dynamic>> children,
  ) {
    final childId = s['child_id'] as String?;
    final child = children.firstWhere(
      (c) => c['id'] == childId,
      orElse: () => const <String, dynamic>{},
    );
    return _Entry(
      sessionId: (s['id'] as String?) ?? '',
      childName: (child['name'] as String?) ?? 'Your kid',
      status: (s['status'] as String?) ?? 'active',
      expiresAt:
          DateTime.tryParse((s['expires_at'] as String?) ?? '')?.toLocal(),
      createdAt:
          DateTime.tryParse((s['created_at'] as String?) ?? '')?.toLocal(),
      heroColor: _heroColor(child['favourite_hero'] as String?),
    );
  }

  bool get isPending => status == 'pending';
  bool get isGrace =>
      expiresAt != null && expiresAt!.isBefore(DateTime.now());

  /// 0.0 = empty, 1.0 = full. Drains from 1 → 0 as time runs out.
  /// Pending: full (no scan yet so nothing's "spent"). Grace: 0.
  double progress() {
    if (isPending) return 1.0;
    final start = createdAt;
    final end = expiresAt;
    if (start == null || end == null) return 0;
    if (isGrace) return 0;
    final now = DateTime.now();
    final total = end.difference(start).inSeconds;
    final remaining = end.difference(now).inSeconds;
    if (total <= 0) return 0;
    return (remaining / total).clamp(0.0, 1.0);
  }

  /// Short label shown INSIDE the ring (the headline number).
  String ringLabel() {
    if (isPending) return '—';
    final end = expiresAt;
    if (end == null) return '—';
    final now = DateTime.now();
    final diff = end.difference(now);
    if (isGrace) {
      final over = (-diff.inMinutes).clamp(0, 999);
      return over == 0 ? '0m' : '+${over}m';
    }
    final mins = diff.inMinutes;
    final secs = diff.inSeconds.remainder(60);
    if (mins >= 60) return '${mins ~/ 60}h ${mins % 60}m';
    return '$mins:${secs.toString().padLeft(2, '0')}';
  }

  /// Status word beneath the kid's name.
  String statusWord() {
    if (isPending) return 'Awaiting check-in';
    if (isGrace) return 'Wrapping up';
    return 'Playing';
  }

  /// Tap → QR screen if not scanned yet, else session detail.
  String route() =>
      isPending ? '/session/qr/$sessionId' : '/session/$sessionId';

  static Color _heroColor(String? hero) => switch (hero) {
        'rafi' => AppColors.rafiCoral,
        'ellie' => AppColors.ellieBlue,
        'gerry' => AppColors.gerryAmber,
        'zena' => AppColors.zenaGreen,
        _ => AppColors.gold,
      };
}

class _SingleKidBody extends StatelessWidget {
  final _Entry entry;
  final Color glowColor;
  const _SingleKidBody({required this.entry, required this.glowColor});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => context.push(entry.route()),
      child: Column(
        children: [
          Center(
            child: SizedBox(
              width: 140,
              height: 140,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Soft character-tinted glow behind the ring. Sits in a
                  // bounded SizedBox so it doesn't bleed out of the card.
                  IgnorePointer(
                    child: Container(
                      width: 130,
                      height: 130,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: glowColor.withValues(alpha: 0.55),
                            blurRadius: 40,
                            spreadRadius: 6,
                          ),
                        ],
                      ),
                    ),
                  ),
                  CustomPaint(
                    size: const Size(120, 120),
                    painter: _RingPainter(
                      progress: entry.progress(),
                      color: entry.heroColor,
                      strokeWidth: 8,
                    ),
                  ),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        entry.ringLabel(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -0.5,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        entry.isPending
                            ? 'waiting'
                            : entry.isGrace
                                ? 'over'
                                : 'left',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.7),
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.8,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            entry.childName,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            entry.statusWord(),
            style: TextStyle(
              color: entry.heroColor,
              fontSize: 13,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }
}

class _MultiKidBody extends StatelessWidget {
  final List<_Entry> entries;
  const _MultiKidBody({required this.entries});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        for (final e in entries)
          Expanded(child: _MultiKidTile(entry: e)),
      ],
    );
  }
}

class _MultiKidTile extends StatelessWidget {
  final _Entry entry;
  const _MultiKidTile({required this.entry});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => context.push(entry.route()),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 68,
              height: 68,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  CustomPaint(
                    size: const Size(68, 68),
                    painter: _RingPainter(
                      progress: entry.progress(),
                      color: entry.heroColor,
                      strokeWidth: 5,
                    ),
                  ),
                  Text(
                    entry.ringLabel(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.3,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              entry.childName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              entry.statusWord(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: entry.heroColor,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Counter-clockwise draining ring. Background track at white@10%,
/// stroke in `color` from -90° sweeping the unspent fraction.
class _RingPainter extends CustomPainter {
  final double progress; // 0..1
  final Color color;
  final double strokeWidth;
  _RingPainter({
    required this.progress,
    required this.color,
    required this.strokeWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final centre = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2 - strokeWidth / 2;

    final trackPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.12)
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(centre, radius, trackPaint);

    if (progress <= 0) return;
    final arcPaint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      Rect.fromCircle(center: centre, radius: radius),
      -math.pi / 2,
      2 * math.pi * progress,
      false,
      arcPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) =>
      old.progress != progress ||
      old.color != color ||
      old.strokeWidth != strokeWidth;
}
