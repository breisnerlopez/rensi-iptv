import 'dart:async';

import 'package:rensi_iptv/l10n/localization_extension.dart';
import 'package:rensi_iptv/models/m3u_item.dart';
import 'package:rensi_iptv/models/playlist_model.dart';
import 'package:rensi_iptv/screens/m3u/m3u_player_screen.dart';
import 'package:rensi_iptv/widgets/playlist_switcher_button.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../../models/content_type.dart';
import '../../models/playlist_content_model.dart';
import '../../utils/navigate_by_content_type.dart';

class M3uItemsScreen extends StatefulWidget {
  final List<M3uItem> m3uItems;
  final Playlist? playlist;
  final int currentIndex;

  const M3uItemsScreen({
    super.key,
    required this.m3uItems,
    this.playlist,
    this.currentIndex = 1,
  });

  @override
  State<M3uItemsScreen> createState() => _M3uItemsScreenState();
}

class _M3uItemsScreenState extends State<M3uItemsScreen> {
  List<M3uItem> filteredItems = [];
  String searchQuery = '';
  final TextEditingController _searchController = TextEditingController();
  bool isSearching = false;
  final ScrollController _chipScrollController = ScrollController();

  /// Memoized list of unique group titles. Recomputed only when
  /// `widget.m3uItems` changes.
  late List<String> _uniqueGroups;

  Timer? _debounce;
  static const _debounceDuration = Duration(milliseconds: 200);

  @override
  void initState() {
    super.initState();
    filteredItems = widget.m3uItems;
    _uniqueGroups = _computeUniqueGroups(widget.m3uItems);
  }

