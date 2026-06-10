import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'safari_colors.dart';

class SafariAnnouncementCard extends StatefulWidget {
  const SafariAnnouncementCard({super.key});

  @override
  State<SafariAnnouncementCard> createState() => _SafariAnnouncementCardState();
}

class _SafariAnnouncementCardState extends State<SafariAnnouncementCard> {
  String? _announcement;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadAnnouncement();
  }

  Future<void> _loadAnnouncement() async {
    try {
      final rows = await Supabase.instance.client
          .from('announcements')
          .select('message')
          .eq('screen', 'safari')
          .eq('is_active', true)
          .order('created_at', ascending: false)
          .limit(1);

      if (rows.isNotEmpty) {
        setState(() {
          _announcement = rows.first['message'] as String?;
          _loading = false;
        });
      } else {
        setState(() => _loading = false);
      }
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading || _announcement == null) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: SafariColors.warmAmber.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: SafariColors.warmAmber.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline, color: SafariColors.warmAmber, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              _announcement!,
              style: const TextStyle(
                color: SafariColors.slate,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
