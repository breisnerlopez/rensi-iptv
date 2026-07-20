#!/usr/bin/env bash
# Generates the local clip that unblocks the real-libmpv player E2E tests.
#
# test/integration/player_remote_e2e_test.dart needs a decodable video to prove
# the player actually reaches "playing" — D-pad audio panel, play/pause and
# channel switch are all asserted against a live libmpv decode. Without a clip
# the file calls markTestSkipped, so its default result is "checked nothing".
#
# The clip is synthetic: no network, no panel subscription, no credentials.
# Two audio tracks, so the audio/subtitle panel has something real to list.
#
#   scripts/make_testclip.sh
#   flutter test --dart-define=RENSI_TESTCLIP="$PWD/build/testclip.mp4"
#
# Requires ffmpeg and libmpv (Debian: apt install ffmpeg libmpv2). Without
# libmpv every player test dies in setUpAll instead of running.
set -euo pipefail

out="${1:-build/testclip.mp4}"
mkdir -p "$(dirname "$out")"

ffmpeg -y -loglevel error \
  -f lavfi -i "testsrc=size=320x240:rate=15:duration=20" \
  -f lavfi -i "sine=frequency=440:duration=20" \
  -f lavfi -i "sine=frequency=880:duration=20" \
  -map 0:v -map 1:a -map 2:a \
  -c:v libx264 -preset ultrafast -pix_fmt yuv420p \
  -c:a aac -shortest \
  "$out"

echo "wrote $out"
echo "run: flutter test --dart-define=RENSI_TESTCLIP=$(realpath "$out")"
