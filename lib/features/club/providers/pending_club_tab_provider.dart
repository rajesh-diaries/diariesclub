import 'package:flutter_riverpod/flutter_riverpod.dart';

/// One-shot "open Club on this tab" request. Set just before navigating to
/// `/club`; ClubScreen consumes the value, animates its TabController to
/// the requested index, then resets back to null so a later plain visit
/// keeps the user's last-viewed tab.
///
/// Tab indices follow ClubScreen's tab order: 0=Cafe, 1=FIT, 2=Combos,
/// 3=Workshops.
final pendingClubTabProvider = StateProvider<int?>((ref) => null);
