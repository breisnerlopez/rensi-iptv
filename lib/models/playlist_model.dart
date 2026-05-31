import 'package:rensi_iptv/utils/type_convertions.dart';

const Object _sentinel = Object();

class Playlist {
  final String id;
  final String name;
  final PlaylistType type;
  final String? url;
  final String? username;
  final String? password;
  final DateTime createdAt;

  Playlist({
    required this.id,
    required this.name,
    required this.type,
    this.url,
    this.username,
    this.password,
    required this.createdAt,
  });

  Playlist copyWith({
    String? id,
    String? name,
    PlaylistType? type,
    Object? url = _sentinel,
    Object? username = _sentinel,
    Object? password = _sentinel,
    DateTime? createdAt,
  }) {
    return Playlist(
      id: id ?? this.id,
      name: name ?? this.name,
      type: type ?? this.type,
      url: identical(url, _sentinel) ? this.url : url as String?,
      username:
          identical(username, _sentinel) ? this.username : username as String?,
      password:
          identical(password, _sentinel) ? this.password : password as String?,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Playlist withoutSecrets() {
    return Playlist(id: id, name: name, type: type, createdAt: createdAt);
  }

  Map<String, dynamic> toJson({bool includeSecrets = true}) {
    return {
      'id': id,
      'name': name,
      'type': type.toString(),
      if (includeSecrets) 'url': url,
      if (includeSecrets) 'username': username,
      if (includeSecrets) 'password': password,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  factory Playlist.fromJson(Map<String, dynamic> json) {
    String? optional(dynamic value) {
      if (value == null) return null;
      final str = safeString(value);
      return str.isEmpty ? null : str;
    }

    return Playlist(
      id: safeString(json['id']),
      name: safeString(json['name']),
      type: PlaylistType.values.firstWhere(
        (e) => e.toString() == json['type'],
        orElse: () => PlaylistType.m3u,
      ),
      url: optional(json['url']),
      username: optional(json['username']),
      password: optional(json['password']),
      createdAt:
          DateTime.tryParse(safeString(json['createdAt'])) ?? DateTime.now(),
    );
  }
}

enum PlaylistType { xtream, m3u }