  @override
  void didUpdateWidget(covariant M3uItemsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.m3uItems, widget.m3uItems)) {
      _uniqueGroups = _computeUniqueGroups(widget.m3uItems);
      _applyFilter(searchQuery);
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    _chipScrollController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String query) {
    _debounce?.cancel();
    _debounce = Timer(_debounceDuration, () {
      if (!mounted) return;
      _applyFilter(query);
    });
  }

  void _applyFilter(String query) {
    setState(() {
      searchQuery = query;
      if (query.isEmpty) {
        filteredItems = widget.m3uItems;
      } else {
        final searchLower = query.toLowerCase();
        filteredItems = widget.m3uItems.where((item) {
          final name = item.name?.toLowerCase() ?? '';
          final group = item.groupTitle?.toLowerCase() ?? '';
          return name.contains(searchLower) || group.contains(searchLower);
        }).toList();
      }
    });
  }

  void _filterByGroup(String group) {
    setState(() {
      filteredItems = widget.m3uItems
          .where((item) => item.groupTitle == group)
          .toList();
      searchQuery = group;
    });
  }

  static List<String> _computeUniqueGroups(List<M3uItem> items) {
    final groups = items
        .where((item) => item.groupTitle != null)
        .map((item) => item.groupTitle!)
        .toSet()
        .toList();
    groups.sort();
    return groups;
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.of(context).size.width > 700;

    return Scaffold(
      appBar: AppBar(
        title: isSearching
            ? TextField(
                controller: _searchController,
                autofocus: true,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: context.loc.search,
                  border: InputBorder.none,
                ),
                onChanged: _onSearchChanged,
                onSubmitted: (_) {/* keep field focused; debounce drives the
                  actual search. */},
              )
            : SelectableText(
                context.loc.iptv_channels_count(filteredItems.length),
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
        actions: [
          IconButton(
            icon: Icon(isSearching ? Icons.close : Icons.search),
            onPressed: () {
              setState(() {
                isSearching = !isSearching;
                if (!isSearching) {
                  _searchController.clear();
                  _applyFilter('');
                }
              });
            },
          ),
          if (widget.playlist != null)
            PlaylistSwitcherButton(
              currentPlaylist: widget.playlist!,
              currentIndex: widget.currentIndex,
            ),
        ],
      ),
      body: Column(
        children: [
          if (!isSearching && _uniqueGroups.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: SizedBox(
                height: 50,
                child: isDesktop
                    ? Scrollbar(
                        controller: _chipScrollController,
                        thumbVisibility: true,
                        child: ListView.builder(
                          controller: _chipScrollController,
                          scrollDirection: Axis.horizontal,
                          itemCount: _uniqueGroups.length + 1,
                          itemBuilder: (context, index) {
                            if (index == 0) {
                              return _buildFilterChip(
                                context.loc.see_all,
                                null,
                              );
                            }
                            final group = _uniqueGroups[index - 1];
                            return _buildFilterChip(group, group);
                          },
                        ),
                      )
                    : ListView.builder(
                        scrollDirection: Axis.horizontal,
                        itemCount: _uniqueGroups.length + 1,
                        itemBuilder: (context, index) {
                          if (index == 0) {
                            return _buildFilterChip(context.loc.see_all, null);
                          }
                          final group = _uniqueGroups[index - 1];
                          return _buildFilterChip(group, group);
                        },
                      ),
              ),
            ),
          Expanded(
            child: ListView.builder(
              itemCount: filteredItems.length,
              itemBuilder: (context, index) {
                final channel = filteredItems[index];

                return Container(
                  height: 80,
                  margin: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.grey.withOpacity(0.1),
                        spreadRadius: 1,
                        blurRadius: 2,
                        offset: const Offset(0, 1),
                      ),
                    ],
                  ),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: () => _onChannelTap(context, channel),
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Row(
                        children: [
                          _buildSimpleLogo(channel),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  channel.name ?? context.loc.unknown_channel,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 14,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                if (channel.groupTitle != null) ...[
                                  const SizedBox(height: 2),
                                  Text(
                                    channel.groupTitle!,
                                    style: TextStyle(
                                      color: Colors.grey[600],
                                      fontSize: 12,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: _getContentTypeColor(
                                channel,
                              ).withOpacity(0.1),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              _getContentTypeText(channel),
                              style: TextStyle(
                                fontSize: 10,
                                color: _getContentTypeColor(channel),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String label, String? groupFilter) {
    final isSelected =
        (groupFilter == null && searchQuery.isEmpty) ||
        (groupFilter != null && searchQuery == groupFilter);

    return Container(
      margin: const EdgeInsets.only(left: 8),
      child: FilterChip(
        label: Text(label),
        selected: isSelected,
        onSelected: (selected) {
          if (groupFilter == null) {
            _applyFilter('');
          } else {
            _filterByGroup(groupFilter);
          }
        },
      ),
    );
  }

  Widget _buildSimpleLogo(M3uItem channel) {
    if (channel.tvgLogo != null && channel.tvgLogo!.isNotEmpty) {
      return Container(
        width: 50,
        height: 35,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(6),
          color: Colors.grey[100],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: CachedNetworkImage(
            imageUrl: channel.tvgLogo!,
            width: 50,
            height: 35,
            fit: BoxFit.contain,
            memCacheWidth: 100,
            memCacheHeight: 70,
            errorWidget: (context, url, error) => _buildPlaceholderIcon(),
            placeholder: (context, url) => _buildPlaceholderIcon(),
          ),
        ),
      );
    }
    return _buildPlaceholderIcon();
  }

  Widget _buildPlaceholderIcon() {
    return Container(
      width: 50,
      height: 35,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6),
        color: Colors.grey[200],
      ),
      child: Icon(Icons.tv, color: Colors.grey[500], size: 20),
    );
  }

  Color _getContentTypeColor(M3uItem channel) {
    switch (channel.contentType) {
      case ContentType.liveStream:
        return Colors.red;
      case ContentType.vod:
        return Colors.blue;
      case ContentType.series:
        return Colors.green;
      default:
        return Colors.grey;
    }
  }

  String _getContentTypeText(M3uItem channel) {
    switch (channel.contentType) {
      case ContentType.liveStream:
        return context.loc.live_content;
      case ContentType.vod:
        return context.loc.movie_content;
      case ContentType.series:
        return context.loc.series_content;
      default:
        return context.loc.media_content;
    }
  }

  void _onChannelTap(BuildContext context, M3uItem m3uItem) {
    if (m3uItem.groupTitle != null &&
        m3uItem.groupTitle!.isNotEmpty &&
        m3uItem.contentType != ContentType.series) {
      navigateByContentType(
        context,
        ContentItem(
          m3uItem.url,
          m3uItem.name ?? '',
          m3uItem.tvgLogo ?? '',
          m3uItem.contentType,
          m3uItem: m3uItem,
        ),
      );
    } else {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => M3uPlayerScreen(
            contentItem: ContentItem(
              m3uItem.id,
              m3uItem.name ?? '',
              m3uItem.tvgLogo ?? '',
              m3uItem.contentType,
              m3uItem: m3uItem,
            ),
          ),
        ),
      );
    }
  }
}
