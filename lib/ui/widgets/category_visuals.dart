import 'package:flutter/material.dart';

/// Curated palette of icons available for category roots. Stored on the
/// [Category.icon] field as the map key (a stable string); the UI resolves
/// it through [categoryIconFor]. Children inherit their root's icon, so
/// callers should look up the root before formatting.
const Map<String, IconData> categoryIcons = {
  'food': Icons.restaurant_outlined,
  'shopping': Icons.shopping_cart_outlined,
  'transport': Icons.directions_car_outlined,
  'home': Icons.home_outlined,
  'bills': Icons.receipt_long_outlined,
  'salary': Icons.work_outline,
  'gift': Icons.card_giftcard_outlined,
  'health': Icons.medical_services_outlined,
  'education': Icons.school_outlined,
  'entertainment': Icons.sports_esports_outlined,
  'travel': Icons.flight_outlined,
  'savings': Icons.savings_outlined,
  'misc': Icons.category_outlined,
};

/// Icon to render for [iconName], or a neutral fallback when unknown.
IconData categoryIconFor(String? iconName) =>
    categoryIcons[iconName] ?? Icons.label_outline;

/// Curated palette of root colors, stored on [Category.color] as a hex
/// string (`#RRGGBB`). Children inherit their root's color.
const Map<String, int> categoryColorHex = {
  'red': 0xFFE57373,
  'pink': 0xFFF06292,
  'purple': 0xFFBA68C8,
  'indigo': 0xFF7986CB,
  'blue': 0xFF64B5F6,
  'teal': 0xFF4DB6AC,
  'green': 0xFF81C784,
  'lime': 0xFFDCE775,
  'orange': 0xFFFFB74D,
  'brown': 0xFFA1887F,
  'grey': 0xFF90A4AE,
};

/// Parses [hex] (with or without leading `#`) into a [Color]. Returns null on
/// an unparseable value so the UI can fall back to a neutral default.
Color? parseCategoryColor(String? hex) {
  if (hex == null) return null;
  final cleaned = hex.startsWith('#') ? hex.substring(1) : hex;
  final value = int.tryParse(cleaned, radix: 16);
  if (value == null) return null;
  // Six-digit hex omits alpha; force it to opaque.
  return Color(cleaned.length == 6 ? value | 0xFF000000 : value);
}

/// Encodes a [color] to `#RRGGBB` for persistence.
String encodeCategoryColor(Color color) {
  final r = (color.r * 255).round();
  final g = (color.g * 255).round();
  final b = (color.b * 255).round();
  return '#${[r, g, b].map((n) => n.toRadixString(16).padLeft(2, '0')).join().toUpperCase()}';
}
