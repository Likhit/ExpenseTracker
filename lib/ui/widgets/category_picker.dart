import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../models/category.dart';
import '../../models/ids.dart';
import '../../models/transaction.dart';
import '../../providers/ledger_provider.dart';
import 'category_visuals.dart';

const _uuid = Uuid();

/// Bottom sheet for picking a category, scoped to one [TransactionType]. Roots
/// render as an icon grid; typing in the search box filters all paths by
/// substring. Inline "Create" creates a new `::` path on the fly (matching the
/// UX-spec category flow), saves it via [LedgerService], and returns it.
///
/// Returns the chosen [Category] via [Navigator.pop], or null if dismissed.
Future<Category?> pickCategory(BuildContext context, {
  required TransactionType parentType,
}) {
  return showModalBottomSheet<Category>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => Padding(
      padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom),
      child: _CategoryPickerSheet(parentType: parentType),
    ),
  );
}

class _CategoryPickerSheet extends ConsumerStatefulWidget {
  final TransactionType parentType;

  const _CategoryPickerSheet({required this.parentType});

  @override
  ConsumerState<_CategoryPickerSheet> createState() =>
      _CategoryPickerSheetState();
}

class _CategoryPickerSheetState extends ConsumerState<_CategoryPickerSheet> {
  final _searchCtl = TextEditingController();
  String _query = '';
  // Segments drilled into so far ([] at the root level). The browser shows the
  // categories one level below this prefix.
  List<String> _stack = const [];

  @override
  void dispose() {
    _searchCtl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final all = ref.watch(categoriesProvider).value ?? const [];
    final pool = [
      for (final c in all)
        if (!c.deleted && c.parentType == widget.parentType) c,
    ];
    final query = _query.trim().toLowerCase();
    final matching = query.isEmpty
        ? const <Category>[]
        : [
            for (final c in pool)
              if (c.path.value.toLowerCase().contains(query)) c,
          ];
    final roots = [
      for (final c in pool)
        if (c.depth == 1) c,
    ]..sort((a, b) => a.path.value.compareTo(b.path.value));

    // Quick lookup root → metadata for icons/colors used in the matching list.
    final rootByName = <String, Category>{
      for (final c in roots) c.path.value: c,
    };

    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.7,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: TextField(
              controller: _searchCtl,
              autofocus: true,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: 'Search or type new path (Food::Snacks)',
                suffixIcon: query.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () {
                          _searchCtl.clear();
                          setState(() => _query = '');
                        },
                      ),
                border: const OutlineInputBorder(),
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
          Expanded(
            child: query.isEmpty
                ? _HierarchyBrowser(
                    pool: pool,
                    rootByName: rootByName,
                    stack: _stack,
                    onDrill: (seg) =>
                        setState(() => _stack = [..._stack, seg]),
                    onUp: () => setState(
                        () => _stack = _stack.sublist(0, _stack.length - 1)),
                    onPick: (c) => Navigator.of(context).pop(c),
                    theme: theme,
                  )
                : _MatchList(
                    matches: matching,
                    rootByName: rootByName,
                    onPick: (c) => Navigator.of(context).pop(c),
                    canCreate: _canCreate(query, pool),
                    onCreate: _createInline,
                    typedPath: _normalizeTyped(_searchCtl.text),
                    theme: theme,
                  ),
          ),
        ],
      ),
    );
  }

  /// "Create new" is offered when the typed text looks like a category path
  /// (no leading/trailing `::`, no empty segments) and isn't already an
  /// active category.
  bool _canCreate(String query, List<Category> pool) {
    final typed = _normalizeTyped(_searchCtl.text);
    if (typed.isEmpty) return false;
    if (typed.startsWith('::') || typed.endsWith('::')) return false;
    if (typed.split('::').any((s) => s.isEmpty)) return false;
    return !pool.any((c) => c.path.value == typed);
  }

  String _normalizeTyped(String raw) => raw.trim();

  Future<void> _createInline() async {
    final typed = _normalizeTyped(_searchCtl.text);
    final ledger = await ref.read(ledgerProvider.future);
    // Inherit icon/color from the root if it already exists; otherwise none.
    final rootName = typed.split('::').first;
    final existingRoot = (ref.read(categoriesProvider).value ?? const [])
        .where((c) =>
            !c.deleted &&
            c.parentType == widget.parentType &&
            c.path.value == rootName)
        .cast<Category?>()
        .firstWhere((_) => true, orElse: () => null);
    final fresh = Category(
      id: CategoryId(_uuid.v4()),
      path: CategoryPath(typed),
      parentType: widget.parentType,
      icon: existingRoot?.icon,
      color: existingRoot?.color,
      createdAt: DateTime.now(),
    );
    final result = await ledger.save(fresh);
    if (!result.isValid || !mounted) return;
    Navigator.of(context).pop(fresh);
  }
}

