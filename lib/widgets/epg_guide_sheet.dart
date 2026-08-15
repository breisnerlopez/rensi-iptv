import 'package:flutter/material.dart';
import 'package:rensi_iptv/database/database.dart';
import 'package:rensi_iptv/l10n/localization_extension.dart';
import 'package:rensi_iptv/models/content_type.dart';
import 'package:rensi_iptv/models/playlist_content_model.dart';
import 'package:rensi_iptv/redesign/rensi_widgets.dart';
import 'package:rensi_iptv/services/reminder_service.dart';
import 'package:rensi_iptv/utils/app_themes.dart';
import 'package:rensi_iptv/utils/build_media_url.dart';
import 'package:rensi_iptv/utils/navigate_by_content_type.dart';
import 'package:rensi_iptv/services/service_locator.dart';
import 'package:rensi_iptv/widgets/player_widget.dart';

/// A per-channel programme guide (now + upcoming) from the stored full EPG.
/// Highlights the live programme, offers a reminder toggle on future ones, and
/// — when the channel has a catch-up archive — a "play from start" button on the
/// programmes still inside the provider's retention window.
/// Degrades gracefully to an empty state when no full guide is loaded.
class EpgGuideSheet extends StatefulWidget {
  const EpgGuideSheet({
    super.key,
    required this.channelId,
    required this.playlistId,
    required this.channelName,
    this.streamId,
    this.hasArchive = false,
    this.archiveDays = 0,
    this.categoryId,
  });

  final String channelId;
  final String playlistId;
  final String channelName;

  /// Live stream id used to build the catch-up/timeshift URL (null → no catch-up).
  final String? streamId;

  /// Whether this channel exposes a catch-up archive.
  final bool hasArchive;

  /// Days of archive the provider retains (bounds the catch-up window).
  final int archiveDays;

  /// Channel's category, for the parental gate on catch-up playback.
  final String? categoryId;

  @override
  State<EpgGuideSheet> createState() => _EpgGuideSheetState();
}

class _EpgGuideSheetState extends State<EpgGuideSheet> {
  late Future<List<EpgProgramData>> _future;
  late final ReminderService _reminders;
  // Reminder state per programme start, loaded lazily as the list builds.
  final Map<int, bool> _reminderOn = {};

  @override
  void initState() {
    super.initState();
    final db = getIt<AppDatabase>();
    _reminders = ReminderService(db);
    final now = DateTime.now();
    _future = _load(db, now);
  }

  /// Load the channel's programmes AND seed [_reminderOn] from the DB for the
  /// future ones, so the bell icon reflects reality on open. Without this the
  /// icon starts OFF even when a reminder is already set, and the first tap
  /// would silently CANCEL it (toggle is DB-authoritative) instead of adding.
  Future<List<EpgProgramData>> _load(AppDatabase db, DateTime now) async {
    // When the channel has a catch-up archive, list the past programmes still
    // inside the retention window so their "play from start" button is actually
    // reachable — not just the last hour. Bounded to keep the query sane.
    final from = (widget.hasArchive && widget.archiveDays > 0)
        ? now.subtract(Duration(days: widget.archiveDays.clamp(1, 14)))
        : now.subtract(const Duration(hours: 1));
    final progs = await db.getEpgForChannel(
      widget.channelId,
      widget.playlistId,
      from: from,
      to: now.add(const Duration(days: 2)),
    );
    for (final p in progs) {
      if (p.start.isAfter(now)) {
        final on = await _reminders.isSet(
            widget.playlistId, widget.channelId, p.start);
        if (on) _reminderOn[p.start.millisecondsSinceEpoch] = true;
      }
    }
    return progs;
  }

