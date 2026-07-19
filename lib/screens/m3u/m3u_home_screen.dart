import 'package:rensi_iptv/l10n/localization_extension.dart';
import 'package:rensi_iptv/screens/global_search_screen.dart';
import 'package:rensi_iptv/screens/m3u/m3u_items_screen.dart';
import 'package:rensi_iptv/screens/m3u/m3u_playlist_settings_screen.dart';
import 'package:rensi_iptv/widgets/confirm_exit_scope.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:rensi_iptv/controllers/m3u_home_controller.dart';
import 'package:rensi_iptv/models/playlist_model.dart';
import 'package:rensi_iptv/models/category_view_model.dart';
import 'package:rensi_iptv/repositories/m3u_repository.dart';
import 'package:rensi_iptv/screens/category_detail_screen.dart';
import 'package:rensi_iptv/widgets/category_section.dart';
import 'package:rensi_iptv/utils/responsive_helper.dart';
import 'package:rensi_iptv/utils/navigate_by_content_type.dart';
import 'package:rensi_iptv/widgets/playlist_switcher_button.dart';
import 'package:rensi_iptv/widgets/tv/focus_highlight.dart';
import 'package:rensi_iptv/redesign/home_redesign.dart';
import 'package:rensi_iptv/redesign/browse_redesign.dart';
import 'package:rensi_iptv/redesign/live_redesign.dart';
import 'package:rensi_iptv/redesign/list_redesign.dart';
import 'package:rensi_iptv/redesign/search_redesign.dart';

import '../../services/app_state.dart';
import '../watch_history_screen.dart';
import 'package:rensi_iptv/widgets/tv/navigation_models.dart';

class M3UHomeScreen extends StatefulWidget {
  final Playlist playlist;
  final int initialIndex;

  const M3UHomeScreen({
    super.key,
    required this.playlist,
    this.initialIndex = 0,
  });

  @override
  State<M3UHomeScreen> createState() => _M3UHomeScreenState();
}

class _M3UHomeScreenState extends State<M3UHomeScreen> {
  late M3UHomeController _controller;

  static const double _desktopBreakpoint = 900.0;
  static const double _largeScreenBreakpoint = 1200.0;
  static const double _defaultNavWidth = 72.0;
  static const double _largeNavWidth = 88.0;
  // 10-foot rail. The old _large* values were gated behind a 1200dp breakpoint
  // that an Android TV never reaches (it reports 960dp), so the TV rail was
  // rendering at phone scale: 72dp wide with a 10dp label, unreadable at 3m.
  // Leanback guidance puts primary navigation at >=18sp.
  static const double _tvNavWidth = 104.0;
  static const double _tvItemHeight = 76.0;
  static const double _tvIconSize = 32.0;
  static const double _tvFontSize = 17.0;
  static const double _defaultItemHeight = 50.0;
  static const double _largeItemHeight = 56.0;
  static const double _defaultIconSize = 24.0;
  static const double _largeIconSize = 28.0;
  static const double _defaultFontSize = 10.0;
  static const double _largeFontSize = 11.0;

  // One focus node per rail item so a tab change (incl. programmatic ones)
  // moves focus to the target rail item instead of losing it.
  final Map<int, FocusNode> _railNodes = {};
  int _lastRailIndex = -1;

  FocusNode _railNode(int index) =>
      _railNodes.putIfAbsent(index, () => FocusNode(debugLabel: 'm3uRail$index'));

