import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/category.dart';
import '../../models/transaction.dart';
import '../../providers/ledger_provider.dart';
import '../widgets/category_edit_dialog.dart';
import '../widgets/category_visuals.dart';

/// Categories list, tabbed by [TransactionType] (Expense / Income). Each tab
/// renders the matching categories as a tree rooted at the depth-1 paths; the
/// root carries the icon/color (set here) which children inherit.
class CategoriesScreen extends ConsumerStatefulWidget {
  const CategoriesScreen({super.key});

  @override
  ConsumerState<CategoriesScreen> createState() => _CategoriesScreenState();
}

class _CategoriesScreenState extends ConsumerState<CategoriesScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  bool _showDeleted = false;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final categoriesAsync = ref.watch(categoriesProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Categories'),
        actions: [
          IconButton(
            icon: Icon(_showDeleted
                ? Icons.visibility_off_outlined
                : Icons.visibility_outlined),
            tooltip: _showDeleted ? 'Hide deleted' : 'Show deleted',
            onPressed: () => setState(() => _showDeleted = !_showDeleted),
          ),
        ],
        bottom: TabBar(
          controller: _tabs,
          tabs: const [
            Tab(text: 'Expense'),
            Tab(text: 'Income'),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openNewRoot(context),
        icon: const Icon(Icons.add),
        label: const Text('New category'),
      ),
      body: categoriesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Failed to load categories: $e')),
        data: (all) => TabBarView(
          controller: _tabs,
          children: [
            _CategoryTree(
                categories: _filter(all, TransactionType.expense),
                parentType: TransactionType.expense,
                showDeleted: _showDeleted),
            _CategoryTree(
                categories: _filter(all, TransactionType.income),
                parentType: TransactionType.income,
                showDeleted: _showDeleted),
          ],
        ),
      ),
    );
  }

  List<Category> _filter(List<Category> all, TransactionType type) {
    return [for (final c in all) if (c.parentType == type) c];
  }

  void _openNewRoot(BuildContext context) {
    final type = _tabs.index == 0
        ? TransactionType.expense
        : TransactionType.income;
    CategoryEditDialog.show(context, parentType: type);
  }
}

class _CategoryTree extends ConsumerWidget {
  final List<Category> categories;
  final TransactionType parentType;
  final bool showDeleted;

  const _CategoryTree({
    required this.categories,
    required this.parentType,
    required this.showDeleted,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final visible = [
      for (final c in categories)
        if (showDeleted || !c.deleted) c,
    ];
    if (visible.isEmpty) {
      return const _EmptyCategories();
    }

    // Index by full path for parent → child traversal. Build a map of
    // root path → all descendants under it (any depth).
    final byPath = {for (final c in visible) c.path.value: c};
    final roots = [
      for (final c in visible)
        if (c.depth == 1) c,
    ]..sort((a, b) => a.path.value.compareTo(b.path.value));

    final descendants = <String, List<Category>>{};
    for (final c in visible) {
      if (c.depth == 1) continue;
      final rootPath = c.pathSegments.first;
      descendants.putIfAbsent(rootPath, () => []).add(c);
    }
    for (final list in descendants.values) {
      list.sort((a, b) => a.path.value.compareTo(b.path.value));
    }
    // Orphans (descendants whose root was deleted-and-hidden) get their own
    // section so they're still editable.
    final orphans = <Category>[];
    for (final entry in descendants.entries) {
      if (!byPath.containsKey(entry.key)) {
        orphans.addAll(entry.value);
      }
    }

    return ListView(
      padding: const EdgeInsets.only(bottom: 80),
      children: [
        for (final root in roots)
          _RootNode(
            root: root,
            children: descendants[root.path.value] ?? const [],
          ),
        if (orphans.isNotEmpty) ...[
          const _SectionLabel(label: 'Without a root'),
          for (final c in orphans) _LeafTile(category: c, root: null),
        ],
      ],
    );
  }
}

class _RootNode extends ConsumerWidget {
  final Category root;
  final List<Category> children;

