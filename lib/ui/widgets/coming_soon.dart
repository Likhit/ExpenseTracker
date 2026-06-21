import 'package:flutter/material.dart';

/// Stub used by Phase 2.1 placeholder destinations. The real screens land in
/// 2.2 onwards; this just renders the screen title so the shell's navigation
/// can be tested end-to-end.
class ComingSoon extends StatelessWidget {
  final String title;

  const ComingSoon({required this.title, super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Center(
        child: Text('Coming soon', style: theme.textTheme.titleMedium),
      ),
    );
  }
}
