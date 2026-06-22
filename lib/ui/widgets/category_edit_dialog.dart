import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../models/category.dart';
import '../../models/ids.dart';
import '../../models/transaction.dart';
import '../../providers/ledger_provider.dart';
import 'category_visuals.dart';

const _uuid = Uuid();

/// Dialog for creating a new category or editing an existing one. Roots
/// expose icon + color pickers; descendants inherit those from their root and
/// only edit name. Returns the saved [Category] via [Navigator.pop] on
/// success.
class CategoryEditDialog extends ConsumerStatefulWidget {
  /// Existing category, or null for a new one.
  final Category? existing;

  /// Type the new category will sit under. Mandatory for new categories; for
  /// edits, the existing category's type is preserved.
  final TransactionType parentType;

  /// Path of the parent root for descendants. Null for roots (top-level
  /// creation under [parentType]).
  final String? parentPath;

  const CategoryEditDialog({
    this.existing,
    required this.parentType,
    this.parentPath,
    super.key,
  });

  static Future<Category?> show(
    BuildContext context, {
    Category? existing,
    required TransactionType parentType,
    String? parentPath,
  }) {
    return showDialog<Category>(
      context: context,
      builder: (_) => CategoryEditDialog(
        existing: existing,
        parentType: parentType,
        parentPath: parentPath,
      ),
    );
  }

  @override
  ConsumerState<CategoryEditDialog> createState() =>
      _CategoryEditDialogState();
}

class _CategoryEditDialogState extends ConsumerState<CategoryEditDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  String? _iconName;
  String? _colorHex;
  String? _saveError;

  /// Roots own the icon/color; descendants inherit them.
  bool get _isRoot {
    final existing = widget.existing;
    if (existing != null) return existing.depth == 1;
    return widget.parentPath == null;
  }

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _name = TextEditingController(text: existing?.displayName ?? '');
    _iconName = existing?.icon;
    _colorHex = existing?.color;
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  String? _validateName(String? raw) {
    final value = (raw ?? '').trim();
    if (value.isEmpty) return 'Name is required';
    if (value.contains('::')) return r'Use a separate row for nested paths';
    final newPath = _buildPath(value);
    final existing = widget.existing;
    final categories = ref.read(categoriesProvider).value ?? const [];
    final clash = categories.any((c) =>
        !c.deleted &&
        c.path.value == newPath &&
        c.parentType == widget.parentType &&
        (existing == null || c.id != existing.id));
    if (clash) return 'A category with this name already exists here';
    return null;
  }

  String _buildPath(String trimmedName) {
    final parent = widget.parentPath;
    if (parent == null || parent.isEmpty) return trimmedName;
    return '$parent::$trimmedName';
  }

  Future<void> _save() async {
    setState(() => _saveError = null);
    if (!_formKey.currentState!.validate()) return;
    final trimmed = _name.text.trim();
    final newPath = _buildPath(trimmed);
    final existing = widget.existing;
    final now = DateTime.now();
    final category = existing == null
        ? Category(
            id: CategoryId(_uuid.v4()),
            path: CategoryPath(newPath),
            parentType: widget.parentType,
            icon: _isRoot ? _iconName : null,
            color: _isRoot ? _colorHex : null,
            createdAt: now,
          )
        : existing.copyWith(
            path: CategoryPath(newPath),
            icon: _isRoot ? _iconName : existing.icon,
            color: _isRoot ? _colorHex : existing.color,
            updatedAt: now,
          );
    final ledger = await ref.read(ledgerProvider.future);
    final result = await ledger.save(category);
    if (!mounted) return;
    if (!result.isValid) {
      setState(() => _saveError = result.errorMessage);
      return;
    }
    Navigator.of(context).pop(category);
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existing != null;
    final title = isEdit
        ? 'Edit category'
        : (widget.parentPath == null
            ? 'New category'
            : 'New under "${widget.parentPath}"');
    return AlertDialog(
      title: Text(title),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          autovalidateMode: AutovalidateMode.onUserInteraction,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _name,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Name'),
                validator: _validateName,
              ),
              if (_isRoot) ...[
                const SizedBox(height: 20),
                _IconPicker(
                  selected: _iconName,
                  onChanged: (name) => setState(() => _iconName = name),
                ),
                const SizedBox(height: 16),
                _ColorPicker(
                  selected: _colorHex,
                  onChanged: (hex) => setState(() => _colorHex = hex),
                ),
              ],
              if (_saveError != null) ...[
                const SizedBox(height: 12),
                Text(_saveError!,
                    style: TextStyle(
                        color: Theme.of(context).colorScheme.error)),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _save,
          child: Text(isEdit ? 'Save' : 'Create'),
        ),
      ],
    );
  }
}

class _IconPicker extends StatelessWidget {
  final String? selected;
  final ValueChanged<String?> onChanged;

  const _IconPicker({required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Icon', style: theme.textTheme.labelLarge),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final entry in categoryIcons.entries)
              ChoiceChip(
                avatar: Icon(entry.value, size: 18),
                label: Text(entry.key),
                selected: selected == entry.key,
                onSelected: (yes) => onChanged(yes ? entry.key : null),
              ),
          ],
        ),
      ],
    );
  }
}

class _ColorPicker extends StatelessWidget {
  final String? selected;
  final ValueChanged<String?> onChanged;

  const _ColorPicker({required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Color', style: theme.textTheme.labelLarge),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final entry in categoryColorHex.entries)
              _ColorDot(
                color: Color(entry.value),
                selected: selected != null &&
                    parseCategoryColor(selected) == Color(entry.value),
                onTap: () => onChanged(
                    '#${(entry.value & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}'),
                tooltip: entry.key,
              ),
          ],
        ),
      ],
    );
  }
}

class _ColorDot extends StatelessWidget {
  final Color color;
  final bool selected;
  final VoidCallback onTap;
  final String tooltip;

  const _ColorDot({
    required this.color,
    required this.selected,
    required this.onTap,
    required this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color,
            border: Border.all(
              color: selected ? scheme.primary : Colors.transparent,
              width: 3,
            ),
          ),
        ),
      ),
    );
  }
}
