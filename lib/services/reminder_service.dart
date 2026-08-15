import 'package:drift/drift.dart' show Value;
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:rensi_iptv/database/database.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// Schedules a local notification a few minutes before an EPG programme starts.
/// Degradation-friendly for Android 14+, where exact alarms need a runtime
/// grant: it tries an EXACT alarm and, if that's not permitted, silently falls
/// back to an inexact one (the reminder still fires, just not to-the-second).
class ReminderService {
  ReminderService(this._db);
  final AppDatabase _db;

  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _inited = false;

  /// How long before the programme start the reminder fires.
  static const Duration lead = Duration(minutes: 5);

  static Future<void> _ensureInit() async {
    if (_inited) return;
    tzdata.initializeTimeZones();
    try {
      // Best-effort local zone; falls back to UTC if the platform name is odd.
      tz.setLocalLocation(tz.getLocation(await _deviceTimeZone()));
    } catch (_) {
      tz.setLocalLocation(tz.UTC);
    }
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const settings = InitializationSettings(android: android);
    await _plugin.initialize(settings);
    _inited = true;
  }

  static Future<String> _deviceTimeZone() async {
    // flutter_local_notifications doesn't expose the zone; DateTime's offset is
    // enough to pick a fixed-offset Etc/GMT zone when a name isn't available.
    final offset = DateTime.now().timeZoneOffset;
    if (offset == Duration.zero) return 'UTC';
    final hours = -offset.inHours; // Etc/GMT signs are inverted
    return 'Etc/GMT${hours >= 0 ? '+' : ''}$hours';
  }

  String reminderId(String playlistId, String channelId, DateTime start) =>
      '$playlistId:$channelId:${start.millisecondsSinceEpoch}';

  /// True if a reminder is already set for this programme.
  Future<bool> isSet(String playlistId, String channelId, DateTime start) async =>
      (await _db.getReminderById(reminderId(playlistId, channelId, start))) !=
      null;

  /// Schedule (or replace) a reminder. Returns false if the start (minus lead)
  /// is already in the past — nothing to schedule.
  Future<bool> schedule({
    required String playlistId,
    required String channelId,
    required String title,
    required DateTime start,
  }) async {
    final fireAt = start.subtract(lead);
    if (fireAt.isBefore(DateTime.now())) return false;
    await _ensureInit();
    final id = reminderId(playlistId, channelId, start);
    final notifId = id.hashCode & 0x7fffffff;

    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        'epg_reminders',
        'Programme reminders',
        channelDescription: 'Reminds you before a scheduled programme starts',
        importance: Importance.high,
        priority: Priority.high,
      ),
    );

    Future<void> doSchedule(AndroidScheduleMode mode) => _plugin.zonedSchedule(
          notifId,
          title,
          null,
          tz.TZDateTime.from(fireAt, tz.local),
          details,
          androidScheduleMode: mode,
          uiLocalNotificationDateInterpretation:
              UILocalNotificationDateInterpretation.absoluteTime,
        );

    try {
      await doSchedule(AndroidScheduleMode.exactAllowWhileIdle);
    } catch (_) {
      // Exact alarms not permitted (Android 14+ without the grant) → inexact.
      try {
        await doSchedule(AndroidScheduleMode.inexactAllowWhileIdle);
      } catch (e) {
        if (kDebugMode) debugPrint('ReminderService schedule failed: $e');
        return false;
      }
    }

    await _db.upsertReminder(RemindersCompanion.insert(
      id: id,
      channelId: channelId,
      playlistId: playlistId,
      title: title,
      start: start,
      notificationId: notifId,
    ));
    return true;
  }

  Future<void> cancel(
      String playlistId, String channelId, DateTime start) async {
    final id = reminderId(playlistId, channelId, start);
    final row = await _db.getReminderById(id);
    if (row != null) {
      await _ensureInit();
      await _plugin.cancel(row.notificationId);
      await _db.deleteReminderById(id);
    }
  }

  /// Toggle: schedule if not set, cancel if set. Returns the new state (true =
  /// reminder now active).
  Future<bool> toggle({
    required String playlistId,
    required String channelId,
    required String title,
    required DateTime start,
  }) async {
    if (await isSet(playlistId, channelId, start)) {
      await cancel(playlistId, channelId, start);
      return false;
    }
    return schedule(
      playlistId: playlistId,
      channelId: channelId,
      title: title,
      start: start,
    );
  }
}
