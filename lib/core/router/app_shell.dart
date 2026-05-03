import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

/// Bottom-nav shell hosting the 4 main tabs. Backed by StatefulShellRoute so
/// each branch preserves its own Navigator stack.
class AppShell extends StatelessWidget {
  final StatefulNavigationShell navigationShell;
  const AppShell({super.key, required this.navigationShell});

  @override
  Widget build(BuildContext context) {
    final i = navigationShell.currentIndex;
    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: i,
        onTap: (idx) => navigationShell.goBranch(
          idx,
          initialLocation: idx == navigationShell.currentIndex,
        ),
        items: [
          BottomNavigationBarItem(
            icon: Icon(i == 0 ? PhosphorIconsFill.house : PhosphorIconsRegular.house),
            label: 'Home',
          ),
          BottomNavigationBarItem(
            icon: Icon(i == 1 ? PhosphorIconsFill.martini : PhosphorIconsRegular.martini),
            label: 'Club',
          ),
          BottomNavigationBarItem(
            icon: Icon(i == 2 ? PhosphorIconsFill.compass : PhosphorIconsRegular.compass),
            label: 'Adventure',
          ),
          BottomNavigationBarItem(
            icon: Icon(i == 3 ? PhosphorIconsFill.user : PhosphorIconsRegular.user),
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}
