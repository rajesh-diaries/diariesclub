import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SafariWaitlistScreen extends StatefulWidget {
  const SafariWaitlistScreen({super.key});

  @override
  State<SafariWaitlistScreen> createState() => _SafariWaitlistScreenState();
}

class _SafariWaitlistScreenState extends State<SafariWaitlistScreen> {
  List<Map<String, dynamic>> _entries = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadEntries();
  }

  Future<void> _loadEntries() async {
    final rows = await Supabase.instance.client
        .from('safari_waitlist')
        .select()
        .order('created_at', ascending: false);
    setState(() {
      _entries = List<Map<String, dynamic>>.from(rows);
      _loading = false;
    });
  }

  Future<void> _updateStatus(String id, String status) async {
    await Supabase.instance.client
        .from('safari_waitlist')
        .update({'status': status, 'contacted_at': DateTime.now().toIso8601String()})
        .eq('id', id);
    await _loadEntries();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Safari Waitlist')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _entries.isEmpty
              ? const Center(child: Text('No entries yet.'))
              : ListView.builder(
                  itemCount: _entries.length,
                  itemBuilder: (context, index) {
                    final e = _entries[index];
                    return Card(
                      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: ListTile(
                        title: Text('${e['parent_name']} — ${e['child_name']} (${e['child_age']})'),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Phone: ${e['phone']}'),
                            Text('Status: ${e['status']}'),
                            Text('Date: ${e['created_at']}'),
                          ],
                        ),
                        isThreeLine: true,
                        trailing: PopupMenuButton<String>(
                          onSelected: (status) => _updateStatus(e['id'], status),
                          itemBuilder: (_) => [
                            const PopupMenuItem(value: 'pending', child: Text('Pending')),
                            const PopupMenuItem(value: 'contacted', child: Text('Contacted')),
                            const PopupMenuItem(value: 'enrolled', child: Text('Enrolled')),
                            const PopupMenuItem(value: 'declined', child: Text('Declined')),
                          ],
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}
