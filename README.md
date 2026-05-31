# Rensi IPTV

**Free & Open Source IPTV Streaming Solution**

Rensi IPTV is a lightweight, multi-platform, and feature-rich IPTV player built with Flutter. It aims to provide all the premium features of paid IPTV players for free and with full transparency.

## Features

- **Xtream Codes API** — full compatibility
- **M3U / M3U8 playlists** — import from URL or local file (50 MB cap, scheme validation, streamed parser)
- **TMDb global search** — searches across all your playlists at once, with movie/TV/wishlist filters and a detail bottom sheet
- **Encrypted backups** — optional AES-GCM + PBKDF2 (200k iter) passphrase protection for backup files; the user keeps full control over whether credentials travel in plain or encrypted form
- **Multi-language** — 10 locales: English, Español, Português, Français, Deutsch, Русский, Türkçe, العربية, हिन्दी, 中文
- **Secure credential storage** — Xtream and TMDb credentials live in the OS keychain / `EncryptedSharedPreferences` (`flutter_secure_storage`)
- **Multi-platform** — Android, iOS, Linux, macOS, Windows, Web

## Credits

Rensi IPTV is a **fork** of [Another IPTV Player](https://github.com/bsogulcan/another-iptv-player) by [@bsogulcan](https://github.com/bsogulcan), distributed under the MIT License.

The original `LICENSE` is preserved in this repository; modifications and new features added by this fork are also released under the MIT License. See [`LICENSE`](./LICENSE) for the full dual-copyright notice.

If you are looking for the upstream project (which this fork tracks selectively), please visit the original repository above.

## License

MIT — see [`LICENSE`](./LICENSE).