  const _RootNode({required this.root, required this.children});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final tint = parseCategoryColor(root.color) ?? theme.colorScheme.secondary;
    final titleStyle = root.deleted
        ? theme.textTheme.titleMedium?.copyWith(
            decoration: TextDecoration.lineThrough,
            color: theme.colorScheme.onSurfaceVariant,
          )
        : theme.textTheme.titleMedium;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        leading: CircleAvatar(
          backgroundColor: tint.withValues(alpha: 0.2),
          foregroundColor: tint,
          child: Icon(categoryIconFor(root.icon)),
        ),
        title: Text(root.displayName, style: titleStyle),
        subtitle: children.isEmpty
            ? null
            : Text('${children.length} '
                '${children.length == 1 ? 'subcategory' : 'subcategories'}'),
        trailing: _CategoryActions(category: root, root: root),
        childrenPadding: const EdgeInsets.only(left: 16, bottom: 8),
        children: [
          for (final c in children) _LeafTile(category: c, root: root),
          if (!root.deleted)
            ListTile(
              leading: const Icon(Icons.add),
              title: Text('Add under "${root.displayName}"'),
              onTap: () => CategoryEditDialog.show(
                context,
                parentType: root.parentType,
                parentPath: root.path.value,
              ),
            ),
        ],
      ),
    );
  }
}

class _LeafTile extends ConsumerWidget {
  final Category category;
  final Category? root;

  const _LeafTile({required this.category, required this.root});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final tint = parseCategoryColor(root?.color) ?? theme.colorScheme.secondary;
    final titleStyle = category.deleted
        ? theme.textTheme.bodyLarge?.copyWith(
            decoration: TextDecoration.lineThrough,
            color: theme.colorScheme.onSurfaceVariant,
          )
        : theme.textTheme.bodyLarge;
    final pathBelowRoot = category.pathSegments.skip(1).join('::');
    return ListTile(
      leading: Icon(categoryIconFor(root?.icon), color: tint),
      title: Text(category.displayName, style: titleStyle),
      subtitle: pathBelowRoot.isEmpty || pathBelowRoot == category.displayName
          ? null
          : Text(category.path.value),
      trailing: _CategoryActions(category: category, root: root),
      onTap: category.deleted
          ? null
          : () => CategoryEditDialog.show(context,
              existing: category, parentType: category.parentType),
    );
  }
}

class _CategoryActions extends ConsumerWidget {
  final Category category;
  final Category? root;

  const _CategoryActions({required this.category, required this.root});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final deleted = category.deleted;
    return PopupMenuButton<_CategoryAction>(
      onSelected: (action) => _handle(context, ref, action),
      itemBuilder: (_) => [
        if (!deleted)
          const PopupMenuItem(
            value: _CategoryAction.edit,
            child: ListTile(
              leading: Icon(Icons.edit_outlined),
              title: Text('Edit'),
            ),
          ),
        if (!deleted)
          const PopupMenuItem(
            value: _CategoryAction.delete,
            child: ListTile(
              leading: Icon(Icons.delete_outline),
              title: Text('Delete'),
            ),
          ),
        if (deleted)
          const PopupMenuItem(
            value: _CategoryAction.restore,
            child: ListTile(
              leading: Icon(Icons.restore),
              title: Text('Restore'),
            ),
          ),
      ],
    );
  }

  Future<void> _handle(
      BuildContext context, WidgetRef ref, _CategoryAction action) async {
    switch (action) {
      case _CategoryAction.edit:
        await CategoryEditDialog.show(context,
            existing: category, parentType: category.parentType);
      case _CategoryAction.delete:
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Delete category?'),
            content: Text(
                'Soft-delete "${category.path.value}". Existing transactions '
                'keep their category string; you can restore from "Show deleted".'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancel')),
              FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Delete')),
            ],
          ),
        );
        if (confirmed != true) return;
        final ledger = await ref.read(ledgerProvider.future);
        await ledger.delete(category);
      case _CategoryAction.restore:
        final ledger = await ref.read(ledgerProvider.future);
        await ledger.save(
            category.copyWith(deleted: false, updatedAt: DateTime.now()));
    }
  }
}

class _SectionLabel extends StatelessWidget {
  final String label;

  const _SectionLabel({required this.label});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        label,
        style: theme.textTheme.labelLarge?.copyWith(
          color: theme.colorScheme.primary,
        ),
      ),
    );
  }
}

class _EmptyCategories extends StatelessWidget {
  const _EmptyCategories();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.category_outlined, size: 56),
            const SizedBox(height: 16),
            Text('No categories yet', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              'Tap "New category" to create your first one. Categories are also '
              'created on the fly when you enter a transaction.',
              style: theme.textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

enum _CategoryAction { edit, delete, restore }
