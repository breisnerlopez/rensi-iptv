import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:rensi_iptv/l10n/localization_extension.dart';
import 'package:rensi_iptv/utils/responsive_helper.dart';

/// Wraps a root TV screen with a confirm-before-exit guard.
///
/// On large screens (TV / desktop / landscape tablet) the system Back
/// button no longer drops the app straight to the launcher — instead
/// we surface an AlertDialog asking the user whether they really want
/// to leave. On phones the wrapper is a no-op so touch users keep the
/// stock pop behaviour.
///
/// Wrap once at the body of every screen the navigation can land on
/// when the back stack is empty (PlaylistScreen, M3UHomeScreen,
/// XtreamCodeHomeScreen).
class ConfirmExitScope extends StatelessWidget {
  const ConfirmExitScope({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!ResponsiveHelper.isDesktopOrTV(context)) return child;
    return PopScope<Object?>(
      // We always own the pop — flipping canPop to false guarantees
      // onPopInvokedWithResult fires for every Back press, including
      // the case where this widget sits at the root of the navigator
      // stack and the framework would otherwise route Back to
      // SystemNavigator.pop.
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final confirmed = await _askConfirmation(context);
        if (confirmed == true) {
          await SystemNavigator.pop();
        }
      },
      child: child,
    );
  }

  Future<bool?> _askConfirmation(BuildContext context) {
    final loc = context.loc;
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(loc.exit_confirm_title),
          content: Text(loc.exit_confirm_message),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              autofocus: true,
              child: Text(loc.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(loc.exit_confirm_action),
            ),
          ],
        );
      },
    );
  }
}
