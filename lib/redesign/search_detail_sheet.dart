import 'package:flutter/material.dart';
import 'package:rensi_iptv/l10n/localization_extension.dart';
import 'package:rensi_iptv/models/global_search_result.dart';
import 'package:rensi_iptv/models/tmdb_search_result.dart';
import 'package:rensi_iptv/redesign/rensi_widgets.dart';
import 'package:rensi_iptv/services/global_search_service.dart';
import 'package:rensi_iptv/utils/app_themes.dart';
import 'package:rensi_iptv/utils/responsive_helper.dart';
import 'package:rensi_iptv/widgets/tv/focus_highlight.dart';

/// Bottom sheet shown when a search result is tapped.
///
/// Two shapes, decided by [GlobalSearchResult.localMatches]:
///  - OWNED (matches present) -> a "Play from" list, one focusable row per
///    playlist that carries the title; tapping plays that copy and closes.
///  - NOT OWNED (tmdbOnly)    -> synopsis/rating and a single primary action:
///    the wishlist toggle. No play affordance.
///
/// The rich synopsis/genres come from [GlobalSearchService.getDetail], fetched
/// once; while it resolves (or if it throws) the header — poster, title, year,
/// rating, type — still renders from the already-known [TmdbSearchResult], so
/// the sheet is never a blank loader and never a hard error.
class SearchDetailSheet extends StatelessWidget {
  const SearchDetailSheet({
    super.key,
    required this.result,
    required this.service,
    required this.onPlayLocal,
    required this.onToggleWishlist,
  });

  final GlobalSearchResult result;
  final GlobalSearchService service;

  /// Play a chosen owned copy. The caller switches AppState + navigates.
  final void Function(LocalContentMatch) onPlayLocal;

  /// Toggle the wishlist for this TMDb title; resolves to the new saved state.
  /// Zero-arg by contract — the caller already closes over the result, and the
  /// sheet reflects the returned bool on its own icon.
  final Future<bool> Function() onToggleWishlist;

