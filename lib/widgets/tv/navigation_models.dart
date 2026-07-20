import 'package:flutter/widgets.dart';

/// Shared by the Xtream and M3U home screens. These classes used to be
/// duplicated verbatim in both files — two sources of truth that had already
/// started to diverge in their comments.
class NavigationItem {
  /// Filled variant, shown when this section is the active one.
  final IconData icon;

  /// Outlined variant for the inactive state. Outline-vs-fill is the state
  /// reinforcement the rail was missing — before, five items mixed filled and
  /// outlined glyphs arbitrarily, so weight carried no meaning.
  final IconData iconOutlined;
  final String label;
  final int index;

  /// When set, selecting this item runs the callback instead of switching the
  /// pager. Search is a first-class destination in the rail but it is not one
  /// of the pages, and forcing it into the PageView just to appear in the rail
  /// would be modelling the menu instead of the app.
  final void Function()? onSelected;

  const NavigationItem({
    required this.icon,
    required this.iconOutlined,
    required this.label,
    required this.index,
    this.onSelected,
  });

  IconData resolve(bool isSelected) => isSelected ? icon : iconOutlined;
}

class NavigationSizes {
  final double itemHeight;
  final double iconSize;
  final double fontSize;

  const NavigationSizes({
    required this.itemHeight,
    required this.iconSize,
    required this.fontSize,
  });
}