  void _maybeRefocusRail(int index) {
    if (index == _lastRailIndex) return;
    final firstBuild = _lastRailIndex == -1;
    _lastRailIndex = index;
    if (firstBuild) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !ResponsiveHelper.isDesktopOrTV(context)) return;
      _railNodes[index]?.requestFocus();
    });
  }

  @override
  void initState() {
    super.initState();
    _initializeController();
  }

  @override
  void dispose() {
    for (final n in _railNodes.values) {
      n.dispose();
    }
    _controller.dispose();
    super.dispose();
  }

  void _initializeController() {
    AppState.currentPlaylist = widget.playlist;
    AppState.m3uRepository = M3uRepository();
    _controller = M3UHomeController(initialIndex: widget.initialIndex);
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: _controller,
      child: Consumer<M3UHomeController>(
        builder: (context, controller, child) =>
            _buildMainContent(context, controller),
      ),
    );
  }

  Widget _buildMainContent(BuildContext context, M3UHomeController controller) {
    if (controller.isLoading) {
      return _buildLoadingScreen(context);
    }

    return ConfirmExitScope(
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Real TV/leanback always gets the side-rail layout; width is only a
          // fallback for large tablets / desktop windows.
          if (ResponsiveHelper.isDesktopOrTV(context) ||
              constraints.maxWidth >= _desktopBreakpoint) {
            return _buildDesktopLayout(context, controller, constraints);
          }

          return _buildMobileLayout(context, controller);
        },
      ),
    );
  }

  Widget _buildLoadingScreen(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(context.loc.loading_lists),
          ],
        ),
      ),
    );
  }

  Widget _buildMobileLayout(
    BuildContext context,
    M3UHomeController controller,
  ) {
    return Scaffold(
      body: _buildPageView(controller),
      bottomNavigationBar: _buildBottomNavigationBar(context, controller),
    );
  }

  Widget _buildDesktopLayout(
    BuildContext context,
    M3UHomeController controller,
    BoxConstraints constraints,
  ) {
    _maybeRefocusRail(controller.currentIndex);
    // Each column is its own FocusTraversalGroup so D-pad left/right
    // resolves the next focusable item in the *other* column (the
    // navigation rail or the page) without falling off the screen.
    return Scaffold(
      body: Row(
        children: [
          FocusTraversalGroup(
            child: _buildDesktopNavigationBar(context, controller, constraints),
          ),
          Expanded(
            child: FocusTraversalGroup(
              child: _buildPageView(controller),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPageView(M3UHomeController controller) {
    final pages = _buildPages(controller);
    // ExcludeFocus pulls hidden pages out of traversal. Do NOT wrap in a
    // FocusScope — it traps directional focus and makes the side rail
    // unreachable from the content. Initial focus is each page's own autofocus.
    return IndexedStack(
      index: controller.currentIndex,
      children: [
        for (int i = 0; i < pages.length; i++)
          ExcludeFocus(
            excluding: i != controller.currentIndex,
            child: pages[i],
          ),
      ],
    );
  }

  void _openSearch() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SearchRedesign(
          onOpen: (it) => navigateByContentType(context, it),
        ),
      ),
    );
  }

  List<Widget> _buildPages(M3UHomeController controller) {
    final movieCats = controller.vodCategories ?? const [];
    final seriesCats = controller.seriesCategories ?? const [];
    return [
      RedesignHome(
        key: ValueKey('inicio_${widget.playlist.id}'),
        movieCategories: movieCats,
        seriesCategories: seriesCats,
        onOpen: (it) => navigateByContentType(context, it),
        onPlay: (it) => playByContentType(context, it),
        onSearch: _openSearch,
        onSettings: () => controller.onNavigationTap(4),
        onSeeAll: _navigateToCategoryDetail,
        playlistSwitcher: PlaylistSwitcherButton(
          currentPlaylist: widget.playlist,
          currentIndex: controller.currentIndex,
        ),
      ),
      BrowseRedesign(
        movieCategories: movieCats,
        seriesCategories: seriesCats,
        onOpen: (it) => navigateByContentType(context, it),
        onSearch: _openSearch,
      ),
      LiveRedesign(
        liveCategories: controller.liveCategories ?? const [],
        onPlay: (it) => navigateByContentType(context, it),
      ),
      ListRedesign(
        key: ValueKey('milista_${controller.currentIndex == 3}'),
        onOpen: (it) => navigateByContentType(context, it),
      ),
      M3uPlaylistSettingsScreen(playlist: widget.playlist),
    ];
  }

  Widget _buildContentPage(
    List<CategoryViewModel> categories,
    M3UHomeController controller,
  ) {
    return NestedScrollView(
      headerSliverBuilder: (context, innerBoxIsScrolled) => [
        _buildSliverAppBar(context, controller),
      ],
      body: _buildCategoryList(categories),
    );
  }

  SliverAppBar _buildSliverAppBar(
    BuildContext context,
    M3UHomeController controller,
  ) {
    if (ResponsiveHelper.isDesktopOrTV(context)) {
      return _buildDesktopSliverAppBar(context, controller);
    }

    return _buildMobileSliverAppBar(context, controller);
  }

  SliverAppBar _buildDesktopSliverAppBar(
    BuildContext context,
    M3UHomeController controller,
  ) {
    return SliverAppBar(
      title: SelectableText(
        context.loc.live_streams,
        style: const TextStyle(fontWeight: FontWeight.bold),
      ),
      floating: true,
      snap: true,
      elevation: 0,
      actions: [
        PlaylistSwitcherButton(
          currentPlaylist: widget.playlist,
          currentIndex: controller.currentIndex,
        ),
      ],
    );
  }

  SliverAppBar _buildMobileSliverAppBar(
    BuildContext context,
    M3UHomeController controller,
  ) {
    return SliverAppBar(
      title: SelectableText(
        controller.getPageTitle(context),
        style: const TextStyle(fontWeight: FontWeight.bold),
      ),
      floating: true,
      snap: true,
      elevation: 0,
      actions: [
        PlaylistSwitcherButton(
          currentPlaylist: widget.playlist,
          currentIndex: controller.currentIndex,
        ),
      ],
    );
  }

  Widget _buildCategoryList(List<CategoryViewModel> categories) {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: categories.length,
      itemBuilder: (context, index) => _buildCategorySection(categories[index]),
    );
  }

  Widget _buildCategorySection(CategoryViewModel category) {
    return CategorySection(
      category: category,
      cardWidth: ResponsiveHelper.getCardWidth(context),
      cardHeight: ResponsiveHelper.getCardHeight(context),
      onSeeAllTap: () => _navigateToCategoryDetail(category),
      onContentTap: (content) => navigateByContentType(context, content),
    );
  }

  void _navigateToCategoryDetail(CategoryViewModel category) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CategoryDetailScreen(category: category),
      ),
    );
  }

  BottomNavigationBar _buildBottomNavigationBar(
    BuildContext context,
    M3UHomeController controller,
  ) {
    return BottomNavigationBar(
      currentIndex: controller.currentIndex,
      onTap: controller.onNavigationTap,
      type: BottomNavigationBarType.fixed,
      items: _buildBottomNavigationItems(context),
    );
  }

  List<BottomNavigationBarItem> _buildBottomNavigationItems(
    BuildContext context,
  ) {
    return _getNavigationItems(context).map((item) {
      // Same outline-inactive / filled-active semantics as the TV rail; the
      // bottom bar was painting every tab filled.
      return BottomNavigationBarItem(
        icon: Icon(item.resolve(false)),
        activeIcon: Icon(item.resolve(true)),
        label: item.label,
      );
    }).toList();
  }

  Widget _buildDesktopNavigationBar(
    BuildContext context,
    M3UHomeController controller,
    BoxConstraints constraints,
  ) {
    final navWidth = _getNavigationWidth(context, constraints.maxWidth);

    return Container(
      width: navWidth,
      decoration: _getNavigationBarDecoration(context),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _buildDesktopNavigationItems(context, controller, constraints),
        ],
      ),
    );
  }

  Widget _buildDesktopNavigationItems(
    BuildContext context,
    M3UHomeController controller,
    BoxConstraints constraints,
  ) {
    final items = _getNavigationItems(context);
    final sizes = _getNavigationSizes(context, constraints.maxWidth);

    return Column(
      children: items.map((item) {
        final isSelected = controller.currentIndex == item.index;
        return _buildNavigationItem(
          context,
          item,
          isSelected,
          sizes,
          item.onSelected ?? () => controller.onNavigationTap(item.index),
        );
      }).toList(),
    );
  }

  Widget _buildNavigationItem(
    BuildContext context,
    NavigationItem item,
    bool isSelected,
    NavigationSizes sizes,
    VoidCallback onTap,
  ) {
    return FocusHighlight(
      borderRadius: BorderRadius.circular(8),
      child: Container(
      width: double.infinity,
      height: sizes.itemHeight,
      // The left inset is what actually moves the item off the overscan strip;
      // reserving it in the rail's width alone did nothing, because a
      // full-width item spanned the reservation and the ring still hit x=0.
      margin: EdgeInsets.only(
          left: ResponsiveHelper.isDesktopOrTV(context)
              ? ResponsiveHelper.safeInset(context)
              : 0,
          top: 2,
          bottom: 2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        // Selected = quiet tint + accent bar; the bright treatment belongs to
        // focus alone. The old filled primaryContainer with accent text was
        // 3.65:1 — the current section was the least legible item in the rail.
        color: isSelected
            ? Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.08)
            : Colors.transparent,
      ),
      child: InkWell(
        onTap: onTap,
        focusNode: _railNode(item.index),
        // Don't autofocus the rail on entry — let page content take initial
        // focus; the rail stays reachable with LEFT.
        autofocus: false,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              item.resolve(isSelected),
              color: _getIconColor(context, isSelected),
              size: sizes.iconSize,
            ),
            const SizedBox(height: 2),
            // Keep long labels ("Configuración") on one line (shrink to fit).
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  item.label,
                  maxLines: 1,
                  style: TextStyle(
                    color: _getTextColor(context, isSelected),
                    fontSize: sizes.fontSize,
                    fontWeight:
                        isSelected ? FontWeight.bold : FontWeight.normal,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ],
        ),
      ),
      ),
    );
  }

  BoxDecoration _getNavigationBarDecoration(BuildContext context) {
    return BoxDecoration(
      color: Theme.of(context).colorScheme.surface,
      border: Border(
        right: BorderSide(color: Theme.of(context).dividerColor, width: 0.5),
      ),
    );
  }

  double _getNavigationWidth(BuildContext context, double screenWidth) {
    // Reserve the overscan inset on top of the rail: at x=0 the rail — and the
    // focus ring of whatever is selected in it — sits in the strip a consumer
    // TV crops.
    if (ResponsiveHelper.isDesktopOrTV(context)) {
      return _tvNavWidth + ResponsiveHelper.safeInset(context);
    }
    return screenWidth >= _largeScreenBreakpoint
        ? _largeNavWidth
        : _defaultNavWidth;
  }

  NavigationSizes _getNavigationSizes(BuildContext context, double screenWidth) {
    if (ResponsiveHelper.isDesktopOrTV(context)) {
      return NavigationSizes(
        itemHeight: _tvItemHeight,
        iconSize: _tvIconSize,
        fontSize: _tvFontSize,
      );
    }
    final isLargeScreen = screenWidth >= _largeScreenBreakpoint;

    return NavigationSizes(
      itemHeight: isLargeScreen ? _largeItemHeight : _defaultItemHeight,
      iconSize: isLargeScreen ? _largeIconSize : _defaultIconSize,
      fontSize: isLargeScreen ? _largeFontSize : _defaultFontSize,
    );
  }

  Color _getIconColor(BuildContext context, bool isSelected) {
    // Accent stays on the icon — it is a large shape, so it clears 3:1 — while
    // the label carries the contrast.
    return isSelected
        ? Theme.of(context).colorScheme.primary
        : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.72);
  }

  Color _getTextColor(BuildContext context, bool isSelected) {
    // The active section must be the MOST readable item, not the least. The
    // accent-on-tint pairing it used before measured 3.65:1, below AA.
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return isSelected ? onSurface : onSurface.withValues(alpha: 0.72);
  }

  List<NavigationItem> _getNavigationItems(BuildContext context) {
    return [
      NavigationItem(
          icon: Icons.home_rounded,
          iconOutlined: Icons.home_outlined,
          label: context.loc.nav_home,
          index: 0),
      // TV only. Search sits right under Home, where Google TV puts it: it is
      // how people reach a specific title in a catalogue of thousands, and on a
      // remote it was reachable only from a small icon in the top bar. It is
      // NOT added on phone: BottomNavigationBar indexes by position, so an item
      // that is an action rather than a page would shift every tab off its own
      // page.
      if (ResponsiveHelper.isDesktopOrTV(context))
        NavigationItem(
            icon: Icons.search_rounded,
            iconOutlined: Icons.search_outlined,
            label: context.loc.search,
            index: -1,
            onSelected: _openSearch),
      NavigationItem(
          icon: Icons.grid_view_rounded,
          iconOutlined: Icons.grid_view_outlined,
          label: context.loc.nav_browse,
          index: 1),
      NavigationItem(
          icon: Icons.live_tv_rounded,
          iconOutlined: Icons.live_tv_outlined,
          label: context.loc.nav_live,
          index: 2),
      NavigationItem(
          icon: Icons.bookmark_rounded,
          iconOutlined: Icons.bookmark_border_rounded,
          label: context.loc.nav_my_list,
          index: 3),
      NavigationItem(
        icon: Icons.settings_rounded,
        iconOutlined: Icons.settings_outlined,
        // nav_settings, not `settings`: the long form clipped against the right
        // edge of the bottom bar on a 360dp phone, and "Ajustes" is the standard
        // Android term in es-ES anyway.
        label: context.loc.nav_settings,
        index: 4,
      ),
    ];
  }
}


