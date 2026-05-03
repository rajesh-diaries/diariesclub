import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../shared/placeholder_screen.dart';

class BirthdayDiscoveryScreen extends StatelessWidget {
  const BirthdayDiscoveryScreen({super.key});
  @override
  Widget build(BuildContext context) => const PlaceholderScreen(
        featureName: 'Plan a birthday',
        subtitle: 'Discovery + reservations. Session 9.',
        icon: PhosphorIconsFill.cake,
      );
}

class BirthdayPackagesScreen extends StatelessWidget {
  const BirthdayPackagesScreen({super.key});
  @override
  Widget build(BuildContext context) => const PlaceholderScreen(
        featureName: 'Birthday packages',
        subtitle: 'Session 9.',
        icon: PhosphorIconsFill.gift,
      );
}

class BirthdayReserveScreen extends StatelessWidget {
  final String packageId;
  const BirthdayReserveScreen({super.key, required this.packageId});
  @override
  Widget build(BuildContext context) => PlaceholderScreen(
        featureName: 'Reserve birthday slot',
        subtitle: 'Package $packageId. Session 9.',
        icon: PhosphorIconsFill.calendarPlus,
      );
}

class BirthdayStatusScreen extends StatelessWidget {
  final String reservationId;
  const BirthdayStatusScreen({super.key, required this.reservationId});
  @override
  Widget build(BuildContext context) => PlaceholderScreen(
        featureName: 'Reservation status',
        subtitle: 'Reservation $reservationId. Session 9.',
        icon: PhosphorIconsFill.clipboard,
      );
}

class BirthdayAlbumScreen extends StatelessWidget {
  final String reservationId;
  const BirthdayAlbumScreen({super.key, required this.reservationId});
  @override
  Widget build(BuildContext context) => PlaceholderScreen(
        featureName: 'Birthday album',
        subtitle: 'Photos from $reservationId. Session 9.',
        icon: PhosphorIconsFill.images,
      );
}