  static Future<void> show(
    BuildContext context, {
    required GlobalSearchResult result,
    required GlobalSearchService service,
    required void Function(LocalContentMatch) onPlayLocal,
    required Future<bool> Function() onToggleWishlist,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      // Dimmed scrim; the sheet paints its own rounded surface.
      barrierColor: Colors.black.withValues(alpha: 0.62),
      builder: (_) => SearchDetailSheet(
        result: result,
        service: service,
        onPlayLocal: onPlayLocal,
        onToggleWishlist: onToggleWishlist,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // The public type is StatelessWidget (fixed by the contract), but the body
    // owns a getDetail future and an optimistic wishlist flag, so it lives in a
    // private StatefulWidget.
    return _SheetBody(
      result: result,
      service: service,
      onPlayLocal: onPlayLocal,
      onToggleWishlist: onToggleWishlist,
    );
  }
}

class _SheetBody extends StatefulWidget {
  const _SheetBody({
    required this.result,
    required this.service,
    required this.onPlayLocal,
    required this.onToggleWishlist,
  });

  final GlobalSearchResult result;
  final GlobalSearchService service;
  final void Function(LocalContentMatch) onPlayLocal;
  final Future<bool> Function() onToggleWishlist;

  @override
  State<_SheetBody> createState() => _SheetBodyState();
}

class _SheetBodyState extends State<_SheetBody> {
  late Future<TmdbDetailResult?> _detail;
  late bool _wishlisted;
  bool _toggling = false;

  @override
  void initState() {
    super.initState();
    // Fetch once. getDetail can throw on a TMDb failure; swallow it to null so
    // the sheet degrades to the header-only view rather than erroring.
    _detail = widget.service
        .getDetail(widget.result.tmdb)
        .then<TmdbDetailResult?>((d) => d)
        .catchError((_) => null);
    _wishlisted = widget.result.isWishlisted;
  }

  bool get _owned => widget.result.localMatches.isNotEmpty;

  Future<void> _toggleWishlist() async {
    if (_toggling) return;
    setState(() {
      _toggling = true;
      _wishlisted = !_wishlisted; // optimistic
    });
    try {
      final saved = await widget.onToggleWishlist();
      if (mounted) setState(() => _wishlisted = saved);
    } catch (_) {
      if (mounted) setState(() => _wishlisted = !_wishlisted); // revert
    } finally {
      if (mounted) setState(() => _toggling = false);
    }
  }

  void _play(LocalContentMatch match) {
    widget.onPlayLocal(match);
    Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    final r = rensi(context);
    final tv = ResponsiveHelper.isDesktopOrTV(context);
    final theme = Theme.of(context);
    final media = MediaQuery.of(context);

    // Cap the sheet so it never eats the whole screen; leave the scrim visible
    // as an implicit "tap outside / BACK to dismiss" affordance.
    final maxHeight = media.size.height * (tv ? 0.9 : 0.86);

    final surface = theme.colorScheme.surface;

    return PopScope(
      // Default canPop:true — BACK (D-pad or system) pops the modal route. The
      // PopScope makes that intent explicit and keeps the hook if it's ever
      // needed to intercept an in-flight toggle.
      canPop: true,
      child: Align(
        alignment: Alignment.bottomCenter,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: maxHeight,
            maxWidth: tv ? 760 : double.infinity,
          ),
          child: Material(
            color: surface,
            clipBehavior: Clip.antiAlias,
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: SafeArea(
              top: false,
              child: SingleChildScrollView(
                padding: EdgeInsets.only(bottom: 20 + media.padding.bottom),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _grabHandle(r, tv),
                    _Header(result: widget.result),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _titleBlock(context, r),
                          const SizedBox(height: 14),
                          // Synopsis/genres arrive from getDetail; header above
                          // is already painted, so this only enriches.
                          FutureBuilder<TmdbDetailResult?>(
                            future: _detail,
                            builder: (context, snap) {
                              if (snap.connectionState !=
                                  ConnectionState.done) {
                                return _synopsisLoader(r);
                              }
                              return _synopsisBlock(context, r, snap.data);
                            },
                          ),
                          const SizedBox(height: 22),
                          _actionSection(context, r, tv),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // --- pieces --------------------------------------------------------------

  Widget _grabHandle(RensiColors r, bool tv) {
    // A drag handle reads as "swipe to dismiss" — a mobile affordance. On TV
    // there is no drag; keep a slim spacer so the header isn't flush to the top.
    if (tv) return const SizedBox(height: 10);
    return Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 2),
      child: Center(
        child: Container(
          width: 40,
          height: 4,
          decoration: BoxDecoration(
            color: r.hairline2,
            borderRadius: BorderRadius.circular(999),
          ),
        ),
      ),
    );
  }

  Widget _titleBlock(BuildContext context, RensiColors r) {
    final t = widget.result.tmdb;
    final loc = context.loc;
    final chips = <Widget>[];

    final year = t.releaseYear;
    if (year != null && year.isNotEmpty) {
      chips.add(_metaText(year, r));
    }
    chips.add(_metaText(
      t.mediaType == TmdbMediaType.movie
          ? loc.search_filter_movies
          : loc.search_filter_tv,
      r,
    ));
    if (t.voteAverage > 0) {
      chips.add(Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.star_rounded, size: 17, color: r.gold),
          const SizedBox(width: 3),
          Text(
            t.voteAverage.toStringAsFixed(1),
            style: TextStyle(
              fontSize: AppThemes.bodySmallSize,
              fontWeight: FontWeight.w700,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
        ],
      ));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          t.title,
          style: const TextStyle(
            fontFamily: 'Bricolage Grotesque',
            fontSize: AppThemes.h2Size,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.4,
            height: 1.1,
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 14,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: chips,
        ),
      ],
    );
  }

  Widget _metaText(String value, RensiColors r) => Text(
        value,
        style: TextStyle(
          fontSize: AppThemes.bodySmallSize,
          fontWeight: FontWeight.w600,
          color: r.text3,
        ),
      );

  Widget _synopsisLoader(RensiColors r) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Align(
          alignment: AlignmentDirectional.centerStart,
          child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(
              strokeWidth: 2.4,
              valueColor: AlwaysStoppedAnimation(r.accent),
            ),
          ),
        ),
      );

  Widget _synopsisBlock(
    BuildContext context,
    RensiColors r,
    TmdbDetailResult? detail,
  ) {
    final overview = detail?.overview ?? widget.result.tmdb.overview;
    final genres = detail?.genres ?? const <String>[];
    final children = <Widget>[];

    if (genres.isNotEmpty) {
      children.add(Text(
        genres.join('  •  '),
        style: TextStyle(
          fontSize: AppThemes.bodySmallSize,
          fontWeight: FontWeight.w600,
          // text2, not accent2: accent2 measured 2.7:1 on the light sheet —
          // below the 4.5:1 AA floor. text2 passes both themes.
          color: r.text2,
          height: 1.3,
        ),
      ));
    }
    if (overview != null && overview.trim().isNotEmpty) {
      if (children.isNotEmpty) children.add(const SizedBox(height: 10));
      children.add(Text(
        overview,
        style: TextStyle(
          fontSize: AppThemes.bodySize,
          height: 1.45,
          color: r.text2,
        ),
      ));
    }
    if (children.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    );
  }

  Widget _actionSection(BuildContext context, RensiColors r, bool tv) {
    if (_owned) return _playFromSection(context, r, tv);
    return _wishlistOnlySection(context, r, tv);
  }

  Widget _playFromSection(BuildContext context, RensiColors r, bool tv) {
    final loc = context.loc;
    final matches = widget.result.localMatches;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          loc.search_play_from,
          style: TextStyle(
            fontFamily: 'Bricolage Grotesque',
            fontSize: AppThemes.h3Size,
            fontWeight: FontWeight.w700,
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: 12),
        for (var i = 0; i < matches.length; i++)
          Padding(
            padding: EdgeInsets.only(bottom: i == matches.length - 1 ? 0 : 10),
            child: _PlayFromRow(
              match: matches[i],
              // First row grabs focus on TV so the D-pad lands somewhere.
              autofocus: tv && i == 0,
              onTap: () => _play(matches[i]),
            ),
          ),
      ],
    );
  }

  Widget _wishlistOnlySection(BuildContext context, RensiColors r, bool tv) {
    final loc = context.loc;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          // Reflect the actual saved state: once saved, the button offers to
          // remove, so the body must not still say "not in your lists, save it".
          _wishlisted ? loc.search_in_wishlist_body : loc.search_not_available_body,
          style: TextStyle(
            fontSize: AppThemes.bodySize,
            height: 1.4,
            // text2, not text3: at 10 feet the dim gray was hard to read, and
            // this line justifies the save.
            color: r.text2,
          ),
        ),
        const SizedBox(height: 18),
        FocusHighlight(
          shape: const StadiumBorder(),
          child: FilledButton.icon(
            onPressed: _toggling ? null : _toggleWishlist,
            autofocus: tv,
            style: FilledButton.styleFrom(
              minimumSize: Size(0, tv ? 56 : 50),
              padding: const EdgeInsets.symmetric(horizontal: 26),
              shape: const StadiumBorder(),
            ),
            icon: Icon(
              _wishlisted ? Icons.bookmark_rounded : Icons.bookmark_add_outlined,
              size: 22,
            ),
            label: Text(
              _wishlisted
                  ? loc.search_remove_from_wishlist
                  : loc.search_add_to_wishlist,
              style: const TextStyle(
                fontSize: AppThemes.bodySize,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Cinematic backdrop header: 16:9 art with a bottom scrim so the title block
/// below reads against it. Falls back to the typographic key-art when TMDb
/// supplied no image.
class _Header extends StatelessWidget {
  const _Header({required this.result});
  final GlobalSearchResult result;

  @override
  Widget build(BuildContext context) {
    final t = result.tmdb;
    final surface = Theme.of(context).colorScheme.surface;
    return AspectRatio(
      aspectRatio: 16 / 9,
      child: Stack(
        fit: StackFit.expand,
        children: [
          RensiKeyArt.raw(
            seed: '${t.id}',
            title: t.title,
            imagePath: t.posterUrl,
            backdrop: t.backdropPosterUrl.isEmpty ? null : [t.backdropPosterUrl],
            preferBackdrop: true,
            // 0, not 0.9: the title is printed once, as the H2 in the block
            // below. Printing it on the fallback art too made it appear twice
            // whenever TMDb supplied no backdrop.
            titleScale: 0,
          ),
          // Fade the art into the sheet surface so the header and body read as
          // one panel rather than a pasted-in thumbnail.
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.transparent,
                  surface.withValues(alpha: 0.0),
                  surface,
                ],
                stops: const [0.0, 0.55, 1.0],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A single "play from `<playlist>`" row: focusable, RTL-safe.
class _PlayFromRow extends StatelessWidget {
  const _PlayFromRow({
    required this.match,
    required this.onTap,
    this.autofocus = false,
  });

  final LocalContentMatch match;
  final VoidCallback onTap;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final r = rensi(context);
    final theme = Theme.of(context);
    return FocusHighlight(
      borderRadius: BorderRadius.circular(14),
      child: Material(
        color: r.surface2,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: r.hairline),
        ),
        child: InkWell(
          onTap: onTap,
          autofocus: autofocus,
          child: Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(16, 14, 14, 14),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: r.accent,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.play_arrow_rounded,
                    color: r.onAccent,
                    size: 26,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    match.playlist.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: AppThemes.bodySize,
                      fontWeight: FontWeight.w700,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  Directionality.of(context) == TextDirection.rtl
                      ? Icons.chevron_left_rounded
                      : Icons.chevron_right_rounded,
                  color: r.text3,
                  size: 24,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
