import 'package:flutter/material.dart';
import 'package:rensi_iptv/utils/responsive_helper.dart';
import 'package:rensi_iptv/models/playlist_content_model.dart';
import 'package:rensi_iptv/redesign/rensi_widgets.dart';
import 'package:rensi_iptv/repositories/favorites_repository.dart';
import 'package:rensi_iptv/utils/app_themes.dart';
import 'package:rensi_iptv/l10n/localization_extension.dart';

/// "Mi lista" — saved favourites in a poster grid, with an empty state.
class ListRedesign extends StatefulWidget {
  const ListRedesign({super.key, required this.onOpen, this.onBrowse});
  final void Function(ContentItem) onOpen;

  /// Where the empty state's primary action goes.
  final VoidCallback? onBrowse;

  @override
  State<ListRedesign> createState() => _ListRedesignState();
}

class _ListRedesignState extends State<ListRedesign> {
  final _repo = FavoritesRepository();
  late Future<List<ContentItem>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<ContentItem>> _load() async {
    final favs = await _repo.getAllFavorites();
    final out = <ContentItem>[];
    for (final f in favs) {
      final it = await _repo.getContentItemFromFavorite(f);
      if (it != null) out.add(it);
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final r = rensi(context);
    final cross = ResponsiveHelper.getCrossAxisCount(context);
    final sidePad = ResponsiveHelper.isDesktopOrTV(context) ? 48.0 : 20.0;
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        bottom: false,
        child: FutureBuilder<List<ContentItem>>(
          future: _future,
          builder: (context, snap) {
            final items = snap.data ?? const <ContentItem>[];
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: EdgeInsets.fromLTRB(sidePad, 10, sidePad, 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Mi lista',
                          style: TextStyle(
                              fontFamily: 'Bricolage Grotesque',
                              fontSize: AppThemes.h2Size,
                              fontWeight: FontWeight.w800)),
                      const SizedBox(height: 3),
                      Text('${items.length} títulos guardados',
                          style: TextStyle(fontSize: AppThemes.bodySmallSize, color: r.text3)),
                    ],
                  ),
                ),
                Expanded(
                  child: snap.connectionState == ConnectionState.waiting
                      ? const Center(child: CircularProgressIndicator())
                      : items.isEmpty
                          ? _empty(context)
                          : GridView.builder(
                              padding: EdgeInsets.fromLTRB(sidePad, 12, sidePad, 24),
                              gridDelegate:
                                  SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: cross,
                                childAspectRatio: 1 / 1.48,
                                crossAxisSpacing: 12,
                                mainAxisSpacing: 12,
                              ),
                              itemCount: items.length,
                              itemBuilder: (_, i) => RensiPoster(
                                item: items[i],
                                width: double.infinity,
                                autofocus: i == 0,
                                onTap: () => widget.onOpen(items[i]),
                              ),
                            ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _empty(BuildContext context) => RensiEmptyState(
        icon: Icons.bookmark_border_rounded,
        title: context.loc.empty_list_title,
        body: context.loc.empty_list_body,
        actionLabel: context.loc.action_browse_catalogue,
        // Without an action this screen had no focusable element at all: on a
        // remote the user arrived and had nothing to press.
        onAction: widget.onBrowse ?? () {},
      );
}
