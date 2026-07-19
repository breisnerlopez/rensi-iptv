import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:rensi_iptv/l10n/localization_extension.dart';
import 'package:rensi_iptv/models/all_category_sentinel.dart';
import 'package:rensi_iptv/models/category_type.dart';
import 'package:rensi_iptv/models/category_view_model.dart';
import 'package:rensi_iptv/models/playlist_content_model.dart';
import 'package:rensi_iptv/redesign/rensi_widgets.dart';
import 'package:rensi_iptv/repositories/favorites_repository.dart';
import 'package:rensi_iptv/utils/responsive_helper.dart';
import 'package:rensi_iptv/widgets/tv/focus_highlight.dart';
import 'package:rensi_iptv/utils/app_themes.dart';

/// Cinematic "Inicio" — hero + themed rails, fed by the real catalogue.
/// Mounts inside the existing home so it reuses controllers / navigation.
class RedesignHome extends StatelessWidget {
  const RedesignHome({
    super.key,
    required this.movieCategories,
    required this.seriesCategories,
    required this.onOpen,
    required this.onPlay,
    this.continueItems = const [],
    this.onSearch,
    this.onSettings,
    this.onSeeAll,
    this.playlistSwitcher,
  });

  final List<CategoryViewModel> movieCategories;
  final List<CategoryViewModel> seriesCategories;
  final List<ContentItem> continueItems;
  final void Function(ContentItem) onOpen;
  final void Function(ContentItem) onPlay;
  final VoidCallback? onSearch;
  final VoidCallback? onSettings;
  // Opens the full category grid ("Ver todo") — a rail only shows the first 18.
  final void Function(CategoryViewModel)? onSeeAll;
  final Widget? playlistSwitcher;

  /// Number of category rails actually CONSTRUCTED (not just mounted). With the
  /// lazy ListView.builder only near-viewport rows build; the old eager
  /// ListView(children:) built every category's widgets on each build. Lets a
  /// test prove the deferral (element-mount counts wouldn't distinguish them).
  @visibleForTesting
  static int debugRailBuilds = 0;

  static String _railTitle(BuildContext context, CategoryViewModel c) {
    if (!isAllCategorySentinel(c.category.categoryId)) {
      return c.category.categoryName;
    }
    switch (c.category.type) {
      case CategoryType.vod:
        return context.loc.view_all_movies;
      case CategoryType.series:
        return context.loc.view_all_series;
      case CategoryType.live:
        return context.loc.view_all_live;
    }
  }

