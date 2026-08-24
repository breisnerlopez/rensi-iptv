import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:rensi_iptv/database/database.dart';
import 'package:rensi_iptv/models/playlist_content_model.dart';
import 'package:rensi_iptv/models/watch_history.dart';
import '../../../models/content_type.dart';
import '../../../services/event_bus.dart';
import '../../../widgets/loading_widget.dart';
import '../../../widgets/player_widget.dart';

class EpisodeScreen extends StatefulWidget {
  final SeriesInfosData? seriesInfo;
  final List<SeasonsData> seasons;
  final List<EpisodesData> episodes;
  final ContentItem contentItem;
  final WatchHistory? watchHistory;

  const EpisodeScreen({
    super.key,
    required this.seriesInfo,
    required this.seasons,
    required this.episodes,
    required this.contentItem,
    this.watchHistory,
  });

  @override
  State<EpisodeScreen> createState() => _EpisodeScreenState();
}

class _EpisodeScreenState extends State<EpisodeScreen> {
  late ContentItem contentItem;
  List<ContentItem> allContents = [];
  bool allContentsLoaded = false;
  int selectedContentItemIndex = 0;
  late StreamSubscription contentItemIndexChangedSubscription;

  @override
  void initState() {
    super.initState();
    contentItem = widget.contentItem;
    _hideSystemUI();
    _initializeQueue();
  }

  @override
  void dispose() {
    contentItemIndexChangedSubscription.cancel();
    _showSystemUI();
    super.dispose();
  }

  void _hideSystemUI() {
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.immersiveSticky,
      overlays: [],
    );
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
      ),
    );
  }

  void _showSystemUI() {
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.edgeToEdge,
      overlays: SystemUiOverlay.values,
    );
  }

  Future<void> _initializeQueue() async {
    // Tüm sezonların tüm bölümlerini ekle (sadece mevcut sezonu değil).
    // Ordenar ASCENDENTE por (temporada, episodio): el auto-avance —tanto el
    // local como, sobre todo, el del CASTING (`_onCompleted` avanza a
    // `_index+1`)— sigue el orden de esta cola. Si la API/BD devuelve los
    // episodios desordenados (p. ej. el E01 al final del array), `_index+1`
    // caería fuera de rango y la serie "no continuaría" en la TV. Ordenar aquí
    // garantiza E01→E02→… en todas las temporadas.
    final ordered = [...widget.episodes]
      ..sort((a, b) {
        final s = a.season.compareTo(b.season);
        return s != 0 ? s : a.episodeNum.compareTo(b.episodeNum);
      });
    allContents = ordered
        .map((x) {
      return ContentItem(
        x.episodeId,
        x.title,
        x.movieImage ?? "",
        ContentType.series,
        containerExtension: x.containerExtension,
        season: x.season,
        seriesId: x.seriesId,
      );
    })
        .toList();

    setState(() {
      selectedContentItemIndex = allContents.indexWhere(
            (element) => element.id == widget.contentItem.id,
      );
      allContentsLoaded = true;
    });

    contentItemIndexChangedSubscription = EventBus()
        .on<int>('player_content_item_index')
        .listen((int index) {
      if (!mounted) return;

      setState(() {
        selectedContentItemIndex = index;
        contentItem = allContents[selectedContentItemIndex];
      });
    });
  }


  @override
  Widget build(BuildContext context) {
    if (!allContentsLoaded) {
      return buildFullScreenLoadingWidget(context);
    } else {
      return Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: SizedBox.expand(
            child: PlayerWidget(contentItem: widget.contentItem, queue: allContents),
          ),
        ),
      );
    }
  }

}