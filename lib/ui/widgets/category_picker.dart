import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/category.dart';
import '../../models/transaction.dart';
import '../../providers/storage_providers.dart';

/// A widget that shows root categories as chips and allows fuzzy search
/// for deeper paths. Typing a new `::` path creates the category on the fly.
class CategoryPicker extends ConsumerStatefulWidget {
  final TransactionType parentType;
  final String? initialPath;
  final ValueChanged<String> onSelected;

  const CategoryPicker({
    super.key,
    required this.parentType,
    this.initialPath,
    required this.onSelected,
  });

  @override
  ConsumerState<CategoryPicker> createState() => _CategoryPickerState();
}

class _CategoryPickerState extends ConsumerState<CategoryPicker> {
  late final TextEditingController _controller;
  String? _selectedPath;
  bool _isSearching = false;

  @override
  void initState() {
    super.initState();
    _selectedPath = widget.initialPath;
    _controller = TextEditingController(text: widget.initialPath ?? '');
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final categoriesAsync = ref.watch(categoriesProvider);

    return categoriesAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (e, _) => Text('Error: $e'),
      data: (allCategories) {
        final categories = allCategories
            .where((c) => c.parentType == widget.parentType)
            .toList();
        final roots =
            categories.where((c) => c.depth == 1).toList()..sort((a, b) => a.path.compareTo(b.path));

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Search field
            TextField(
              controller: _controller,
              decoration: InputDecoration(
                labelText: 'Category',
                hintText: 'Type to search or create (e.g., Food::Takeout)',
                suffixIcon: _controller.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _controller.clear();
                          setState(() {
                            _selectedPath = null;
                            _isSearching = false;
                          });
                        },
                      )
                    : null,
              ),
              onChanged: (value) {
                setState(() => _isSearching = value.isNotEmpty);
              },
              onSubmitted: (value) {
                if (value.trim().isNotEmpty) {
                  _select(value.trim());
                }
              },
            ),
            const SizedBox(height: 8),

            if (_isSearching && _controller.text.isNotEmpty)
              // Filtered results
              _buildSearchResults(categories)
            else
              // Root category chips
              _buildRootChips(roots),
          ],
        );
      },
    );
  }

  Widget _buildRootChips(List<Category> roots) {
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      children: roots.map((c) {
        final isSelected = _selectedPath == c.path;
        return FilterChip(
          selected: isSelected,
          label: Text(c.displayName),
          onSelected: (_) => _select(c.path),
        );
      }).toList(),
    );
  }

  Widget _buildSearchResults(List<Category> categories) {
    final query = _controller.text.toLowerCase();
    final matches = categories
        .where((c) => c.path.toLowerCase().contains(query))
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));

    final showCreate =
        !matches.any((c) => c.path.toLowerCase() == query);

    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 200),
      child: ListView(
        shrinkWrap: true,
        children: [
          ...matches.map((c) => ListTile(
                title: Text(c.path),
                dense: true,
                selected: _selectedPath == c.path,
                onTap: () => _select(c.path),
              )),
          if (showCreate && _controller.text.trim().isNotEmpty)
            ListTile(
              leading: const Icon(Icons.add),
              title: Text('Create "${_controller.text.trim()}"'),
              dense: true,
              onTap: () => _select(_controller.text.trim()),
            ),
        ],
      ),
    );
  }

  void _select(String path) {
    setState(() {
      _selectedPath = path;
      _controller.text = path;
      _isSearching = false;
    });
    widget.onSelected(path);
  }
}
