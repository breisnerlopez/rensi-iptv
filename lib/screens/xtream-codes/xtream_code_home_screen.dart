import 'dart:async';

import 'package:rensi_iptv/l10n/localization_extension.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:rensi_iptv/repositories/user_preferences.dart';
import 'package:rensi_iptv/services/player_state.dart';
import 'package:rensi_iptv/controllers/xtream_code_home_controller.dart';
import 'package:rensi_iptv/models/api_configuration_model.dart';
import 'package:rensi_iptv/models/category_view_model.dart';
import 'package:rensi_iptv/models/playlist_model.dart';
import 'package:rensi_iptv/controllers/watch_history_controller.dart';
import 'package:rensi_iptv/models/content_type.dart';
import 'package:rensi_iptv/models/watch_history.dart';
import 'package:rensi_iptv/repositories/iptv_repository.dart';
import 'package:rensi_iptv/screens/category_detail_screen.dart';
import 'package:rensi_iptv/screens/xtream-codes/xtream_code_playlist_settings_screen.dart';
import 'package:rensi_iptv/services/app_state.dart';
import 'package:rensi_iptv/services/event_bus.dart';
import 'package:rensi_iptv/utils/navigate_by_content_type.dart';
import 'package:rensi_iptv/utils/responsive_helper.dart';
import 'package:rensi_iptv/widgets/confirm_exit_scope.dart';
import 'package:rensi_iptv/widgets/playlist_switcher_button.dart';
import 'package:rensi_iptv/widgets/tv/focus_highlight.dart';
import 'package:rensi_iptv/redesign/home_redesign.dart';
import 'package:rensi_iptv/redesign/browse_redesign.dart';
import 'package:rensi_iptv/redesign/continue_watching_all_screen.dart';
import 'package:rensi_iptv/redesign/list_redesign.dart';
import 'package:rensi_iptv/redesign/live_redesign.dart';
import 'package:rensi_iptv/redesign/search_redesign.dart';
import 'package:rensi_iptv/widgets/tv/navigation_models.dart';
import 'package:rensi_iptv/services/epg_service.dart';

class XtreamCodeHomeScreen extends StatefulWidget {
  final Playlist playlist;
  final int initialIndex;

  const XtreamCodeHomeScreen({
    super.key,
    required this.playlist,
    this.initialIndex = 0,
  });

  @override
  State<XtreamCodeHomeScreen> createState() => _XtreamCodeHomeScreenState();
}

