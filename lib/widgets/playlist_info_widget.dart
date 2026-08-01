import 'package:rensi_iptv/utils/app_themes.dart';
import 'package:rensi_iptv/utils/get_playlist_type.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:rensi_iptv/models/playlist_model.dart';
import 'package:rensi_iptv/l10n/localization_extension.dart';
import 'package:rensi_iptv/utils/credential_scrubber.dart';
import 'section_title_widget.dart';
import 'info_tile_widget.dart';

class PlaylistInfoWidget extends StatefulWidget {
  final Playlist playlist;

  const PlaylistInfoWidget({super.key, required this.playlist});

  @override
  State<PlaylistInfoWidget> createState() => _PlaylistInfoWidgetState();
}

class _PlaylistInfoWidgetState extends State<PlaylistInfoWidget> {
  // One switch for every credential on this card. The server URL counts: for an
  // M3U playlist it is the `get.php?username=…&password=…` link, so revealing
  // it reveals the account. Hidden by default so the screen is safe to show,
  // screenshot or cast without leaking the subscription.
  bool _secretsVisible = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: SectionTitleWidget(title: context.loc.playlist_information),
            ),
            // Lives here, not inside the password tile: an M3U playlist has no
            // password row, and hiding the switch there left M3U users unable
            // to ever reveal their own server URL.
            IconButton(
              icon: Icon(
                _secretsVisible ? Icons.visibility_off : Icons.visibility,
                size: 20,
              ),
              onPressed: () => setState(() => _secretsVisible = !_secretsVisible),
            ),
          ],
        ),
        Card(
          child: Column(
            children: [
              InfoTileWidget(
                icon: Icons.label_outline,
                label: context.loc.playlist_name,
                value: widget.playlist.name,
                copyOnTap: true,
              ),
              const Divider(height: 1),
              InfoTileWidget(
                icon: Icons.link,
                label: context.loc.server_url,
                value: widget.playlist.url == null
                    ? context.loc.not_found_in_category
                    : _secretsVisible
                        ? widget.playlist.url!
                        : scrubUrlForDisplay(widget.playlist.url),
                // Copy always yields the real URL — a masked one is useless.
                copyValue: widget.playlist.url,
                copyOnTap: true,
              ),
              if (isXtreamCode) ...[
                const Divider(height: 1),
                InfoTileWidget(
                  icon: Icons.person,
                  label: context.loc.username,
                  value: _secretsVisible
                      ? (widget.playlist.username ?? context.loc.not_found_in_category)
                      // Fixed length: a bullet-per-character leaks how long the
                      // username is.
                      : '•' * 8,
                  // Only copy the real username once it is revealed; while masked,
                  // the tap copies the bullets (copyValue null → shown value), so
                  // the credential can't be shared while hidden.
                  copyValue:
                      _secretsVisible ? widget.playlist.username : null,
                  copyOnTap: _secretsVisible,
                ),
              ],
              if (isXtreamCode && widget.playlist.password != null) ...[
                const Divider(height: 1),
                ListTile(
                  leading: Icon(Icons.lock_outline, color: Colors.grey[700]),
                  title: Text(context.loc.password, style: TextStyle(fontSize: AppThemes.tenFoot(context, 13))),
                  subtitle: Text(
                    _secretsVisible
                        ? widget.playlist.password!
                        : '•' * 8,
                    style: TextStyle(color: Colors.grey[600]),
                  ),
                  dense: true,
                  trailing: IconButton(
                    icon: Icon(
                      _secretsVisible ? Icons.visibility_off : Icons.visibility,
                      size: 20,
                    ),
                    onPressed: () {
                      setState(() {
                        _secretsVisible = !_secretsVisible;
                      });
                    },
                  ),
                  // While masked, tapping must not put the real password on the
                  // clipboard — that would let the secret be shared without ever
                  // revealing it. Copy is enabled only once the eye toggle has
                  // exposed it. (The reveal toggle is the trailing button, so it
                  // keeps working regardless.)
                  onTap: _secretsVisible
                      ? () async {
                          await Clipboard.setData(
                            ClipboardData(text: widget.playlist.password!),
                          );
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(context.loc.copied_to_clipboard),
                                duration: const Duration(seconds: 2),
                              ),
                            );
                          }
                        }
                      : null,
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
