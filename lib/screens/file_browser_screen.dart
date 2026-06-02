import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:rensi_iptv/l10n/localization_extension.dart';

/// Simple in-app file browser meant for Android-TV boxes whose stripped
/// DocumentsUI rejects the system file picker.
///
/// Navigates the device filesystem starting from a small set of common
/// roots (Downloads, sdcard root, the app's own external dir). Files are
/// filtered to [extensions] (lowercase, no leading dot). The user picks a
/// file with D-pad center / tap; the route pops with the chosen [File].
/// Cancel pops with `null`.
class FileBrowserScreen extends StatefulWidget {
  const FileBrowserScreen({
    super.key,
    required this.title,
    required this.extensions,
  });

  final String title;
  final List<String> extensions;

  @override
  State<FileBrowserScreen> createState() => _FileBrowserScreenState();
}

class _FileBrowserScreenState extends State<FileBrowserScreen> {
  Directory? _current;
  List<_BrowserEntry> _entries = const [];
  bool _loading = true;
  String? _errorKey;
  List<Directory> _roots = const [];

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    final granted = await _ensurePermission();
    if (!granted) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _errorKey = 'denied';
      });
      return;
    }
    _roots = await _resolveRoots();
    final initial = _roots.isNotEmpty ? _roots.first : null;
    await _enter(initial);
  }

  /// On Android ≤32 we need READ_EXTERNAL_STORAGE; 33+ has no equivalent
  /// for arbitrary files and we fall back to scanning the app-private
  /// dirs that are always readable. iOS/desktop have no permission to
  /// request — `Permission.storage.request()` no-ops there.
  Future<bool> _ensurePermission() async {
    if (!Platform.isAndroid) return true;
    final status = await Permission.storage.request();
    return status.isGranted ||
        status.isLimited ||
        status.isRestricted ||
        // Android 13+ returns "permanentlyDenied" because the permission
        // is a no-op there; we still try to browse the app-private dirs
        // (which never need a permission), so don't block the flow.
        status.isPermanentlyDenied;
  }

  Future<List<Directory>> _resolveRoots() async {
    final roots = <Directory>[];

    // 1. Downloads — covers ~99% of the "I put my backup here" case.
    for (final candidate in const [
      '/sdcard/Download',
      '/storage/emulated/0/Download',
      '/storage/self/primary/Download',
    ]) {
      final dir = Directory(candidate);
      if (await dir.exists()) {
        roots.add(dir);
        break;
      }
    }

    // 2. Root of primary external storage.
    for (final candidate in const [
      '/sdcard',
      '/storage/emulated/0',
      '/storage/self/primary',
    ]) {
      final dir = Directory(candidate);
      if (await dir.exists() && !roots.any((d) => d.path == dir.path)) {
        roots.add(dir);
        break;
      }
    }

    // 3. App-private external dirs — always accessible, useful when the
    //    user side-loaded the file via adb push into Android/data/<pkg>.
    try {
      final dirs = await getExternalStorageDirectories();
      if (dirs != null) {
        for (final d in dirs) {
          if (!roots.any((r) => r.path == d.path)) {
            roots.add(d);
          }
        }
      }
    } catch (_) {
      // Ignore — getExternalStorageDirectories isn't available on every
      // OS configuration.
    }

    return roots;
  }

  Future<void> _enter(Directory? dir) async {
    if (dir == null) {
      setState(() {
        _loading = false;
        _current = null;
        _entries = const [];
        _errorKey = 'no_roots';
      });
      return;
    }
    setState(() => _loading = true);
    try {
      final entries = await _listDirectory(dir);
      if (!mounted) return;
      setState(() {
        _current = dir;
        _entries = entries;
        _errorKey = null;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _errorKey = 'unreadable';
      });
    }
  }

  Future<List<_BrowserEntry>> _listDirectory(Directory dir) async {
    final out = <_BrowserEntry>[];
    final wanted = widget.extensions
        .map((e) => e.toLowerCase().replaceFirst(RegExp(r'^\.'), ''))
        .toSet();
    await for (final entity in dir.list(followLinks: false)) {
      final base = entity.path.split(Platform.pathSeparator).last;
      if (base.startsWith('.')) continue; // Hide dotfiles.
      if (entity is Directory) {
        out.add(_BrowserEntry.directory(entity, base));
      } else if (entity is File) {
        final dot = base.lastIndexOf('.');
        if (dot < 0) continue;
        final ext = base.substring(dot + 1).toLowerCase();
        if (!wanted.contains(ext)) continue;
        FileStat? stat;
        try {
          stat = await entity.stat();
        } catch (_) {/* leave null */}
        out.add(_BrowserEntry.file(entity, base, stat));
      }
    }
    // Directories first, then alpha.
    out.sort((a, b) {
      if (a.isDirectory != b.isDirectory) {
        return a.isDirectory ? -1 : 1;
      }
      return a.label.toLowerCase().compareTo(b.label.toLowerCase());
    });
    return out;
  }

  bool get _canGoUp {
    final current = _current;
    if (current == null) return false;
    // Don't allow walking above a configured root (keep the user inside a
    // sensible tree).
    if (_roots.any((r) => r.path == current.path)) return false;
    final parentPath =
        current.parent.path.isEmpty ? '/' : current.parent.path;
    return parentPath != current.path;
  }

  Future<void> _goUp() async {
    final current = _current;
    if (current == null) return;
    await _enter(current.parent);
  }

  Future<void> _switchRoot(Directory dir) => _enter(dir);

  void _pickFile(File f) => Navigator.of(context).pop(f);

  @override
  Widget build(BuildContext context) {
    final loc = context.loc;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          if (_roots.length > 1)
            PopupMenuButton<Directory>(
              tooltip: loc.file_browser_root_picker,
              icon: const Icon(Icons.swap_horiz),
              onSelected: _switchRoot,
              itemBuilder: (_) => [
                for (final r in _roots)
                  PopupMenuItem<Directory>(
                    value: r,
                    child: Text(_shortenPath(r.path)),
                  ),
              ],
            ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (_current != null)
              Container(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                child: Row(
                  children: [
                    const Icon(Icons.folder_open, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _current!.path,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ),
            Expanded(child: _buildBody(loc)),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(dynamic loc) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_errorKey == 'denied') {
      return _Message(
        icon: Icons.block,
        text: loc.file_browser_permission_denied,
      );
    }
    if (_errorKey == 'unreadable') {
      return _Message(
        icon: Icons.folder_off,
        text: loc.file_browser_unreadable,
      );
    }
    if (_errorKey == 'no_roots' || _roots.isEmpty) {
      return _Message(
        icon: Icons.folder_off,
        text: loc.file_browser_no_roots,
      );
    }
    if (_entries.isEmpty && !_canGoUp) {
      return _Message(
        icon: Icons.folder_open,
        text: loc.file_browser_empty,
      );
    }
    return Shortcuts(
      shortcuts: const <ShortcutActivator, Intent>{
        SingleActivator(LogicalKeyboardKey.escape): _BackIntent(),
        SingleActivator(LogicalKeyboardKey.goBack): _BackIntent(),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          _BackIntent: CallbackAction<_BackIntent>(
            onInvoke: (_) {
              if (_canGoUp) {
                _goUp();
              }
              return null;
            },
          ),
        },
        child: ListView.separated(
          itemCount: _entries.length + (_canGoUp ? 1 : 0),
          separatorBuilder: (_, __) =>
              const Divider(height: 1, indent: 56),
          itemBuilder: (context, index) {
            if (_canGoUp && index == 0) {
              return ListTile(
                autofocus: true,
                leading: const Icon(Icons.arrow_upward),
                title: Text(loc.file_browser_parent_directory),
                onTap: _goUp,
              );
            }
            final entry = _entries[index - (_canGoUp ? 1 : 0)];
            return ListTile(
              autofocus: index == 0,
              leading: Icon(
                entry.isDirectory
                    ? Icons.folder
                    : Icons.insert_drive_file,
              ),
              title: Text(entry.label),
              subtitle: entry.subtitle == null
                  ? null
                  : Text(entry.subtitle!),
              onTap: () {
                if (entry.isDirectory) {
                  _enter(entry.directory!);
                } else {
                  _pickFile(entry.file!);
                }
              },
            );
          },
        ),
      ),
    );
  }

  static String _shortenPath(String path) {
    const cuts = <String, String>{
      '/storage/emulated/0': '~',
      '/storage/self/primary': '~',
      '/sdcard': '~',
    };
    for (final entry in cuts.entries) {
      if (path == entry.key) return entry.value;
      if (path.startsWith('${entry.key}/')) {
        return '${entry.value}${path.substring(entry.key.length)}';
      }
    }
    return path;
  }
}

class _BrowserEntry {
  _BrowserEntry.directory(Directory dir, this.label)
      : isDirectory = true,
        directory = dir,
        file = null,
        subtitle = null;

  _BrowserEntry.file(File f, this.label, FileStat? stat)
      : isDirectory = false,
        directory = null,
        file = f,
        subtitle = _formatStat(stat);

  final bool isDirectory;
  final String label;
  final Directory? directory;
  final File? file;
  final String? subtitle;

  static String? _formatStat(FileStat? stat) {
    if (stat == null) return null;
    final size = _formatSize(stat.size);
    final mod = stat.modified.toLocal();
    final modStr =
        '${mod.year.toString().padLeft(4, '0')}-'
        '${mod.month.toString().padLeft(2, '0')}-'
        '${mod.day.toString().padLeft(2, '0')}';
    return '$size • $modStr';
  }

  static String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KiB';
    }
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MiB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GiB';
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.icon, required this.text});
  final IconData icon;
  final String text;
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: Theme.of(context).disabledColor),
            const SizedBox(height: 12),
            Text(
              text,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
          ],
        ),
      ),
    );
  }
}

class _BackIntent extends Intent {
  const _BackIntent();
}
