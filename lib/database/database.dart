import 'dart:io';
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart' hide Category;
import 'package:rensi_iptv/database/drift_flutter.dart';
import 'package:rensi_iptv/models/category.dart';
import 'package:rensi_iptv/models/content_type.dart';
import 'package:rensi_iptv/models/live_stream.dart';
import 'package:rensi_iptv/models/series.dart';
import 'package:rensi_iptv/models/vod_streams.dart';
import 'package:rensi_iptv/models/server_info.dart';
import 'package:rensi_iptv/models/user_info.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import '../models/category_type.dart';
import '../models/m3u_item.dart';
import '../models/m3u_series.dart';
import '../models/playlist_model.dart';
import '../models/favorite.dart';

part 'database.g.dart';

@DataClassName('PlaylistData')
class Playlists extends Table {
  TextColumn get id => text()();

  TextColumn get name => text()();

  TextColumn get type => text()();

  TextColumn get url => text().nullable()();

  TextColumn get username => text().nullable()();

  TextColumn get password => text().nullable()();

  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('CategoriesData')
class Categories extends Table {
  TextColumn get categoryId => text()();

  TextColumn get categoryName => text()();

  IntColumn get parentId => integer().withDefault(const Constant(0))();

  TextColumn get playlistId => text()();

  TextColumn get type => text()(); // 'live', 'vod', 'series'
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {categoryId, playlistId, type};

  @override
  List<Index> get indexes => [
    Index('idx_categories_playlist_type', 'playlist_id, type'),
  ];
}

@DataClassName('UserInfosData')
class UserInfos extends Table {
  IntColumn get id => integer().autoIncrement()();

  TextColumn get playlistId => text()();

  TextColumn get username => text()();

  TextColumn get password => text()();

  TextColumn get message => text()();

  IntColumn get auth => integer()();

  TextColumn get status => text()();

  TextColumn get expDate => text()();

  TextColumn get isTrial => text()();

  TextColumn get activeCons => text()();

  TextColumn get createdAt => text()();

  TextColumn get maxConnections => text()();

  TextColumn get allowedOutputFormats => text()();
}

@DataClassName('ServerInfosData')
class ServerInfos extends Table {
  IntColumn get id => integer().autoIncrement()();

  TextColumn get playlistId => text()();

  TextColumn get url => text()();

  TextColumn get port => text()();

  TextColumn get httpsPort => text()();

  TextColumn get serverProtocol => text()();

  TextColumn get rtmpPort => text()();

  TextColumn get timezone => text()();

  IntColumn get timestampNow => integer()();

  TextColumn get timeNow => text()();
}

@DataClassName('LiveStreamsData')
class LiveStreams extends Table {
  TextColumn get streamId => text()();

  TextColumn get name => text()();

  TextColumn get streamIcon => text()();

  TextColumn get categoryId => text()();

  TextColumn get epgChannelId => text()();

  TextColumn get playlistId => text()(); // Ekstra property
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {streamId, playlistId};

  @override
  List<Index> get indexes => [
    Index('idx_live_streams_playlist_category', 'playlist_id, category_id'),
  ];
}

@DataClassName('VodStreamsData')
class VodStreams extends Table {
  TextColumn get streamId => text()();

  TextColumn get name => text()();

  TextColumn get streamIcon => text()();

  TextColumn get categoryId => text()();

  TextColumn get rating => text()();

  RealColumn get rating5based => real()();

  TextColumn get containerExtension => text()();

  TextColumn get playlistId => text()();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  TextColumn get genre => text().nullable()();

  TextColumn get youtubeTrailer => text().nullable()();

  // The TMDb id the provider persisted for this movie, when it ships one (in
  // the bulk list or backfilled lazily from get_vod_info). Nullable: existing
  // rows and providers that omit it stay NULL, and search falls back to title
  // matching for them.
  IntColumn get tmdbId => integer().nullable()();

  @override
  Set<Column> get primaryKey => {streamId, playlistId};

  @override
  List<Index> get indexes => [
    Index('idx_vod_streams_playlist_category', 'playlist_id, category_id'),
    Index('idx_vod_streams_playlist_name', 'playlist_id, name'),
  ];
}

@DataClassName('SeriesStreamsData')
class SeriesStreams extends Table {
  TextColumn get seriesId => text()();

  TextColumn get name => text()();

  TextColumn get cover => text().nullable()();

  TextColumn get plot => text().nullable()();

  TextColumn get cast => text().nullable()();

  TextColumn get director => text().nullable()();

  TextColumn get genre => text().nullable()();

  TextColumn get releaseDate => text().nullable()();

  TextColumn get rating => text().nullable()();

  RealColumn get rating5based => real().nullable()();

  TextColumn get youtubeTrailer => text().nullable()();

  TextColumn get episodeRunTime => text().nullable()();

  TextColumn get categoryId => text().nullable()();

  TextColumn get playlistId => text()();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  TextColumn get lastModified => text().nullable()();

  TextColumn get backdropPath => text().nullable()();

  // The TMDb id the provider persisted for this series, when it ships one (in
  // the bulk list or backfilled lazily from get_series_info). Nullable for the
  // same reasons as VodStreams.tmdbId.
  IntColumn get tmdbId => integer().nullable()();

  @override
  Set<Column> get primaryKey => {seriesId, playlistId};

  @override
  List<Index> get indexes => [
    Index('idx_series_streams_playlist_category', 'playlist_id, category_id'),
    Index('idx_series_streams_playlist_name', 'playlist_id, name'),
  ];
}

@DataClassName('SeriesInfosData')
class SeriesInfos extends Table {
  IntColumn get id => integer().autoIncrement()();

  TextColumn get seriesId => text()();

  TextColumn get name => text()();

  TextColumn get cover => text().nullable()();

  TextColumn get plot => text().nullable()();

  TextColumn get cast => text().nullable()();

  TextColumn get director => text().nullable()();

  TextColumn get genre => text().nullable()();

  TextColumn get releaseDate => text().nullable()();

  TextColumn get lastModified => text().nullable()();

  TextColumn get rating => text().nullable()();

  IntColumn get rating5based => integer().nullable()();

  TextColumn get backdropPath => text().nullable()();

  TextColumn get youtubeTrailer => text().nullable()();

  TextColumn get episodeRunTime => text().nullable()();

  TextColumn get categoryId => text().nullable()();

  TextColumn get playlistId => text()();
}

@DataClassName('SeasonsData')
class Seasons extends Table {
  IntColumn get id => integer().autoIncrement()();

  TextColumn get seriesId => text()();

  TextColumn get airDate => text().nullable()();

  IntColumn get episodeCount => integer().nullable()();

  IntColumn get seasonId => integer()();

  TextColumn get name => text()();

  TextColumn get overview => text().nullable()();

  IntColumn get seasonNumber => integer()();

  IntColumn get voteAverage => integer().nullable()();

  TextColumn get cover => text().nullable()();

  TextColumn get coverBig => text().nullable()();

  TextColumn get playlistId => text()();
}

@DataClassName('EpisodesData')
class Episodes extends Table {
  IntColumn get id => integer().autoIncrement()();

  TextColumn get seriesId => text()();

  TextColumn get episodeId => text()();

  IntColumn get episodeNum => integer()();

  TextColumn get title => text()();

  TextColumn get containerExtension => text().nullable()();

  IntColumn get season => integer()();

  TextColumn get customSid => text().nullable()();

  TextColumn get added => text().nullable()();

  TextColumn get directSource => text().nullable()();

  TextColumn get playlistId => text()();

  // Episode Info
  IntColumn get tmdbId => integer().nullable()();

  TextColumn get releasedate => text().nullable()();

  TextColumn get plot => text().nullable()();

  IntColumn get durationSecs => integer().nullable()();

  TextColumn get duration => text().nullable()();

  TextColumn get movieImage => text().nullable()();

  IntColumn get bitrate => integer().nullable()();

  RealColumn get rating => real().nullable()();
}

@DataClassName('WatchHistoriesData')
class WatchHistories extends Table {
  TextColumn get playlistId => text()();

  IntColumn get contentType => intEnum<ContentType>()();

  TextColumn get streamId => text()();

  TextColumn get seriesId => text().nullable()();

