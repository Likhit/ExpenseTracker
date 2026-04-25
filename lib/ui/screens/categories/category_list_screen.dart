import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import 'package:collection/collection.dart';

import '../../../models/category.dart';
import '../../../models/transaction.dart';
import '../../../providers/storage_providers.dart';

class CategoryListScreen extends ConsumerWidget {
  const CategoryListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categoriesAsync = ref.watch(categoriesProvider);

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Categories'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Expense'),
              Tab(text: 'Income'),
            ],
          ),
        ),
        floatingActionButton: FloatingActionButton(
          onPressed: () => _showCategoryDialog(context, ref),
          child: const Icon(Icons.add),
        ),
        body: categoriesAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('Error: $e')),
          data: (categories) {
            final expense = categories
                .where((c) => c.parentType == TransactionType.expense)
                .toList();
            final income = categories
                .where((c) => c.parentType == TransactionType.income)
                .toList();

            return TabBarView(
              children: [
                _CategoryTabView(categories: expense),
                _CategoryTabView(categories: income),
              ],
            );
          },
        ),
      ),
    );
  }

  void _showCategoryDialog(BuildContext context, WidgetRef ref,
      [Category? existing]) {
    showDialog(
      context: context,
      builder: (_) => _CategoryDialog(existing: existing, ref: ref),
    );
  }
}

class _CategoryTabView extends ConsumerWidget {
  final List<Category> categories;
  const _CategoryTabView({required this.categories});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (categories.isEmpty) {
      return const Center(child: Text('No categories yet.'));
    }

    // Group by root category
    final grouped = groupBy(categories, (Category c) => c.root);
    final roots = grouped.keys.toList()..sort();

    return ListView.builder(
      itemCount: roots.length,
      itemBuilder: (context, index) {
        final root = roots[index];
        final children = grouped[root]!..sort((a, b) => a.path.compareTo(b.path));
        final rootCategory =
            children.firstWhereOrNull((c) => c.depth == 1);

        return ExpansionTile(
          leading: rootCategory?.icon != null
              ? Icon(_resolveIcon(rootCategory!.icon!))
              : const Icon(Icons.category),
          title: Text(root),
          subtitle:
              Text('${children.length} ${children.length == 1 ? 'category' : 'categories'}'),
          children: children.map((c) {
            final indent = (c.depth - 1) * 16.0;
            return ListTile(
              contentPadding: EdgeInsets.only(left: 16.0 + indent, right: 16.0),
              title: Text(c.displayName),
              subtitle: c.depth > 1 ? Text(c.path) : null,
              trailing: PopupMenuButton<String>(
                onSelected: (action) {
                  if (action == 'edit') {
                    showDialog(
                      context: context,
                      builder: (_) =>
                          _CategoryDialog(existing: c, ref: ref),
                    );
                  } else if (action == 'delete') {
                    ref.read(categoriesProvider.notifier).remove(c);
                  }
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(value: 'edit', child: Text('Edit')),
                  const PopupMenuItem(value: 'delete', child: Text('Delete')),
                ],
              ),
            );
          }).toList(),
        );
      },
    );
  }

  IconData _resolveIcon(String iconName) {
    const iconMap = <String, IconData>{
      'restaurant': Icons.restaurant,
      'directions_car': Icons.directions_car,
      'home': Icons.home,
      'local_hospital': Icons.local_hospital,
      'school': Icons.school,
      'movie': Icons.movie,
      'shopping_bag': Icons.shopping_bag,
      'bolt': Icons.bolt,
      'work': Icons.work,
      'card_giftcard': Icons.card_giftcard,
      'trending_up': Icons.trending_up,
      'account_balance': Icons.account_balance,
      'category': Icons.category,
    };
    return iconMap[iconName] ?? Icons.category;
  }
}

class _CategoryDialog extends StatefulWidget {
  final Category? existing;
  final WidgetRef ref;

  const _CategoryDialog({this.existing, required this.ref});

  @override
  State<_CategoryDialog> createState() => _CategoryDialogState();
}

class _CategoryDialogState extends State<_CategoryDialog> {
  late final TextEditingController _pathController;
  late TransactionType _parentType;

  @override
  void initState() {
    super.initState();
    _pathController =
        TextEditingController(text: widget.existing?.path ?? '');
    _parentType =
        widget.existing?.parentType ?? TransactionType.expense;
  }

  @override
  void dispose() {
    _pathController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.existing != null;

    return AlertDialog(
      title: Text(isEditing ? 'Edit Category' : 'New Category'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _pathController,
              decoration: const InputDecoration(
                labelText: 'Path',
                hintText: 'e.g., Food::Snacks::Cake',
              ),
              autofocus: true,
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<TransactionType>(
              initialValue: _parentType,
              decoration: const InputDecoration(labelText: 'Type'),
              items: TransactionType.values
                  .map((t) => DropdownMenuItem(
                        value: t,
                        child: Text(
                            t.name[0].toUpperCase() + t.name.substring(1)),
                      ))
                  .toList(),
              onChanged: isEditing
                  ? null
                  : (v) => setState(() => _parentType = v!),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _save,
          child: Text(isEditing ? 'Save' : 'Add'),
        ),
      ],
    );
  }

  void _save() {
    final path = _pathController.text.trim();
    if (path.isEmpty) return;

    final notifier = widget.ref.read(categoriesProvider.notifier);

    if (widget.existing != null) {
      notifier.edit(widget.existing!.copyWith(path: path));
    } else {
      notifier.add(Category(
        id: const Uuid().v4(),
        path: path,
        parentType: _parentType,
        createdAt: DateTime.now(),
      ));
    }
    Navigator.pop(context);
  }
}
