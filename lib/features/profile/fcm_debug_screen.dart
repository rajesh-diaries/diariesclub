import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/notifications/fcm_setup.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/widgets/primary_button.dart';
import '../../flavors.dart';

/// Dev-flavor-only screen to verify FCM end-to-end on a physical device.
/// Shows the current token + permission state + a one-line curl command
/// to send a test push from a terminal. Reachable from the profile menu
/// in dev only — gated by F.isDev so prod customers never see it.
class FcmDebugScreen extends ConsumerStatefulWidget {
  const FcmDebugScreen({super.key});

  @override
  ConsumerState<FcmDebugScreen> createState() => _FcmDebugScreenState();
}

class _FcmDebugScreenState extends ConsumerState<FcmDebugScreen> {
  String? _token;
  String _permStatus = 'unknown';
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() => _busy = true);
    try {
      final settings = await FirebaseMessaging.instance.getNotificationSettings();
      final token = currentFcmToken ??
          await FirebaseMessaging.instance.getToken();
      if (!mounted) return;
      setState(() {
        _token = token;
        _permStatus = settings.authorizationStatus.toString().split('.').last;
        _busy = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _permStatus = 'error: $e';
        _busy = false;
      });
    }
  }

  Future<void> _requestPermission() async {
    await FirebaseMessaging.instance.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    await _refresh();
  }

  String _curlSnippet() {
    if (_token == null) return '(no token yet)';
    // Send via legacy HTTP API (FCM_SERVER_KEY). Documenting only — we
    // don't ship the server key to the client. The reader is expected to
    // export FCM_SERVER_KEY locally before running.
    return '''
curl -X POST https://fcm.googleapis.com/fcm/send \\
  -H "Authorization: key=\$FCM_SERVER_KEY" \\
  -H "Content-Type: application/json" \\
  -d '{
    "to": "$_token",
    "notification": {
      "title": "Diaries test",
      "body": "Hi from your terminal"
    },
    "data": {
      "type": "debug_test",
      "deep_link": "/profile",
      "channel": "default"
    }
  }'
''';
  }

  @override
  Widget build(BuildContext context) {
    if (!F.isDev) {
      return Scaffold(
        appBar: AppBar(title: const Text('FCM debug')),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(32),
            child: Text(
              'This screen is dev-flavor only.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('FCM debug'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _busy ? null : _refresh,
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Section(
                title: 'Permission',
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        _permStatus,
                        style: AppTextStyles.bodyLarge(context),
                      ),
                    ),
                    if (_permStatus != 'authorized')
                      OutlinedButton(
                        onPressed: _busy ? null : _requestPermission,
                        child: const Text('Request'),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              _Section(
                title: 'Token',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SelectableText(
                      _token ?? '(none yet — try requesting permission)',
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (_token != null)
                      OutlinedButton.icon(
                        onPressed: () async {
                          await Clipboard.setData(
                              ClipboardData(text: _token!));
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Token copied.')),
                          );
                        },
                        icon: const Icon(Icons.copy),
                        label: const Text('Copy'),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              _Section(
                title: 'Test from terminal',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Set FCM_SERVER_KEY in your shell, then paste the '
                      'snippet below. Push should arrive within a few seconds.',
                      style: AppTextStyles.body(
                        context,
                        color: AppColors.lightTextSecondary,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.lightBackground,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: SelectableText(
                        _curlSnippet(),
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 11,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    PrimaryButton(
                      label: 'Copy curl',
                      onPressed: _token == null
                          ? null
                          : () async {
                              await Clipboard.setData(
                                  ClipboardData(text: _curlSnippet()));
                              if (!context.mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                    content: Text('Curl snippet copied.')),
                              );
                            },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Pending deep link (cold-start tap): '
                '${pendingFcmDeepLink ?? '(none)'}',
                style: AppTextStyles.caption(
                  context,
                  color: AppColors.lightTextSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  final Widget child;
  const _Section({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.lightSurface,
        border: Border.all(color: AppColors.lightBorder),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            style: AppTextStyles.caption(
              context,
              color: AppColors.lightTextSecondary,
            ).copyWith(letterSpacing: 1, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }
}