  ContentItem? get _hero {
    for (final c in movieCategories) {
      for (final it in c.contentItems) {
        if (it.imagePath.isNotEmpty) return it;
      }
    }
    for (final c in movieCategories) {
      if (c.contentItems.isNotEmpty) return c.contentItems.first;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final r = rensi(context);
    final hero = _hero;
    final tv = ResponsiveHelper.isDesktopOrTV(context);
    final posterW = tv ? 168.0 : 138.0;
    final sidePad = tv ? 48.0 : 20.0;

    // Category rows are built lazily by the outer ListView.builder (only those
    // near the viewport) instead of materializing SectionHeader + RensiRail + 18
    // poster configs for EVERY category on each build. On a large catalogue
    // (50+ categories) that upfront construction was a build-time spike on
    // entering Inicio. Element-level laziness (and thus D-pad focus traversal)
    // is unchanged — only widget-config construction is deferred.
    final cats = <CategoryViewModel>[
      for (final c in movieCategories)
        if (c.contentItems.isNotEmpty) c,
      for (final c in seriesCategories)
        if (c.contentItems.isNotEmpty) c,
    ];
    // With no hero (e.g. a live-only playlist has no movie to feature), the
    // first content poster must take focus so the remote lands on something.
    final noHero = tv && hero == null;

    // Fixed leading items (O(1)); always near the top so eager build is fine.
    final leading = <Widget>[
      _TopBar(
          tv: tv,
          onSearch: onSearch,
          onSettings: onSettings,
          playlistSwitcher: playlistSwitcher),
      if (hero != null)
        _Hero(item: hero, onOpen: onOpen, onPlay: onPlay, tv: tv),
      const SizedBox(height: 8),
      if (continueItems.isNotEmpty) ...[
        SectionHeader(title: context.loc.history, sidePad: sidePad),
        _ContinueRail(items: continueItems, onPlay: onPlay),
        const SizedBox(height: 26),
      ],
    ];

    final showEmpty = cats.isEmpty && continueItems.isEmpty;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        bottom: false,
        child: ListView.builder(
          padding: const EdgeInsets.only(bottom: 18),
          itemCount: leading.length + (showEmpty ? 1 : cats.length),
          itemBuilder: (context, index) {
            if (index < leading.length) return leading[index];
            if (showEmpty) {
              return Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 40, vertical: 60),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.movie_filter_outlined,
                          size: 56, color: r.text3),
                      const SizedBox(height: 16),
                      Text(
                        'No hay películas ni series en esta lista todavía.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: tv ? 20 : 16,
                            fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Usa "En vivo" en el menú para ver canales, o busca contenido.',
                        textAlign: TextAlign.center,
                        style:
                            TextStyle(color: r.text3, fontSize: tv ? 15 : 13),
                      ),
                      const SizedBox(height: 20),
                      // Always a focusable target so the remote lands somewhere.
                      FocusHighlight(
                        borderRadius: BorderRadius.circular(14),
                        child: FilledButton.icon(
                          autofocus: tv,
                          onPressed: onSearch,
                          icon: const Icon(Icons.search),
                          label: const Text('Buscar'),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }
            final i = index - leading.length;
            return _CategoryRail(
              category: cats[i],
              posterWidth: posterW,
              sidePad: sidePad,
              tv: tv,
              onOpen: onOpen,
              onSeeAll: onSeeAll,
              autofocusFirst: noHero && i == 0,
            );
          },
        ),
      ),
    );
  }
}

/// One home rail (header + horizontal posters + spacing) as a single widget so
/// the outer ListView.builder can defer its construction until it's near the
/// viewport. Same output as the old inline per-category block.
class _CategoryRail extends StatelessWidget {
  const _CategoryRail({
    required this.category,
    required this.posterWidth,
    required this.sidePad,
    required this.tv,
    required this.onOpen,
    required this.onSeeAll,
    required this.autofocusFirst,
  });

  final CategoryViewModel category;
  final double posterWidth;
  final double sidePad;
  final bool tv;
  final void Function(ContentItem) onOpen;
  final void Function(CategoryViewModel)? onSeeAll;
  final bool autofocusFirst;

  @override
  Widget build(BuildContext context) {
    RedesignHome.debugRailBuilds++; // instrumentation for the deferral test
    final items = category.contentItems.take(18).toList();
    // Only surface "Ver todo" when there's more than the rail shows, so the
    // extra content past 18 is actually reachable (was silently truncated).
    final hasMore =
        onSeeAll != null && category.contentItems.length > items.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          title: RedesignHome._railTitle(context, category),
          sidePad: sidePad,
          actionLabel: hasMore ? context.loc.see_all : null,
          onAction: hasMore ? () => onSeeAll!(category) : null,
        ),
        RensiRail(
          sidePadding: sidePad,
          posterWidth: posterWidth,
          children: [
            for (var i = 0; i < items.length; i++)
              RensiPoster(
                item: items[i],
                width: posterWidth,
                autofocus: autofocusFirst && i == 0,
                onTap: () => onOpen(items[i]),
              ),
          ],
        ),
        SizedBox(height: tv ? 34 : 26),
      ],
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar(
      {this.onSearch, this.onSettings, this.playlistSwitcher, this.tv = false});
  final VoidCallback? onSearch;
  final VoidCallback? onSettings;
  final Widget? playlistSwitcher;
  final bool tv;
  @override
  Widget build(BuildContext context) {
    final r = rensi(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(tv ? 48 : 20, tv ? 20 : 12, tv ? 48 : 20, 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!tv)
                Text('Buenas noches',
                    style: TextStyle(
                        fontSize: AppThemes.labelSize,
                        fontWeight: FontWeight.w600,
                        color: r.text3)),
              Text('Rensi',
                  style: TextStyle(
                      fontFamily: 'Bricolage Grotesque',
                      fontSize: tv ? 28 : 22,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.4)),
            ],
          ),
          Row(
            children: [
              if (playlistSwitcher != null) ...[
                playlistSwitcher!,
                const SizedBox(width: 6),
              ],
              // Search stays here on phone. On TV it now lives in the rail as
              // a first-class destination, so duplicating it in the top bar
              // would give the same target two homes.
              if (!tv) _IconBtn(icon: Icons.search, onTap: onSearch),
              // The avatar was a second door to Settings, which the rail already
              // owns — a decorative control competing with a real one. Removed;
              // the identity it implied (a single letter "A") was not real
              // either, since the app has no accounts.
            ],
          ),
        ],
      ),
    );
  }
}

