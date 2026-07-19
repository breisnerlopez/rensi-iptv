import 'package:flutter/material.dart';
import 'package:rensi_iptv/models/epg_entry.dart';
import 'package:rensi_iptv/redesign/rensi_widgets.dart';
import 'package:rensi_iptv/services/epg_service.dart';
import 'package:rensi_iptv/utils/app_themes.dart';

/// What is on this channel right now, plus how far through it is.
///
/// This is the line that separates a TV product from a list of URLs: a channel
/// list that shows only names asks the user to remember a schedule. Plex,
/// TiviMate, Google TV and every serious IPTV player put the current programme
/// and a progress bar on the row.
///
/// Renders nothing at all when the panel has no usable data — a channel with no
/// EPG should look like a channel with no EPG, not like one stuck on a
/// programme that ended hours ago.
class NowPlayingLine extends StatefulWidget {
  const NowPlayingLine({
    super.key,
    required this.streamId,
    required this.service,
  });

  final String streamId;
  final EpgService service;

  @override
  State<NowPlayingLine> createState() => _NowPlayingLineState();
}

class _NowPlayingLineState extends State<NowPlayingLine> {
  EpgEntry? _entry;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(NowPlayingLine old) {
    super.didUpdateWidget(old);
    // Rows are recycled as the list scrolls; without this a reused row would
    // keep showing the previous channel's programme.
    if (old.streamId != widget.streamId) {
      _entry = null;
      _loaded = false;
      _load();
    }
  }

  Future<void> _load() async {
    // Capture the id: the row can be recycled onto another channel while this
    // request is in flight, and applying a stale result would show one
    // channel's programme on another's row.
    final requested = widget.streamId;
    final entry = await widget.service.nowPlaying(requested);
    if (!mounted || requested != widget.streamId) return;
    setState(() {
      _entry = entry;
      _loaded = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final entry = _entry;
    // Reserve no height while loading and none when there is nothing to show:
    // a placeholder row that later collapses makes the whole list jump.
    if (!_loaded || entry == null) return const SizedBox.shrink();

    final r = rensi(context);
    final progress = entry.progressAt(DateTime.now());

    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            entry.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: AppThemes.labelSize,
              color: r.text2,
            ),
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 3,
              backgroundColor: r.surface3,
              valueColor: AlwaysStoppedAnimation<Color>(r.live),
            ),
          ),
        ],
      ),
    );
  }
}
