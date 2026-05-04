import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:pub_semver/pub_semver.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

enum AppVersionStatus { upToDate, softUpdate, forceUpdate, unknown }

class AppVersionResult {
  final AppVersionStatus status;
  final String currentVersion;
  final String minVersion;
  final String latestVersion;

  const AppVersionResult({
    required this.status,
    required this.currentVersion,
    required this.minVersion,
    required this.latestVersion,
  });

  static const unknown = AppVersionResult(
    status: AppVersionStatus.unknown,
    currentVersion: '0.0.0',
    minVersion: '0.0.0',
    latestVersion: '0.0.0',
  );
}

/// Compares the running app version against `venue_config.{platform}_*_version`.
/// Used by the router to gate the app behind /update-required when below min.
///
/// Web builds short-circuit to `upToDate` — there's no app store to direct
/// users to, and `dart:io Platform` throws on web (BUG-001 in BUGS.md).
final appVersionStatusProvider = FutureProvider<AppVersionResult>((ref) async {
  final info = await PackageInfo.fromPlatform();

  // Strip Flutter build suffix (1.0.0+1 → 1.0.0)
  final currentRaw = info.version.split('+').first;

  if (kIsWeb) {
    return AppVersionResult(
      status: AppVersionStatus.upToDate,
      currentVersion: currentRaw,
      minVersion: '0.0.0',
      latestVersion: currentRaw,
    );
  }

  final platform = defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android';

  try {
    final config = await Supabase.instance.client
        .from('venue_config')
        .select('${platform}_min_supported_version, ${platform}_latest_version')
        .single();

    final minStr = (config['${platform}_min_supported_version'] as String?) ?? '0.0.0';
    final latestStr = (config['${platform}_latest_version'] as String?) ?? '0.0.0';

    final current = Version.parse(currentRaw);
    final min = Version.parse(minStr);
    final latest = Version.parse(latestStr);

    AppVersionStatus status;
    if (current < min) {
      status = AppVersionStatus.forceUpdate;
    } else if (current < latest) {
      status = AppVersionStatus.softUpdate;
    } else {
      status = AppVersionStatus.upToDate;
    }

    return AppVersionResult(
      status: status,
      currentVersion: currentRaw,
      minVersion: minStr,
      latestVersion: latestStr,
    );
  } catch (_) {
    // Network down / venue_config unreachable — don't lock the user out.
    return AppVersionResult(
      status: AppVersionStatus.unknown,
      currentVersion: currentRaw,
      minVersion: '0.0.0',
      latestVersion: '0.0.0',
    );
  }
});
