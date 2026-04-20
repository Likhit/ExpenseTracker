import 'package:flutter/material.dart';
import 'currency_list_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          ListTile(
            leading: const Icon(Icons.currency_exchange),
            title: const Text('Currencies'),
            subtitle: const Text('Manage fiat, stock, and crypto currencies'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const CurrencyListScreen()),
            ),
          ),
        ],
      ),
    );
  }
}