/// Drill-down browser over the category hierarchy. At the root level it lists
/// the root categories; tapping one that has descendants drills into its next
/// level, and so on until a leaf. A row with descendants exposes a chevron to
/// drill in and (when it is itself a real category) taps through to select it;
/// a leaf row selects directly. A back row and a `Use <path>` row at the top
/// let the user step up and pick a non-leaf category.
class _HierarchyBrowser extends StatelessWidget {
  final List<Category> pool;
  final Map<String, Category> rootByName;
  final List<String> stack;
  final ValueChanged<String> onDrill;
  final VoidCallback onUp;
  final ValueChanged<Category> onPick;
  final ThemeData theme;

  const _HierarchyBrowser({
    required this.pool,
    required this.rootByName,
    required this.stack,
    required this.onDrill,
    required this.onUp,
    required this.onPick,
    required this.theme,
  });

  static bool _startsWith(List<String> full, List<String> prefix) {
    if (full.length < prefix.length) return false;
    for (var i = 0; i < prefix.length; i++) {
      if (full[i] != prefix[i]) return false;
    }
    return true;
  }

  Category? _entityAt(String path) => pool
      .where((c) => c.path.value == path)
      .cast<Category?>()
      .firstWhere((_) => true, orElse: () => null);

  @override
  Widget build(BuildContext context) {
    if (pool.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'No categories yet. Type a name above to create one.',
            style: theme.textTheme.bodyMedium,
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    // The distinct next segments one level below the current prefix, sorted.
    final segments = <String>{};
    for (final c in pool) {
      final parts = c.pathSegments;
      if (parts.length > stack.length && _startsWith(parts, stack)) {
        segments.add(parts[stack.length]);
      }
    }
    final ordered = segments.toList()..sort();
    final prefixPath = stack.join('::');
    final currentEntity = stack.isEmpty ? null : _entityAt(prefixPath);

    return ListView(
      children: [
        if (stack.isNotEmpty) ...[
          ListTile(
            leading: const Icon(Icons.arrow_back),
            title: Text(prefixPath,
                style: theme.textTheme.titleSmall
                    ?.copyWith(color: theme.colorScheme.primary)),
            onTap: onUp,
          ),
          if (currentEntity != null)
            ListTile(
              leading: const Icon(Icons.check_circle_outline),
              title: Text('Use "$prefixPath"'),
              onTap: () => onPick(currentEntity),
            ),
          const Divider(height: 1),
        ],
        for (final seg in ordered)
          _segmentRow(seg),
      ],
    );
  }

  Widget _segmentRow(String seg) {
    final fullParts = [...stack, seg];
    final fullPath = fullParts.join('::');
    final entity = _entityAt(fullPath);
    final hasChildren =
        pool.any((c) => _startsWith(c.pathSegments, fullParts) &&
            c.pathSegments.length > fullParts.length);
    final rootName = fullParts.first;
    final root = rootByName[rootName];
    final tint =
        parseCategoryColor(root?.color) ?? theme.colorScheme.secondary;

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: tint.withValues(alpha: 0.2),
        foregroundColor: tint,
        child: Icon(categoryIconFor(root?.icon)),
      ),
      title: Text(seg),
      // A branch drills in; a leaf selects. Non-leaf real categories are still
      // selectable via the "Use ..." row after drilling in.
      trailing: hasChildren ? const Icon(Icons.chevron_right) : null,
      onTap: () {
        if (hasChildren) {
          onDrill(seg);
        } else if (entity != null) {
          onPick(entity);
        }
      },
    );
  }
}

class _MatchList extends StatelessWidget {
  final List<Category> matches;
  final Map<String, Category> rootByName;
  final ValueChanged<Category> onPick;
  final bool canCreate;
  final Future<void> Function() onCreate;
  final String typedPath;
  final ThemeData theme;

  const _MatchList({
    required this.matches,
    required this.rootByName,
    required this.onPick,
    required this.canCreate,
    required this.onCreate,
    required this.typedPath,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        for (final c in matches)
          ListTile(
            leading: Icon(
              categoryIconFor(rootByName[c.pathSegments.first]?.icon),
              color: parseCategoryColor(
                      rootByName[c.pathSegments.first]?.color) ??
                  theme.colorScheme.secondary,
            ),
            title: Text(c.path.value),
            onTap: () => onPick(c),
          ),
        if (canCreate)
          ListTile(
            leading: const Icon(Icons.add),
            title: Text('Create "$typedPath"'),
            onTap: onCreate,
          ),
      ],
    );
  }
}
