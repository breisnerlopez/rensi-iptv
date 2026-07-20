import 'dart:math' as math;
import 'package:rensi_iptv/utils/responsive_helper.dart';
import 'package:flutter/material.dart';
import 'tv/focus_highlight.dart';
import 'package:rensi_iptv/utils/app_themes.dart';

/// Identifies the box that holds a settings dropdown's current value.
///
/// Exists so a test can assert the box is wide enough for the text inside it.
/// The 10-foot type promotion made that text grow while the box stayed at a
/// hand-tuned 120dp, and the result — "Españ", "Oscur" — is invisible to every
/// automatic check: clipping inside a bounded box is not a RenderFlex overflow,
/// so nothing throws. It has to be measured.
const Key dropdownTileValueBoxKey = Key('dropdown-tile-value-box');

/// Ceiling for the value field. A control does not become easier to use by
/// being 900dp wide; past this it just stops reading as a control.
///
/// Not derived from any particular string — the value that used to set the
/// floor here, "Automático (recomendado)" at ~390dp, was shortened in the same
/// change that introduced this constant, so quoting it would be justifying a
/// number by a measurement that no longer exists. What keeps the field wide
/// enough is the check in test/widgets/promoted_type_overflow_test.dart, which
/// measures every option against the room the paragraph actually gets.
const double _maxFieldWidth = 560;

/// Identifies the row's help line, so a test can assert it is promoted for the
/// 10-foot surface alongside the label rather than left at its authored size.
const Key dropdownTileDescriptionKey = Key('dropdown-tile-description');

class DropdownTileWidget<T> extends StatelessWidget {
  final IconData icon;
  final String label;
  final T value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onChanged;

  /// Optional guidance for the row. Belongs here rather than folded into an
  /// option label: advice inside a closed dropdown is shown on every glance at
  /// a setting nobody is changing, and it made the widest value wider than the
  /// control can be on a handset.
  final String? description;

  const DropdownTileWidget({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
    this.description,
  });

  @override
  Widget build(BuildContext context) =>
      // LayoutBuilder, not MediaQuery.sizeOf: the decision is about how much
      // room THIS tile has, and those two numbers are the same only for as long
      // as settings occupies the whole window. Put the tab inside a column next
      // to the 10-foot nav rail — the direction the redesign is already going —
      // and the window would still say 1280 while the tile measured 480, so a
      // 460dp trailing box would leave the label negative width.
      LayoutBuilder(builder: (context, constraints) => _layout(context, constraints));

  Widget _layout(BuildContext context, BoxConstraints constraints) {
    final available = constraints.hasBoundedWidth
        ? constraints.maxWidth
        : MediaQuery.sizeOf(context).width;

    // The value always goes UNDER the label, on every surface.
    //
    // The obvious layout — label left, value right — was tried at five widths
    // and does not fit this content at any of them. A 1080p Android TV reports
    // 960 LOGICAL dp, not 1920, so there is less room than it looks: every
    // constant tried (120, 200, 340, 460, a 45% share, a 60% share) either
    // clipped the value or squeezed the label into three lines, and the first
    // three of those shipped.
    //
    // Stacking has room by construction, and it is not a consolation prize: the
    // TMDb token row further down this same screen was already label-then-field,
    // so this is the settings screen agreeing with itself.
    final fieldWidth = math.min(available - 32, _maxFieldWidth);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 20),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: AppThemes.tenFoot(context, AppThemes.labelSize),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
          if (description != null) ...[
            const SizedBox(height: 2),
            Padding(
              padding: const EdgeInsets.only(left: 36),
              child: Text(
                key: dropdownTileDescriptionKey,
                description!,
                style: TextStyle(
                  fontSize: AppThemes.tenFoot(context, 12),
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
          const SizedBox(height: 8),
          SizedBox(
            key: dropdownTileValueBoxKey,
            width: fieldWidth,
            child: FocusHighlight(
              borderRadius: BorderRadius.circular(8),
              child: _field(context),
            ),
          ),
        ],
      ),
    );
  }

  Widget _field(BuildContext context) {
    return DropdownButtonFormField<T>(
            value: value,
            decoration: InputDecoration(
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 8,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(
                  color: Theme.of(context).colorScheme.outline,
                ),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(
                  color: Theme.of(
                    context,
                  ).colorScheme.outline.withOpacity(0.5),
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(
                  color: Theme.of(context).colorScheme.primary,
                  width: 2,
                ),
              ),
            ),
            items: items,
            onChanged: onChanged,
            isExpanded: true,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(fontSize: AppThemes.tenFoot(context, 12)),
            dropdownColor: Theme.of(context).colorScheme.surface,
            icon: Icon(Icons.keyboard_arrow_down, size: 18),
          );
  }
}
