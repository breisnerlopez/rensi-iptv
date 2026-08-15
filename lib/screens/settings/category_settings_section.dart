import 'package:rensi_iptv/repositories/user_preferences.dart';
import 'package:rensi_iptv/services/parental_service.dart';
import 'package:flutter/material.dart';
import 'package:rensi_iptv/l10n/localization_extension.dart';
import 'package:provider/provider.dart';
import '../../controllers/xtream_code_home_controller.dart';
import '../../redesign/rensi_widgets.dart';
import '../../widgets/section_title_widget.dart';

class CategorySettingsScreen extends StatefulWidget {
  final XtreamCodeHomeController controller;

  const CategorySettingsScreen({super.key, required this.controller});

  @override
  State<CategorySettingsScreen> createState() => _CategorySettingsScreenState();
}

class _CategorySettingsScreenState extends State<CategorySettingsScreen> {
  Set<String> _hiddenCategories = {};
  Set<String> _lockedCategories = {};
  bool _hasChanges = false;

  @override
  void initState() {
    super.initState();
    _loadHiddenCategories();
  }

  Future<void> _loadHiddenCategories() async {
    final hidden = await UserPreferences.getHiddenCategories();
    final locked = await UserPreferences.getLockedCategories();
    setState(() {
      _hiddenCategories = hidden.toSet();
      _lockedCategories = locked.toSet();
    });
  }

  /// Parental lock toggle for a category (asks for the PIN on open — the PIN is
  /// set in Settings; if none is set the lock is a no-op until then).
  Future<void> _toggleLocked(String categoryId) async {
    final adding = !_lockedCategories.contains(categoryId);
    setState(() {
      if (adding) {
        _lockedCategories.add(categoryId);
      } else {
        _lockedCategories.remove(categoryId);
      }
    });
    await UserPreferences.setLockedCategories(_lockedCategories.toList());
    // Locking is a no-op without a PIN — nudge the user to set one so the lock
    // actually gates content (fail-open otherwise).
    if (adding && !await ParentalService.instance.hasPin() && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.loc.parental_locked_note)),
      );
    }
  }

  Future<void> _toggleHidden(bool isVisible, String categoryId) async {
    setState(() {
      _hasChanges = true;
      if (isVisible) {
        _hiddenCategories.remove(categoryId);
      } else {
        _hiddenCategories.add(categoryId);
      }
    });
    await UserPreferences.setHiddenCategories(_hiddenCategories.toList());
    await widget.controller.refreshCategoryVisibility();
  }

  Future<void> _setAllCategoriesVisible(
    Iterable<String> ids,
    bool visible,
  ) async {
    setState(() {
      _hasChanges = true;
      if (visible) {
        _hiddenCategories.removeAll(ids);
      } else {
        _hiddenCategories.addAll(ids);
      }
    });
    await UserPreferences.setHiddenCategories(_hiddenCategories.toList());
    await widget.controller.refreshCategoryVisibility();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: widget.controller,
      child: PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, result) {
          if (didPop) return;
          Navigator.pop(context, _hasChanges);
        },
        child: Scaffold(
          appBar: AppBar(
            title: Text(context.loc.hide_category),
            leading: IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () {
                Navigator.pop(context, _hasChanges);
              },
            ),
          ),
          body: Consumer<XtreamCodeHomeController>(
            builder: (context, controller, _) {
              return RensiSafeColumn(
                verticalPadding: 8,
                child: ListView(
                children: [
                  SectionTitleWidget(title: context.loc.live),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => _setAllCategoriesVisible(
                          (widget.controller.liveCategories ?? const []).map(
                            (c) => c.category.categoryId,
                          ),
                          true,
                        ),
                        child: Text(context.loc.select_all),
                      ),
                      TextButton(
                        onPressed: () => _setAllCategoriesVisible(
                          (widget.controller.liveCategories ?? const []).map(
                            (c) => c.category.categoryId,
                          ),
                          false,
                        ),
                        child: Text(context.loc.deselect_all),
                      ),
                    ],
                  ),
                  ...?controller.liveCategories?.map((cat) {
                    final isHidden = _hiddenCategories.contains(
                      cat.category.categoryId,
                    );
                    final isLocked =
                        _lockedCategories.contains(cat.category.categoryId);
                    return SwitchListTile(
                      secondary: IconButton(
                        icon: Icon(isLocked
                            ? Icons.lock
                            : Icons.lock_open_outlined),
                        tooltip: context.loc.parental_lock_category,
                        onPressed: () =>
                            _toggleLocked(cat.category.categoryId),
                      ),
                      title: Text(cat.category.categoryName),
                      value: !isHidden,
                      onChanged: (val) =>
                          _toggleHidden(val, cat.category.categoryId),
                    );
                  }),

                  const Divider(),
                  SectionTitleWidget(title: context.loc.movies),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => _setAllCategoriesVisible(
                          widget.controller.movieCategories.map(
                            (c) => c.category.categoryId,
                          ),
                          true,
                        ),
                        child: Text(context.loc.select_all),
                      ),
                      TextButton(
                        onPressed: () => _setAllCategoriesVisible(
                          widget.controller.movieCategories.map(
                            (c) => c.category.categoryId,
                          ),
                          false,
                        ),
                        child: Text(context.loc.deselect_all),
                      ),
                    ],
                  ),
                  ...controller.movieCategories.map((cat) {
                    final isHidden = _hiddenCategories.contains(
                      cat.category.categoryId,
                    );
                    final isLocked =
                        _lockedCategories.contains(cat.category.categoryId);
                    return SwitchListTile(
                      secondary: IconButton(
                        icon: Icon(isLocked
                            ? Icons.lock
                            : Icons.lock_open_outlined),
                        tooltip: context.loc.parental_lock_category,
                        onPressed: () =>
                            _toggleLocked(cat.category.categoryId),
                      ),
                      title: Text(cat.category.categoryName),
                      value: !isHidden,
                      onChanged: (val) =>
                          _toggleHidden(val, cat.category.categoryId),
                    );
                  }),

                  const Divider(),
                  SectionTitleWidget(title: context.loc.series_plural),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => _setAllCategoriesVisible(
                          widget.controller.seriesCategories.map(
                            (c) => c.category.categoryId,
                          ),
                          true,
                        ),
                        child: Text(context.loc.select_all),
                      ),
                      TextButton(
                        onPressed: () => _setAllCategoriesVisible(
                          widget.controller.seriesCategories.map(
                            (c) => c.category.categoryId,
                          ),
                          false,
                        ),
                        child: Text(context.loc.deselect_all),
                      ),
                    ],
                  ),
                  ...controller.seriesCategories.map((cat) {
                    final isHidden = _hiddenCategories.contains(
                      cat.category.categoryId,
                    );
                    final isLocked =
                        _lockedCategories.contains(cat.category.categoryId);
                    return SwitchListTile(
                      secondary: IconButton(
                        icon: Icon(isLocked
                            ? Icons.lock
                            : Icons.lock_open_outlined),
                        tooltip: context.loc.parental_lock_category,
                        onPressed: () =>
                            _toggleLocked(cat.category.categoryId),
                      ),
                      title: Text(cat.category.categoryName),
                      value: !isHidden,
                      onChanged: (val) =>
                          _toggleHidden(val, cat.category.categoryId),
                    );
                  }),
                ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