class _IconBtn extends StatelessWidget {
  const _IconBtn({required this.icon, this.onTap});
  final IconData icon;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) {
    final r = rensi(context);
    return FocusHighlight(
      borderRadius: BorderRadius.circular(12),
      child: Material(
        color: Theme.of(context).colorScheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: r.hairline),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: SizedBox(width: 40, height: 40, child: Icon(icon, size: 21)),
        ),
      ),
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero(
      {required this.item,
      required this.onOpen,
      required this.onPlay,
      this.tv = false});
  final ContentItem item;
  final void Function(ContentItem) onOpen;
  final void Function(ContentItem) onPlay;
  final bool tv;

  @override
  Widget build(BuildContext context) {
    final r = rensi(context);

    final playBtnCore = FilledButton.icon(
      onPressed: () => onPlay(item),
      autofocus: tv,
      style: FilledButton.styleFrom(
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        minimumSize: Size(0, tv ? 60 : 50),
        padding: EdgeInsets.symmetric(horizontal: tv ? 30 : 16),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      icon: const Icon(Icons.play_arrow_rounded, size: 24),
      label: Text(context.loc.start_watching,
          style: TextStyle(
              fontSize: tv ? 19 : 15.5, fontWeight: FontWeight.w700)),
    );
    // This is the remote's landing target on entry, and it was the ONE control
    // with no visible focus state: a white fill ringed in #FFF5F0 by the theme
    // is 1.03:1 — the user could not see where the D-pad had put them.
    final playBtn = tv
        ? FocusHighlight(
            borderRadius: BorderRadius.circular(14),
            child: playBtnCore,
          )
        : playBtnCore;

    final actions = Row(
      mainAxisSize: tv ? MainAxisSize.min : MainAxisSize.max,
      children: [
        tv ? playBtn : Expanded(child: playBtn),
        const SizedBox(width: 12),
        _GlassBtn(icon: Icons.info_outline, onTap: () => onOpen(item)),
        const SizedBox(width: 10),
        _FavBtn(item: item),
      ],
    );

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.4),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
          ),
          child: const Text('★ DESTACADO HOY',
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                  color: Colors.white)),
        ),
        Text(
          item.name,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontFamily: 'Bricolage Grotesque',
            fontSize: tv ? 52 : 32,
            fontWeight: FontWeight.w800,
            height: 0.98,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 10),
        _HeroMeta(item: item),
        const SizedBox(height: 16),
        // On TV constrain the action row so it doesn't stretch edge-to-edge.
        tv ? actions : actions,
      ],
    );

    return Container(
      margin: tv
          ? const EdgeInsets.only(bottom: 8)
          : const EdgeInsets.fromLTRB(16, 0, 16, 24),
      // Proportional, not fixed: an Android TV viewport is 540dp tall, so the
      // old flat 520 left the hero CTAs under the fold and showed not one rail.
      // Every competitor keeps the top of the first row visible on load — it is
      // the signal that says "there is a catalogue here".
      height: tv
          ? math.min(520.0, MediaQuery.sizeOf(context).height * 0.68)
          : 440,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: tv ? BorderRadius.zero : BorderRadius.circular(22),
        border: tv ? null : Border.all(color: r.hairline),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Landscape backdrop when the provider gave us one. The hero used to
          // render `item.imagePath` — a 2:3 POSTER — with BoxFit.cover into a
          // wide box, which crops ~15% of it and scales it hard. Series already
          // carry backdropPath in the DB and the detail screens use it; the
          // hero was the one place still stretching a poster.
          RensiKeyArt(item: item, preferBackdrop: true, titleScale: 0),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                colors: [Color(0xF5080808), Color(0x99080808), Color(0x00080808)],
                stops: [0.0, 0.4, 0.78],
              ),
            ),
          ),
          if (tv)
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [Color(0xCC080808), Color(0x00080808)],
                  stops: [0.0, 0.55],
                ),
              ),
            ),
          Positioned(
            // 48 to match the top bar and the rails; it was 56, and those 8dp
            // put the hero's badge visibly out of line with the wordmark above.
            left: tv ? 48 : 18,
            right: 18,
            bottom: tv ? 44 : 18,
            child: tv
                ? ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 760),
                    child: content,
                  )
                : content,
          ),
        ],
      ),
    );
  }
}

