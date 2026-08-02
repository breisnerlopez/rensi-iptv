import 'dart:ffi';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:rensi_iptv/database/database.dart';
import 'package:rensi_iptv/models/content_type.dart';
import 'package:rensi_iptv/models/watch_history.dart';
import 'package:sqlite3/open.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:path/path.dart' as p;
import 'package:flutter_test/flutter_test.dart';

// Faithful historical DDL, derived by dumping the current Drift schema and
// removing the columns/tables added AFTER the target version (see the migration
// map in database.dart onUpgrade):
//   - tmdb_id (vod_streams, series_streams) added at v10  -> absent v3/v6/v9
//   - vod_streams.genre / youtube_trailer   added at v9   -> absent v3/v6, present v9
//   - favorites table                       added at v8   -> absent v3/v6, present v9
//   - m3u_items                             added at v5, DROP+recreate at v6->v7
//   - downloads table                       added at v11  -> absent v3/v6/v9

const _ddlPlaylists =
    'CREATE TABLE "playlists" ("id" TEXT NOT NULL, "name" TEXT NOT NULL, "type" TEXT NOT NULL, "url" TEXT NULL, "username" TEXT NULL, "password" TEXT NULL, "created_at" INTEGER NOT NULL, PRIMARY KEY ("id"))';

const _ddlCategories =
    'CREATE TABLE "categories" ("category_id" TEXT NOT NULL, "category_name" TEXT NOT NULL, "parent_id" INTEGER NOT NULL DEFAULT 0, "playlist_id" TEXT NOT NULL, "type" TEXT NOT NULL, "created_at" INTEGER NOT NULL DEFAULT (CAST(strftime(\'%s\', CURRENT_TIMESTAMP) AS INTEGER)), "updated_at" INTEGER NOT NULL DEFAULT (CAST(strftime(\'%s\', CURRENT_TIMESTAMP) AS INTEGER)), PRIMARY KEY ("category_id", "playlist_id", "type"))';

const _ddlUserInfos =
    'CREATE TABLE "user_infos" ("id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, "playlist_id" TEXT NOT NULL, "username" TEXT NOT NULL, "password" TEXT NOT NULL, "message" TEXT NOT NULL, "auth" INTEGER NOT NULL, "status" TEXT NOT NULL, "exp_date" TEXT NOT NULL, "is_trial" TEXT NOT NULL, "active_cons" TEXT NOT NULL, "created_at" TEXT NOT NULL, "max_connections" TEXT NOT NULL, "allowed_output_formats" TEXT NOT NULL)';

const _ddlServerInfos =
    'CREATE TABLE "server_infos" ("id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, "playlist_id" TEXT NOT NULL, "url" TEXT NOT NULL, "port" TEXT NOT NULL, "https_port" TEXT NOT NULL, "server_protocol" TEXT NOT NULL, "rtmp_port" TEXT NOT NULL, "timezone" TEXT NOT NULL, "timestamp_now" INTEGER NOT NULL, "time_now" TEXT NOT NULL)';

const _ddlLiveStreams =
    'CREATE TABLE "live_streams" ("stream_id" TEXT NOT NULL, "name" TEXT NOT NULL, "stream_icon" TEXT NOT NULL, "category_id" TEXT NOT NULL, "epg_channel_id" TEXT NOT NULL, "playlist_id" TEXT NOT NULL, "created_at" INTEGER NOT NULL DEFAULT (CAST(strftime(\'%s\', CURRENT_TIMESTAMP) AS INTEGER)), PRIMARY KEY ("stream_id", "playlist_id"))';

const _ddlSeriesInfos =
    'CREATE TABLE "series_infos" ("id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, "series_id" TEXT NOT NULL, "name" TEXT NOT NULL, "cover" TEXT NULL, "plot" TEXT NULL, "cast" TEXT NULL, "director" TEXT NULL, "genre" TEXT NULL, "release_date" TEXT NULL, "last_modified" TEXT NULL, "rating" TEXT NULL, "rating5based" INTEGER NULL, "backdrop_path" TEXT NULL, "youtube_trailer" TEXT NULL, "episode_run_time" TEXT NULL, "category_id" TEXT NULL, "playlist_id" TEXT NOT NULL)';

const _ddlSeasons =
    'CREATE TABLE "seasons" ("id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, "series_id" TEXT NOT NULL, "air_date" TEXT NULL, "episode_count" INTEGER NULL, "season_id" INTEGER NOT NULL, "name" TEXT NOT NULL, "overview" TEXT NULL, "season_number" INTEGER NOT NULL, "vote_average" INTEGER NULL, "cover" TEXT NULL, "cover_big" TEXT NULL, "playlist_id" TEXT NOT NULL)';

const _ddlEpisodes =
    'CREATE TABLE "episodes" ("id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, "series_id" TEXT NOT NULL, "episode_id" TEXT NOT NULL, "episode_num" INTEGER NOT NULL, "title" TEXT NOT NULL, "container_extension" TEXT NULL, "season" INTEGER NOT NULL, "custom_sid" TEXT NULL, "added" TEXT NULL, "direct_source" TEXT NULL, "playlist_id" TEXT NOT NULL, "tmdb_id" INTEGER NULL, "releasedate" TEXT NULL, "plot" TEXT NULL, "duration_secs" INTEGER NULL, "duration" TEXT NULL, "movie_image" TEXT NULL, "bitrate" INTEGER NULL, "rating" REAL NULL)';

// watch_histories never changed across the whole migration history.
const _ddlWatchHistories =
    'CREATE TABLE "watch_histories" ("playlist_id" TEXT NOT NULL, "content_type" INTEGER NOT NULL, "stream_id" TEXT NOT NULL, "series_id" TEXT NULL, "watch_duration" INTEGER NULL, "total_duration" INTEGER NULL, "last_watched" INTEGER NOT NULL, "image_path" TEXT NULL, "title" TEXT NOT NULL, PRIMARY KEY ("playlist_id", "stream_id"))';

