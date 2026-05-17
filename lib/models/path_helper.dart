import 'ids.dart';

/// Mixin for models with hierarchical `::` separated paths.
///
/// Implementations supply [pathString], the raw `::` separated path. The
/// mixin exposes segment/root/leaf/depth/matching helpers derived from it.
mixin PathHelper {
  /// Raw `::` separated path string (e.g., "Food::Snacks::Cake").
  String get pathString;

  /// Returns the segments of the path (e.g., "Food::Snacks::Cake" -> ["Food", "Snacks", "Cake"]).
  List<String> get pathSegments => pathString.split('::');

  /// Returns the root segment of the path (e.g., "Chase::Checking" -> "Chase").
  String get root => pathSegments.first;

  /// Returns the leaf name (e.g., "Chase::Checking" -> "Checking").
  String get displayName => pathSegments.last;

  /// Returns the depth of the path (e.g., "Food" -> 1, "Food::Snacks" -> 2).
  int get depth => pathSegments.length;

  /// True if this path equals or descends from [ancestor]. Segment-aware:
  /// `Food::Snacks` matches `Food` but `Foodie` does not.
  bool matches(String ancestor) => _matches(pathString, ancestor);

  /// Returns this path truncated to at most [depth] segments. If the
  /// path is already shallower, returns it unchanged.
  String truncated(int depth) => _truncated(pathString, depth);
}

bool _matches(String path, String ancestor) {
  if (path == ancestor) return true;
  return path.startsWith('$ancestor::');
}

String _truncated(String path, int depth) {
  final segments = path.split('::');
  if (segments.length <= depth) return path;
  return segments.take(depth).join('::');
}

/// Path operations on [CategoryPath]. Mirrors [PathHelper] but returns
/// strongly-typed [CategoryPath] values where appropriate.
extension CategoryPathOps on CategoryPath {
  bool matches(CategoryPath ancestor) => _matches(value, ancestor.value);

  CategoryPath truncated(int depth) => CategoryPath(_truncated(value, depth));
}
