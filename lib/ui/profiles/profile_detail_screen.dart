/// Profile detail (U5 + U6): the active profile's two surfaces — the
/// overview of predictions (U6) and the month calendar of logged days
/// (U5) — behind a simple in-place toggle. Both are scoped to exactly one
/// profile (R3). Archived profiles open in read-only mode (view-only day
/// sheets, no logging affordances) with an unarchive action; the overview
/// itself has no write affordances and stays viewable.
library;

import 'package:flutter/material.dart';
import 'package:lunarlog/domain/models/local_date.dart';
import 'package:lunarlog/domain/models/profile.dart';
import 'package:lunarlog/ui/logging/month_calendar.dart';
import 'package:lunarlog/ui/overview/overview_panel.dart';
import 'package:lunarlog/ui/profiles/profile_controller.dart';
import 'package:provider/provider.dart';

enum _DetailTab { overview, calendar }

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
  _DetailTab _tab = _DetailTab.calendar;

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
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: SegmentedButton<_DetailTab>(
              key: const ValueKey('detail-tab-toggle'),
              segments: const [
                ButtonSegment(
                  value: _DetailTab.overview,
                  label: Text('Overview'),
                ),
                ButtonSegment(
                  value: _DetailTab.calendar,
                  label: Text('Calendar'),
                ),
              ],
              selected: {_tab},
              onSelectionChanged: (selection) =>
                  setState(() => _tab = selection.first),
            ),
          ),
          Expanded(
            child: _tab == _DetailTab.overview
                ? OverviewPanel(
                    profileId: widget.profile.id,
                    todayProvider: widget.todayProvider,
                  )
                : MonthCalendar(
                    profileId: widget.profile.id,
                    readOnly: widget.readOnly,
                    todayProvider: widget.todayProvider,
                  ),
          ),
        ],
      ),
    );
  }
}
