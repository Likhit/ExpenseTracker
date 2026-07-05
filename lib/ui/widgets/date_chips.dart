import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Today / Yesterday / Pick… chip row for choosing a transaction date.
/// Pressing "Pick…" opens a date picker. Always displays the currently
/// selected date below the chips so the user can confirm.
class DateChips extends StatelessWidget {
  final DateTime value;
  final ValueChanged<DateTime> onChanged;

  const DateChips({
    required this.value,
    required this.onChanged,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final selectedDay = DateTime(value.year, value.month, value.day);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Date', style: theme.textTheme.labelLarge),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          children: [
            ChoiceChip(
              label: const Text('Today'),
              selected: selectedDay == today,
              onSelected: (_) => onChanged(today),
            ),
            ChoiceChip(
              label: const Text('Yesterday'),
              selected: selectedDay == yesterday,
              onSelected: (_) => onChanged(yesterday),
            ),
            ActionChip(
              label: const Text('Pick…'),
              avatar: const Icon(Icons.event, size: 18),
              onPressed: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: value,
                  firstDate: DateTime(2000),
                  lastDate: DateTime(now.year + 10),
                );
                if (picked != null) onChanged(picked);
              },
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          DateFormat.yMMMMd().format(value),
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}
