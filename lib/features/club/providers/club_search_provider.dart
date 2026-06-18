import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Current search query typed in the Club app bar.
/// Each tab (Cafe/FIT/Combos) watches this and filters its own items.
final clubSearchQueryProvider = StateProvider<String>((ref) => '');
