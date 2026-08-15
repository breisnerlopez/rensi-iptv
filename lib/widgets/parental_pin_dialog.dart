import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:rensi_iptv/l10n/localization_extension.dart';
import 'package:rensi_iptv/services/parental_service.dart';
import 'package:rensi_iptv/widgets/tv/tv_field_traversal.dart';

/// Prompts for the parental PIN to open locked content. Returns true when the
/// session is already unlocked, when no PIN is set (nothing to gate), or when
/// the entered PIN verifies; false if cancelled or wrong.
Future<bool> showParentalPinDialog(BuildContext context) async {
  final svc = ParentalService.instance;
  if (svc.isUnlocked) return true;
  if (!await svc.hasPin()) return true; // can't gate without a PIN set
  if (!context.mounted) return false;
  final ok = await showDialog<bool>(
    context: context,
    builder: (_) => const _ParentalPinDialog(),
  );
  return ok ?? false;
}

class _ParentalPinDialog extends StatefulWidget {
  const _ParentalPinDialog();

  @override
  State<_ParentalPinDialog> createState() => _ParentalPinDialogState();
}

class _ParentalPinDialogState extends State<_ParentalPinDialog> {
  final _controller = TextEditingController();
  bool _wrong = false;
  bool _checking = false;
  // Rate-limit brute force: after a few wrong tries, a growing cooldown disables
  // submitting (a 4-digit PIN is otherwise trivial to guess with physical access).
  int _attempts = 0;
  bool _cooldown = false;
  Timer? _cooldownTimer;

  @override
  void dispose() {
    _cooldownTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_checking || _cooldown) return;
    setState(() => _checking = true);
    final ok = await ParentalService.instance.verifyPin(_controller.text.trim());
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop(true);
    } else {
      _attempts++;
      setState(() {
        _wrong = true;
        _checking = false;
        _controller.clear();
        // 3rd wrong attempt onward: exponential-ish cooldown, capped at 30s.
        if (_attempts >= 3) {
          _cooldown = true;
          final secs = min(30, (1 << (_attempts - 3)).clamp(1, 30)).toInt();
          _cooldownTimer?.cancel();
          _cooldownTimer = Timer(Duration(seconds: secs), () {
            if (mounted) setState(() => _cooldown = false);
          });
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final loc = context.loc;
    return AlertDialog(
      title: Text(loc.parental_control),
      content: TvFieldTraversal(
        child: TextField(
          controller: _controller,
          autofocus: true,
          obscureText: true,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          onSubmitted: (_) => _submit(),
          decoration: InputDecoration(
            labelText: loc.parental_enter_pin,
            errorText: _wrong ? loc.parental_wrong_pin : null,
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(loc.cancel),
        ),
        FilledButton(
          onPressed: (_checking || _cooldown) ? null : _submit,
          child: Text(loc.confirm),
        ),
      ],
    );
  }
}
