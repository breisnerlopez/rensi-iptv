import 'package:flutter/material.dart';

/// Section heading for the settings / info screens.
///
/// Renders with the redesign's display font (Bricolage Grotesque, w700) at the
/// small section-header step, so every legacy call-site (settings, developer,
/// playlist / subscription / server info) picks up the cinematic type without
/// being touched. Kept as its own widget — rather than swapped for
/// [SectionHeader] — so the existing API and call-sites are preserved.
class SectionTitleWidget extends StatelessWidget {
  final String title;

  const SectionTitleWidget({super.key, required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 6),
      child: Semantics(
        header: true,
        child: Text(
          title,
          style: TextStyle(
            fontFamily: 'Bricolage Grotesque',
            fontSize: 19,
            fontWeight: FontWeight.w700,
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
      ),
    );
  }
}
