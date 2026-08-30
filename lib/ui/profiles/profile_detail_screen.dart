/// Profile detail (U4 placeholder for U5's calendar): a read-only list of
/// logged days scoped to exactly one profile (R3). Archived profiles open in
/// read-only mode with an unarchive action.
library;

import 'package:flutter/material.dart';
import 'package:lunarlog/domain/models/day_entry.dart';
import 'package:lunarlog/domain/models/flow_level.dart';
import 'package:lunarlog/domain/models/profile.dart';
import 'package:lunarlog/domain/repositories/day_entries_repository.dart';
import 'package:lunarlog/ui/profiles/profile_controller.dart';
import 'package:provider/provider.dart';

String _flowLabel(FlowLevel flow) {
  final name = flow.name;
  return name[0].toUpperCase() + name.substring(1);
}

class ProfileDetailScreen extends StatefulWidget {
  const ProfileDetailScreen({
    super.key,
    required this.profile,
    this.readOnly = false,
  });

  final Profile profile;
  final bool readOnly;

  @override
  State<ProfileDetailScreen> createState() => _ProfileDetailScreenState();
}

class _ProfileDetailScreenState extends State<ProfileDetailScreen> {
  Stream<List<DayEntry>>? _entriesStream;

  @override
  void initState() {
    super.initState();
    _entriesStream = context
        .read<DayEntriesRepository>()
        .watchForProfile(widget.profile.id);
  }

  @override
  void didUpdateWidget(ProfileDetailScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.profile.id != widget.profile.id) {
      _entriesStream = context
          .read<DayEntriesRepository>()
          .watchForProfile(widget.profile.id);
    }
  }

  Future<void> _unarchive() async {
    final controller = context.read<ProfileController>();
    await controller.unarchiveProfile(widget.profile.id);
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    context.watch<ProfileController>();
    return Scaffold(
      appBar: AppBar(
        title: Text(
            '${widget.profile.displayName}${widget.readOnly ? ' (archived)' : ''}'),
        actions: [
          if (widget.readOnly)
            TextButton(
              onPressed: _unarchive,
              child: const Text('Unarchive'),
            )
          else
            IconButton(
              tooltip: 'Switch profile',
              icon: const Icon(Icons.swap_horiz),
              onPressed: context.read<ProfileController>().openPicker,
            ),
        ],
      ),
      body: StreamBuilder<List<DayEntry>>(
        stream: _entriesStream,
        builder: (context, snapshot) {
          final entries = snapshot.data;
          if (entries == null) {
            return const Center(child: CircularProgressIndicator());
          }
          if (entries.isEmpty) {
            return const Center(child: Text('No days logged yet.'));
          }
          return ListView.builder(
            itemCount: entries.length,
            itemBuilder: (context, index) {
              final entry = entries[index];
              return ListTile(
                title: Text(entry.localDate.iso),
                trailing: Text(_flowLabel(entry.flow)),
                subtitle: entry.note == null
                    ? null
                    : Text(
                        entry.note!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
              );
            },
          );
        },
      ),
    );
  }
}
