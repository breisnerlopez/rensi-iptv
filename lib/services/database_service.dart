import 'package:rensi_iptv/services/service_locator.dart';

import '../database/database.dart';
import '../models/playlist_model.dart';

class DatabaseService {
  static AppDatabase get database => getIt<AppDatabase>();

  // Playlist kaydet
  static Future<void> savePlaylist(Playlist playlist) async {
    await database.insertPlaylist(playlist);
  }

  // Tüm playlistleri getir
  static Future<List<Playlist>> getPlaylists() async {
    return await database.getAllPlaylists();
  }

  // Playlist sil
  static Future<void> deletePlaylist(String id) async {
    await database.deletePlaylistById(id);
  }

  // Playlist güncelle
  static Future<void> updatePlaylist(Playlist playlist) async {
    await database.updatePlaylist(playlist);
  }

  // ID'ye göre playlist getir
  static Future<Playlist?> getPlaylistById(String id) async {
    return await database.getPlaylistById(id);
  }

  // Tip filtreleme
  static Future<List<Playlist>> getPlaylistsByType(PlaylistType type) async {
    return await database.getPlaylistsByType(type);
  }

  // Veritabanını kapat
  static Future<void> close() async {
    await database.close();
  }
}
