import 'dart:async';
import 'package:flutter/material.dart';
import 'package:rensi_iptv/utils/responsive_helper.dart';
import 'package:rensi_iptv/widgets/tv/focus_highlight.dart';
import 'package:rensi_iptv/database/database.dart';
import 'package:rensi_iptv/models/content_type.dart';
import 'package:rensi_iptv/models/playlist_content_model.dart';
import 'package:rensi_iptv/redesign/rensi_widgets.dart';
import 'package:rensi_iptv/services/app_state.dart';
import 'package:rensi_iptv/services/service_locator.dart';
import 'package:rensi_iptv/widgets/tv/tv_keyboard.dart';
import 'package:rensi_iptv/utils/app_themes.dart';

/// Full-screen global search (redesign). Queries the local catalogue in the
/// database across live + movies + series — not just the loaded categories —
/// so it returns the complete set of matches for the current playlist.
class SearchRedesign extends StatefulWidget {
  const SearchRedesign({super.key, required this.onOpen});
  final void Function(ContentItem) onOpen;

  @override
  State<SearchRedesign> createState() => _SearchRedesignState();
}

class _SearchRedesignState extends State<SearchRedesign> {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  final _db = getIt<AppDatabase>();
  Timer? _debounce;
  String _query = '';
  bool _loading = false;
  List<ContentItem> _results = const [];

  @override
  void initState() {
    super.initState();
    // On TV, don't auto-open the full-screen IME on entry — the user focuses
    // the field with the D-pad and presses OK to bring up the keyboard.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!ResponsiveHelper.isDesktopOrTV(context)) _focus.requestFocus();
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onChanged(String v) {
    setState(() => _query = v);
    _debounce?.cancel();
    final q = v.trim();
    if (q.length < 2) {
      setState(() {
        _results = const [];
        _loading = false;
      });
      return;
    }
    setState(() => _loading = true);
    _debounce = Timer(const Duration(milliseconds: 300), () => _run(q));
  }

  Future<void> _run(String q) async {
    final pid = AppState.currentPlaylist?.id;
    if (pid == null) return;
    try {
      final results = await Future.wait([
        _db.searchMovieBroad(pid, q),
        _db.searchSeriesBroad(pid, q),
        _db.searchLiveStreams(pid, q),
      ]);
      final movies = results[0] as List;
      final series = results[1] as List;
      final live = results[2] as List;
      final out = <ContentItem>[
        for (final v in movies)
          ContentItem(v.streamId, v.name, v.streamIcon, ContentType.vod,
              vodStream: v, containerExtension: v.containerExtension),
        for (final s in series)
          ContentItem(s.seriesId, s.name, s.cover ?? '', ContentType.series,
              seriesStream: s),
        for (final l in live)
          ContentItem(l.streamId, l.name, l.streamIcon, ContentType.liveStream,
              liveStream: l),
      ];
      if (mounted && _query.trim() == q) {
        setState(() {
          _results = out;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = rensi(context);
    final cross = ResponsiveHelper.getCrossAxisCount(context);
    // safeInset, not a duplicated 48/20: the hand-written pair gave 20dp on
    // phones where every other screen uses 24, and did not scale with wider
    // surfaces the way the overscan margin has to.
    final sidePad = ResponsiveHelper.safeInset(context);
    final q = _query.trim();

    Widget body;
    if (q.length < 2) {
      body = Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search, size: 56, color: r.surface3),
            const SizedBox(height: 12),
            Text('Busca en todo tu catálogo',
                style: TextStyle(color: r.text3, fontSize: AppThemes.labelSize)),
          ],
        ),
      );
    } else if (_loading && _results.isEmpty) {
      body = const Center(child: CircularProgressIndicator());
    } else if (_results.isEmpty) {
      body = Center(
        child: Text('Sin resultados para "$q"',
            style: TextStyle(color: r.text3)),
      );
    } else {
      body = GridView.builder(
        padding: EdgeInsets.fromLTRB(sidePad, 4, sidePad, 24),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: cross,
          childAspectRatio: 1 / 1.48,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
        ),
        itemCount: _results.length,
        itemBuilder: (_, i) => RensiPoster(
          item: _results[i],
          width: double.infinity,
          // Land focus on the first result when results arrive on TV.
          autofocus: i == 0 && ResponsiveHelper.isDesktopOrTV(context),
          onTap: () => widget.onOpen(_results[i]),
        ),
      );
    }

    final tv = ResponsiveHelper.isDesktopOrTV(context);
    if (tv) {
      // Keyboard on the left, results on the right — the layout every TV
      // streaming app converges on, because leanback's system IME covers the
      // results you are typing to find.
      body = Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(sidePad, 4, 24, 24),
            child: TvKeyboard(
              onKey: (c) {
                _controller.text = _controller.text + c.toLowerCase();
                _onChanged(_controller.text);
              },
              onBackspace: () {
                final t = _controller.text;
                if (t.isEmpty) return;
                _controller.text = t.substring(0, t.length - 1);
                _onChanged(_controller.text);
              },
              onClear: () {
                _controller.clear();
                _onChanged('');
              },
            ),
          ),
          Expanded(child: body),
        ],
      );
    }

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  Expanded(
                    child: Container(
                      height: 48,
                      decoration: BoxDecoration(
                        color: r.surface2,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      child: Row(
                        children: [
                          Icon(Icons.search, size: 20, color: r.text3),
                          const SizedBox(width: 10),
                          Expanded(
                            child: TextField(
                              controller: _controller,
                              focusNode: _focus,
                              // On TV the on-screen keyboard feeds this field,
                              // so it is a display of the query rather than a
                              // focus target — focusing it would summon the
                              // very system IME we are replacing.
                              readOnly: ResponsiveHelper.isDesktopOrTV(context),
                              autofocus: !ResponsiveHelper.isDesktopOrTV(context),
                              textInputAction: TextInputAction.search,
                              onChanged: _onChanged,
                              decoration: const InputDecoration(
                                border: InputBorder.none,
                                isCollapsed: true,
                                hintText: 'Buscar películas, series, canales…',
                              ),
                            ),
                          ),
                          if (q.isNotEmpty)
                            FocusHighlight(
                              borderRadius: BorderRadius.circular(20),
                              child: IconButton(
                                iconSize: 18,
                                padding: const EdgeInsets.all(4),
                                constraints: const BoxConstraints(),
                                tooltip: 'Limpiar',
                                onPressed: () {
                                  _controller.clear();
                                  _onChanged('');
                                },
                                icon: Icon(Icons.close,
                                    size: 18, color: r.text3),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(child: body),
          ],
        ),
      ),
    );
  }
}
