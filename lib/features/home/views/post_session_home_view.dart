import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'idle_home_view.dart';

/// Recently-completed-session state. Session reflections live in the
/// Adventure tab only — the Home screen simply returns to the normal
/// idle state so parents can start their next session or order food.
class PostSessionHomeView extends ConsumerWidget {
  final Map<String, dynamic> session;
  const PostSessionHomeView({super.key, required this.session});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return const SingleChildScrollView(
      padding: EdgeInsets.only(left: 20, right: 20, bottom: 12),
      child: IdleHomeBody(),
    );
  }
}
