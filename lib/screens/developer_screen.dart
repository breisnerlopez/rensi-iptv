// Pantalla "Desarrollador": vuelca todo el detalle técnico disponible del
// proveedor IPTV activo (Xtream o M3U) más metadatos de la app/base de datos.
//
// Xtream: se muestran las secciones Cuenta (user_info) y Servidor (server_info),
// cacheadas en la BD y refrescables en vivo con getPlayerInfo(forceRefresh).
// M3U: no existe user_info/server_info, así que solo se muestran los datos de la
// playlist (URL saneada, nombre, fecha), el conteo de ítems y la última sync.
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../database/database.dart';
import '../l10n/localization_extension.dart';
import '../models/api_response.dart';
import '../models/playlist_model.dart';
import '../repositories/user_preferences.dart';
import '../services/app_state.dart';
import '../services/service_locator.dart';
import '../utils/credential_scrubber.dart';
import '../widgets/info_tile_widget.dart';
import '../widgets/section_title_widget.dart';

/// Snapshot inmutable de todo lo que la pantalla necesita renderizar. Se resuelve
/// de una sola pasada (una Future) para que el FutureBuilder no parpadee sección
/// a sección.
class _DevInfo {
  final Playlist playlist;
  final ApiResponse? api; // null para M3U
  final String appVersion;
  final String buildNumber;
  final int schemaVersion;
  final DateTime? lastSync;
  final int liveCount;
  final int vodCount;
  final int seriesCount;
  final int m3uItemCount;

  _DevInfo({
    required this.playlist,
    required this.api,
    required this.appVersion,
    required this.buildNumber,
    required this.schemaVersion,
    required this.lastSync,
    required this.liveCount,
    required this.vodCount,
    required this.seriesCount,
    required this.m3uItemCount,
  });
}

class DeveloperScreen extends StatefulWidget {
  const DeveloperScreen({super.key});

  @override
  State<DeveloperScreen> createState() => _DeveloperScreenState();
}

class _DeveloperScreenState extends State<DeveloperScreen> {
  final AppDatabase _db = getIt<AppDatabase>();
  late Future<_DevInfo> _future;
  bool _refreshing = false;

  bool _dvr = false;

  @override
  void initState() {
    super.initState();
    _future = _load();
    UserPreferences.getDvrExperimental().then((v) {
      if (mounted) setState(() => _dvr = v);
    });
  }

  Future<_DevInfo> _load({bool forceRefresh = false}) async {
    final playlist = AppState.currentPlaylist!;
    final pid = playlist.id;
    final isXtream = playlist.type == PlaylistType.xtream;

    final pkg = await PackageInfo.fromPlatform();
    final lastSync = await UserPreferences.getLastSync(pid);

    // Conteos: no hay COUNT dedicado, así que se usan los getters de lista
    // existentes (aceptable en una pantalla técnica de apertura puntual).
    final liveCount = (await _db.getLiveStreams(pid)).length;
    final vodCount = (await _db.getVodStreamsByPlaylistId(pid)).length;
    final seriesCount = (await _db.getSeriesStreamsByPlaylistId(pid)).length;
    final m3uItemCount =
        isXtream ? 0 : (await _db.getM3uItemsByPlaylist(pid)).length;

    ApiResponse? api;
    if (isXtream && AppState.xtreamCodeRepository != null) {
      api = await AppState.xtreamCodeRepository!
          .getPlayerInfo(forceRefresh: forceRefresh);
    }

    return _DevInfo(
      playlist: playlist,
      api: api,
      appVersion: pkg.version,
      buildNumber: pkg.buildNumber,
      schemaVersion: _db.schemaVersion,
      lastSync: lastSync,
      liveCount: liveCount,
      vodCount: vodCount,
      seriesCount: seriesCount,
      m3uItemCount: m3uItemCount,
    );
  }