  String _fmt(DateTime d) {
    final l = d.toLocal();
    final h = l.hour.toString().padLeft(2, '0');
    final m = l.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  /// True when [p] can be replayed from the catch-up archive: the channel has an
  /// archive, the programme has already started, and its start is still inside
  /// the provider's retention window.
  bool _canCatchup(EpgProgramData p, DateTime now) {
    if (!widget.hasArchive || (widget.streamId ?? '').isEmpty) return false;
    if (!p.start.isBefore(now)) return false; // not started yet → use reminder
    // Same bounded window the guide is loaded over (_load): never offer catch-up
    // for a programme older than what we actually fetched, even if the provider
    // claims a longer retention.
    final oldestKept =
        now.subtract(Duration(days: widget.archiveDays.clamp(1, 14)));
    return p.start.isAfter(oldestKept);
  }

  Future<void> _playCatchup(EpgProgramData p) async {
    final loc = context.loc;
    // Parental gate: catch-up is a playback route, so it must honour a locked
    // category just like the live channel does.
    if (!await parentalAllowsCategory(context, widget.categoryId)) return;
    if (!mounted) return;
    final url = buildTimeshiftUrl(
      streamId: widget.streamId!,
      start: p.start,
      durationMinutes: p.stop.difference(p.start).inMinutes,
    );
    if (url == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(loc.epg_catchup_unavailable)),
      );
      return;
    }
    // A catch-up ContentItem plays as a seekable VOD (via overrideUrl) but is
    // marked transient so it never lands in "Continue watching".
    final item = ContentItem(
      widget.streamId!,
      p.title,
      '',
      ContentType.vod,
      duration: p.stop.difference(p.start),
      overrideUrl: url,
      isCatchup: true,
    );
    Navigator.of(context).pop(); // close the guide sheet first
    Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => Scaffold(
          backgroundColor: Colors.black,
          body: SafeArea(
            child: SizedBox.expand(
              child: PlayerWidget(contentItem: item),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final r = rensi(context);
    final loc = context.loc;
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Row(
                children: [
                  Icon(Icons.tv_outlined, color: r.accent),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '${loc.epg_guide} · ${widget.channelName}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontFamily: 'Bricolage Grotesque',
                        fontSize: AppThemes.bodySize,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Flexible(
              child: FutureBuilder<List<EpgProgramData>>(
                future: _future,
                builder: (context, snap) {
                  if (snap.connectionState == ConnectionState.waiting) {
                    return const Padding(
                      padding: EdgeInsets.all(32),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }
                  final progs = snap.data ?? const [];
                  if (progs.isEmpty) {
                    // No full guide loaded — honest empty state (add an XMLTV URL
                    // in Settings to populate it).
                    return Padding(
                      padding: const EdgeInsets.all(28),
                      child: Text(
                        loc.epg_xmltv_hint,
                        textAlign: TextAlign.center,
                        style: TextStyle(color: r.text3),
                      ),
                    );
                  }
                  final now = DateTime.now();
                  return ListView.builder(
                    shrinkWrap: true,
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                    itemCount: progs.length,
                    itemBuilder: (context, i) {
                      final p = progs[i];
                      final isLive =
                          !now.isBefore(p.start) && now.isBefore(p.stop);
                      final isFuture = p.start.isAfter(now);
                      final key = p.start.millisecondsSinceEpoch;
                      final reminderOn = _reminderOn[key] ?? false;
                      return Container(
                        margin: const EdgeInsets.only(bottom: 6),
                        decoration: BoxDecoration(
                          color: isLive ? r.surface3 : r.surface2,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                              color: isLive ? r.accent : r.hairline),
                        ),
                        child: ListTile(
                          dense: true,
                          leading: Text('${_fmt(p.start)}\n${_fmt(p.stop)}',
                              style: TextStyle(
                                  fontSize: AppThemes.labelSize,
                                  color: r.text3)),
                          title: Text(p.title,
                              maxLines: 2, overflow: TextOverflow.ellipsis),
                          subtitle: p.description == null
                              ? null
                              : Text(p.description!,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(color: r.text3)),
                          trailing: isFuture
                              ? IconButton(
                                  icon: Icon(reminderOn
                                      ? Icons.notifications_active
                                      : Icons.notifications_none),
                                  color: reminderOn ? r.accent : r.text2,
                                  tooltip: loc.set_reminder,
                                  onPressed: () async {
                                    // Al ACTIVAR, asegurar el permiso de
                                    // notificaciones primero: si no, el toggle
                                    // devolvería false y se mostraría el mensaje
                                    // engañoso "recordatorio quitado" cuando en
                                    // realidad nunca llegaría a avisar.
                                    final turningOn =
                                        !(_reminderOn[key] ?? false);
                                    if (turningOn &&
                                        !await ReminderService
                                            .ensureNotificationPermission()) {
                                      if (!context.mounted) return;
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(
                                          content: Text(
                                              loc.reminder_needs_notifications),
                                        ),
                                      );
                                      return;
                                    }
                                    final on = await _reminders.toggle(
                                      playlistId: widget.playlistId,
                                      channelId: widget.channelId,
                                      title: p.title,
                                      start: p.start,
                                    );
                                    if (!context.mounted) return;
                                    setState(() => _reminderOn[key] = on);
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(on
                                            ? loc.reminder_set
                                            : loc.reminder_removed),
                                      ),
                                    );
                                  },
                                )
                              : _canCatchup(p, now)
                                  ? IconButton(
                                      icon: const Icon(
                                          Icons.play_circle_outline),
                                      color: r.accent,
                                      tooltip: loc.epg_catchup_play,
                                      onPressed: () => _playCatchup(p),
                                    )
                                  : null,
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
