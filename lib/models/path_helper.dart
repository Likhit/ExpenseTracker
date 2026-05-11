/// Mixin for models with hierarchical `::` separated paths.
mixin PathHelper {
  /// The full `::` separated path (e.g., "Food::Snacks::Cake").
  String get path;

  /// Returns the segments of the path (e.g., "Food::Snacks::Cake" -> ["Food", "Snacks", "Cake"]).
  List<String> get pathSegments => path.split('::');

  /// Returns the top-level group/root name (e.g., "Chase::Checking" -> "Chase").
  String get group => pathSegments.first;

  /// Alias for [group] — the root segment of the path.
  String get root => group;

  /// Returns the leaf name (e.g., "Chase::Checking" -> "Checking").
  String get displayName => pathSegments.last;

  /// Returns the depth of the path (e.g., "Food" -> 1, "Food::Snacks" -> 2).
  int get depth => pathSegments.length;
}
