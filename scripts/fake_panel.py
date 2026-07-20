"""Minimal Xtream panel that only answers get_short_epg.

Exists so the EPG chain can be proved end to end on a real device without a
real subscription: the widget, the service, the HTTP client and the parser all
run for real, and the only thing faked is the panel on the other end.

Run:
    python3 scripts/fake_panel.py            # listens on 127.0.0.1:8799
    python3 scripts/fake_panel.py --host 0.0.0.0 --port 9000   # real device on the LAN

Then point the capture at it:
    flutter drive ... --dart-define=EPG_PANEL_URL=http://10.0.2.2:8799
"""
import argparse
import base64
import json
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse, parse_qs


# Titles are base64 in the real API; sending plain text would exercise the
# fallback path instead of the one panels actually use.
def b64(s):
    return base64.b64encode(s.encode()).decode()


# Keyed on the ids the capture fixture generates (`<categoryId>-<index>`).
# Deliberately varied in length: a guide line that only ever gets short titles
# never exercises the ellipsis, which is where a row layout usually breaks.
SCHEDULE = {
    "l1-0": ("Premier League: Arsenal vs Liverpool", "Jornada 28 desde el Emirates."),
    "l1-1": ("SportsCenter", "Resumen y analisis del dia."),
    "l1-2": ("NBA: Lakers vs Celtics en el Crypto.com Arena, partido completo",
             "Cobertura integral."),
    "l1-3": ("Boxeo", "Velada estelar."),
    "l1-4": ("Roland Garros: cuartos de final", "Desde la Philippe-Chatrier."),
    "l2-0": ("Noticias de la Noche", "La actualidad internacional."),
    "l2-1": ("Panorama Mundial", "Reportajes en profundidad."),
    "l2-2": ("Debate", "Analisis con invitados."),
}


class H(BaseHTTPRequestHandler):
    def do_GET(self):
        url = urlparse(self.path)
        q = parse_qs(url.query)

        # Validate the request instead of answering anything. Replying to every
        # path and every query made the capture prove only that the parser and
        # the row could paint; whether the client builds the right call went
        # untested, and that is the half of the round trip carrying the
        # credentials.
        if not url.path.endswith("player_api.php"):
            return self.fail(404, "not player_api.php: %s" % url.path)
        if q.get("action", [""])[0] != "get_short_epg":
            return self.fail(400, "missing or wrong action=%r" % q.get("action"))
        # Presence, not correctness: this panel has no user database and is not
        # trying to be an auth check. What it verifies is that the client PUT
        # the credentials in the request at all — the parameters the real API
        # requires and the ones the scrubber has to keep out of the logs.
        if not q.get("username", [""])[0] or not q.get("password", [""])[0]:
            return self.fail(401, "no credentials in query")
        sid = q.get("stream_id", [""])[0]
        if not sid:
            return self.fail(400, "no stream_id")

        title, desc = SCHEDULE.get(sid, ("Programacion Continua", "Emision en directo."))
        now = int(time.time())
        # Start 22 min ago, run 75 min: mid-programme, so the progress bar has
        # to render a partial fill rather than 0% or 100%.
        start, stop = now - 22 * 60, now + 53 * 60
        self.send_json(200, {"epg_listings": [
            {
                "id": "%s-1" % sid,
                "title": b64(title),
                "description": b64(desc),
                "start_timestamp": str(start),
                "stop_timestamp": str(stop),
            },
            {
                "id": "%s-2" % sid,
                "title": b64("A continuacion"),
                "description": b64(""),
                "start_timestamp": str(stop),
                "stop_timestamp": str(stop + 3600),
            },
        ]})

    def fail(self, code, why):
        # Loud on the console, ordinary HTTP error on the wire: a capture that
        # silently got a valid guide for a malformed request would be reporting
        # success for a broken client.
        print("REJECTED %s: %s" % (code, why), flush=True)
        self.send_json(code, {"error": why})

    def send_json(self, code, payload):
        body = json.dumps(payload).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *a):
        pass


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    # Loopback by default. The emulator reaches the host's loopback through its
    # own 10.0.2.2 alias, so binding every interface buys nothing for the normal
    # case and puts an unauthenticated HTTP server on whatever network the
    # development machine happens to be on. Pass --host 0.0.0.0 deliberately
    # when driving a real device over the LAN.
    ap.add_argument("--host", default="127.0.0.1")
    ap.add_argument("--port", type=int, default=8799)
    args = ap.parse_args()

    # Threading: the guide is fetched once per visible channel, and a
    # single-threaded server serialised ~20 requests behind the capture's fixed
    # wait — which is how one row got photographed without its programme.
    server = ThreadingHTTPServer((args.host, args.port), H)
    print("fake panel on %s:%d" % (args.host, args.port), flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()