  Future<void> _refresh() async {
    if (_refreshing) return;
    // Fuerza getPlayerInfo(forceRefresh) para traer active_cons/time_now en vivo.
    // Reemplaza la Future para que el FutureBuilder repinte con datos frescos; el
    // propio FutureBuilder ya muestra el estado de error si la carga falla.
    final next = _load(forceRefresh: true);
    setState(() {
      _refreshing = true;
      _future = next;
    });
    try {
      await next;
    } catch (_) {
      // Tragado a propósito: el FutureBuilder pinta el fallo, aquí solo hay que
      // reponer el botón de refresco.
    }
    if (mounted) setState(() => _refreshing = false);
  }

  @override
  Widget build(BuildContext context) {
    final loc = context.loc;
    return Scaffold(
      appBar: AppBar(
        title: Text(loc.developer),
        actions: [
          IconButton(
            tooltip: loc.refresh,
            onPressed: _refreshing ? null : _refresh,
            icon: _refreshing
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh),
          ),
        ],
      ),
      body: FutureBuilder<_DevInfo>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final info = snap.data;
          if (info == null) {
            return Center(child: Text(loc.dev_no_data));
          }
          return ListView(
            padding: const EdgeInsets.only(bottom: 24),
            children: _sections(context, info),
          );
        },
      ),
    );
  }

  List<Widget> _sections(BuildContext context, _DevInfo info) {
    final loc = context.loc;
    final isXtream = info.playlist.type == PlaylistType.xtream;
    final widgets = <Widget>[];

    // --- Playlist (ambos tipos) ---------------------------------------------
    widgets.add(SectionTitleWidget(title: loc.dev_playlist));
    widgets.add(_tile(Icons.label_outline, loc.name, info.playlist.name));
    widgets.add(_tile(
      Icons.category_outlined,
      loc.dev_playlist,
      isXtream ? 'Xtream Codes' : 'M3U',
    ));
    if (info.playlist.url != null && info.playlist.url!.isNotEmpty) {
      final masked = scrubUrlForDisplay(info.playlist.url);
      widgets.add(_tile(Icons.link, loc.dev_source_url, masked, copy: true));
    }
    widgets.add(_tile(
      Icons.event_outlined,
      loc.dev_created,
      _fmtDate(info.playlist.createdAt),
    ));

    // --- Cuenta (solo Xtream) -----------------------------------------------
    final user = info.api?.userInfo;
    if (isXtream && user != null) {
      widgets.add(SectionTitleWidget(title: loc.dev_account));
      widgets.add(_tile(Icons.person_outline, loc.username, user.username));
      widgets.add(_tile(Icons.verified_user_outlined, loc.dev_status, user.status));
      widgets.add(_tile(
        Icons.timelapse_outlined,
        loc.dev_trial,
        _boolLabel(context, user.isTrial),
      ));
      widgets.add(_tile(
        Icons.event_busy_outlined,
        loc.dev_expires,
        _fmtUnix(user.expDate),
      ));
      widgets.add(_tile(
        Icons.settings_ethernet,
        loc.dev_active_connections,
        user.activeCons.isEmpty ? '—' : user.activeCons,
      ));
      widgets.add(_tile(
        Icons.groups_outlined,
        loc.dev_max_connections,
        user.maxConnections.isEmpty ? '—' : user.maxConnections,
      ));
      widgets.add(_tile(
        Icons.schedule_outlined,
        loc.dev_created,
        _fmtUnix(user.createdAt),
      ));
      if (user.allowedOutputFormats.isNotEmpty) {
        widgets.add(_tile(
          Icons.video_settings_outlined,
          loc.dev_output_formats,
          user.allowedOutputFormats.join(', '),
        ));
      }
    }

    // --- Servidor (solo Xtream) ---------------------------------------------
    final server = info.api?.serverInfo;
    if (isXtream && server != null) {
      widgets.add(SectionTitleWidget(title: loc.dev_server));
      if (server.url.isNotEmpty) {
        widgets.add(_tile(Icons.dns_outlined, loc.dev_server_url, server.url,
            copy: true));
      }
      if (server.port.isNotEmpty) {
        widgets.add(_tile(Icons.lan_outlined, loc.dev_port, server.port));
      }
      if (server.httpsPort.isNotEmpty) {
        widgets
            .add(_tile(Icons.https_outlined, loc.dev_https_port, server.httpsPort));
      }
      if (server.serverProtocol.isNotEmpty) {
        widgets.add(_tile(
            Icons.http_outlined, loc.dev_protocol, server.serverProtocol));
      }
      if (server.rtmpPort.isNotEmpty) {
        widgets
            .add(_tile(Icons.cast_outlined, loc.dev_rtmp_port, server.rtmpPort));
      }
      if (server.timezone.isNotEmpty) {
        widgets.add(
            _tile(Icons.public_outlined, loc.timezone, server.timezone));
      }
      if (server.timeNow.isNotEmpty) {
        widgets.add(_tile(
            Icons.access_time_outlined, loc.dev_server_time, server.timeNow));
      }
    }

    // --- Catálogo (ambos, con conteos según tipo) ---------------------------
    widgets.add(SectionTitleWidget(title: loc.dev_catalogue));
    if (isXtream) {
      widgets.add(_tile(
          Icons.live_tv_outlined, loc.live, info.liveCount.toString()));
      widgets.add(_tile(
          Icons.movie_outlined, loc.movies, info.vodCount.toString()));
      widgets.add(_tile(
          Icons.video_library_outlined, loc.dev_series, info.seriesCount.toString()));
    } else {
      widgets.add(_tile(
          Icons.playlist_play, loc.dev_items, info.m3uItemCount.toString()));
    }

    // --- Aplicación (ambos) -------------------------------------------------
    widgets.add(SectionTitleWidget(title: loc.dev_application));
    widgets.add(_tile(Icons.info_outline, loc.app_version, info.appVersion));
    widgets.add(_tile(
        Icons.build_outlined, loc.dev_build_number, info.buildNumber));
    widgets.add(_tile(
        Icons.storage_outlined,
        loc.dev_schema_version,
        info.schemaVersion.toString()));
    widgets.add(_tile(
      Icons.sync_outlined,
      loc.dev_last_sync,
      info.lastSync == null ? loc.dev_never : _fmtDate(info.lastSync!),
    ));

    // Experimental features (opt-in, may be unreliable).
    widgets.add(SectionTitleWidget(title: loc.dvr_experimental));
    widgets.add(SwitchListTile(
      secondary: const Icon(Icons.fiber_manual_record_outlined),
      title: Text(loc.dvr_experimental),
      subtitle: Text(loc.dvr_experimental_hint),
      value: _dvr,
      onChanged: (v) async {
        await UserPreferences.setDvrExperimental(v);
        if (mounted) setState(() => _dvr = v);
      },
    ));

    return widgets;
  }

  Widget _tile(IconData icon, String label, String value, {bool copy = false}) {
    final shown = value.isEmpty ? '—' : value;
    return InfoTileWidget(
      icon: icon,
      label: label,
      value: shown,
      // Se copia SOLO lo mostrado (ya saneado) — nunca el secreto real.
      copyOnTap: copy && value.isNotEmpty,
    );
  }

  String _boolLabel(BuildContext context, String raw) {
    final v = raw.trim();
    final truthy = v == '1' || v.toLowerCase() == 'true';
    return truthy ? context.loc.dev_yes : context.loc.dev_no;
  }

  static String _two(int n) => n.toString().padLeft(2, '0');

  static String _fmtDate(DateTime dt) {
    final l = dt.toLocal();
    return '${l.year}-${_two(l.month)}-${_two(l.day)} '
        '${_two(l.hour)}:${_two(l.minute)}';
  }

  /// Xtream entrega expDate/createdAt como segundos unix en un String. Se formatea
  /// a fecha legible; si no parsea (o es 0/vacío) se muestra el valor crudo.
  static String _fmtUnix(String s) {
    final trimmed = s.trim();
    if (trimmed.isEmpty) return '—';
    final sec = int.tryParse(trimmed);
    if (sec == null || sec == 0) return trimmed;
    return _fmtDate(DateTime.fromMillisecondsSinceEpoch(sec * 1000));
  }
}
