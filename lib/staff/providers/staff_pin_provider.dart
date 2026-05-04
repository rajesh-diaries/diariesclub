import 'package:flutter_riverpod/flutter_riverpod.dart';

/// One verified-staff identity for the duration of a sensitive action.
/// Set when verify_staff_pin succeeds; consumed by the action's RPC; left
/// in place for ~30s so a parent flow (e.g., PIN → confirm dialog → submit)
/// doesn't re-prompt.
class VerifiedStaff {
  final String staffId;
  final String staffName;
  final String role;
  final bool forcePinChange;
  final DateTime verifiedAt;

  const VerifiedStaff({
    required this.staffId,
    required this.staffName,
    required this.role,
    required this.forcePinChange,
    required this.verifiedAt,
  });

  VerifiedStaff.fromRpc(Map<String, dynamic> json)
      : staffId = json['staff_id'] as String,
        staffName = (json['staff_name'] as String?) ?? '',
        role = (json['role'] as String?) ?? 'cashier',
        forcePinChange = json['force_pin_change'] == true,
        verifiedAt = DateTime.now();

  bool get isStale =>
      DateTime.now().difference(verifiedAt) > const Duration(seconds: 30);
}

/// The most-recently-verified staff identity. Cleared after each action.
final lastVerifiedStaffProvider =
    StateProvider<VerifiedStaff?>((ref) => null);