class _HeroMeta extends StatelessWidget {
  const _HeroMeta({required this.item});
  final ContentItem item;
  @override
  Widget build(BuildContext context) {
    final r = rensi(context);
    final rating = item.vodStream?.rating ?? item.seriesStream?.rating;
    final genre = item.vodStream?.genre ?? item.seriesStream?.genre;
    final hasRating = rating != null && rating.isNotEmpty && rating != '0';
    final parts = <Widget>[];
    if (hasRating) {
      parts.add(Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.star_rounded, size: 16, color: r.gold),
        const SizedBox(width: 4),
        Text(rating,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w600)),
      ]));
    }
    if (genre != null && genre.isNotEmpty) {
      parts.add(Text(genre.split(',').first.trim(),
          style: TextStyle(
              color: Colors.white.withValues(alpha: 0.85), fontSize: 18)));
    }
    if (parts.isEmpty) return const SizedBox.shrink();
    return Wrap(
      spacing: 12,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: parts,
    );
  }
}

class _FavBtn extends StatefulWidget {
  const _FavBtn({required this.item});
  final ContentItem item;
  @override
  State<_FavBtn> createState() => _FavBtnState();
}

class _FavBtnState extends State<_FavBtn> {
  final _repo = FavoritesRepository();
  bool _saved = false;

  @override
  void initState() {
    super.initState();
    _repo
        .isFavorite(widget.item.id, widget.item.contentType)
        .then((v) {
      if (mounted) setState(() => _saved = v);
    });
  }

  Future<void> _toggle() async {
    final now = await _repo.toggleFavorite(widget.item);
    if (mounted) setState(() => _saved = now);
  }

  @override
  Widget build(BuildContext context) {
    return _GlassBtn(
      icon: _saved ? Icons.check : Icons.add,
      onTap: _toggle,
    );
  }
}

class _GlassBtn extends StatelessWidget {
  const _GlassBtn({required this.icon, this.onTap});
  final IconData icon;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) {
    return FocusHighlight(
      borderRadius: BorderRadius.circular(14),
      child: Material(
        color: Colors.white.withValues(alpha: 0.14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: Colors.white.withValues(alpha: 0.25)),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: SizedBox(
              width: 50,
              height: 50,
              child: Icon(icon, size: 22, color: Colors.white)),
        ),
      ),
    );
  }
}

class _ContinueRail extends StatelessWidget {
  const _ContinueRail({required this.items, required this.onPlay});
  final List<ContentItem> items;
  final void Function(ContentItem) onPlay;
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 134,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (_, i) {
          final it = items[i];
          return FocusHighlight(
            borderRadius: BorderRadius.circular(14),
            child: SizedBox(
              width: 230,
              height: 130,
              child: Material(
                color: Colors.black,
                clipBehavior: Clip.antiAlias,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
                child: InkWell(
                  onTap: () => onPlay(it),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      RensiKeyArt(item: it),
                      const DecoratedBox(
                          decoration: BoxDecoration(gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: [Color(0xD1000000), Color(0x00000000)],
                        stops: [0.0, 0.6],
                      ))),
                      const Center(
                        child: Icon(Icons.play_circle_outline,
                            size: 44, color: Colors.white),
                      ),
                      Positioned(
                        left: 12,
                        right: 12,
                        bottom: 11,
                        child: Text(
                          it.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontFamily: 'Bricolage Grotesque',
                              fontSize: 14.5,
                              fontWeight: FontWeight.w700,
                              color: Colors.white),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
