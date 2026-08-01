<div align="center">

<img src="assets/logo_full.png" alt="Rensi IPTV" width="120" />

# Rensi IPTV

**Your IPTV playlists, beautifully organized — watch on your phone or cast to your TV.**

[![Platform](https://img.shields.io/badge/platform-Android%20%C2%B7%20Android%20TV%20%C2%B7%20Linux-2d7d46)](#-download--install)
[![License](https://img.shields.io/badge/license-MIT-blue)](./LICENSE)
[![Built with Flutter](https://img.shields.io/badge/built%20with-Flutter-02569B?logo=flutter)](https://flutter.dev)
[![Version](https://img.shields.io/badge/version-2.15.0-orange)](./CHANGELOG.md)

[Español](README.md) · **English**

🌍 English · Español · Português · Français · Deutsch · Русский · Türkçe · العربية · हिन्दी · 中文

</div>

---

Rensi IPTV turns your **Xtream Codes** account or **M3U playlist** into a clean, modern streaming app — the kind of experience you'd expect from a paid service, but free, open source, and fully under your control. It enriches your movies and series with posters, cast, and synopses from **TMDb**, lets you **download for offline** viewing, and — its signature feature — lets you browse on your phone and **cast to your Android TV over your own home network**, no third-party account or Chromecast required.

> **Bring your own playlist.** Rensi is a *player*. It ships with **no channels, no streams, and no content** — you connect the Xtream account or M3U playlist you already have. See [Legal](#-legal).

---

## 📸 Screenshots

### On your phone

| Home | Browse & discover | Detail + cast |
|:---:|:---:|:---:|
| <img src="docs/screenshots/home-phone.png" width="230" /> | <img src="docs/screenshots/browse-phone.png" width="230" /> | <img src="docs/screenshots/search-detail-cast-phone.png" width="230" /> |
| A personal home with a featured banner and *Popular* rails | Filter by Live TV, Movies, Series and genre | TMDb synopsis, rating and full cast |

| Player | Offline downloads | Search the whole catalogue |
|:---:|:---:|:---:|
| <img src="docs/screenshots/player-phone.png" width="230" /> | <img src="docs/screenshots/downloads-phone.png" width="230" /> | <img src="docs/screenshots/search-phone.png" width="230" /> |
| Hardware-accelerated playback with audio & subtitle tracks | Download movies and episodes to watch without a connection | Global search across all your playlists |

| My List | One consistent Save button |
|:---:|:---:|
| <img src="docs/screenshots/mylist-phone.png" width="230" /> | <img src="docs/screenshots/bookmark-phone.png" width="230" /> |
| Your favourites from **all** your playlists in one view, badged by where each came from | The same **bookmark** on movies and series, with confirmation |

### Cast to your TV

| Casting controls (with volume) | Persistent mini-controller |
|:---:|:---:|
| <img src="docs/screenshots/casting-phone.png" width="230" /> | <img src="docs/screenshots/casting-mini-controller-phone.png" width="230" /> |
| Your phone is the remote: **volume**, audio, subtitles and channels | Keep browsing while it plays on the TV |

On the TV itself, Rensi runs as a **cast receiver** — with a visible **connection status** and a **watch-history rail with cover art**, playing what you send:

<div align="center"><img src="docs/screenshots/receiver-tv.png" width="480" /></div>

---

## ✨ Features

**📺 Watch anything from your playlists**
- **Xtream Codes API** and **M3U / M3U8** playlists (import from URL or local file)
- **Multiple playlists** at once — switch between accounts in a tap
- Live TV, Movies and Series, organized by category
- Hardware-accelerated playback (libmpv) with **audio-track and subtitle selection**

**🔎 Discover, don't just scroll**
- **TMDb enrichment** — posters, backdrops, ratings, synopses and full cast
- **Global search** across *all* your playlists at once — by title, actor, studio or genre
- **Popular this month / year / all-time**, filtered by genre
- **Cast filmography** — tap an actor to see everything of theirs in your library
- **Continue watching** and **My List** — your favourites from **all your playlists** gathered in one view

**📲 Cast to your Android TV — no Chromecast needed**
- A **direct phone-to-TV connection over your own home network** — no cloud, no third-party account; pair once with a PIN
- Your phone stays in charge: browse, queue, pause, seek and **control the volume** while the TV plays
- TV shows rich metadata — **cover art**, title, synopsis and cast, sent from your phone — even for a file you downloaded offline
- Remembers paired TVs so it just reconnects next time

**💾 Take it offline**
- **Download** movies and episodes; watch with no connection
- Background downloads with pause/resume and a storage meter
- Cast a downloaded file straight to the TV

**🎨 Made to live with**
- **10 languages**, light & dark theme
- Encrypted, passphrase-protected **backups** of your setup (optional)
- Credentials stored in the OS keychain / `EncryptedSharedPreferences`

### Phone vs. Android TV

Rensi is designed around **one idea: your phone is the remote, the TV is the screen.**

| | 📱 Phone / Tablet | 📺 Android TV |
|---|:---:|:---:|
| Browse, search & discover | ✅ | — |
| Play on the device | ✅ | ✅ |
| Cast to a TV | ✅ *sender* | ✅ *receiver* |
| Offline downloads | ✅ | — |
| Play a downloaded file on the TV | ✅ | ✅ |
| D-pad / 10-foot playback UI | — | ✅ |

> On the TV, downloaded files play by **casting them from the phone** — the TV keeps no downloads of its own.

*(Rensi also builds and runs on **Linux** desktop as a player.)*

---

## 📥 Download & install

Grab the latest signed **APK** from the [**Releases**](https://github.com/breisnerlopez/rensi-iptv/releases) page.

- **📱 Phone / tablet:** download the APK for your device's architecture — `rensi-iptv-android-arm64-v8a-<version>.apk` fits almost every modern phone — then open it. You may need to allow "Install unknown apps" for your browser.
- **📺 Android TV:** install the same APK via a sideload tool (e.g. *Downloader* by AFTVnews, or `adb install`). Rensi installs as the on-TV **cast receiver + player**.

> Rensi is **not yet on the Google Play Store.** Releases are distributed as signed APKs here on GitHub.

---

## 🚀 Quick start

1. **Open the app** and go to **Add playlist**.
2. Choose your source:
   - **Xtream Codes** — enter your server URL, username and password, or
   - **M3U** — paste a playlist URL or pick an `.m3u` file.
3. Rensi imports and, for movies/series, **matches them against TMDb** for artwork and details.
4. Browse, search, and press play. That's it.

**To cast to your TV:** open Rensi on the Android TV first (leave it on the receiver screen), then on your phone tap the **cast** icon, pick your TV, and enter the **PIN** shown on the TV. After the first pairing it reconnects automatically.

---

## ❓ FAQ & troubleshooting

- **My phone can't find the TV to cast.** Both devices must be on the **same Wi-Fi network**, and the network has to allow local device-to-device traffic. Guest networks and routers with **"AP isolation"** enabled block discovery — turn AP isolation off, or use your main network.
- **Does Rensi come with channels?** No. It's a player — you bring your own Xtream account or M3U playlist. See [Legal](#-legal).
- **Why isn't it on the Play Store?** For now, Rensi is distributed as signed APKs here on GitHub.

---

## ⚖️ Legal

Rensi IPTV is a **media player**, in the same spirit as VLC. It does **not** provide, host, bundle, or resell any TV channels, movies, series, or streams, and it is **not affiliated with any IPTV provider**. To use it you must supply your own legally-obtained Xtream Codes account or M3U playlist. You are responsible for ensuring you have the rights to any content you play. The developers assume no liability for how the app is used or for third-party content accessed through it.

Movie and series metadata (posters, cast, synopses) is provided by **[The Movie Database (TMDb)](https://www.themoviedb.org/)**. This product uses the TMDb API but is **not endorsed or certified by TMDb**.

---

## 🛠️ Tech & architecture

Rensi is a single Flutter codebase targeting Android phone, Android TV and desktop.

- **UI:** Flutter (Material 3), custom type system (Bricolage Grotesque / Hanken Grotesk)
- **Playback:** [`media_kit`](https://github.com/media-kit/media-kit) → **libmpv** (hardware-accelerated, wide codec support)
- **Data:** [Drift](https://drift.simonbinder.eu/) (SQLite) with versioned, transactional migrations
- **Metadata:** The Movie Database (TMDb) API
- **Downloads:** `background_downloader` (native background transfers, pause/resume)
- **State / DI:** Provider + `get_it`, an `rxdart`-based event bus

**Casting** is a purpose-built, LAN-only second-screen protocol (no cloud, no Cast Connect):

- **Discovery** via mDNS/DNS-SD (`bonsoir`) — the TV advertises, the phone finds it
- **Control channel** over `wss://` (self-signed EC certificate generated at runtime, **fingerprint-pinned**)
- **Pairing** with a 6-digit PIN → HKDF/HMAC session keys; **trusted-device tokens** so paired TVs reconnect silently
- The phone sends the **content URL + TMDb metadata** in the play command, so the TV never needs your credentials

---

## 🧑‍💻 Build from source

Requires the [Flutter SDK](https://docs.flutter.dev/get-started/install) (Dart `^3.9.2`).

```bash
git clone https://github.com/breisnerlopez/rensi-iptv.git
cd rensi-iptv
flutter pub get

# Run on a connected device / emulator
flutter run

# Build a release APK (split per ABI)
flutter build apk --release --split-per-abi
```

---

## 🤝 Contributing

Issues and pull requests are welcome. If you're filing a bug, please include your device/Android version and steps to reproduce — and **never paste your Xtream URL, username, password, or any playlist link** into a public issue.

---

## 📜 Credits & license

Rensi IPTV is a **fork** of [Another IPTV Player](https://github.com/bsogulcan/another-iptv-player) by [@bsogulcan](https://github.com/bsogulcan), distributed under the MIT License. The original `LICENSE` is preserved; modifications and new features added by this fork are also released under the MIT License — see [`LICENSE`](./LICENSE) for the full dual-copyright notice.

Metadata by [TMDb](https://www.themoviedb.org/). Playback by [media_kit](https://github.com/media-kit/media-kit) / [mpv](https://mpv.io/).

**MIT** — see [`LICENSE`](./LICENSE).
