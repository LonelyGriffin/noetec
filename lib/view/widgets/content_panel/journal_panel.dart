// Noetec.
// Copyright (c) 2026 The Noetec Authors.
// See the AUTHORS file for the full list of contributors.
// AGPLv3 License: https://www.gnu.org/licenses/agpl-3.0.html

import 'package:flutter/material.dart';

class JournalPanel extends StatelessWidget {
  const JournalPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final today = DateTime.now();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text(
            'Journal',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        _MiniCalendar(currentDate: today),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Text(
            'Agenda',
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            children: const [
              _AgendaItem(title: 'Meeting notes', time: '10:00'),
              _AgendaItem(title: 'Project ideas', time: '14:00'),
              _AgendaItem(title: 'Daily review', time: '18:00'),
            ],
          ),
        ),
      ],
    );
  }
}

class _MiniCalendar extends StatelessWidget {
  const _MiniCalendar({required this.currentDate});

  final DateTime currentDate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final year = currentDate.year;
    final month = currentDate.month;
    final firstDay = DateTime(year, month, 1);
    final daysInMonth = DateTime(year, month + 1, 0).day;
    final startWeekday = firstDay.weekday % 7;

    final monthName = _monthNames[month - 1];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Column(
        children: [
          Text(
            '$monthName $year',
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              for (final day in ['Mo', 'Tu', 'We', 'Th', 'Fr', 'Sa', 'Su'])
                Expanded(
                  child: Center(
                    child: Text(
                      day,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          ...List.generate(((startWeekday + daysInMonth) / 7).ceil(), (week) {
            return Row(
              children: [
                for (var col = 0; col < 7; col++)
                  Expanded(
                    child: Builder(
                      builder: (context) {
                        final dayNum = week * 7 + col - startWeekday + 1;
                        if (dayNum < 1 || dayNum > daysInMonth) {
                          return const SizedBox(height: 32);
                        }
                        final isToday = dayNum == currentDate.day;
                        return Container(
                          height: 32,
                          alignment: Alignment.center,
                          decoration: isToday
                              ? BoxDecoration(
                                  color: theme.colorScheme.primary,
                                  borderRadius: BorderRadius.circular(8),
                                )
                              : null,
                          child: Text(
                            '$dayNum',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: isToday
                                  ? theme.colorScheme.onPrimary
                                  : theme.colorScheme.onSurface,
                              fontWeight: isToday ? FontWeight.w600 : null,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
              ],
            );
          }),
        ],
      ),
    );
  }
}

const _monthNames = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

class _AgendaItem extends StatelessWidget {
  const _AgendaItem({required this.title, required this.time});

  final String title;
  final String time;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListTile(
      dense: true,
      leading: Text(
        time,
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.primary,
          fontWeight: FontWeight.w600,
        ),
      ),
      title: Text(title, style: theme.textTheme.bodyMedium),
    );
  }
}