class _XtreamCodeHomeScreenState extends State<XtreamCodeHomeScreen>
    with WidgetsBindingObserver {
  late XtreamCodeHomeController _controller;

  /// Refresh the catalogue in the background when the user returns to a
  /// playlist last synced more than this ago. Internal constant, not exposed.
  static const Duration _staleAfter = Duration(hours: 4);
  late EpgService _epgService;

  /// Continue-watching, loaded here because the home screen is the only place
  /// that shows it. The rail has existed since the redesign landed and has
  /// never once appeared: `continueWatching` defaulted to an empty list and no
  /// caller ever passed anything, so the feature shipped inert.
  final WatchHistoryController _history = WatchHistoryController();
  StreamSubscription<dynamic>? _historyChangedSub;

  /// Drives the rail's dimming: full strength only while it holds the focus.
  bool _railHasFocus = false;
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
  // One focus node per rail item, so a tab change (incl. programmatic ones like
  // the avatar → settings shortcut) can move focus to the target rail item
  // instead of losing it when the previous page gets ExcludeFocus'd.
  final Map<int, FocusNode> _railNodes = {};
  int _lastRailIndex = -1;

  FocusNode _railNode(int index) =>
      _railNodes.putIfAbsent(index, () => FocusNode(debugLabel: 'rail$index'));

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeController();
    // Refrescar "Continuar viendo" en cuanto se guarda historial (ver algo local
    // o castear a la TV), sin depender de cambiar de pestaña.
    _historyChangedSub = EventBus()
        .on<dynamic>('history_changed')
        .listen((_) => mounted ? _history.loadWatchHistory() : null);
    // Also check on first mount: a cold start into a stale last-playlist should
    // freshen too, not only an app resume.
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _maybeBackgroundRefresh());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_maybeBackgroundRefresh());
    }
  }

  /// Quietly refresh the active playlist's catalogue if it's stale. Guards keep
  /// it invisible and cheap: skip while watching (PiP resume included), while a
  /// refresh is already running, when fresh, and — on mobile — off Wi-Fi.
  Future<void> _maybeBackgroundRefresh() async {
    if (!mounted) return;
    final playlist = AppState.currentPlaylist;
    if (playlist == null || playlist.type != PlaylistType.xtream) return;
    if (PlayerState.isPlayerActive) return;
    if (_controller.isRefreshing) return;
    final last = await UserPreferences.getLastSync(playlist.id);
    if (last != null && DateTime.now().difference(last) < _staleAfter) return;
    // A TV is wired/plugged; a phone on cellular should not spend data silently.
    if (!ResponsiveHelper.isTelevisionDevice) {
      try {
        final conn = await Connectivity().checkConnectivity();
        final onUnmetered = conn.contains(ConnectivityResult.wifi) ||
            conn.contains(ConnectivityResult.ethernet);
        if (!onUnmetered) return;
      } catch (_) {
        // Can't tell the connection type → err on the side of not spending data.
        return;
      }
    }
    if (!mounted) return;
    await _controller.refreshInBackground();
  }

  void _onHistoryChanged() {
    if (mounted) setState(() {});
  }

  /// Reloads continue-watching whenever Inicio comes back to the front.
  ///
  /// Settings is page 4 of this same IndexedStack, so "clear all history" runs
  /// a few centimetres away from this rail and never told it. Without this the
  /// viewer wipes their history, returns to Inicio, sees the same cards, and
  /// every one of them fails silently on tap because its row is gone.
  int _lastIndex = 0;
  void _onTabChanged() {
    final i = _controller.currentIndex;
    if (i == 0 && _lastIndex != 0) _history.loadWatchHistory();
    _lastIndex = i;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _historyChangedSub?.cancel();
    _controller.removeListener(_onTabChanged);
    _history.removeListener(_onHistoryChanged);
    _history.dispose();
    for (final n in _railNodes.values) {
      n.dispose();
    }
    _controller.dispose();
    super.dispose();
  }

  /// On a tab change, land focus on the target rail item (TV only). Skips the
  /// initial build so the page's own autofocus (e.g. the Home hero) wins.
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

  void _initializeController() {
    AppState.currentPlaylist = widget.playlist;
    final repository = IptvRepository(
      ApiConfig(
        baseUrl: widget.playlist.url!,
        username: widget.playlist.username!,
        password: widget.playlist.password!,
      ),
      widget.playlist.id,
    );
    AppState.xtreamCodeRepository = repository;
    // One service per playlist, and rebuilt here so switching playlists cannot
    // serve the previous panel's schedule: stream ids are only unique within a
    // provider, so a shared cache would show the wrong programme.
    // Rebuilt per playlist AND explicitly emptied: stream ids are only unique
    // within a provider, so carrying entries across would show one panel's
    // schedule on another's channels. A test asserted this guarantee while
    // production never exercised it.
    _epgService = EpgService(repository.getShortEpg)..invalidate();
    // After the playlist is in AppState: the controller reads it to scope the
    // query, and reading it earlier returns the previous playlist's history.
    // The load is async and the rail is built from a plain getter, so without
    // a listener the home paints once with an empty list and never again.
    _history.addListener(_onHistoryChanged);
    _history.loadWatchHistory();
    _controller = XtreamCodeHomeController(
      false,
      initialIndex: widget.initialIndex,
    );
    // After the controller exists: the tab listener is what reloads the rail
    // when Inicio comes back to the front.
    _controller.addListener(_onTabChanged);
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: _controller,
      child: Consumer<XtreamCodeHomeController>(
        builder: (context, controller, child) =>
            _buildMainContent(context, controller),
      ),
    );
  }

  Widget _buildMainContent(
    BuildContext context,
    XtreamCodeHomeController controller,
  ) {
    if (controller.isLoading) {
      return _buildLoadingScreen(context);
    }
    return ConfirmExitScope(
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Real TV/leanback always gets the side-rail layout. Width takes over
          // at 600dp — Material 3's breakpoint, and where every tablet
          // streaming app switches. A 10" tablet reports 800dp and was still
          // stretching a five-tab bottom bar across it.
          if (ResponsiveHelper.useNavigationRail(context)) {
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
            Text(context.loc.loading_playlists),
          ],
        ),
      ),
    );
  }

  Widget _buildMobileLayout(
    BuildContext context,
    XtreamCodeHomeController controller,
  ) {
    return Scaffold(
      body: _withRefreshLine(_buildPageView(controller)),
      bottomNavigationBar: _buildBottomNavigationBar(context, controller),
    );
  }

  Widget _buildDesktopLayout(
    BuildContext context,
    XtreamCodeHomeController controller,
    BoxConstraints constraints,
  ) {
    _maybeRefocusRail(controller.currentIndex);
    // Each column is its own FocusTraversalGroup so D-pad left/right
    // resolves the next focusable item in the *other* column (the
    // navigation rail or the page) without falling off the screen.
    return Scaffold(
      body: _withRefreshLine(Row(
        children: [
          // Dimmed while the focus lives in the content. With both areas at
          // full strength the eye reads two active zones and you have to hunt
          // for the white ring to know where you are — Netflix collapses the
          // rail, Google TV fades it to about half.
          FocusTraversalGroup(
            child: Focus(
              canRequestFocus: false,
              skipTraversal: true,
              onFocusChange: (f) {
                if (f != _railHasFocus) setState(() => _railHasFocus = f);
              },
              child: AnimatedOpacity(
                opacity: _railHasFocus ? 1.0 : 0.45,
                duration: const Duration(milliseconds: 200),
                child: _buildDesktopNavigationBar(
                    context, controller, constraints),
              ),
            ),
          ),
          Expanded(
            child: FocusTraversalGroup(
              child: _buildPageView(controller),
            ),
          ),
        ],
      )),
    );
  }

  /// Overlays a thin, delayed background-refresh line at the very top of the
  /// shell. Invisible unless a refresh runs past ~3s (see [_RefreshLine]).
  Widget _withRefreshLine(Widget child) {
    return Stack(
      children: [
        Positioned.fill(child: child),
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: _RefreshLine(_controller),
        ),
      ],
    );
  }

  // Tabs that have actually been opened at least once. Building all five pages
  // up front (Home + Browse + Live + My-list + full Settings) at entry is a
  // startup jank spike on a weak TV — each carries its own first viewport of
  // deep poster tiles. We build a tab the first time it becomes current and
  // keep it mounted thereafter, so tab-switch state still survives.
  final Set<int> _visitedTabs = {};

  Widget _buildPageView(XtreamCodeHomeController controller) {
    _visitedTabs.add(controller.currentIndex);
    // IndexedStack keeps every page mounted (so state survives tab switches),
    // but the off-screen pages stay in the focus tree — on TV the D-pad can
    // then jump focus into an invisible page and "disappear". ExcludeFocus
    // pulls the hidden pages out of traversal so focus stays on screen.
    // NOTE: do NOT wrap pages in a FocusScope — it traps directional focus and
    // makes the side rail unreachable from the content. Initial focus is
    // handled by each page's own `autofocus` (e.g. the Home hero Play button).
    return IndexedStack(
      index: controller.currentIndex,
      children: [
        for (int i = 0; i < 5; i++)
          ExcludeFocus(
            excluding: i != controller.currentIndex,
            // Not yet visited → a cheap placeholder instead of the real page.
            child: _visitedTabs.contains(i)
                ? _buildPage(i, controller)
                : const SizedBox.shrink(),
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


  Widget _buildPage(int i, XtreamCodeHomeController controller) {
    switch (i) {
      case 0:
        return RedesignHome(
          key: ValueKey('inicio_${widget.playlist.id}'),
          movieCategories: controller.movieCategories,
          seriesCategories: controller.seriesCategories,
          onOpen: (it) => navigateByContentType(context, it),
          onPlay: (it) => playByContentType(context, it),
          onSearch: _openSearch,
          onSettings: () => controller.onNavigationTap(4),
          onSeeAll: _navigateToCategoryDetail,
          onSeeAllContinue: _navigateToContinueAll,
          continueWatching: resumableFrom(_history.continueWatching),
          // Reload on the way back: the viewer has just moved the position of
          // whatever they resumed, and a rail still showing the old progress —
          // or still showing a title they have now finished — is worse than one
          // that was never there.
          onResume: (h) async {
            final started = await _history.playContent(context, h);
            if (!mounted) return;
            if (!started) {
              // La acción va aquí a propósito: éste es el momento exacto en que
              // el usuario descubre que la entrada está muerta. Retirarla
              // automáticamente sería peor — un refresh del catálogo a medias
              // haría desaparecer historial válido.
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(context.loc.resume_failed),
                  action: SnackBarAction(
                    label: context.loc.remove,
                    onPressed: () => _history.removeHistory(h),
                  ),
                ),
              );
            }
            await _history.loadWatchHistory();
          },
          onRemove: (h) => _history.removeHistory(h),
          playlistSwitcher: PlaylistSwitcherButton(
            currentPlaylist: widget.playlist,
            currentIndex: controller.currentIndex,
          ),
        );
      case 1:
        return BrowseRedesign(
          movieCategories: controller.movieCategories,
          seriesCategories: controller.seriesCategories,
          onOpen: (it) => navigateByContentType(context, it),
          onSearch: _openSearch,
        );
      case 2:
        return LiveRedesign(
          liveCategories: controller.liveCategories ?? const [],
          onPlay: (it) => navigateByContentType(context, it),
          // Xtream only: M3U playlists have no panel to ask for a schedule, and
          // their item ids are not stream ids.
          epgService: _epgService,
          // Same switcher as the Home header, so the Live section shows (and can
          // change) the active playlist.
          playlistSwitcher: PlaylistSwitcherButton(
            currentPlaylist: widget.playlist,
            currentIndex: controller.currentIndex,
          ),
        );
      case 3:
        return ListRedesign(
          key: ValueKey('milista_${controller.currentIndex == 3}'),
          onOpen: (it) => navigateByContentType(context, it),
        );
      default:
        return XtreamCodePlaylistSettingsScreen(playlist: widget.playlist);
    }
  }

  void _navigateToCategoryDetail(CategoryViewModel category) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CategoryDetailScreen(category: category),
      ),
    );
  }

  /// Opens the "Seguir viendo → Ver todo" grid (last 20 watched). onResume is
  /// the SAME block the Home rail runs: play + reload + offer to remove a dead
  /// entry.
  void _navigateToContinueAll() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (ctx) => ContinueWatchingAllScreen(
          listenable: _history,
          itemsBuilder: () =>
              resumableFrom(_history.continueWatching).take(20).toList(),
          onResume: (h) async {
            final started = await _history.playContent(context, h);
            if (!mounted) return;
            if (!started) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(context.loc.resume_failed),
                  action: SnackBarAction(
                    label: context.loc.remove,
                    onPressed: () => _history.removeHistory(h),
                  ),
                ),
              );
            }
            await _history.loadWatchHistory();
          },
        ),
      ),
    );
  }

  BottomNavigationBar _buildBottomNavigationBar(
    BuildContext context,
    XtreamCodeHomeController controller,
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
    XtreamCodeHomeController controller,
    BoxConstraints constraints,
  ) {
    // The rail sits flush against the left edge — no overscan inset. It used to
    // reserve a safe margin there, but on the modern TVs/monitors this targets
    // that just reads as a wasted black strip beside the icons; the nav is
    // chrome that can live at the edge (as Netflix / Google TV do).
    final isTv = ResponsiveHelper.isDesktopOrTV(context);
    final panelWidth = isTv
        ? _tvNavWidth * ResponsiveHelper.tvScale(context)
        : _getNavigationWidth(context, constraints.maxWidth);
    return Container(
      width: panelWidth,
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
    XtreamCodeHomeController controller,
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
    // InkWell (not GestureDetector) so D-pad OK/Enter actually activates the
    // rail item — a bare GestureDetector takes focus but ignores key events.
    return FocusHighlight(
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: double.infinity,
        height: sizes.itemHeight,
        // Overscan is now handled by the rail's outer padding (see
        // _buildDesktopNavigationBar), so the item just fills the flush panel.
        margin: const EdgeInsets.only(top: 2, bottom: 2),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          // Selected = a quiet tint; the accent bar is drawn as a child, not as
          // a Border, because BoxDecoration asserts on a non-uniform border
          // combined with a borderRadius. It used to be a filled
          // primaryContainer with accent-coloured text (3.65:1), which made the
          // CURRENT section the least legible item in the rail — hierarchy
          // upside down. The bright treatment now belongs to focus alone.
          color: isSelected
              ? Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.08)
              : Colors.transparent,
        ),
        child: InkWell(
          onTap: onTap,
          focusNode: _railNode(item.index),
          // Don't autofocus the rail on entry — let the page content (e.g. the
          // Home hero Play button) take initial focus; the rail stays reachable
          // with LEFT.
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
              // Keep long labels ("Configuración") on ONE line — shrink to fit
              // instead of wrapping a single orphaned character.
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
    // Tablet: wide enough to read, far from the 10-foot scale.
    return screenWidth >= _desktopBreakpoint ? _largeNavWidth : _defaultNavWidth;
  }

  NavigationSizes _getNavigationSizes(BuildContext context, double screenWidth) {
    if (ResponsiveHelper.isDesktopOrTV(context)) {
      // Scale the DIMENSIONAL sizes (item box, icon) to the panel; the label
      // fontSize is left alone because the global TV textScaler in main.dart
      // already scales all text — multiplying here too would double-shrink it.
      final s = ResponsiveHelper.tvScale(context);
      return NavigationSizes(
        itemHeight: _tvItemHeight * s,
        iconSize: _tvIconSize * s,
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
      // NOT added when the bottom bar is in use: BottomNavigationBar indexes by
      // position, so an item that is an action rather than a page would shift
      // every tab off its own page.
      if (ResponsiveHelper.useNavigationRail(context))
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

/// A hair-thin, low-contrast line that appears at the top of the shell ONLY if
/// a background refresh is still running after ~3s — routine fast refreshes stay
/// completely invisible (how Netflix/Plex/Google TV behave). Deliberately NOT
/// the accent colour (which already means content progress and TV focus), and
/// never shown on a TV, where a 3 m hairline is both imperceptible and misplaced.
class _RefreshLine extends StatefulWidget {
  const _RefreshLine(this.controller);
  final XtreamCodeHomeController controller;

  @override
  State<_RefreshLine> createState() => _RefreshLineState();
}

class _RefreshLineState extends State<_RefreshLine> {
  Timer? _delay;
  bool _show = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onChange);
  }

  @override
  void dispose() {
    _delay?.cancel();
    widget.controller.removeListener(_onChange);
    super.dispose();
  }

  void _onChange() {
    if (widget.controller.isRefreshing) {
      _delay ??= Timer(const Duration(seconds: 3), () {
        if (mounted && widget.controller.isRefreshing) {
          setState(() => _show = true);
        }
      });
    } else {
      _delay?.cancel();
      _delay = null;
      if (_show && mounted) setState(() => _show = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_show || ResponsiveHelper.isTelevisionDevice) {
      return const SizedBox.shrink();
    }
    final scheme = Theme.of(context).colorScheme;
    return LinearProgressIndicator(
      minHeight: 2.5,
      backgroundColor: Colors.transparent,
      valueColor:
          AlwaysStoppedAnimation(scheme.onSurface.withValues(alpha: 0.35)),
    );
  }
}

