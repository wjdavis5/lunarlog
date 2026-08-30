/// Profile detail (U5): a month calendar of logged days scoped to exactly
/// one profile (R3). Archived profiles open in read-only mode (view-only day
/// sheets, no logging affordances) with an unarchive action.
library;

import 'package:flutter/material.dart';
import 'package:lunarlog/domain/models/local_date.dart';
import 'package:lunarlog/domain/models/profile.dart';
import 'package:lunarlog/ui/logging/month_calendar.dart';
import 'package:lunarlog/ui/profiles/profile_controller.dart';
import 'package:provider/provider.dart';

class ProfileDetailScreen extends StatefulWidget {
  const ProfileDetailScreen({
    super.key,
    required this.profile,
    this.readOnly = false,
    this.todayProvider = LocalDate.today,
  });

  final Profile profile;
  final bool readOnly;

  /// "Today" as the device-local civil date; injectable for tests.
  final LocalDate Function() todayProvider;

  @override
  State<ProfileDetailScreen> createState() => _ProfileDetailScreenState();
}

class _ProfileDetailScreenState extends State<ProfileDetailScreen> {
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
      body: MonthCalendar(
        profileId: widget.profile.id,
        readOnly: widget.readOnly,
        todayProvider: widget.todayProvider,
      ),
    );
  }
}
