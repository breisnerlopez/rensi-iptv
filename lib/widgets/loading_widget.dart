import 'package:flutter/material.dart';
import 'package:rensi_iptv/l10n/localization_extension.dart';

// Takes a context because the label is localized: this widget used to render a
// hard-coded Turkish "Yükleniyor..." to every user, in every language.
Widget buildFullScreenLoadingWidget(BuildContext context) {
  return Center(
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const CircularProgressIndicator(),
        const SizedBox(height: 16),
        Text(context.loc.loading),
      ],
    ),
  );
}
