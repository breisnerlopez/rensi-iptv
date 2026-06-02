import 'dart:async';
import 'dart:convert';
import 'dart:io' show HttpClient;
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:file_picker/file_picker.dart';

import '../models/playlist_model.dart';
import '../repositories/user_preferences.dart';
import 'playlist_service.dart';
import 'tmdb_credentials_service.dart';

/// Public stats returned by the backup service so the UI can localize the
/// outcome message without having to inspect internal state.
class BackupImportResult {
  final int created;
  final int updated;
  final int skipped;

  const BackupImportResult({
    this.created = 0,
    this.updated = 0,
    this.skipped = 0,
  });

  int get total => created + updated;

  BackupImportResult copyWith({int? created, int? updated, int? skipped}) {
    return BackupImportResult(
      created: created ?? this.created,
      updated: updated ?? this.updated,
      skipped: skipped ?? this.skipped,
    );
  }
}

/// Strategy for handling playlists that already exist in the local database
/// during a restore.
enum BackupMergeStrategy {
  /// Overwrite existing playlists with the imported version.
  overwrite,

  /// Keep the local version when the same id already exists. Imported
  /// playlists that do not exist locally are still added.
  keepLocal,
}

class BackupFormatException implements Exception {
  final String code;
  final String? detail;
  BackupFormatException(this.code, [this.detail]);

  @override
  String toString() =>
      detail == null ? 'BackupFormatException($code)' : 'BackupFormatException($code): $detail';
}

class BackupService {
  static const int _schemaVersion = 1;

  /// Magic header (8 bytes) used to identify encrypted backups produced by
  /// this app. Encrypted layout (big-endian):
  ///   magic(8) | version(1) | iterations(uint32) | salt(16) | nonce(12) | ciphertext(...) | mac(16)
  static const _encMagic = [0x41, 0x49, 0x50, 0x42, 0x41, 0x4b, 0x76, 0x31]; // "AIPBAKv1"
  static const _encVersion = 1;
  static const _pbkdf2Iterations = 200000;
  static const _saltLen = 16;
  static const _nonceLen = 12;

  static final _algo = AesGcm.with256bits();

  static Future<Uint8List> exportBytes({
    String? passphrase,
    bool includeSecrets = true,
  }) async {
    final playlists = await PlaylistService.getPlaylists();
    final settings = await UserPreferences.exportSettings();
    final credentials = <String, dynamic>{};
    if (includeSecrets) {
      final tmdb = await TmdbCredentialsService.getCredential();
      if (tmdb != null && tmdb.isNotEmpty) {
        credentials['tmdb'] = tmdb;
      }
    }
    final payload = {
      'schemaVersion': _schemaVersion,
      'exportedAt': DateTime.now().toUtc().toIso8601String(),
      'includesSecrets': includeSecrets,
      'playlists': playlists
          .map((playlist) => playlist.toJson(includeSecrets: includeSecrets))
          .toList(),
      'settings': settings,
      if (credentials.isNotEmpty) 'credentials': credentials,
    };
    final plain = Uint8List.fromList(utf8.encode(jsonEncode(payload)));
    if (passphrase == null || passphrase.isEmpty) {
      return plain;
    }
    return _encrypt(plain, passphrase);
  }

  static Future<bool> exportToFile({
    String? passphrase,
    bool includeSecrets = true,
  }) async {
    final bytes = await exportBytes(
      passphrase: passphrase,
      includeSecrets: includeSecrets,
    );
    final date = DateTime.now().toIso8601String().split('T').first;
    final isEncrypted = passphrase != null && passphrase.isNotEmpty;
    final fileName = isEncrypted
        ? 'rensi-iptv-backup-$date.aipbak'
        : 'rensi-iptv-backup-$date.json';
    // Same FileType.any rationale as pickBackupFile — the SAF picker on
    // some Android TV firmwares (Mi Box, certain Realtek boxes) rejects
    // the MIME-constrained intent and would otherwise throw here.
    final path = await FilePicker.platform.saveFile(
      dialogTitle: 'Export playlists and settings',
      fileName: fileName,
      type: FileType.any,
      bytes: bytes,
    );
    return path != null;
  }

