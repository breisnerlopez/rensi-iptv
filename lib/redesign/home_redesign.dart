import 'package:flutter/material.dart';
import 'package:rensi_iptv/l10n/localization_extension.dart';
import 'package:rensi_iptv/models/all_category_sentinel.dart';
import 'package:rensi_iptv/models/category_type.dart';
import 'package:rensi_iptv/models/category_view_model.dart';
import 'package:rensi_iptv/models/playlist_content_model.dart';
import 'package:rensi_iptv/redesign/rensi_widgets.dart';
import 'package:rensi_iptv/repositories/favorites_repository.dart';
import 'package:rensi_iptv/utils/app_themes.dart';
import 'package:rensi_iptv/widgets/tv/focus_highlight.dart';

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
  });

  final List<CategoryViewModel> movieCategories;
  final List<CategoryViewModel> seriesCategories;
  final List<ContentItem> continueItems;
  final void Function(ContentItem) onOpen;
  final void Function(ContentItem) onPlay;
  final VoidCallback? onSearch;
  final VoidCallback? onSettings;

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
    final rails = <Widget>[];

    if (continueItems.isNotEmpty) {
      rails
        ..add(SectionHeader(title: context.loc.history))
        ..add(_ContinueRail(items: continueItems, onPlay: onPlay))
        ..add(const SizedBox(height: 26));
    }

    void addRails(List<CategoryViewModel> cats) {
      for (final c in cats) {
        if (c.contentItems.isEmpty) continue;
        rails
          ..add(SectionHeader(title: _railTitle(context, c)))
          ..add(RensiRail(
            children: [
              for (final it in c.contentItems.take(18))
                RensiPoster(item: it, onTap: () => onOpen(it)),
            ],
          ))
          ..add(const SizedBox(height: 26));
      }
    }

    addRails(movieCategories);
    addRails(seriesCategories);

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: ListView(
        padding: const EdgeInsets.only(bottom: 18),
        children: [
          _TopBar(onSearch: onSearch, onSettings: onSettings),
          if (hero != null) _Hero(item: hero, onOpen: onOpen, onPlay: onPlay),
          const SizedBox(height: 8),
          ...rails,
          if (rails.isEmpty)
            Padding(
              padding: const EdgeInsets.all(40),
              child: Center(
                child: Text('—', style: TextStyle(color: r.text3)),
              ),
            ),
        ],
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({this.onSearch, this.onSettings});
  final VoidCallback? onSearch;
  final VoidCallback? onSettings;
  @override
  Widget build(BuildContext context) {
    final r = rensi(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Buenas noches',
                  style: TextStyle(
                      fontSize: 12.5, fontWeight: FontWeight.w600, color: r.text3)),
              const Text('Rensi',
                  style: TextStyle(
                      fontFamily: 'Bricolage Grotesque',
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.4)),
            ],
          ),
          Row(
            children: [
              _IconBtn(icon: Icons.search, onTap: onSearch),
              const SizedBox(width: 10),
              FocusHighlight(
                borderRadius: BorderRadius.circular(12),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: onSettings,
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        gradient: LinearGradient(colors: [r.accent, r.accent2]),
                      ),
                      child: const Center(
                        child: Text('A',
                            style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                                fontSize: 15)),
                      ),
                    ),
                  ),
                ),
              ),
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
  const _Hero({required this.item, required this.onOpen, required this.onPlay});
  final ContentItem item;
  final void Function(ContentItem) onOpen;
  final void Function(ContentItem) onPlay;

  @override
  Widget build(BuildContext context) {
    final r = rensi(context);
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      height: 440,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: r.hairline),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          RensiKeyArt(item: item),
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
          Positioned(
            left: 18,
            right: 18,
            bottom: 18,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
                  ),
                  child: const Text('★ DESTACADO HOY',
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.5,
                          color: Colors.white)),
                ),
                Text(
                  item.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: 'Bricolage Grotesque',
                    fontSize: 32,
                    fontWeight: FontWeight.w800,
                    height: 0.98,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 10),
                _HeroMeta(item: item),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: () => onPlay(item),
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: Colors.black,
                          minimumSize: const Size(0, 50),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14)),
                        ),
                        icon: const Icon(Icons.play_arrow_rounded, size: 22),
                        label: const Text('Reproducir',
                            style: TextStyle(
                                fontSize: 15.5, fontWeight: FontWeight.w700)),
                      ),
                    ),
                    const SizedBox(width: 10),
                    _GlassBtn(icon: Icons.info_outline, onTap: () => onOpen(item)),
                    const SizedBox(width: 10),
                    _FavBtn(item: item),
                  ],
                ),
              ],
            ),
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
                fontSize: 13,
                fontWeight: FontWeight.w600)),
      ]));
    }
    if (genre != null && genre.isNotEmpty) {
      parts.add(Text(genre.split(',').first.trim(),
          style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 13)));
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