// vod_streams BEFORE genre/youtube_trailer (v9) and tmdb_id (v10): the v3/v6 shape.
const _ddlVodStreamsPreGenre =
    'CREATE TABLE "vod_streams" ("stream_id" TEXT NOT NULL, "name" TEXT NOT NULL, "stream_icon" TEXT NOT NULL, "category_id" TEXT NOT NULL, "rating" TEXT NOT NULL, "rating5based" REAL NOT NULL, "container_extension" TEXT NOT NULL, "playlist_id" TEXT NOT NULL, "created_at" INTEGER NOT NULL DEFAULT (CAST(strftime(\'%s\', CURRENT_TIMESTAMP) AS INTEGER)), PRIMARY KEY ("stream_id", "playlist_id"))';

// vod_streams at v9: genre + youtube_trailer present, tmdb_id still absent.
const _ddlVodStreamsV9 =
    'CREATE TABLE "vod_streams" ("stream_id" TEXT NOT NULL, "name" TEXT NOT NULL, "stream_icon" TEXT NOT NULL, "category_id" TEXT NOT NULL, "rating" TEXT NOT NULL, "rating5based" REAL NOT NULL, "container_extension" TEXT NOT NULL, "playlist_id" TEXT NOT NULL, "created_at" INTEGER NOT NULL DEFAULT (CAST(strftime(\'%s\', CURRENT_TIMESTAMP) AS INTEGER)), "genre" TEXT NULL, "youtube_trailer" TEXT NULL, PRIMARY KEY ("stream_id", "playlist_id"))';

// series_streams before tmdb_id (v3/v6/v9 shape).
const _ddlSeriesStreamsPreTmdb =
    'CREATE TABLE "series_streams" ("series_id" TEXT NOT NULL, "name" TEXT NOT NULL, "cover" TEXT NULL, "plot" TEXT NULL, "cast" TEXT NULL, "director" TEXT NULL, "genre" TEXT NULL, "release_date" TEXT NULL, "rating" TEXT NULL, "rating5based" REAL NULL, "youtube_trailer" TEXT NULL, "episode_run_time" TEXT NULL, "category_id" TEXT NULL, "playlist_id" TEXT NOT NULL, "created_at" INTEGER NOT NULL DEFAULT (CAST(strftime(\'%s\', CURRENT_TIMESTAMP) AS INTEGER)), "last_modified" TEXT NULL, "backdrop_path" TEXT NULL, PRIMARY KEY ("series_id", "playlist_id"))';

// Minimal m3u_items at v6 (its whole table is DROPped by the from<=6 step, so
// the exact historical columns are irrelevant — only that a row can live here).
const _ddlM3uItemsV6 =
    'CREATE TABLE "m3u_items" ("id" TEXT NOT NULL, "playlist_id" TEXT NOT NULL, "url" TEXT NOT NULL, "content_type" INTEGER NOT NULL, PRIMARY KEY ("id"))';
const _ddlM3uSeriesV6 =
    'CREATE TABLE "m3u_series" ("playlist_id" TEXT NOT NULL, "series_id" TEXT NOT NULL, "name" TEXT NOT NULL, "category_id" TEXT NULL, "cover" TEXT NULL, PRIMARY KEY ("playlist_id", "series_id"))';
const _ddlM3uEpisodesV6 =
    'CREATE TABLE "m3u_episodes" ("playlist_id" TEXT NOT NULL, "series_id" TEXT NOT NULL, "season_number" INTEGER NOT NULL, "episode_number" INTEGER NOT NULL, "name" TEXT NOT NULL, "url" TEXT NOT NULL, "category_id" TEXT NULL, "cover" TEXT NULL, PRIMARY KEY ("playlist_id", "series_id", "season_number", "episode_number"))';

// favorites (created at v8, current shape) — used for the v9/v11 fixtures.
const _ddlFavorites =
    'CREATE TABLE "favorites" ("id" TEXT NOT NULL, "playlist_id" TEXT NOT NULL, "content_type" INTEGER NOT NULL, "stream_id" TEXT NOT NULL, "episode_id" TEXT NULL, "m3u_item_id" TEXT NULL, "name" TEXT NOT NULL, "image_path" TEXT NULL, "created_at" INTEGER NOT NULL DEFAULT (CAST(strftime(\'%s\', CURRENT_TIMESTAMP) AS INTEGER)), "updated_at" INTEGER NOT NULL DEFAULT (CAST(strftime(\'%s\', CURRENT_TIMESTAMP) AS INTEGER)), PRIMARY KEY ("id"))';

// vod_streams at v11 (current): genre/yt AND tmdb_id present.
const _ddlVodStreamsCurrent =
    'CREATE TABLE "vod_streams" ("stream_id" TEXT NOT NULL, "name" TEXT NOT NULL, "stream_icon" TEXT NOT NULL, "category_id" TEXT NOT NULL, "rating" TEXT NOT NULL, "rating5based" REAL NOT NULL, "container_extension" TEXT NOT NULL, "playlist_id" TEXT NOT NULL, "created_at" INTEGER NOT NULL DEFAULT (CAST(strftime(\'%s\', CURRENT_TIMESTAMP) AS INTEGER)), "genre" TEXT NULL, "youtube_trailer" TEXT NULL, "tmdb_id" INTEGER NULL, PRIMARY KEY ("stream_id", "playlist_id"))';

// series_streams at v11 (current): tmdb_id present.
const _ddlSeriesStreamsCurrent =
    'CREATE TABLE "series_streams" ("series_id" TEXT NOT NULL, "name" TEXT NOT NULL, "cover" TEXT NULL, "plot" TEXT NULL, "cast" TEXT NULL, "director" TEXT NULL, "genre" TEXT NULL, "release_date" TEXT NULL, "rating" TEXT NULL, "rating5based" REAL NULL, "youtube_trailer" TEXT NULL, "episode_run_time" TEXT NULL, "category_id" TEXT NULL, "playlist_id" TEXT NOT NULL, "created_at" INTEGER NOT NULL DEFAULT (CAST(strftime(\'%s\', CURRENT_TIMESTAMP) AS INTEGER)), "last_modified" TEXT NULL, "backdrop_path" TEXT NULL, "tmdb_id" INTEGER NULL, PRIMARY KEY ("series_id", "playlist_id"))';

