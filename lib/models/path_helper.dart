/// Mixin for models with hierarchical `::` separated paths.
///
/// Implementations supply [pathString], the raw `::` separated path. The
/// mixin exposes segment/root/leaf/depth helpers derived from it.
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
}
