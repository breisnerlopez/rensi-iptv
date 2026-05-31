import 'package:rensi_iptv/models/category.dart';
import 'package:rensi_iptv/models/playlist_content_model.dart';

class CategoryViewModel {
  final Category category;
  final List<ContentItem> contentItems;

  CategoryViewModel({required this.category, required this.contentItems});
}