// Full current m3u_items (needed on any path that reaches beforeOpen, which
// creates an index on m3u_items(playlist_id, category_id)).
const _ddlM3uItemsCurrent =
    'CREATE TABLE "m3u_items" ("id" TEXT NOT NULL, "playlist_id" TEXT NOT NULL, "url" TEXT NOT NULL, "name" TEXT NULL, "tvg_id" TEXT NULL, "tvg_name" TEXT NULL, "tvg_logo" TEXT NULL, "tvg_url" TEXT NULL, "tvg_rec" TEXT NULL, "tvg_shift" TEXT NULL, "group_title" TEXT NULL, "group_name" TEXT NULL, "user_agent" TEXT NULL, "referrer" TEXT NULL, "category_id" TEXT NULL, "content_type" INTEGER NOT NULL, "created_at" INTEGER NOT NULL DEFAULT (CAST(strftime(\'%s\', CURRENT_TIMESTAMP) AS INTEGER)), "updated_at" INTEGER NOT NULL DEFAULT (CAST(strftime(\'%s\', CURRENT_TIMESTAMP) AS INTEGER)), PRIMARY KEY ("id"), CHECK (LENGTH(id) > 0), CHECK (LENGTH(url) > 0), CHECK (LENGTH(playlist_id) > 0))';

// downloads at v11: created WITHOUT error/url (those are added by the 11->12 step).
const _ddlDownloadsV11 =
    'CREATE TABLE "downloads" ("id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, "content_id" TEXT NOT NULL, "content_type" TEXT NOT NULL, "title" TEXT NOT NULL, "image_path" TEXT NOT NULL DEFAULT \'\', "file_path" TEXT NULL, "ext" TEXT NULL, "task_id" TEXT NULL, "bytes_downloaded" INTEGER NOT NULL DEFAULT 0, "total_bytes" INTEGER NULL, "status" TEXT NOT NULL DEFAULT \'queued\', "added_at" INTEGER NOT NULL, "watched" INTEGER NOT NULL DEFAULT 0 CHECK ("watched" IN (0, 1)), "playlist_id" TEXT NOT NULL)';

// downloads in its CURRENT/FULL shape (error + url present). This is exactly
// what the buggy builds v2.10.0–v2.14.0 wrote: `from<=10 createTable(downloads)`
// emitted the current DDL (already carrying error/url), the `from<=11`
// addColumn(error) then crashed on a duplicate column, and — because onUpgrade
// was not atomic — the createTable side effect stuck while user_version stayed
// behind (9 or 10). The majority of affected users are in exactly this state.
const _ddlDownloadsCurrent =
    'CREATE TABLE "downloads" ("id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, "content_id" TEXT NOT NULL, "content_type" TEXT NOT NULL, "title" TEXT NOT NULL, "image_path" TEXT NOT NULL DEFAULT \'\', "file_path" TEXT NULL, "ext" TEXT NULL, "task_id" TEXT NULL, "bytes_downloaded" INTEGER NOT NULL DEFAULT 0, "total_bytes" INTEGER NULL, "status" TEXT NOT NULL DEFAULT \'queued\', "added_at" INTEGER NOT NULL, "watched" INTEGER NOT NULL DEFAULT 0 CHECK ("watched" IN (0, 1)), "playlist_id" TEXT NOT NULL, "error" TEXT NULL, "url" TEXT NULL)';

void _useLinuxSqlite() {
  open.overrideFor(
    OperatingSystem.linux,
    () => DynamicLibrary.open('libsqlite3.so.0'),
  );
}

/// Seed four realistic watch_history rows into [raw]. Note streamId '100'
/// appears under BOTH pl-A and pl-B — distinct rows under the composite PK.
void _seedWatch(Database raw) {
  raw.execute(
    'INSERT INTO watch_histories (playlist_id, content_type, stream_id, series_id, watch_duration, total_duration, last_watched, image_path, title) VALUES '
    "('pl-A', 1, '100', NULL, 300000, 3600000, 1700000000, NULL, 'Movie A'),"
    "('pl-A', 2, '200', 's1', 600000, 1800000, 1700000100, NULL, 'Series B'),"
    "('pl-B', 1, '100', NULL, 120000, 5400000, 1700000200, NULL, 'Movie C'),"
    "('pl-B', 1, '300', NULL, 45000, NULL, 1700000300, NULL, 'Movie D')",
  );
}