  IntColumn get watchDuration => integer().nullable()();

  IntColumn get totalDuration => integer().nullable()();

  DateTimeColumn get lastWatched => dateTime()();

  TextColumn get imagePath => text().nullable()();

  TextColumn get title => text()();

  @override
  Set<Column> get primaryKey => {playlistId, streamId};

  @override
  List<Index> get indexes => [
    Index('idx_watch_histories_playlist_last', 'playlist_id, last_watched'),
  ];
}

@DataClassName('M3uItemData')
class M3uItems extends Table {
  TextColumn get id => text()();

  TextColumn get playlistId => text()();

  TextColumn get url => text()();

  TextColumn get name => text().nullable()();

  TextColumn get tvgId => text().nullable()();

  TextColumn get tvgName => text().nullable()();

  TextColumn get tvgLogo => text().nullable()();

  TextColumn get tvgUrl => text().nullable()();

  TextColumn get tvgRec => text().nullable()();

  TextColumn get tvgShift => text().nullable()();

  TextColumn get groupTitle => text().nullable()();

  TextColumn get groupName => text().nullable()();

  TextColumn get userAgent => text().nullable()();

  TextColumn get referrer => text().nullable()();

  TextColumn get categoryId => text().nullable()();

  IntColumn get contentType => integer()();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<Index> get indexes => [
    Index('idx_m3u_items_playlist_category', 'playlist_id, category_id'),
    Index('idx_m3u_items_playlist_content', 'playlist_id, content_type'),
    Index('idx_m3u_items_playlist_url', 'playlist_id, url'),
  ];

  @override
  List<String> get customConstraints => [
    'CHECK (LENGTH(id) > 0)',
    'CHECK (LENGTH(url) > 0)',
    'CHECK (LENGTH(playlist_id) > 0)',
  ];
}

@DataClassName('M3uSeriesData')
class M3uSeries extends Table {
  TextColumn get playlistId => text()();

  TextColumn get seriesId => text()();

  TextColumn get name => text()();

  TextColumn get categoryId => text().nullable()();

  TextColumn get cover => text().nullable()();

  @override
  Set<Column> get primaryKey => {playlistId, seriesId};
}

@DataClassName('M3uEpisodesData')
class M3uEpisodes extends Table {
  TextColumn get playlistId => text()();

  TextColumn get seriesId => text()();

  IntColumn get seasonNumber => integer()();

  IntColumn get episodeNumber => integer()();

  TextColumn get name => text()();

  TextColumn get url => text()();

  TextColumn get categoryId => text().nullable()();

  TextColumn get cover => text().nullable()();

  @override
  Set<Column> get primaryKey => {
    playlistId,
    seriesId,
    seasonNumber,
    episodeNumber,
  };
}

@DataClassName('FavoritesData')
class Favorites extends Table {
  TextColumn get id => text()();

  TextColumn get playlistId => text()();

  IntColumn get contentType => integer()();

  TextColumn get streamId => text()();

  TextColumn get episodeId => text().nullable()();

  TextColumn get m3uItemId => text().nullable()();

  TextColumn get name => text()();

  TextColumn get imagePath => text().nullable()();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<Index> get indexes => [
    Index('idx_favorites_playlist_content', 'playlist_id, content_type'),
    Index('idx_favorites_lookup', 'playlist_id, stream_id, content_type'),
  ];
}

/// Descargas offline (VOD/series). Una fila por contenido descargado o en cola.
class Downloads extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get contentId => text()(); // stream/episode id de Xtream
  TextColumn get contentType => text()(); // 'vod' | 'series'
  TextColumn get title => text()();
  TextColumn get imagePath => text().withDefault(const Constant(''))();
  TextColumn get filePath => text().nullable()(); // ruta local al completar
  TextColumn get ext => text().nullable()(); // container_extension
  TextColumn get taskId => text().nullable()(); // id de background_downloader
  IntColumn get bytesDownloaded => integer().withDefault(const Constant(0))();
  IntColumn get totalBytes => integer().nullable()();
  TextColumn get status =>
      text().withDefault(const Constant('queued'))(); // queued|downloading|paused|complete|failed
  IntColumn get addedAt => integer()(); // epoch ms
  BoolColumn get watched => boolean().withDefault(const Constant(false))();
  TextColumn get playlistId => text()();
  // Motivo legible del último fallo (null si nunca falló o si ya no aplica
  // tras un reinicio/reintento exitoso). Mostrado en DownloadsScreen.
  TextColumn get error => text().nullable()();
  // URL de origen (Xtream/M3U) usada al encolar. Persistida para poder
  // reintentar una descarga fallida sin depender de que el plugin todavía
  // conserve el DownloadTask original (no lo garantiza una vez 'failed').
  TextColumn get url => text().nullable()();
}

