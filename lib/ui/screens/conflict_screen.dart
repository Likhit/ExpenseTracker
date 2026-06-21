import 'package:flutter/material.dart';

/// Shown when the startup sync surfaced one or more [EntityConflict]s.
/// Phase 2.1 only ships the gate — the actual side-by-side resolution UI
/// (per the UX Spec in CLAUDE.md) lands in a later phase.
class ConflictScreen extends StatelessWidget {
  final int conflictCount;

  const ConflictScreen({required this.conflictCount, super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Sync conflict')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.merge_type,
                  size: 56, color: theme.colorScheme.error),
              const SizedBox(height: 16),
              Text(
                '$conflictCount '
                '${conflictCount == 1 ? 'entity was' : 'entities were'} '
                'edited on another device',
                style: theme.textTheme.titleMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'Resolve before continuing. Writes are paused until conflicts '
                'are resolved.',
                style: theme.textTheme.bodyMedium,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
