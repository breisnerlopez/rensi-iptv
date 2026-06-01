/// Sentinel category id used to denote the synthetic "All movies" / "All
/// series" pseudo-category injected at the top of the Xtream-codes home
/// screen.
///
/// When [CategoryDetailScreen] / [ContentService] / [CategorySection] see
/// this id they aggregate every item of the matching content type instead
/// of querying by `category_id`, and they substitute the title with the
/// localised "View all …" string at render time.
///
/// The id is prefixed with double underscores so it cannot collide with
/// any real `category_id` returned by Xtream Codes (those are numeric
/// strings).
const String kAllCategoryId = '__rensi_all__';

bool isAllCategorySentinel(String? categoryId) =>
    categoryId == kAllCategoryId;