  /// Returns the raw bytes of the picked backup file, so the UI can prompt for
  /// a passphrase before attempting decryption.
  ///
  /// FileType.any is intentional: FileType.custom + allowedExtensions builds
  /// an ACTION_OPEN_DOCUMENT intent with MIME constraints that Android TV
  /// boxes (e.g. Mi Box) reject with ActivityNotFoundException because their
  /// SAF document provider doesn't advertise those types. FileType.any maps
  /// to a broader picker that's available on virtually every Android build,
  /// and the content is validated by [looksEncrypted] / JSON parsing
  /// downstream so extension filtering is purely a UX nicety.
  static Future<Uint8List?> pickBackupFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.any,
      allowMultiple: false,
      withData: true,
    );
    return result?.files.single.bytes;
  }

  /// Maximum size we will accept for a remote backup file. Matches the
  /// M3U URL fetcher's cap so a buggy or malicious URL can't OOM the app.
  static const int _maxRemoteBackupBytes = 50 * 1024 * 1024;

  /// Downloads a backup file from an http(s) URL and returns the raw bytes.
  ///
  /// Intended as an SAF-less alternative for Android TV boxes (Mi Box,
  /// etc.) whose stripped DocumentsUI rejects the file picker. The caller
  /// keeps using [importBytes] on the result, so the encryption /
  /// schema / merge logic stays in one place.
  ///
  /// Throws [BackupFormatException] with codes:
  ///   - `backup_url_invalid`    — scheme / parse error
  ///   - `backup_url_too_large`  — content-length exceeds [_maxRemoteBackupBytes]
  ///   - `backup_url_http_error` — non-2xx response
  ///   - `backup_url_fetch_failed` — network / IO failure
  static Future<Uint8List> fetchBackupFromUrl(String url) async {
    final uri = Uri.tryParse(url.trim());
    if (uri == null || !(uri.isScheme('http') || uri.isScheme('https'))) {
      throw BackupFormatException('backup_url_invalid', url);
    }
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 20);
    try {
      final request = await client
          .getUrl(uri)
          .timeout(const Duration(seconds: 60));
      final response =
          await request.close().timeout(const Duration(seconds: 60));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw BackupFormatException(
          'backup_url_http_error',
          'HTTP ${response.statusCode}',
        );
      }
      if (response.contentLength > _maxRemoteBackupBytes) {
        throw BackupFormatException(
          'backup_url_too_large',
          '${response.contentLength}',
        );
      }
      final builder = BytesBuilder(copy: false);
      await for (final chunk in response) {
        builder.add(chunk);
        if (builder.length > _maxRemoteBackupBytes) {
          throw BackupFormatException('backup_url_too_large', '${builder.length}');
        }
      }
      return builder.takeBytes();
    } on BackupFormatException {
      rethrow;
    } catch (e) {
      throw BackupFormatException('backup_url_fetch_failed', e.toString());
    } finally {
      client.close(force: true);
    }
  }

  static bool looksEncrypted(Uint8List bytes) {
    if (bytes.length < _encMagic.length) return false;
    for (var i = 0; i < _encMagic.length; i++) {
      if (bytes[i] != _encMagic[i]) return false;
    }
    return true;
  }

  static Future<BackupImportResult> importBytes(
    Uint8List bytes, {
    String? passphrase,
    BackupMergeStrategy strategy = BackupMergeStrategy.overwrite,
  }) async {
    Uint8List plain;
    if (looksEncrypted(bytes)) {
      if (passphrase == null || passphrase.isEmpty) {
        throw BackupFormatException('backup_passphrase_required');
      }
      try {
        plain = await _decrypt(bytes, passphrase);
      } on SecretBoxAuthenticationError {
        throw BackupFormatException('backup_passphrase_invalid');
      }
    } else {
      plain = bytes;
    }

    Map<String, dynamic> decoded;
    try {
      final raw = jsonDecode(utf8.decode(plain));
      if (raw is! Map<String, dynamic>) {
        throw BackupFormatException('backup_invalid_format');
      }
      decoded = raw;
    } on FormatException catch (e) {
      throw BackupFormatException('backup_invalid_format', e.message);
    }

    final schemaVersion = decoded['schemaVersion'];
    if (schemaVersion is! int) {
      throw BackupFormatException('backup_invalid_format', 'schemaVersion');
    }
    if (schemaVersion > _schemaVersion) {
      throw BackupFormatException(
        'backup_schema_unsupported',
        schemaVersion.toString(),
      );
    }

    final settings = decoded['settings'];
    if (settings is Map<String, dynamic>) {
      await UserPreferences.importSettings(settings);
    }

    final credentials = decoded['credentials'];
    if (credentials is Map<String, dynamic>) {
      final tmdb = credentials['tmdb'];
      if (tmdb is String && tmdb.isNotEmpty) {
        // Honour the same conflict policy as playlists: when the user picked
        // "keep local", we don't clobber an existing credential.
        final existing = await TmdbCredentialsService.getCredential();
        if (existing == null || strategy == BackupMergeStrategy.overwrite) {
          await TmdbCredentialsService.saveCredential(tmdb);
        }
      }
    }

    final playlists = decoded['playlists'];
    if (playlists is! List) {
      return const BackupImportResult();
    }

    var created = 0;
    var updated = 0;
    var skipped = 0;
    for (final item in playlists) {
      if (item is! Map<String, dynamic>) {
        skipped++;
        continue;
      }
      final playlist = Playlist.fromJson(item);
      final existing = await PlaylistService.getPlaylistById(playlist.id);
      if (existing == null) {
        await PlaylistService.savePlaylist(playlist);
        created++;
      } else {
        if (strategy == BackupMergeStrategy.keepLocal) {
          skipped++;
          continue;
        }
        await PlaylistService.updatePlaylist(playlist);
        updated++;
      }
    }
    return BackupImportResult(
      created: created,
      updated: updated,
      skipped: skipped,
    );
  }

  static Future<BackupImportResult> importFromFile({
    String? passphrase,
    BackupMergeStrategy strategy = BackupMergeStrategy.overwrite,
  }) async {
    final bytes = await pickBackupFile();
    if (bytes == null) return const BackupImportResult();
    return importBytes(bytes, passphrase: passphrase, strategy: strategy);
  }

  // --- Encryption helpers ---

  static Uint8List _randomBytes(int length) {
    final rng = Random.secure();
    final out = Uint8List(length);
    for (var i = 0; i < length; i++) {
      out[i] = rng.nextInt(256);
    }
    return out;
  }

  static Future<SecretKey> _deriveKey(
    String passphrase,
    Uint8List salt,
    int iterations,
  ) async {
    final pbkdf2 = Pbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: iterations,
      bits: 256,
    );
    return pbkdf2.deriveKey(
      secretKey: SecretKey(utf8.encode(passphrase)),
      nonce: salt,
    );
  }

  static Future<Uint8List> _encrypt(
    Uint8List plain,
    String passphrase,
  ) async {
    final salt = _randomBytes(_saltLen);
    final nonce = _randomBytes(_nonceLen);
    final key = await _deriveKey(passphrase, salt, _pbkdf2Iterations);
    final box = await _algo.encrypt(plain, secretKey: key, nonce: nonce);
    final mac = box.mac.bytes;

    final out = BytesBuilder(copy: false);
    out.add(_encMagic);
    out.addByte(_encVersion);
    final iterBytes = ByteData(4)..setUint32(0, _pbkdf2Iterations, Endian.big);
    out.add(iterBytes.buffer.asUint8List());
    out.add(salt);
    out.add(nonce);
    out.add(box.cipherText);
    out.add(mac);
    return out.toBytes();
  }

  static Future<Uint8List> _decrypt(
    Uint8List bytes,
    String passphrase,
  ) async {
    var offset = _encMagic.length;
    if (bytes.length < offset + 1 + 4 + _saltLen + _nonceLen + 16) {
      throw BackupFormatException('backup_invalid_format', 'truncated');
    }
    final version = bytes[offset];
    offset += 1;
    if (version != _encVersion) {
      throw BackupFormatException(
        'backup_schema_unsupported',
        'encv$version',
      );
    }
    final iterations = ByteData.sublistView(bytes, offset, offset + 4)
        .getUint32(0, Endian.big);
    offset += 4;
    final salt = Uint8List.sublistView(bytes, offset, offset + _saltLen);
    offset += _saltLen;
    final nonce = Uint8List.sublistView(bytes, offset, offset + _nonceLen);
    offset += _nonceLen;
    final macLen = 16;
    final cipherEnd = bytes.length - macLen;
    final cipherText = Uint8List.sublistView(bytes, offset, cipherEnd);
    final mac = Mac(Uint8List.sublistView(bytes, cipherEnd, bytes.length));

    final key = await _deriveKey(passphrase, salt, iterations);
    final clear = await _algo.decrypt(
      SecretBox(cipherText, nonce: nonce, mac: mac),
      secretKey: key,
    );
    return Uint8List.fromList(clear);
  }
}
