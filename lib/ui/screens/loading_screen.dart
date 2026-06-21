import 'package:flutter/material.dart';

/// Splash shown while the async `ledgerProvider` is opening the JSONL files
/// and running the startup sync.
class LoadingScreen extends StatelessWidget {
  const LoadingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: CircularProgressIndicator()),
    );
  }
}
