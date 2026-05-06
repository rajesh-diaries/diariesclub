import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/theme/app_colors.dart';
import '../core/theme/app_text_styles.dart';

/// Camera-based QR scanner. On detect, calls qr_scan_validate RPC. On
/// success, routes to /staff/scan-success with the validated session
/// metadata; on failure, shows an inline error toast and resumes scanning
/// after a short cooldown.
class QrScannerScreen extends ConsumerStatefulWidget {
  final String staffId;
  const QrScannerScreen({super.key, required this.staffId});

  @override
  ConsumerState<QrScannerScreen> createState() => _QrScannerScreenState();
}

class _QrScannerScreenState extends ConsumerState<QrScannerScreen> {
  final MobileScannerController _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
  );
  bool _busy = false;
  String? _errorText;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_busy) return;
    final code = capture.barcodes.isEmpty
        ? null
        : capture.barcodes.first.rawValue;
    if (code == null || code.isEmpty) return;

    setState(() {
      _busy = true;
      _errorText = null;
    });
    HapticFeedback.lightImpact();

    try {
      final raw = await Supabase.instance.client.rpc<dynamic>(
        'qr_scan_validate',
        params: {'p_qr_payload': code, 'p_staff_pin_id': widget.staffId},
      );
      final result =
          raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
      if (!mounted) return;
      context.replace('/staff/scan-success', extra: result);
    } on PostgrestException catch (e) {
      if (!mounted) return;
      final msg = e.message;
      setState(() {
        _errorText = msg.contains('qr_already_scanned')
            ? 'QR already scanned earlier.'
            : msg.contains('session_not_active')
                ? 'Session is not active.'
                : msg.contains('session_not_found')
                    ? 'Session not found.'
                    : msg.contains('qr_payload_invalid')
                        ? 'QR not recognised.'
                        : 'Scan failed.';
      });
      await Future<void>.delayed(const Duration(milliseconds: 1500));
      if (!mounted) return;
      setState(() => _busy = false);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _errorText = 'Network error.';
      });
      await Future<void>.delayed(const Duration(milliseconds: 1500));
      if (!mounted) return;
      setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Scan QR'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(PhosphorIconsRegular.flashlight),
            onPressed: () => _controller.toggleTorch(),
          ),
        ],
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
          ),
          // Overlay box — clamps to viewport so it fits narrow phones.
          LayoutBuilder(
            builder: (context, constraints) {
              final size = constraints.biggest.shortestSide - 48;
              final box = size > 320 ? 320.0 : size.clamp(180.0, 320.0);
              return Center(
                child: Container(
                  width: box,
                  height: box,
                  decoration: BoxDecoration(
                    border: Border.all(color: AppColors.gold, width: 3),
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
              );
            },
          ),
          if (_errorText != null)
            Positioned(
              top: 24,
              left: 24,
              right: 24,
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.adminRed,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  _errorText!,
                  style:
                      AppTextStyles.body(context, color: Colors.white),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          Positioned(
            bottom: 32,
            left: 24,
            right: 24,
            child: Center(
              child: TextButton.icon(
                style: TextButton.styleFrom(
                  backgroundColor: Colors.black54,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 12),
                ),
                icon: const Icon(PhosphorIconsRegular.phoneCall),
                onPressed: () => context.replace(
                  '/staff/manual',
                  extra: {'staffId': widget.staffId},
                ),
                label: const Text('Trouble scanning? Manual session →'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
