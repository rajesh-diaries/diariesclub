import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _kPrefsKey = 'selected_adventure_child_id';

/// Persists the parent's last-selected child for the Adventure tab in
/// SharedPreferences. Returning to the tab restores the previous selection
/// rather than dumping the parent back into the multi-child picker.
///
/// Single-child families never enter this state — `AdventureScreen`
/// auto-selects the lone child.
class SelectedAdventureChildIdNotifier extends StateNotifier<String?> {
  SelectedAdventureChildIdNotifier() : super(null) {
    _restore();
  }

  Future<void> _restore() async {
    final p = await SharedPreferences.getInstance();
    final stored = p.getString(_kPrefsKey);
    if (stored != null && stored.isNotEmpty) state = stored;
  }

  Future<void> select(String childId) async {
    state = childId;
    final p = await SharedPreferences.getInstance();
    await p.setString(_kPrefsKey, childId);
  }

  /// Clear the selection — used by the dashboard's "switch" affordance to
  /// pop back to the multi-child selector.
  Future<void> clear() async {
    state = null;
    final p = await SharedPreferences.getInstance();
    await p.remove(_kPrefsKey);
  }
}

final selectedAdventureChildIdProvider =
    StateNotifierProvider<SelectedAdventureChildIdNotifier, String?>(
  (ref) => SelectedAdventureChildIdNotifier(),
);
