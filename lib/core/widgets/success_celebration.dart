import 'package:confetti/confetti.dart';
import 'package:flutter/material.dart';

/// A short confetti burst that can be triggered around a child widget.
class SuccessCelebration extends StatefulWidget {
  final Widget child;
  final bool shouldPlay;

  const SuccessCelebration({
    super.key,
    required this.child,
    this.shouldPlay = false,
  });

  @override
  State<SuccessCelebration> createState() => _SuccessCelebrationState();
}

class _SuccessCelebrationState extends State<SuccessCelebration> {
  late final ConfettiController _controller;

  @override
  void initState() {
    super.initState();
    _controller = ConfettiController(
      duration: const Duration(milliseconds: 800),
    );
  }

  @override
  void didUpdateWidget(covariant SuccessCelebration oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.shouldPlay && !oldWidget.shouldPlay) {
      _controller.play();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        widget.child,
        Positioned.fill(
          child: Align(
            alignment: Alignment.topCenter,
            child: ConfettiWidget(
              confettiController: _controller,
              blastDirectionality: BlastDirectionality.explosive,
              numberOfParticles: 18,
              maxBlastForce: 10,
              minBlastForce: 5,
              emissionFrequency: 0.02,
              gravity: 0.2,
            ),
          ),
        ),
      ],
    );
  }
}
