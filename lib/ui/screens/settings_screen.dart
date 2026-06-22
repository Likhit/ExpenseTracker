import 'package:flutter/material.dart';

import 'categories_screen.dart';

/// Settings hub. The UX spec lists more entries (sync folder, default
/// currency, theme, …) — Phase 2.7 fills them in. For now this is just the
/// jumping-off point for the per-type management screens that other phases
/// land first.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          ListTile(
            leading: const Icon(Icons.category_outlined),
            title: const Text('Categories'),
            subtitle: const Text('Edit the expense and income hierarchies'),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const CategoriesScreen()),
            ),
          ),
        ],
      ),
    );
  }
}
