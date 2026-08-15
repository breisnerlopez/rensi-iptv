// Seeds the in-memory DB so an Xtream home renders populated (no network).
import 'package:drift/drift.dart' show Value;
import 'package:rensi_iptv/database/database.dart';
import 'package:rensi_iptv/models/category.dart';
import 'package:rensi_iptv/models/category_type.dart';
import 'package:rensi_iptv/models/live_stream.dart';
import 'package:rensi_iptv/models/playlist_model.dart';
import 'package:rensi_iptv/models/series.dart';
import 'package:rensi_iptv/models/vod_streams.dart';

Future<Playlist> seedXtreamHome(AppDatabase db) async {
  final playlist = Playlist(
    id: 'test-playlist-1',
    name: 'Test Xtream',
    type: PlaylistType.xtream,
    url: 'http://example.test',
    username: 'testuser',
    password: 'testpass',
    createdAt: DateTime(2026, 1, 1),
  );
  await db.insertPlaylist(playlist);

  final liveCats = [
    Category(categoryId: 'live_1', categoryName: 'Deportes', parentId: 0, playlistId: playlist.id, type: CategoryType.live),
    Category(categoryId: 'live_2', categoryName: 'Noticias', parentId: 0, playlistId: playlist.id, type: CategoryType.live),
    Category(categoryId: 'live_3', categoryName: 'Entretenimiento', parentId: 0, playlistId: playlist.id, type: CategoryType.live),
  ];
  final vodCats = [
    Category(categoryId: 'vod_1', categoryName: 'Acción', parentId: 0, playlistId: playlist.id, type: CategoryType.vod),
    Category(categoryId: 'vod_2', categoryName: 'Comedia', parentId: 0, playlistId: playlist.id, type: CategoryType.vod),
    Category(categoryId: 'vod_3', categoryName: 'Terror', parentId: 0, playlistId: playlist.id, type: CategoryType.vod),
  ];
  final seriesCats = [
    Category(categoryId: 'series_1', categoryName: 'Drama', parentId: 0, playlistId: playlist.id, type: CategoryType.series),
    Category(categoryId: 'series_2', categoryName: 'Ciencia Ficción', parentId: 0, playlistId: playlist.id, type: CategoryType.series),
  ];
  await db.insertCategories([...liveCats, ...vodCats, ...seriesCats]);

  final liveNames = {
    'live_1': ['ESPN', 'ESPN 2', 'Fox Sports', 'TNT Sports', 'DAZN', 'beIN Sports'],
    'live_2': ['CNN', 'CNN en Español', 'BBC News', 'Fox News', 'France 24', 'Al Jazeera'],
    'live_3': ['HBO', 'HBO 2', 'FX', 'AMC', 'Comedy Central', 'MTV', 'E!'],
  };
  final liveStreams = <LiveStream>[];
  liveNames.forEach((catId, names) {
    for (var i = 0; i < names.length; i++) {
      liveStreams.add(LiveStream(
        streamId: '${catId}_stream_$i',
        name: names[i],
        streamIcon: '',
        categoryId: catId,
        epgChannelId: '${catId}_epg_$i',
        playlistId: playlist.id,
      ));
    }
  });
  await db.insertLiveStreams(liveStreams);

  final vodNames = {
    'vod_1': ['Mad Max: Fury Road', 'John Wick', 'Duro de Matar', 'Misión Imposible', 'The Matrix', 'Máxima Velocidad'],
    'vod_2': ['Superbad', '¿Qué Pasó Ayer?', 'El Reportero', 'Hermanastros', 'Dos Tontos', 'Ted'],
    'vod_3': ['El Conjuro', 'Hereditary', 'It', 'Insidious', 'El Exorcista', 'Get Out', 'Nosotros'],
  };
  final vodStreams = <VodStream>[];
  vodNames.forEach((catId, names) {
    for (var i = 0; i < names.length; i++) {
      vodStreams.add(VodStream(
        streamId: '${catId}_movie_$i',
        name: names[i],
        streamIcon: '',
        categoryId: catId,
        rating: '8.0',
        rating5based: 4.0,
        containerExtension: 'mp4',
        playlistId: playlist.id,
        createdAt: DateTime(2026, 1, 1).subtract(Duration(days: i)),
        genre: 'Acción',
      ));
    }
  });
  await db.insertVodStreams(vodStreams);

  final seriesNames = {
    'series_1': ['Breaking Bad', 'The Wire', 'Succession', 'The Crown', 'Better Call Saul'],
    'series_2': ['Stranger Things', 'The Expanse', 'Black Mirror', 'Westworld', 'Foundation'],
  };
  final seriesStreams = <SeriesStream>[];
  seriesNames.forEach((catId, names) {
    for (var i = 0; i < names.length; i++) {
      seriesStreams.add(SeriesStream(
        playlistId: playlist.id,
        seriesId: '${catId}_series_$i',
        name: names[i],
        cover: '',
        categoryId: catId,
        rating: '9.0',
        rating5based: 4.5,
        genre: 'Drama',
        lastModified: DateTime(2026, 1, 1).subtract(Duration(days: i)).millisecondsSinceEpoch.toString(),
      ));
    }
  });
  await db.insertSeriesStreams(seriesStreams);

  return playlist;
}

/// Seeds a catch-up-capable live channel (tv_archive>0) plus a small EPG for it:
/// one PAST programme (replayable from archive), one LIVE now, one FUTURE
/// (reminder-eligible). Times are relative to [now] so the guide's now/past/
/// future logic is exercised deterministically. Returns the channel's stream id.
Future<String> seedEpgAndArchiveChannel(
  AppDatabase db,
  Playlist playlist, {
  DateTime? now,
}) async {
  final base = now ?? DateTime.now();
  const chId = 'archive_epg_1';
  const streamId = 'live_1_archive';

  await db.insertLiveStreams([
    LiveStream(
      streamId: streamId,
      name: 'Canal Archivo',
      streamIcon: '',
      categoryId: 'live_1',
      epgChannelId: chId,
      playlistId: playlist.id,
      tvArchive: 1,
      tvArchiveDuration: 7,
    ),
  ]);

  await db.replaceEpgForPlaylist(playlist.id, [
    // PAST: fully aired → catch-up "play from start".
    EpgProgramsCompanion.insert(
      channelId: chId,
      playlistId: playlist.id,
      start: base.subtract(const Duration(hours: 2)),
      stop: base.subtract(const Duration(hours: 1)),
      title: 'Programa Pasado',
      description: const Value('Emitido hace un rato'),
    ),
    // LIVE: airing now → highlighted; also catch-up-from-start eligible.
    EpgProgramsCompanion.insert(
      channelId: chId,
      playlistId: playlist.id,
      start: base.subtract(const Duration(minutes: 20)),
      stop: base.add(const Duration(minutes: 40)),
      title: 'Programa En Vivo',
      description: const Value('Ahora mismo'),
    ),
    // FUTURE: reminder-eligible.
    EpgProgramsCompanion.insert(
      channelId: chId,
      playlistId: playlist.id,
      start: base.add(const Duration(hours: 1)),
      stop: base.add(const Duration(hours: 2)),
      title: 'Programa Futuro',
      description: const Value('Más tarde'),
    ),
  ]);

  return streamId;
}