@DriftDatabase(
  tables: [
    Playlists,
    Downloads,
    Categories,
    UserInfos,
    ServerInfos,
    LiveStreams,
    VodStreams,
    SeriesStreams,
    SeriesInfos,
    Seasons,
    Episodes,
    WatchHistories,
    M3uItems,
    M3uSeries,
    M3uEpisodes,
    Favorites,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? e])
    : super(
        e ??
            driftDatabase(
              name: 'rensi-iptv',
              native: const DriftNativeOptions(
                databaseDirectory: getApplicationSupportDirectory,
              ),
              web: DriftWebOptions(
                sqlite3Wasm: Uri.parse('sqlite3.wasm'),
                driftWorker: Uri.parse('drift_worker.js'),
                onResult: (result) {
                  if (result.missingFeatures.isNotEmpty) {
                    debugPrint(
                      'Using ${result.chosenImplementation} due to unsupported '
                      'browser features: ${result.missingFeatures}',
                    );
                  }
                },
              ),
            ),
      );

  @override
  int get schemaVersion => 12;

  // === PLAYLIST İŞLEMLERİ ===

  // Playlist oluştur
  Future<void> insertPlaylist(Playlist playlist) async {
    await into(playlists).insert(
      PlaylistsCompanion(
        id: Value(playlist.id),
        name: Value(playlist.name),
        type: Value(playlist.type.toString()),
        url: Value(playlist.url),
        username: Value(playlist.username),
        password: Value(playlist.password),
        createdAt: Value(playlist.createdAt),
      ),
    );
  }

  // Tüm playlistleri getir
  Future<List<Playlist>> getAllPlaylists() async {
    final playlistData = await select(playlists).get();
    return playlistData.map((data) => _convertToPlaylist(data)).toList();
  }

  // ID'ye göre playlist getir
  Future<Playlist?> getPlaylistById(String id) async {
    final query = select(playlists)..where((p) => p.id.equals(id));
    final result = await query.getSingleOrNull();
    return result != null ? _convertToPlaylist(result) : null;
  }

  // Playlist sil
  Future<void> deletePlaylistById(String id) async {
    await transaction(() async {
      await deleteAllCategoriesByPlaylist(id);
      await deleteAllM3uItems(id);
      await deleteLiveStreamsByPlaylistId(id);
      await deleteVodStreamsByPlaylistId(id);
      await deleteSeriesStreamsByPlaylistId(id);
      await deleteUserInfoByPlaylistId(id);
      await deleteServerInfoByPlaylistId(id);
      // Watch history is keyed by playlistId, not by a foreign key, so nothing
      // reaps it when the playlist goes. Left behind it is both retention of
      // viewing data the user asked to delete and a correctness bug: ids are
      // not globally unique, and a later playlist reusing this one's id
      // resurrects the old rows in the "Continue watching" rail.
      await deleteWatchHistoryByPlaylistId(id);
      // Favourites are the other table holding the user's own choices — names
      // included — keyed the same way, and "Mi lista" reads them by playlistId.
      // Everything the comment above says about watch history applies here
      // verbatim; leaving it out made the cascade look closed while the same
      // hole stayed open in the sibling table.
      await deleteFavoritesByPlaylistId(id);
      // Offline downloads are keyed by playlistId too and were the one branch
      // the cascade forgot: left behind, their rows are dead weight and their
      // files sit on disk forever (both storage and a privacy leak of content
      // the user asked to delete). The on-disk files are removed ahead of this
      // by DownloadService.deleteDownloadsForPlaylist; this reaps the rows and
      // also guards the path where the DB is torn down without that service.
      await deleteDownloadsByPlaylistId(id);
      // Catalogue leftovers: not privacy, but they are dead weight forever and
      // would surface as stale content under a reused playlist id.
      await deleteSeriesInfosByPlaylistId(id);
      await deleteSeasonsByPlaylistId(id);
      await deleteEpisodesByPlaylistId(id);
      await deleteM3uSeriesByPlaylistId(id);
      await deleteM3uEpisodesByPlaylistId(id);
      await (delete(playlists)..where((p) => p.id.equals(id))).go();
    });
  }

  // Playlist güncelle
  Future<void> updatePlaylist(Playlist playlist) async {
    await (update(playlists)..where((p) => p.id.equals(playlist.id))).write(
      PlaylistsCompanion(
        name: Value(playlist.name),
        type: Value(playlist.type.toString()),
        url: Value(playlist.url),
        username: Value(playlist.username),
        password: Value(playlist.password),
      ),
    );
  }

  // Tip filtreleme
  Future<List<Playlist>> getPlaylistsByType(PlaylistType type) async {
    final query = select(playlists)
      ..where((p) => p.type.equals(type.toString()));
    final playlistData = await query.get();
    return playlistData.map((data) => _convertToPlaylist(data)).toList();
  }

  // === KATEGORİ İŞLEMLERİ ===

  // Kategorileri tip ve playlist'e göre getir
  Future<List<Category>> getCategoriesByTypeAndPlaylist(
    String playlistId,
    CategoryType type,
  ) async {
    final categoriesData =
        await (select(categories)..where(
              (tbl) =>
                  tbl.playlistId.equals(playlistId) &
                  tbl.type.equals(type.value),
            ))
            .get();

    return categoriesData.map((cat) => Category.fromDrift(cat)).toList();
  }

  Future<List<Category>> getCategoriesByPlaylist(String playlistId) async {
    final categoriesData = await (select(
      categories,
    )..where((tbl) => tbl.playlistId.equals(playlistId))).get();

    return categoriesData.map((cat) => Category.fromDrift(cat)).toList();
  }

  Future<void> insertCategories(List<Category> categoryList) async {
    await batch((batch) {
      batch.insertAllOnConflictUpdate(
        categories,
        categoryList.map((cat) => cat.toCompanion()).toList(),
      );
    });
  }

  // Belirli tip ve playlist'teki kategorileri sil
  Future<void> deleteCategoriesByTypeAndPlaylist(
    String playlistId,
    CategoryType type,
  ) async {
    await (delete(categories)..where(
          (tbl) =>
              tbl.playlistId.equals(playlistId) & tbl.type.equals(type.value),
        ))
        .go();
  }

  // Playlist'teki tüm kategorileri sil
  Future<void> deleteAllCategoriesByPlaylist(String playlistId) async {
    await (delete(
      categories,
    )..where((tbl) => tbl.playlistId.equals(playlistId))).go();
  }

  // Parent kategorileri getir
  Future<List<Category>> getParentCategories(
    String playlistId,
    CategoryType type,
  ) async {
    final categoriesData =
        await (select(categories)
              ..where(
                (tbl) =>
                    tbl.playlistId.equals(playlistId) &
                    tbl.type.equals(type.value) &
                    tbl.parentId.equals(0),
              )
              ..orderBy([(tbl) => OrderingTerm.asc(tbl.categoryName)]))
            .get();

    return categoriesData.map((cat) => Category.fromDrift(cat)).toList();
  }

  // Alt kategorileri getir
  Future<List<Category>> getSubCategories(
    String playlistId,
    CategoryType type,
    String parentId,
  ) async {
    final categoriesData =
        await (select(categories)
              ..where(
                (tbl) =>
                    tbl.playlistId.equals(playlistId) &
                    tbl.type.equals(type.value) &
                    tbl.parentId.equals(int.parse(parentId)),
              )
              ..orderBy([(tbl) => OrderingTerm.asc(tbl.categoryName)]))
            .get();

    return categoriesData.map((cat) => Category.fromDrift(cat)).toList();
  }

  // Kategori ara
  Future<List<Category>> searchCategories(
    String playlistId,
    CategoryType type,
    String query,
  ) async {
    final categoriesData =
        await (select(categories)
              ..where(
                (tbl) =>
                    tbl.playlistId.equals(playlistId) &
                    tbl.type.equals(type.value) &
                    tbl.categoryName.contains(query),
              )
              ..orderBy([(tbl) => OrderingTerm.asc(tbl.categoryName)]))
            .get();

    return categoriesData.map((cat) => Category.fromDrift(cat)).toList();
  }

  // Kategori sayısını getir
  Future<int> getCategoryCount(String playlistId, CategoryType type) async {
    final result =
        await (select(categories)..where(
              (tbl) =>
                  tbl.playlistId.equals(playlistId) &
                  tbl.type.equals(type.value),
            ))
            .get();

    return result.length;
  }

  // Tüm kategorileri getir (tüm tipler)
  Future<Map<CategoryType, List<Category>>> getAllCategoriesByPlaylist(
    String playlistId,
  ) async {
    final allCategoriesData =
        await (select(categories)
              ..where((tbl) => tbl.playlistId.equals(playlistId))
              ..orderBy([(tbl) => OrderingTerm.asc(tbl.categoryName)]))
            .get();

    final result = <CategoryType, List<Category>>{};

    for (final type in CategoryType.values) {
      result[type] = allCategoriesData
          .where((cat) => cat.type == type.value)
          .map((cat) => Category.fromDrift(cat))
          .toList();
    }

    return result;
  }

  // Playlist'in kategori istatistiklerini getir
  Future<Map<CategoryType, int>> getCategoryStatsByPlaylist(
    String playlistId,
  ) async {
    final result = <CategoryType, int>{};

    for (final type in CategoryType.values) {
      final count = await getCategoryCount(playlistId, type);
      result[type] = count;
    }

    return result;
  }

  // Kategori ID'sine göre tek kategori getir
  Future<Category?> getCategoryById(
    String playlistId,
    String categoryId,
    CategoryType type,
  ) async {
    final query = select(categories)
      ..where(
        (tbl) =>
            tbl.playlistId.equals(playlistId) &
            tbl.categoryId.equals(categoryId) &
            tbl.type.equals(type.value),
      );

    final result = await query.getSingleOrNull();
    return result != null ? Category.fromDrift(result) : null;
  }

  // Kategori var mı kontrol et
  Future<bool> categoryExists(
    String playlistId,
    String categoryId,
    CategoryType type,
  ) async {
    final category = await getCategoryById(playlistId, categoryId, type);
    return category != null;
  }

  // === YARDIMCI METODLAR ===

  // PlaylistData'yı Playlist'e çevir
  Playlist _convertToPlaylist(PlaylistData data) {
    return Playlist(
      id: data.id,
      name: data.name,
      type: PlaylistType.values.firstWhere((e) => e.toString() == data.type),
      url: data.url,
      username: data.username,
      password: data.password,
      createdAt: data.createdAt,
    );
  }

  // === USER INFO İŞLEMLERİ ===

  // UserInfo ekleme/güncelleme (upsert)
  Future<int> insertOrUpdateUserInfo(UserInfo userInfo) async {
    final existingUser = await getUserInfoByPlaylistId(userInfo.playlistId);

    if (existingUser != null) {
      // Güncelle
      return await (update(
        userInfos,
      )..where((tbl) => tbl.playlistId.equals(userInfo.playlistId))).write(
        UserInfosCompanion(
          username: Value(userInfo.username),
          password: Value(userInfo.password),
          message: Value(userInfo.message),
          auth: Value(userInfo.auth),
          status: Value(userInfo.status),
          expDate: Value(userInfo.expDate),
          isTrial: Value(userInfo.isTrial),
          activeCons: Value(userInfo.activeCons),
          createdAt: Value(userInfo.createdAt),
          maxConnections: Value(userInfo.maxConnections),
          allowedOutputFormats: Value(userInfo.allowedOutputFormats.join(',')),
        ),
      );
    } else {
      // Yeni ekle
      return await into(userInfos).insert(
        UserInfosCompanion.insert(
          playlistId: userInfo.playlistId,
          username: userInfo.username,
          password: userInfo.password,
          message: userInfo.message,
          auth: userInfo.auth,
          status: userInfo.status,
          expDate: userInfo.expDate,
          isTrial: userInfo.isTrial,
          activeCons: userInfo.activeCons,
          createdAt: userInfo.createdAt,
          maxConnections: userInfo.maxConnections,
          allowedOutputFormats: userInfo.allowedOutputFormats.join(','),
        ),
      );
    }
  }

  // PlaylistId'ye göre UserInfo getirme
  Future<UserInfo?> getUserInfoByPlaylistId(String playlistId) async {
    final query = select(userInfos)
      ..where((tbl) => tbl.playlistId.equals(playlistId));

    final result = await query.getSingleOrNull();
    if (result == null) return null;

    return UserInfo(
      id: result.id,
      playlistId: result.playlistId,
      username: result.username,
      password: result.password,
      message: result.message,
      auth: result.auth,
      status: result.status,
      expDate: result.expDate,
      isTrial: result.isTrial,
      activeCons: result.activeCons,
      createdAt: result.createdAt,
      maxConnections: result.maxConnections,
      allowedOutputFormats: result.allowedOutputFormats.isNotEmpty
          ? result.allowedOutputFormats.split(',')
          : [],
    );
  }

  // Tüm UserInfo'ları getirme
  Future<List<UserInfo>> getAllUserInfos() async {
    final results = await select(userInfos).get();
    return results
        .map(
          (result) => UserInfo(
            id: result.id,
            playlistId: result.playlistId,
            username: result.username,
            password: result.password,
            message: result.message,
            auth: result.auth,
            status: result.status,
            expDate: result.expDate,
            isTrial: result.isTrial,
            activeCons: result.activeCons,
            createdAt: result.createdAt,
            maxConnections: result.maxConnections,
            allowedOutputFormats: result.allowedOutputFormats.isNotEmpty
                ? result.allowedOutputFormats.split(',')
                : [],
          ),
        )
        .toList();
  }

  // PlaylistId'ye göre UserInfo silme
  Future<int> deleteUserInfoByPlaylistId(String playlistId) async {
    return await (delete(
      userInfos,
    )..where((tbl) => tbl.playlistId.equals(playlistId))).go();
  }

  // === SERVER INFO İŞLEMLERİ ===

  // ServerInfo ekleme/güncelleme (upsert)
  Future<int> insertOrUpdateServerInfo(ServerInfo serverInfo) async {
    final existingServer = await getServerInfoByPlaylistId(
      serverInfo.playlistId,
    );

    if (existingServer != null) {
      // Güncelle
      return await (update(
        serverInfos,
      )..where((tbl) => tbl.playlistId.equals(serverInfo.playlistId))).write(
        ServerInfosCompanion(
          url: Value(serverInfo.url),
          port: Value(serverInfo.port),
          httpsPort: Value(serverInfo.httpsPort),
          serverProtocol: Value(serverInfo.serverProtocol),
          rtmpPort: Value(serverInfo.rtmpPort),
          timezone: Value(serverInfo.timezone),
          timestampNow: Value(serverInfo.timestampNow),
          timeNow: Value(serverInfo.timeNow),
        ),
      );
    } else {
      // Yeni ekle
      return await into(serverInfos).insert(
        ServerInfosCompanion.insert(
          playlistId: serverInfo.playlistId,
          url: serverInfo.url,
          port: serverInfo.port,
          httpsPort: serverInfo.httpsPort,
          serverProtocol: serverInfo.serverProtocol,
          rtmpPort: serverInfo.rtmpPort,
          timezone: serverInfo.timezone,
          timestampNow: serverInfo.timestampNow,
          timeNow: serverInfo.timeNow,
        ),
      );
    }
  }

  // PlaylistId'ye göre ServerInfo getirme
  Future<ServerInfo?> getServerInfoByPlaylistId(String playlistId) async {
    final query = select(serverInfos)
      ..where((tbl) => tbl.playlistId.equals(playlistId));

    final result = await query.getSingleOrNull();
    if (result == null) return null;

    return ServerInfo(
      id: result.id,
      playlistId: result.playlistId,
      url: result.url,
      port: result.port,
      httpsPort: result.httpsPort,
      serverProtocol: result.serverProtocol,
      rtmpPort: result.rtmpPort,
      timezone: result.timezone,
      timestampNow: result.timestampNow,
      timeNow: result.timeNow,
    );
  }

  // Tüm ServerInfo'ları getirme
  Future<List<ServerInfo>> getAllServerInfos() async {
    final results = await select(serverInfos).get();
    return results
        .map(
          (result) => ServerInfo(
            id: result.id,
            playlistId: result.playlistId,
            url: result.url,
            port: result.port,
            httpsPort: result.httpsPort,
            serverProtocol: result.serverProtocol,
            rtmpPort: result.rtmpPort,
            timezone: result.timezone,
            timestampNow: result.timestampNow,
            timeNow: result.timeNow,
          ),
        )
        .toList();
  }

  // PlaylistId'ye göre ServerInfo silme
  Future<int> deleteServerInfoByPlaylistId(String playlistId) async {
    return await (delete(
      serverInfos,
    )..where((tbl) => tbl.playlistId.equals(playlistId))).go();
  }

  // Live Streams
  Future<void> insertLiveStreams(List<LiveStream> liveStreams) async {
    final liveStreamsCompanions = liveStreams
        .map(
          (liveStream) => LiveStreamsCompanion(
            streamId: Value(liveStream.streamId),
            name: Value(liveStream.name),
            streamIcon: Value(liveStream.streamIcon),
            categoryId: Value(liveStream.categoryId),
            epgChannelId: Value(liveStream.epgChannelId),
            playlistId: Value(liveStream.playlistId ?? ''),
          ),
        )
        .toList();

    await batch((batch) {
      batch.insertAllOnConflictUpdate(this.liveStreams, liveStreamsCompanions);
    });
  }

  Future<List<LiveStream>> getLiveStreams(String playlistId) async {
    final rows = await (select(
      liveStreams,
    )..where((ls) => ls.playlistId.equals(playlistId))).get();

    return rows.map((row) => LiveStream.fromDriftLiveStream(row)).toList();
  }

  Future<List<LiveStream>> getLiveStreamsByCategoryId(
    String playlistId,
    String categoryId, {
    int? top,
  }) async {
    var query = select(liveStreams)
      ..where(
        (ls) =>
            ls.playlistId.equals(playlistId) & ls.categoryId.equals(categoryId),
      );

    if (top != null) {
      query = query..limit(top);
    }

    final rows = await query.get();

    return rows.map((row) => LiveStream.fromDriftLiveStream(row)).toList();
  }

  Future<void> deleteWatchHistoryByPlaylistId(String playlistId) async {
    await (delete(
      watchHistories,
    )..where((tbl) => tbl.playlistId.equals(playlistId))).go();
  }

  Future<void> deleteFavoritesByPlaylistId(String playlistId) async {
    await (delete(
      favorites,
    )..where((tbl) => tbl.playlistId.equals(playlistId))).go();
  }

  /// Reaps the `Downloads` rows of a playlist. The `Downloads` table carries a
  /// `playlistId`, but the delete cascade never touched it, so removing a
  /// playlist orphaned both its rows here and (separately) its files on disk.
  /// This closes the rows half; the on-disk files are removed by
  /// `DownloadService.deleteDownloadsForPlaylist`, called ahead of the cascade.
  Future<void> deleteDownloadsByPlaylistId(String playlistId) async {
    await (delete(
      downloads,
    )..where((tbl) => tbl.playlistId.equals(playlistId))).go();
  }

  Future<void> deleteSeriesInfosByPlaylistId(String playlistId) async {
    await (delete(
      seriesInfos,
    )..where((tbl) => tbl.playlistId.equals(playlistId))).go();
  }

  Future<void> deleteSeasonsByPlaylistId(String playlistId) async {
    await (delete(
      seasons,
    )..where((tbl) => tbl.playlistId.equals(playlistId))).go();
  }

  Future<void> deleteEpisodesByPlaylistId(String playlistId) async {
    await (delete(
      episodes,
    )..where((tbl) => tbl.playlistId.equals(playlistId))).go();
  }

  Future<void> deleteM3uSeriesByPlaylistId(String playlistId) async {
    await (delete(
      m3uSeries,
    )..where((tbl) => tbl.playlistId.equals(playlistId))).go();
  }

  Future<void> deleteM3uEpisodesByPlaylistId(String playlistId) async {
    await (delete(
      m3uEpisodes,
    )..where((tbl) => tbl.playlistId.equals(playlistId))).go();
  }

  Future<void> deleteLiveStreamsByPlaylistId(String playlistId) async {
    await (delete(
      liveStreams,
    )..where((ls) => ls.playlistId.equals(playlistId))).go();
  }

  // Vod Streams
  Future<void> insertVodStreams(List<VodStream> vodStreams) async {
    final vodStreamsCompanions = vodStreams
        .map((vodStream) => vodStream.toDriftCompanion())
        .toList();

    await batch((batch) {
      batch.insertAllOnConflictUpdate(this.vodStreams, vodStreamsCompanions);
    });
  }

  Future<List<VodStream>> getVodStreamsByPlaylistId(String playlistId) async {
    final rows = await (select(
      vodStreams,
    )..where((vs) => vs.playlistId.equals(playlistId))).get();

    return rows.map((row) => VodStream.fromDriftVodStream(row)).toList();
  }

  /// Newest [limit] VOD rows for the playlist, ordered by date-added and
  /// limited in SQL. Lets the "View all movies" preview strip avoid loading and
  /// sorting the entire (tens-of-thousands-row) catalogue on the UI isolate.
  Future<List<VodStream>> getRecentVodStreamsByPlaylistId(String playlistId,
      {int limit = 10}) async {
    final rows = await (select(vodStreams)
          ..where((vs) => vs.playlistId.equals(playlistId))
          ..orderBy([(vs) => OrderingTerm.desc(vs.createdAt)])
          ..limit(limit))
        .get();

    return rows.map((row) => VodStream.fromDriftVodStream(row)).toList();
  }

  /// Persist a corrected container extension after the player self-healed a
  /// stale one, so future plays of the same title don't pay the retry cost
  /// again. Best-effort: a no-op if the row is gone.
  Future<void> updateVodStreamContainerExtension(
      String streamId, String playlistId, String extension) async {
    await (update(vodStreams)
          ..where((vs) =>
              vs.streamId.equals(streamId) & vs.playlistId.equals(playlistId)))
        .write(VodStreamsCompanion(containerExtension: Value(extension)));
  }

  /// Backfill the TMDb id on a VOD row once it is learned from get_vod_info, so
  /// global search can reconcile an owned title with its TMDb result by id even
  /// when the localized titles don't string-match. The WHERE clause makes this a
  /// no-op unless the stored value is actually different (null or another id),
  /// so opening a title repeatedly costs at most one write. Best-effort: a no-op
  /// if the row is gone.
  Future<void> updateVodStreamTmdbId(
      String streamId, String playlistId, int tmdbId) async {
    await (update(vodStreams)
          ..where((vs) =>
              vs.streamId.equals(streamId) &
              vs.playlistId.equals(playlistId) &
              (vs.tmdbId.isNull() | vs.tmdbId.equals(tmdbId).not())))
        .write(VodStreamsCompanion(tmdbId: Value(tmdbId)));
  }

  /// Backfill the TMDb id on a series row once it is learned from
  /// get_series_info. Same contract as [updateVodStreamTmdbId].
  Future<void> updateSeriesStreamTmdbId(
      String seriesId, String playlistId, int tmdbId) async {
    await (update(seriesStreams)
          ..where((ss) =>
              ss.seriesId.equals(seriesId) &
              ss.playlistId.equals(playlistId) &
              (ss.tmdbId.isNull() | ss.tmdbId.equals(tmdbId).not())))
        .write(SeriesStreamsCompanion(tmdbId: Value(tmdbId)));
  }

  Future<List<VodStream>> getVodStreamsByCategoryAndPlaylistId({
    required String categoryId,
    required String playlistId,
    int? top,
  }) async {
    var query = select(vodStreams)
      ..where(
        (vs) =>
            vs.categoryId.equals(categoryId) & vs.playlistId.equals(playlistId),
      );

    if (top != null) {
      query = query..limit(top);
    }

    final rows = await query.get();

    return rows.map((row) => VodStream.fromDriftVodStream(row)).toList();
  }

  Future<List<VodStream>> getVodStreamsByCategory(String categoryId) async {
    final rows = await (select(
      vodStreams,
    )..where((vs) => vs.categoryId.equals(categoryId))).get();

    return rows.map((row) => VodStream.fromDriftVodStream(row)).toList();
  }

  Future<List<VodStream>> getVodStreamsFiltered({
    String? categoryId,
    String? playlistId,
    String? searchQuery,
  }) async {
    final query = select(vodStreams);

    if (categoryId != null && playlistId != null) {
      query.where(
        (vs) =>
            vs.categoryId.equals(categoryId) & vs.playlistId.equals(playlistId),
      );
    } else if (categoryId != null) {
      query.where((vs) => vs.categoryId.equals(categoryId));
    } else if (playlistId != null) {
      query.where((vs) => vs.playlistId.equals(playlistId));
    }

    if (searchQuery != null && searchQuery.isNotEmpty) {
      query.where((vs) => vs.name.like('%$searchQuery%'));
    }

    final rows = await query.get();
    return rows.map((row) => VodStream.fromDriftVodStream(row)).toList();
  }

  Future<void> deleteVodStreamsByPlaylistId(String playlistId) async {
    await (delete(
      vodStreams,
    )..where((vs) => vs.playlistId.equals(playlistId))).go();
  }

  Future<void> deleteVodStreamsByCategoryAndPlaylistId({
    required String categoryId,
    required String playlistId,
  }) async {
    await (delete(vodStreams)..where(
          (vs) =>
              vs.categoryId.equals(categoryId) &
              vs.playlistId.equals(playlistId),
        ))
        .go();
  }

  Future<void> insertSeriesStreams(List<SeriesStream> seriesStreams) async {
    final seriesStreamsCompanions = seriesStreams
        .map((seriesStream) => seriesStream.toDriftCompanion())
        .toList();

    await batch((batch) {
      batch.insertAllOnConflictUpdate(
        this.seriesStreams,
        seriesStreamsCompanions,
      );
    });
  }

  Future<List<SeriesStream>> getSeriesStreamsByPlaylistId(
    String playlistId,
  ) async {
    final rows = await (select(
      seriesStreams,
    )..where((ss) => ss.playlistId.equals(playlistId))).get();

    return rows.map((row) => SeriesStream.fromDriftSeriesStream(row)).toList();
  }

  Future<List<SeriesStream>> getSeriesStreamsByCategoryAndPlaylistId({
    required String categoryId,
    required String playlistId,
    int? top,
  }) async {
    var query = select(seriesStreams)
      ..where(
        (ss) =>
            ss.categoryId.equals(categoryId) & ss.playlistId.equals(playlistId),
      );

    if (top != null) {
      query = query..limit(top);
    }

    final rows = await query.get();

    return rows.map((row) => SeriesStream.fromDriftSeriesStream(row)).toList();
  }

  Future<List<SeriesStream>> getSeriesStreamsByCategory(
    String categoryId,
  ) async {
    final rows = await (select(
      seriesStreams,
    )..where((ss) => ss.categoryId.equals(categoryId))).get();

    return rows.map((row) => SeriesStream.fromDriftSeriesStream(row)).toList();
  }

  Future<List<SeriesStream>> getSeriesStreamsFiltered({
    String? categoryId,
    String? playlistId,
    String? searchQuery,
  }) async {
    final query = select(seriesStreams);

    if (categoryId != null && playlistId != null) {
      query.where(
        (ss) =>
            ss.categoryId.equals(categoryId) & ss.playlistId.equals(playlistId),
      );
    } else if (categoryId != null) {
      query.where((ss) => ss.categoryId.equals(categoryId));
    } else if (playlistId != null) {
      query.where((ss) => ss.playlistId.equals(playlistId));
    }

    if (searchQuery != null && searchQuery.isNotEmpty) {
      query.where((ss) => ss.name.like('%$searchQuery%'));
    }

    final rows = await query.get();
    return rows.map((row) => SeriesStream.fromDriftSeriesStream(row)).toList();
  }

  Future<void> deleteSeriesStreamsByPlaylistId(String playlistId) async {
    await (delete(
      seriesStreams,
    )..where((ss) => ss.playlistId.equals(playlistId))).go();
  }

  Future<void> deleteSeriesStreamsByCategoryAndPlaylistId({
    required String categoryId,
    required String playlistId,
  }) async {
    await (delete(seriesStreams)..where(
          (ss) =>
              ss.categoryId.equals(categoryId) &
              ss.playlistId.equals(playlistId),
        ))
        .go();
  }

  // Series Info CRUD Operations
  Future<int> insertSeriesInfo(SeriesInfosCompanion seriesInfo) {
    return into(seriesInfos).insert(seriesInfo);
  }

  Future<SeriesInfosData?> getSeriesInfo(String seriesId, String playlistId) {
    return (select(seriesInfos)..where(
          (tbl) =>
              tbl.seriesId.equals(seriesId) & tbl.playlistId.equals(playlistId),
        ))
        .getSingleOrNull();
  }

  // Seasons CRUD Operations
  Future<int> insertSeason(SeasonsCompanion season) {
    return into(seasons).insert(season);
  }

  Future<List<SeasonsData>> getSeasonsBySeriesId(
    String seriesId,
    String playlistId,
  ) {
    return (select(seasons)..where(
          (tbl) =>
              tbl.seriesId.equals(seriesId) & tbl.playlistId.equals(playlistId),
        ))
        .get();
  }

  // Episodes CRUD Operations
  Future<int> insertEpisode(EpisodesCompanion episode) {
    return into(episodes).insert(episode);
  }

  Future<List<EpisodesData>> getEpisodesBySeriesId(
    String seriesId,
    String playlistId,
  ) {
    // Orden ascendente (temporada, episodio) en la FUENTE: la cola de cast/local
    // y el selector de episodios (series_screen) consumen esto tal cual; sin este
    // ORDER BY llegaban en orden de rowid → el auto-avance por cast no encontraba
    // el "siguiente" y el selector se veía desordenado.
    return (select(episodes)
          ..where(
            (tbl) =>
                tbl.seriesId.equals(seriesId) &
                tbl.playlistId.equals(playlistId),
          )
          ..orderBy([
            (t) => OrderingTerm(expression: t.season),
            (t) => OrderingTerm(expression: t.episodeNum),
          ]))
        .get();
  }

  Future<List<EpisodesData>> getEpisodesBySeason(
    String seriesId,
    int seasonNumber,
    String playlistId,
  ) {
    return (select(episodes)
          ..where(
            (tbl) =>
                tbl.seriesId.equals(seriesId) &
                tbl.season.equals(seasonNumber) &
                tbl.playlistId.equals(playlistId),
          )
          ..orderBy([(t) => OrderingTerm(expression: t.episodeNum)]))
        .get();
  }

  Future<EpisodesData?> findEpisodesById(String episodeId, String playlistId) {
    return (select(episodes)..where(
          (tbl) =>
              tbl.playlistId.equals(playlistId) &
              tbl.episodeId.equals(episodeId),
        ))
        .getSingleOrNull();
  }

  Future<VodStream?> findMovieById(String streamId, String playlistId) async {
    var vodStreamData =
        await (select(vodStreams)..where(
              (tbl) =>
                  tbl.playlistId.equals(playlistId) &
                  tbl.streamId.equals(streamId),
            ))
            .getSingleOrNull();

    return vodStreamData != null
        ? VodStream.fromDriftVodStream(vodStreamData)
        : null;
  }

  /// A single series row by its id within a playlist — the series analogue of
  /// [findMovieById]. Lets a caller (unified "Mi lista" resolving a favourite)
  /// fetch ONE series without reading the whole series table (the old N+1).
  Future<SeriesStream?> findSeriesById(String seriesId, String playlistId) async {
    var row =
        await (select(seriesStreams)..where(
              (ss) =>
                  ss.playlistId.equals(playlistId) &
                  ss.seriesId.equals(seriesId),
            ))
            .getSingleOrNull();

    return row != null ? SeriesStream.fromDriftSeriesStream(row) : null;
  }

  Future<LiveStream?> findLiveStreamById(
    String streamId,
    String playlistId,
  ) async {
    var liveStreamData =
        await (select(liveStreams)..where(
              (tbl) =>
                  tbl.playlistId.equals(playlistId) &
                  tbl.streamId.equals(streamId),
            ))
            .getSingleOrNull();

    return liveStreamData != null
        ? LiveStream.fromDriftLiveStream(liveStreamData)
        : null;
  }

  Future<int> clearSeriesData(String seriesId, String playlistId) async {
    await (delete(episodes)..where(
          (tbl) =>
              tbl.seriesId.equals(seriesId) & tbl.playlistId.equals(playlistId),
        ))
        .go();
    await (delete(seasons)..where(
          (tbl) =>
              tbl.seriesId.equals(seriesId) & tbl.playlistId.equals(playlistId),
        ))
        .go();
    return await (delete(seriesInfos)..where(
          (tbl) =>
              tbl.seriesId.equals(seriesId) & tbl.playlistId.equals(playlistId),
        ))
        .go();
  }

  Future<List<LiveStream>> searchLiveStreams(
    String playlistId,
    String query,
  ) async {
    final liveStreamList =
        await (select(liveStreams)
              ..where(
                (tbl) =>
                    tbl.playlistId.equals(playlistId) &
                    tbl.name.contains(query),
              )
              ..orderBy([(tbl) => OrderingTerm.asc(tbl.name)])
              ..limit(20))
            .get();

    return liveStreamList
        .map((x) => LiveStream.fromDriftLiveStream(x))
        .toList();
  }

  Future<List<VodStream>> searchMovie(String playlistId, String query) async {
    final movieList =
        await (select(vodStreams)
              ..where(
                (tbl) =>
                    tbl.playlistId.equals(playlistId) &
                    tbl.name.contains(query),
              )
              ..orderBy([(tbl) => OrderingTerm.asc(tbl.name)])
              ..limit(20))
            .get();

    return movieList.map((x) => VodStream.fromDriftVodStream(x)).toList();
  }

  Future<List<VodStream>> searchMovieBroad(
    String playlistId,
    String query,
  ) async {
    // An empty query is `LIKE '%%'` — it matches everything and the limit(60)
    // then returns 30 arbitrary alphabetical rows. No caller wants that; it
    // silently misclassified wishlist-browse lookups. Return nothing instead.
    if (query.trim().isEmpty) return const [];
    final movieList =
        await (select(vodStreams)
              ..where(
                (tbl) =>
                    tbl.playlistId.equals(playlistId) &
                    (tbl.name.contains(query) |
                        tbl.genre.contains(query)),
              )
              // A title whose NAME matches must rank ABOVE one that only matches
              // on genre metadata: otherwise a common query that appears in many
              // genres pushes the actual name-match past the limit(60) cap and it
              // vanishes from search. Name-match rows first, then alphabetical.
              ..orderBy([
                (tbl) => OrderingTerm(
                      expression: tbl.name.contains(query),
                      mode: OrderingMode.desc,
                    ),
                (tbl) => OrderingTerm.asc(tbl.name),
              ])
              ..limit(60))
            .get();

    return movieList.map((x) => VodStream.fromDriftVodStream(x)).toList();
  }

  Future<List<SeriesStream>> searchSeriesBroad(
    String playlistId,
    String query,
  ) async {
    // See searchMovieBroad: an empty query would return 30 arbitrary rows.
    if (query.trim().isEmpty) return const [];
    final seriesList =
        await (select(seriesStreams)
              ..where(
                (tbl) =>
                    tbl.playlistId.equals(playlistId) &
                    (tbl.name.contains(query) |
                        tbl.genre.contains(query) |
                        tbl.cast.contains(query) |
                        tbl.director.contains(query)),
              )
              // A title whose NAME matches must rank ABOVE one that only matches
              // via cast / director / genre. "rick" is a substring of countless
              // cast names (Patrick, Frederick, Kendrick…); without this, those
              // metadata-only matches — sorted alphabetically — fill the limit(60)
              // cap and bury the actual owned show ("Rick y Morty"), so searching
              // a common first word found nothing while a rarer word still hit.
              // Name-match rows first, then alphabetical within each group.
              ..orderBy([
                (tbl) => OrderingTerm(
                      expression: tbl.name.contains(query),
                      mode: OrderingMode.desc,
                    ),
                (tbl) => OrderingTerm.asc(tbl.name),
              ])
              ..limit(60))
            .get();

    return seriesList
        .map((x) => SeriesStream.fromDriftSeriesStream(x))
        .toList();
  }

  Future<int> insertM3uItem(M3uItem item) {
    return into(m3uItems).insert(item.toCompanion());
  }

  Future<void> insertM3uItems(List<M3uItem> items) {
    return batch((batch) {
      batch.insertAll(m3uItems, items.map((item) => item.toCompanion()));
    });
  }

  Future<bool> updateM3uItem(M3uItem item) {
    return update(m3uItems).replace(item.toCompanion());
  }

  Future<List<M3uItem>> getM3uItemsByCategoryId(
    String playlistId,
    String categoryId, {
    int? top,
    ContentType? contentType,
  }) async {
    var query = select(m3uItems)
      ..where(
        (ls) =>
            ls.playlistId.equals(playlistId) & ls.categoryId.equals(categoryId),
      );

    if (top != null) {
      query = query..limit(top);
    }

    if (contentType != null) {
      query = query..where((x) => x.contentType.equals(contentType.index));
    }

    final rows = await query.get();

    return rows.map((row) => M3uItem.fromData(row)).toList();
  }

  Future<int> deleteM3uItem(String playlistId, String url) {
    return (delete(m3uItems)..where(
          (tbl) => tbl.playlistId.equals(playlistId) & tbl.url.equals(url),
        ))
        .go();
  }

  Future<int> deleteAllM3uItems(String playlistId) {
    return (delete(
      m3uItems,
    )..where((tbl) => tbl.playlistId.equals(playlistId))).go();
  }

  Future<List<M3uItem>> getM3uItemsByPlaylist(String playlistId) async {
    final data = await (select(
      m3uItems,
    )..where((tbl) => tbl.playlistId.equals(playlistId))).get();
    return data.map((item) => M3uItem.fromData(item)).toList();
  }

  Future<List<M3uItem>> searchM3uItems(
    String playlistId,
    String query, {
    int limit = 15,
  }) async {
    if (query.trim().isEmpty || limit <= 0) return const [];
    final data =
        await (select(m3uItems)
              ..where(
                (tbl) =>
                    tbl.playlistId.equals(playlistId) &
                    (tbl.name.contains(query) |
                        tbl.groupTitle.contains(query)),
              )
              ..orderBy([(tbl) => OrderingTerm.asc(tbl.name)])
              ..limit(limit))
            .get();
    return data.map((item) => M3uItem.fromData(item)).toList();
  }

  Future<M3uItem?> getM3uItemsByIdAndPlaylist(
    String playlistId,
    String id,
  ) async {
    final query = select(m3uItems)
      ..where((tbl) => tbl.id.equals(id) & tbl.playlistId.equals(playlistId));
    final data = await query.getSingleOrNull();

    if (data == null) return null;
    return M3uItem.fromData(data);
  }

  Future<M3uItem?> getM3uItemsByUrlAndPlaylist(
    String playlistId,
    String url,
  ) async {
    final query = select(m3uItems)
      ..where((tbl) => tbl.url.equals(url) & tbl.playlistId.equals(playlistId));
    final data = await query.getSingleOrNull();

    if (data == null) return null;
    return M3uItem.fromData(data);
  }

  Future<List<M3uItem>> getM3uItemsByCategory(String categoryId) async {
    final data = await (select(
      m3uItems,
    )..where((tbl) => tbl.categoryId.equals(categoryId))).get();
    return data.map((item) => M3uItem.fromData(item)).toList();
  }

  Future<List<SeriesStream>> searchSeries(
    String playlistId,
    String query,
  ) async {
    final seriesList =
        await (select(seriesStreams)
              ..where(
                (tbl) =>
                    tbl.playlistId.equals(playlistId) &
                    tbl.name.contains(query),
              )
              ..orderBy([(tbl) => OrderingTerm.asc(tbl.name)])
              ..limit(20))
            .get();

    return seriesList
        .map((x) => SeriesStream.fromDriftSeriesStream(x))
        .toList();
  }

  Future<void> insertM3uSeries(List<M3uSeriesCompanion> seriesList) async {
    await batch((batch) {
      batch.insertAll(m3uSeries, seriesList, mode: InsertMode.insertOrReplace);
    });
  }

  Future<void> insertM3uEpisodes(
    List<M3uEpisodesCompanion> episodesList,
  ) async {
    await batch((batch) {
      batch.insertAll(
        m3uEpisodes,
        episodesList,
        mode: InsertMode.insertOrReplace,
      );
    });
  }

  Future<List<M3uSerie>> getM3uSeriesByCategoryId(
    String playlistId,
    String categoryId, {
    int? top,
  }) async {
    var query = select(m3uSeries)
      ..where(
        (ls) =>
            ls.playlistId.equals(playlistId) & ls.categoryId.equals(categoryId),
      );

    if (top != null) {
      query = query..limit(top);
    }

    final rows = await query.get();

    return rows.map((row) => M3uSerie.fromData(row)).toList();
  }

  Future<List<M3uEpisode>> getM3uEpisodesBySeriesId(
    String playlistId,
    String seriesId,
  ) async {
    var query = select(m3uEpisodes)
      ..where(
        (ls) => ls.playlistId.equals(playlistId) & ls.seriesId.equals(seriesId),
      );

    final rows = await query.get();

    return rows.map((row) => M3uEpisode.fromData(row)).toList();
  }

  Future<void> insertFavorite(Favorite favorite) async {
    await into(favorites).insert(favorite.toCompanion());
  }

  Future<void> updateFavorite(Favorite favorite) async {
    await (update(
      favorites,
    )..where((f) => f.id.equals(favorite.id))).write(favorite.toCompanion());
  }

  Future<void> deleteFavorite(String id) async {
    await (delete(favorites)..where((f) => f.id.equals(id))).go();
  }

  Future<List<Favorite>> getAllFavorites() async {
    final favoritesData = await select(favorites).get();
    return favoritesData.map((data) => Favorite.fromDrift(data)).toList();
  }

  /// UNSCOPED favourites across EVERY playlist, newest first. Backs the unified
  /// "Mi lista" READ (favourites are one list across all the user's playlists);
  /// writes/toggles stay playlist-scoped via [getFavoritesByPlaylist]. Ordered
  /// by `createdAt desc` — the plain [getAllFavorites] above has no ORDER BY, so
  /// the list would otherwise arrive in SQLite's rowid order, not most-recent.
  Future<List<Favorite>> getAllFavoritesAcrossPlaylists() async {
    final query = select(favorites)
      ..orderBy([(f) => OrderingTerm.desc(f.createdAt)]);
    final favoritesData = await query.get();
    return favoritesData.map((data) => Favorite.fromDrift(data)).toList();
  }

  Future<List<Favorite>> getFavoritesByPlaylist(String playlistId) async {
    final query = select(favorites)
      ..where((f) => f.playlistId.equals(playlistId))
      ..orderBy([(f) => OrderingTerm.desc(f.createdAt)]);
    final favoritesData = await query.get();
    return favoritesData.map((data) => Favorite.fromDrift(data)).toList();
  }

  Future<List<Favorite>> getFavoritesByContentType(
    String playlistId,
    ContentType contentType,
  ) async {
    final query = select(favorites)
      ..where(
        (f) =>
            f.playlistId.equals(playlistId) &
            f.contentType.equals(contentType.index),
      )
      ..orderBy([(f) => OrderingTerm.desc(f.createdAt)]);
    final favoritesData = await query.get();
    return favoritesData.map((data) => Favorite.fromDrift(data)).toList();
  }

  Future<bool> isFavorite(
    String playlistId,
    String streamId,
    ContentType contentType,
    String? episodeId,
  ) async {
    final query = select(favorites)
      ..where(
        (f) =>
            f.playlistId.equals(playlistId) &
            f.streamId.equals(streamId) &
            f.contentType.equals(contentType.index) &
            (episodeId == null
                ? f.episodeId.isNull()
                : f.episodeId.equals(episodeId)),
      );
    final result = await query.getSingleOrNull();
    return result != null;
  }

  // Favori sayısını getir
  Future<int> getFavoriteCount(String playlistId) async {
    final query = select(favorites)
      ..where((f) => f.playlistId.equals(playlistId));
    final result = await query.get();
    return result.length;
  }

  // İçerik tipine göre favori sayısını getir
  Future<int> getFavoriteCountByContentType(
    String playlistId,
    ContentType contentType,
  ) async {
    final query = select(favorites)
      ..where(
        (f) =>
            f.playlistId.equals(playlistId) &
            f.contentType.equals(contentType.index),
      );
    final result = await query.get();
    return result.length;
  }

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (Migrator m) async {
      await m.createAll();
    },
    onUpgrade: (Migrator m, int from, int to) async {
      // Atomicidad: Drift 2.29 NO envuelve onUpgrade en una transacción. Sin
      // esto, si el proceso muere entre dos pasos (p.ej. entre dos addColumn),
      // al reabrir se re-ejecuta un paso ya aplicado y — como `addColumn` es un
      // `ALTER TABLE ADD COLUMN` crudo, no idempotente — lanza "duplicate
      // column" y deja el equipo "bricked" permanentemente. Envolver todo el
      // cuerpo en una transacción hace que un fallo parcial haga ROLLBACK (SQLite
      // sí revierte DDL), de modo que un reintento parte de un estado limpio y
      // vuelve a intentar la migración completa. `createTable` ya es
      // `CREATE TABLE IF NOT EXISTS` (idempotente); los `addColumn` se hacen
      // idempotentes vía [_addColumnIfMissing] como defensa en profundidad.
      await transaction(() async {
        if (from <= 2) {
          await m.createTable(categories);
          await m.createTable(userInfos);
          await m.createTable(serverInfos);
          await m.createTable(liveStreams);
          // vod_streams / series_streams se crean aquí con la DDL ACTUAL, que YA
          // incluye genre/youtube_trailer/tmdb_id (vod) y tmdb_id (series). Los
          // addColumn de from<=8 y from<10 volverían a añadir esas columnas y
          // lanzarían "duplicate column" — por eso van vía _addColumnIfMissing.
          await m.createTable(vodStreams);
          await m.createTable(seriesStreams);
          // await m.addColumn(seriesStreams, seriesStreams.lastModified);
          // await m.addColumn(seriesStreams, seriesStreams.backdropPath);
          await customStatement('''
            UPDATE series_streams
            SET last_modified = '0', backdrop_path = '[]'
            WHERE last_modified IS NULL OR backdrop_path IS NULL
          ''');
          await m.createTable(seriesInfos);
          await m.createTable(seasons);
          await m.createTable(episodes);
          await m.createTable(watchHistories);
        }

        if (from <= 3) {
          await customStatement('''
              UPDATE playlists
              SET type = 'PlaylistType.xtream'
              WHERE type = 'PlaylistType.xstream'
            ''');
        }

        if (from <= 4) {
          await m.createTable(m3uItems);
        }

        if (from <= 5) {
          await m.createTable(m3uSeries);
          await m.createTable(m3uEpisodes);
        }

        if (from <= 6) {
          await m.deleteTable('m3u_items');
          await m.createTable(m3uItems);
        }

        if (from <= 7) {
          await m.createTable(favorites);
        }

        if (from <= 8) {
          await _addColumnIfMissing(m, vodStreams, vodStreams.genre);
          await _addColumnIfMissing(m, vodStreams, vodStreams.youtubeTrailer);
        }

        if (from <= 8) {
          await _createPerformanceIndexes();
        }

        if (from < 10) {
          // Additive, backward compatible: a nullable tmdb_id on VOD and series.
          // Existing rows land NULL and search falls back to title matching until
          // each title is opened (lazy backfill) or the next catalogue sync fills
          // it from the bulk list. No data is touched or lost.
          await _addColumnIfMissing(m, vodStreams, vodStreams.tmdbId);
          await _addColumnIfMissing(m, seriesStreams, seriesStreams.tmdbId);
        }

        if (from <= 10) {
          // Descargas offline (feat/downloads): tabla aditiva, sin tocar datos.
          // `createTable` es CREATE TABLE IF NOT EXISTS, así que crea la tabla
          // con su DDL actual (que ya incluye error/url); el bloque from<=11 de
          // abajo es entonces un no-op idempotente para este camino, y para una
          // BD ya en esquema 11 (donde este bloque no corre) sí añade error/url.
          await m.createTable(downloads);
        }

        if (from <= 11) {
          // Hardening de descargas offline: motivo de fallo (para mostrar en
          // DownloadsScreen) y URL de origen (para poder reintentar sin
          // depender de que el plugin retenga el DownloadTask original).
          // Ambas aditivas y nullable: filas existentes quedan en NULL.
          await _addColumnIfMissing(m, downloads, downloads.error);
          await _addColumnIfMissing(m, downloads, downloads.url);
        }
      });
    },
    beforeOpen: (_) async {
      await _createPerformanceIndexes();
    },
  );

  /// Idempotent [Migrator.addColumn]: adds [column] to [table] only when it is
  /// not already present. Drift's raw `addColumn` is a plain
  /// `ALTER TABLE ADD COLUMN` that throws "duplicate column name" when the
  /// column already exists — which happens on two real paths in this app:
  ///  1. A table created by `m.createTable(...)` on a very old upgrade path uses
  ///     the CURRENT Drift DDL, which already carries columns that a LATER
  ///     `addColumn` step then tries to add again (e.g. vod_streams created at
  ///     from<=2 already has `genre`, yet from<=8 adds `genre`).
  ///  2. onUpgrade is re-run after a crash between two steps (Drift 2.29 does
  ///     not wrap onUpgrade in a transaction of its own; the explicit
  ///     [transaction] above mitigates this, and this guard is the belt to that
  ///     suspenders).
  /// Guarding on `PRAGMA table_info` turns every addColumn into a safe no-op in
  /// those cases while still applying genuinely-missing columns.
  Future<void> _addColumnIfMissing(
    Migrator m,
    TableInfo table,
    GeneratedColumn column,
  ) async {
    final info =
        await customSelect('PRAGMA table_info(${table.actualTableName})').get();
    final exists =
        info.any((row) => row.read<String>('name') == column.$name);
    if (!exists) {
      await m.addColumn(table, column);
    }
  }

  Future<void> _createPerformanceIndexes() async {
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_categories_playlist_type '
      'ON categories (playlist_id, type)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_live_streams_playlist_category '
      'ON live_streams (playlist_id, category_id)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_vod_streams_playlist_category '
      'ON vod_streams (playlist_id, category_id)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_vod_streams_playlist_name '
      'ON vod_streams (playlist_id, name)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_series_streams_playlist_category '
      'ON series_streams (playlist_id, category_id)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_series_streams_playlist_name '
      'ON series_streams (playlist_id, name)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_watch_histories_playlist_last '
      'ON watch_histories (playlist_id, last_watched)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_m3u_items_playlist_category '
      'ON m3u_items (playlist_id, category_id)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_m3u_items_playlist_content '
      'ON m3u_items (playlist_id, content_type)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_m3u_items_playlist_url '
      'ON m3u_items (playlist_id, url)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_favorites_playlist_content '
      'ON favorites (playlist_id, content_type)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_favorites_lookup '
      'ON favorites (playlist_id, stream_id, content_type)',
    );
  }

  Future<void> deleteDatabase() async {
    await close();
    final dbFolder = await getApplicationDocumentsDirectory();
    final file = File(p.join(dbFolder.path, 'playlists.sqlite'));

    if (await file.exists()) {
      await file.delete();
    }
  }
}