void main() {
  group('QA M/AC14 migrations preserve data', () {
    test('v3 -> v13 keeps all watch_history rows; new columns land NULL',
        () async {
      _useLinuxSqlite();
      final dir = Directory.systemTemp.createTempSync('qa_mig_v3');
      final path = p.join(dir.path, 'old.sqlite');

      // Build a faithful v3 database (watch_histories exists; no m3u_items,
      // favorites, downloads; vod without genre/yt/tmdb; series without tmdb).
      final raw = sqlite3.open(path);
      for (final ddl in [
        _ddlPlaylists,
        _ddlCategories,
        _ddlUserInfos,
        _ddlServerInfos,
        _ddlLiveStreams,
        _ddlVodStreamsPreGenre,
        _ddlSeriesStreamsPreTmdb,
        _ddlSeriesInfos,
        _ddlSeasons,
        _ddlEpisodes,
        _ddlWatchHistories,
      ]) {
        raw.execute(ddl);
      }
      // A playlist row so the from<=3 UPDATE has something to touch, plus the
      // xstream->xtream typo it repairs.
      raw.execute(
        "INSERT INTO playlists (id, name, type, url, username, password, created_at) VALUES ('pl-A', 'Old', 'PlaylistType.xstream', NULL, NULL, NULL, 1700000000)",
      );
      _seedWatch(raw);
      // A VOD row to prove the columns added by later migrations exist & are
      // NULL for pre-existing rows.
      raw.execute(
        "INSERT INTO vod_streams (stream_id, name, stream_icon, category_id, rating, rating5based, container_extension, playlist_id, created_at) VALUES ('v1', 'Old Movie', '', 'c1', '7', 3.5, 'mp4', 'pl-A', 1700000000)",
      );
      final beforeWatch =
          raw.select('SELECT COUNT(*) c FROM watch_histories').first['c'];
      final beforeVod =
          raw.select('SELECT COUNT(*) c FROM vod_streams').first['c'];
      raw.userVersion = 3;
      raw.dispose();

      expect(beforeWatch, 4, reason: 'seeded 4 watch rows at v3');
      expect(beforeVod, 1);

      // Open with the CURRENT schema (v13) -> Drift runs onUpgrade(3, 13).
      // With the layered-createTable fix, the `from<=10` step now creates
      // downloads in its schema-11 shape (WITHOUT error/url) so the `from<=11`
      // addColumn is valid, and the migration completes cleanly to v13 with all
      // seeded data intact.
      final db = AppDatabase(NativeDatabase(File(path)));
      final watch = await db.select(db.watchHistories).get();
      expect(watch, hasLength(4), reason: 'all 4 watch rows survive v3->v13');

      // The columns added by later migrations exist and land NULL for the
      // pre-existing v3 row.
      final vod = await db.select(db.vodStreams).get();
      expect(vod, hasLength(1));
      expect(vod.single.genre, isNull);
      expect(vod.single.youtubeTrailer, isNull);
      expect(vod.single.tmdbId, isNull);

      // downloads (added at v11, hardened at v12) was created and is empty.
      expect(await db.select(db.downloads).get(), isEmpty);

      // The xstream->xtream typo repair (from<=3) ran.
      final pls = await db.select(db.playlists).get();
      expect(pls.single.type, 'PlaylistType.xtream');
      await db.close();

      // The migration reached v13 and stays there (no half-migrated re-crash).
      final after = sqlite3.open(path);
      expect(after.userVersion, 13,
          reason: 'user_version bumped to 13 — migration completed');
      after.dispose();
      dir.deleteSync(recursive: true);
    });

    test('v9 -> v13 keeps watch_history + favorites; downloads created',
        () async {
      _useLinuxSqlite();
      final dir = Directory.systemTemp.createTempSync('qa_mig_v9');
      final path = p.join(dir.path, 'old.sqlite');

      final raw = sqlite3.open(path);
      for (final ddl in [
        _ddlPlaylists,
        _ddlCategories,
        _ddlUserInfos,
        _ddlServerInfos,
        _ddlLiveStreams,
        _ddlVodStreamsV9, // has genre/yt, no tmdb
        _ddlSeriesStreamsPreTmdb,
        _ddlSeriesInfos,
        _ddlSeasons,
        _ddlEpisodes,
        _ddlWatchHistories,
        // A real v9 DB's m3u_items was recreated with the FULL DDL at the v6->v7
        // step (from<=6 drop+recreate); a v9->v13 upgrade never rebuilds it
        // (v9 > 6), so it must carry the current columns — beforeOpen builds an
        // index on m3u_items(playlist_id, category_id), which the minimal v6
        // shape lacks. Use the faithful current DDL.
        _ddlM3uItemsCurrent,
        _ddlM3uSeriesV6,
        _ddlM3uEpisodesV6,
        _ddlFavorites, // favorites exists at v9
      ]) {
        raw.execute(ddl);
      }
      _seedWatch(raw);
      raw.execute(
        "INSERT INTO vod_streams (stream_id, name, stream_icon, category_id, rating, rating5based, container_extension, playlist_id, created_at, genre, youtube_trailer) VALUES ('v1', 'Old Movie', '', 'c1', '7', 3.5, 'mp4', 'pl-A', 1700000000, 'Action', NULL)",
      );
      raw.execute(
        'INSERT INTO favorites (id, playlist_id, content_type, stream_id, name, created_at, updated_at) VALUES '
        "('f1', 'pl-A', 1, '100', 'Fav Movie', 1700000000, 1700000000),"
        "('f2', 'pl-B', 2, '200', 'Fav Series', 1700000000, 1700000000)",
      );
      final beforeWatch =
          raw.select('SELECT COUNT(*) c FROM watch_histories').first['c'];
      final beforeFav =
          raw.select('SELECT COUNT(*) c FROM favorites').first['c'];
      // downloads must NOT exist at v9.
      final dlExistsBefore = raw
          .select(
              "SELECT COUNT(*) c FROM sqlite_master WHERE type='table' AND name='downloads'")
          .first['c'];
      raw.userVersion = 9;
      raw.dispose();

      expect(beforeWatch, 4);
      expect(beforeFav, 2);
      expect(dlExistsBefore, 0, reason: 'downloads absent at v9');

      // onUpgrade(9, 12): from<=10 creates downloads in its schema-11 shape,
      // from<=11 adds error/url. Migration completes; watch + favorites survive
      // and the freshly-created downloads table is empty.
      final db = AppDatabase(NativeDatabase(File(path)));
      expect(await db.select(db.watchHistories).get(), hasLength(4),
          reason: 'watch rows survive v9->v13');
      expect(await db.select(db.favorites).get(), hasLength(2),
          reason: 'favorites survive v9->v13');
      expect(await db.select(db.downloads).get(), isEmpty,
          reason: 'downloads created empty at v9->v13');
      await db.close();

      final after = sqlite3.open(path);
      final dlExistsAfter = after
          .select(
              "SELECT COUNT(*) c FROM sqlite_master WHERE type='table' AND name='downloads'")
          .first['c'];
      expect(dlExistsAfter, 1, reason: 'downloads table now exists');
      expect(after.userVersion, 13,
          reason: 'user_version bumped to 13 — migration completed');
      after.dispose();
      dir.deleteSync(recursive: true);
    });

    test(
        'from<=6 deleteTable(m3u_items) clears ONLY m3u_items; watch survives',
        () async {
      _useLinuxSqlite();
      final dir = Directory.systemTemp.createTempSync('qa_mig_v6');
      final path = p.join(dir.path, 'old.sqlite');

      // v6: m3u_items exists (created at v5); no favorites/downloads; vod/series
      // without genre/yt/tmdb.
      final raw = sqlite3.open(path);
      for (final ddl in [
        _ddlPlaylists,
        _ddlCategories,
        _ddlUserInfos,
        _ddlServerInfos,
        _ddlLiveStreams,
        _ddlVodStreamsPreGenre,
        _ddlSeriesStreamsPreTmdb,
        _ddlSeriesInfos,
        _ddlSeasons,
        _ddlEpisodes,
        _ddlWatchHistories,
        _ddlM3uItemsV6,
        _ddlM3uSeriesV6,
        _ddlM3uEpisodesV6,
      ]) {
        raw.execute(ddl);
      }
      _seedWatch(raw);
      raw.execute(
        'INSERT INTO m3u_items (id, playlist_id, url, content_type) VALUES '
        "('m1', 'pl-A', 'http://a', 0),"
        "('m2', 'pl-A', 'http://b', 1),"
        "('m3', 'pl-B', 'http://c', 1)",
      );
      final beforeWatch =
          raw.select('SELECT COUNT(*) c FROM watch_histories').first['c'];
      final beforeM3u =
          raw.select('SELECT COUNT(*) c FROM m3u_items').first['c'];
      raw.userVersion = 6;
      raw.dispose();

      expect(beforeWatch, 4);
      expect(beforeM3u, 3);

      // The migration now completes to v13. The from<=6 deleteTable('m3u_items')
      // step is a single-table DROP+recreate that must clear ONLY m3u_items and
      // never touch watch_histories — verify exactly that on the migrated DB.
      final db = AppDatabase(NativeDatabase(File(path)));
      expect(await db.select(db.watchHistories).get(), hasLength(4),
          reason: 'watch_histories untouched by the m3u_items DROP');
      await db.close();

      // Reopen raw and inspect the migrated on-disk state.
      final after = sqlite3.open(path);
      final afterM3u =
          after.select('SELECT COUNT(*) c FROM m3u_items').first['c'];
      final afterWatch =
          after.select('SELECT COUNT(*) c FROM watch_histories').first['c'];
      final afterVersion = after.userVersion;
      after.dispose();

      expect(afterM3u, 0,
          reason: 'from<=6 deleteTable cleared ONLY m3u_items (0 rows)');
      expect(afterWatch, 4,
          reason: 'watch_histories kept all 4 rows through the scoped DROP');
      expect(afterVersion, 13,
          reason: 'migration completed and bumped user_version to 13');

      dir.deleteSync(recursive: true);
    });

    test('WORKING PATH v11 -> v13 preserves watch + favorites + downloads',
        () async {
      // v11 already has downloads (without error/url), so onUpgrade(11, 12)
      // runs ONLY the from<=11 addColumn step and does NOT hit the createTable
      // conflict. This isolates the bug to upgrades from schemaVersion <= 10
      // and demonstrates the data-preservation machinery is otherwise sound.
      _useLinuxSqlite();
      final dir = Directory.systemTemp.createTempSync('qa_mig_v11');
      final path = p.join(dir.path, 'old.sqlite');

      final raw = sqlite3.open(path);
      for (final ddl in [
        _ddlPlaylists,
        _ddlCategories,
        _ddlUserInfos,
        _ddlServerInfos,
        _ddlLiveStreams,
        _ddlVodStreamsCurrent,
        _ddlSeriesStreamsCurrent,
        _ddlSeriesInfos,
        _ddlSeasons,
        _ddlEpisodes,
        _ddlWatchHistories,
        _ddlM3uItemsCurrent,
        _ddlM3uSeriesV6,
        _ddlM3uEpisodesV6,
        _ddlFavorites,
        _ddlDownloadsV11,
      ]) {
        raw.execute(ddl);
      }
      _seedWatch(raw);
      raw.execute(
        'INSERT INTO favorites (id, playlist_id, content_type, stream_id, name, created_at, updated_at) VALUES '
        "('f1', 'pl-A', 1, '100', 'Fav Movie', 1700000000, 1700000000),"
        "('f2', 'pl-B', 2, '200', 'Fav Series', 1700000000, 1700000000)",
      );
      raw.execute(
        'INSERT INTO downloads (content_id, content_type, title, image_path, bytes_downloaded, status, added_at, watched, playlist_id) VALUES '
        "('d1', 'vod', 'Downloaded A', '', 0, 'complete', 1700000000, 0, 'pl-A'),"
        "('d2', 'series', 'Downloaded B', '', 0, 'queued', 1700000100, 0, 'pl-B')",
      );
      final beforeWatch =
          raw.select('SELECT COUNT(*) c FROM watch_histories').first['c'];
      final beforeFav =
          raw.select('SELECT COUNT(*) c FROM favorites').first['c'];
      final beforeDl =
          raw.select('SELECT COUNT(*) c FROM downloads').first['c'];
      raw.userVersion = 11;
      raw.dispose();

      expect(beforeWatch, 4);
      expect(beforeFav, 2);
      expect(beforeDl, 2);

      final db = AppDatabase(NativeDatabase(File(path)));
      final watch = await db.select(db.watchHistories).get();
      expect(watch, hasLength(4), reason: 'watch rows survive 11->12');
      final fav = await db.select(db.favorites).get();
      expect(fav, hasLength(2), reason: 'favorites survive 11->12');
      final dl = await db.select(db.downloads).get();
      expect(dl, hasLength(2), reason: 'downloads survive 11->12');
      // error/url columns added by 11->12 land NULL for the old rows.
      expect(dl.every((d) => d.error == null && d.url == null), isTrue,
          reason: 'new nullable columns are NULL for pre-existing rows');
      expect(dl.firstWhere((d) => d.contentId == 'd1').title, 'Downloaded A');

      final byKey = {for (final r in watch) '${r.playlistId}/${r.streamId}': r};
      expect(byKey['pl-A/100']!.watchDuration, 300000);
      expect(byKey['pl-A/100']!.totalDuration, 3600000);
      expect(byKey['pl-B/300']!.totalDuration, isNull);
      expect(WatchHistory.fromDrift(byKey['pl-A/200']!).contentType,
          ContentType.series);

      await db.close();
      dir.deleteSync(recursive: true);
    });

    test('v2 -> v13: from<=2 creates vod/series with the CURRENT DDL, yet the '
        'later genre/tmdb_id addColumns do NOT duplicate; playlists survive',
        () async {
      _useLinuxSqlite();
      final dir = Directory.systemTemp.createTempSync('qa_mig_v2');
      final path = p.join(dir.path, 'old.sqlite');

      // A faithful v2 DB: only `playlists` exists — the core tables
      // (vod_streams, series_streams, …) are CREATED by the from<=2 migration,
      // so a v2 DB does not yet carry them. This path exposes the SECOND latent
      // duplicate-column bug: from<=2 creates vod_streams/series_streams with
      // the CURRENT Drift DDL (already carrying genre/youtube_trailer/tmdb_id),
      // and from<=8 / from<10 then addColumn those SAME columns. The pre-fix
      // code threw "duplicate column name: genre"; the idempotent
      // _addColumnIfMissing turns them into no-ops.
      final raw = sqlite3.open(path);
      raw.execute(_ddlPlaylists);
      raw.execute(
        "INSERT INTO playlists (id, name, type, url, username, password, created_at) VALUES ('pl-A', 'Old', 'PlaylistType.xstream', NULL, NULL, NULL, 1700000000)",
      );
      raw.userVersion = 2;
      raw.dispose();

      final db = AppDatabase(NativeDatabase(File(path)));
      // Migration must complete without a duplicate-column throw.
      final pls = await db.select(db.playlists).get();
      expect(pls, hasLength(1), reason: 'the v2 playlist row survives v2->v13');
      expect(pls.single.type, 'PlaylistType.xtream',
          reason: 'the from<=3 xstream->xtream repair still runs');
      expect(await db.select(db.vodStreams).get(), isEmpty);
      expect(await db.select(db.seriesStreams).get(), isEmpty);
      expect(await db.select(db.downloads).get(), isEmpty);
      await db.close();

      final after = sqlite3.open(path);
      // Each column the addColumn steps would have added is present EXACTLY once.
      final vodCols = after
          .select('PRAGMA table_info(vod_streams)')
          .map((r) => r['name'] as String)
          .toList();
      expect(vodCols.where((c) => c == 'genre'), hasLength(1),
          reason: 'genre added once, not duplicated');
      expect(vodCols, containsAll(['genre', 'youtube_trailer', 'tmdb_id']));
      final seriesCols = after
          .select('PRAGMA table_info(series_streams)')
          .map((r) => r['name'] as String)
          .toList();
      expect(seriesCols.where((c) => c == 'tmdb_id'), hasLength(1));
      expect(after.userVersion, 13,
          reason: 'migration completed and bumped user_version to 13');
      after.dispose();
      dir.deleteSync(recursive: true);
    });

    test('BUGGY-BUILD COHORT v10 (downloads already FULL: error/url present) -> '
        'v13 migrates idempotently and preserves all rows', () async {
      _useLinuxSqlite();
      final dir = Directory.systemTemp.createTempSync('qa_mig_v10c');
      final path = p.join(dir.path, 'old.sqlite');

      // A v2.10.0–v2.14.0 victim left at user_version 10 with downloads ALREADY
      // in its full shape (error/url present, written by the buggy
      // createTable-current-DDL). Reopening with the fixed AppDatabase must NOT
      // throw — the from<=11 addColumn(error/url) detect the columns already
      // exist and no-op — and must reach v13 with every row intact. This is the
      // MAJORITY of affected users.
      final raw = sqlite3.open(path);
      for (final ddl in [
        _ddlPlaylists,
        _ddlCategories,
        _ddlUserInfos,
        _ddlServerInfos,
        _ddlLiveStreams,
        _ddlVodStreamsCurrent,
        _ddlSeriesStreamsCurrent,
        _ddlSeriesInfos,
        _ddlSeasons,
        _ddlEpisodes,
        _ddlWatchHistories,
        _ddlM3uItemsCurrent,
        _ddlM3uSeriesV6,
        _ddlM3uEpisodesV6,
        _ddlFavorites,
        _ddlDownloadsCurrent, // full shape, as the buggy build left it
      ]) {
        raw.execute(ddl);
      }
      _seedWatch(raw);
      raw.execute(
        'INSERT INTO favorites (id, playlist_id, content_type, stream_id, name, created_at, updated_at) VALUES '
        "('f1', 'pl-A', 1, '100', 'Fav Movie', 1700000000, 1700000000)",
      );
      raw.execute(
        'INSERT INTO downloads (content_id, content_type, title, image_path, bytes_downloaded, status, added_at, watched, playlist_id, error, url) VALUES '
        "('d1', 'vod', 'Downloaded A', '', 0, 'failed', 1700000000, 0, 'pl-A', 'net error', 'http://x')",
      );
      raw.userVersion = 10;
      raw.dispose();

      final db = AppDatabase(NativeDatabase(File(path)));
      expect(await db.select(db.watchHistories).get(), hasLength(4));
      expect(await db.select(db.favorites).get(), hasLength(1));
      final dl = await db.select(db.downloads).get();
      expect(dl, hasLength(1), reason: 'the pre-existing download survives');
      expect(dl.single.error, 'net error',
          reason: 'the values the buggy build wrote are preserved verbatim');
      expect(dl.single.url, 'http://x');
      await db.close();

      final after = sqlite3.open(path);
      expect(after.userVersion, 13,
          reason: 'the stuck-at-10 cohort is rescued to v13');
      after.dispose();
      dir.deleteSync(recursive: true);
    });

    test('BUGGY-BUILD COHORT v9 (partial: tmdb_id + full downloads already '
        'applied, user_version stuck at 9) -> v13 idempotently', () async {
      _useLinuxSqlite();
      final dir = Directory.systemTemp.createTempSync('qa_mig_v9c');
      final path = p.join(dir.path, 'old.sqlite');

      // The buggy onUpgrade(9,12) applied from<10 (vod/series tmdb_id) and
      // from<=10 (createTable downloads, full DDL) BEFORE crashing on from<=11
      // addColumn(error); user_version stayed at 9. So on disk: vod & series
      // ALREADY carry tmdb_id AND downloads ALREADY has error/url, yet
      // user_version is 9. The fixed migration must treat EVERY one of those
      // addColumns as a no-op and still reach v13 with data intact.
      final raw = sqlite3.open(path);
      for (final ddl in [
        _ddlPlaylists,
        _ddlCategories,
        _ddlUserInfos,
        _ddlServerInfos,
        _ddlLiveStreams,
        _ddlVodStreamsCurrent, // tmdb_id already present (partial migration)
        _ddlSeriesStreamsCurrent, // tmdb_id already present
        _ddlSeriesInfos,
        _ddlSeasons,
        _ddlEpisodes,
        _ddlWatchHistories,
        _ddlM3uItemsCurrent,
        _ddlM3uSeriesV6,
        _ddlM3uEpisodesV6,
        _ddlFavorites,
        _ddlDownloadsCurrent, // full shape already present
      ]) {
        raw.execute(ddl);
      }
      _seedWatch(raw);
      raw.execute(
        'INSERT INTO favorites (id, playlist_id, content_type, stream_id, name, created_at, updated_at) VALUES '
        "('f1', 'pl-A', 1, '100', 'Fav Movie', 1700000000, 1700000000),"
        "('f2', 'pl-B', 2, '200', 'Fav Series', 1700000000, 1700000000)",
      );
      raw.execute(
        'INSERT INTO downloads (content_id, content_type, title, image_path, bytes_downloaded, status, added_at, watched, playlist_id) VALUES '
        "('d1', 'vod', 'Downloaded A', '', 0, 'complete', 1700000000, 0, 'pl-A')",
      );
      raw.userVersion = 9;
      raw.dispose();

      final db = AppDatabase(NativeDatabase(File(path)));
      expect(await db.select(db.watchHistories).get(), hasLength(4));
      expect(await db.select(db.favorites).get(), hasLength(2));
      expect(await db.select(db.downloads).get(), hasLength(1));
      await db.close();

      final after = sqlite3.open(path);
      expect(after.userVersion, 13);
      final vodCols = after
          .select('PRAGMA table_info(vod_streams)')
          .map((r) => r['name'] as String)
          .toList();
      expect(vodCols.where((c) => c == 'tmdb_id'), hasLength(1),
          reason: 'tmdb_id stays a single column — no duplicate-column crash');
      after.dispose();
      dir.deleteSync(recursive: true);
    });

    test('idempotent re-run: a v13 schema whose user_version was left behind at '
        '10 migrates again without throwing (crash-safety)', () async {
      _useLinuxSqlite();
      final dir = Directory.systemTemp.createTempSync('qa_mig_rerun');
      final path = p.join(dir.path, 'old.sqlite');

      // Migrate a v11 DB up to a real v13 schema first.
      final raw = sqlite3.open(path);
      for (final ddl in [
        _ddlPlaylists,
        _ddlCategories,
        _ddlUserInfos,
        _ddlServerInfos,
        _ddlLiveStreams,
        _ddlVodStreamsCurrent,
        _ddlSeriesStreamsCurrent,
        _ddlSeriesInfos,
        _ddlSeasons,
        _ddlEpisodes,
        _ddlWatchHistories,
        _ddlM3uItemsCurrent,
        _ddlM3uSeriesV6,
        _ddlM3uEpisodesV6,
        _ddlFavorites,
        _ddlDownloadsV11,
      ]) {
        raw.execute(ddl);
      }
      _seedWatch(raw);
      raw.userVersion = 11;
      raw.dispose();

      final db1 = AppDatabase(NativeDatabase(File(path)));
      expect(await db1.select(db1.watchHistories).get(), hasLength(4));
      await db1.close();

      // Simulate a crash that applied the schema but never committed the version
      // bump: rewind user_version to 10 on the now-fully-v13 schema. Reopening
      // must re-run onUpgrade(10,13) over already-present columns/tables and NOT
      // throw (createTable is IF NOT EXISTS; addColumns are idempotent).
      final mid = sqlite3.open(path);
      expect(mid.userVersion, 13);
      mid.userVersion = 10;
      mid.dispose();

      final db2 = AppDatabase(NativeDatabase(File(path)));
      expect(await db2.select(db2.watchHistories).get(), hasLength(4),
          reason: 'a re-run over an already-migrated schema is a safe no-op');
      await db2.close();

      final after = sqlite3.open(path);
      expect(after.userVersion, 13, reason: 're-run completes back to v13');
      after.dispose();
      dir.deleteSync(recursive: true);
    });
  });

  group('QA M2 composite PK {playlistId, streamId}', () {
    test('same streamId under two playlists are distinct rows; write isolates',
        () async {
      _useLinuxSqlite();
      final db = AppDatabase(NativeDatabase.memory());

      Future<void> put(String playlistId, int watchMs) =>
          db.into(db.watchHistories).insertOnConflictUpdate(WatchHistory(
                playlistId: playlistId,
                contentType: ContentType.vod,
                streamId: 'SHARED-STREAM',
                watchDuration: Duration(milliseconds: watchMs),
                totalDuration: const Duration(hours: 1),
                lastWatched: DateTime(2026),
                title: 'Title $playlistId',
              ).toDriftCompanion());

      await put('pl-A', 111);
      await put('pl-B', 222);

      final all = await db.select(db.watchHistories).get();
      expect(all, hasLength(2),
          reason: 'same streamId + different playlistId => 2 distinct rows');

      // Update pl-A only.
      await put('pl-A', 999);
      final after = {
        for (final r in await db.select(db.watchHistories).get())
          r.playlistId: r.watchDuration
      };
      expect(after['pl-A'], 999, reason: 'pl-A row updated');
      expect(after['pl-B'], 222,
          reason: 'pl-B row must be untouched by the pl-A write');

      await db.close();
    });
  });

  // Feature H (TV standalone playback) — the 12->13 additive migration adds two
  // NULLABLE columns to watch_histories (container_extension, provider_id) so a
  // `__cast__` history row can later rebuild a standalone Xtream URL. It follows
  // the SAME hardened pattern as every prior additive step: idempotent
  // _addColumnIfMissing inside the transaction()-wrapped onUpgrade. These tests
  // are the regression guard against a repeat of the onUpgrade brick loop.
  group('QA feature-H watch_histories 12->13', () {
    test('v12 -> v13 adds container_extension + provider_id (nullable, default '
        'NULL) and preserves every watch_history row', () async {
      _useLinuxSqlite();
      final dir = Directory.systemTemp.createTempSync('qa_mig_v12');
      final path = p.join(dir.path, 'old.sqlite');

      // A faithful v12 DB: current shape for every table EXCEPT watch_histories,
      // which is at its pre-13 shape (no container_extension / provider_id).
      final raw = sqlite3.open(path);
      for (final ddl in [
        _ddlPlaylists,
        _ddlCategories,
        _ddlUserInfos,
        _ddlServerInfos,
        _ddlLiveStreams,
        _ddlVodStreamsCurrent,
        _ddlSeriesStreamsCurrent,
        _ddlSeriesInfos,
        _ddlSeasons,
        _ddlEpisodes,
        _ddlWatchHistories, // v12: no container_extension / provider_id yet
        _ddlM3uItemsCurrent,
        _ddlM3uSeriesV6,
        _ddlM3uEpisodesV6,
        _ddlFavorites,
        _ddlDownloadsCurrent,
      ]) {
        raw.execute(ddl);
      }
      _seedWatch(raw);
      raw.execute(
        'INSERT INTO favorites (id, playlist_id, content_type, stream_id, name, created_at, updated_at) VALUES '
        "('f1', 'pl-A', 1, '100', 'Fav Movie', 1700000000, 1700000000)",
      );
      final beforeWatch =
          raw.select('SELECT COUNT(*) c FROM watch_histories').first['c'];
      // The new columns must NOT exist yet at v12.
      final colsBefore = raw
          .select('PRAGMA table_info(watch_histories)')
          .map((r) => r['name'] as String)
          .toList();
      raw.userVersion = 12;
      raw.dispose();

      expect(beforeWatch, 4, reason: 'seeded 4 watch rows at v12');
      expect(colsBefore, isNot(contains('container_extension')));
      expect(colsBefore, isNot(contains('provider_id')));

      // Open with the CURRENT schema (v13) -> Drift runs onUpgrade(12, 13),
      // which executes ONLY the from<=12 step (adds both columns idempotently).
      final db = AppDatabase(NativeDatabase(File(path)));
      final watch = await db.select(db.watchHistories).get();
      expect(watch, hasLength(4), reason: 'all 4 watch rows survive v12->v13');

      // The two new columns exist and land NULL for every pre-existing row.
      expect(watch.every((w) => w.containerExtension == null), isTrue,
          reason: 'container_extension defaults NULL on migrated rows');
      expect(watch.every((w) => w.providerId == null), isTrue,
          reason: 'provider_id defaults NULL on migrated rows');
      // Existing data is byte-for-byte intact.
      final byKey = {for (final r in watch) '${r.playlistId}/${r.streamId}': r};
      expect(byKey['pl-A/100']!.watchDuration, 300000);
      expect(byKey['pl-A/100']!.totalDuration, 3600000);
      expect(byKey['pl-A/200']!.title, 'Series B');
      expect(byKey['pl-B/300']!.totalDuration, isNull);
      // Favorites untouched by the watch_histories migration.
      expect(await db.select(db.favorites).get(), hasLength(1));

      // A fresh row CAN carry the new fields round-trip through the model.
      await db.into(db.watchHistories).insertOnConflictUpdate(WatchHistory(
            playlistId: '__cast__',
            contentType: ContentType.vod,
            streamId: '900',
            watchDuration: const Duration(minutes: 5),
            totalDuration: const Duration(hours: 1),
            lastWatched: DateTime(2026),
            title: 'Cast Movie',
            containerExtension: 'mkv',
            providerId: 'prov-1',
          ).toDriftCompanion());
      final cast = WatchHistory.fromDrift((await db.select(db.watchHistories).get())
          .firstWhere((r) => r.streamId == '900'));
      expect(cast.containerExtension, 'mkv');
      expect(cast.providerId, 'prov-1');
      await db.close();

      // The new columns are present on disk exactly once, and the migration
      // reached v13 and stays there (no half-migrated re-crash).
      final after = sqlite3.open(path);
      final colsAfter = after
          .select('PRAGMA table_info(watch_histories)')
          .map((r) => r['name'] as String)
          .toList();
      expect(colsAfter.where((c) => c == 'container_extension'), hasLength(1));
      expect(colsAfter.where((c) => c == 'provider_id'), hasLength(1));
      expect(after.userVersion, 13,
          reason: 'user_version bumped to 13 — migration completed');
      after.dispose();
      dir.deleteSync(recursive: true);
    });

    test('idempotent re-run: a v13 schema whose user_version was rewound to 12 '
        'migrates again without throwing "duplicate column" (crash-safety)',
        () async {
      _useLinuxSqlite();
      final dir = Directory.systemTemp.createTempSync('qa_mig_v13rerun');
      final path = p.join(dir.path, 'old.sqlite');

      // Bring a v12 DB up to a real v13 schema first.
      final raw = sqlite3.open(path);
      for (final ddl in [
        _ddlPlaylists,
        _ddlCategories,
        _ddlUserInfos,
        _ddlServerInfos,
        _ddlLiveStreams,
        _ddlVodStreamsCurrent,
        _ddlSeriesStreamsCurrent,
        _ddlSeriesInfos,
        _ddlSeasons,
        _ddlEpisodes,
        _ddlWatchHistories,
        _ddlM3uItemsCurrent,
        _ddlM3uSeriesV6,
        _ddlM3uEpisodesV6,
        _ddlFavorites,
        _ddlDownloadsCurrent,
      ]) {
        raw.execute(ddl);
      }
      _seedWatch(raw);
      raw.userVersion = 12;
      raw.dispose();

      final db1 = AppDatabase(NativeDatabase(File(path)));
      expect(await db1.select(db1.watchHistories).get(), hasLength(4));
      await db1.close();

      // Simulate a crash that applied the schema (both columns now exist) but
      // never committed the version bump: rewind user_version to 12 on the
      // now-fully-v13 schema. Reopening must re-run onUpgrade(12,13) over the
      // already-present columns and NOT throw — _addColumnIfMissing no-ops.
      final mid = sqlite3.open(path);
      expect(mid.userVersion, 13);
      mid.userVersion = 12;
      mid.dispose();

      final db2 = AppDatabase(NativeDatabase(File(path)));
      expect(await db2.select(db2.watchHistories).get(), hasLength(4),
          reason: 'a re-run over an already-migrated schema is a safe no-op');
      await db2.close();

      final after = sqlite3.open(path);
      expect(after.userVersion, 13, reason: 're-run completes back to v13');
      // Still exactly one of each new column — no duplicate created.
      final cols = after
          .select('PRAGMA table_info(watch_histories)')
          .map((r) => r['name'] as String)
          .toList();
      expect(cols.where((c) => c == 'container_extension'), hasLength(1));
      expect(cols.where((c) => c == 'provider_id'), hasLength(1));
      after.dispose();
      dir.deleteSync(recursive: true);
    });
  });
}
