#!/usr/bin/env python3
# usage: server.py [host [port]]   (default 0.0.0.0 18490)
# Debug hot-swap server (see Flipcash/Debug/HotSwap.swift). Serves .build/hotswap/serve/, appends each POST /report body to
# serve/reports.jsonl with a receive time, and carries the live-patch notices:
#
#   POST /publish   the watcher announces a new patch (JSON, must hold "seq")
#   GET  /next?after=N
#                   long-polls until a patch newer than N is published, then
#                   answers it; 204 after 30s with nothing new
import http.server, json, os, sys, threading, time, urllib.parse

ROOT = os.path.join(os.environ.get("HOTSWAP_DIR", os.path.join(os.path.dirname(os.path.abspath(__file__)), "../../.build/hotswap")), "serve")
os.makedirs(os.path.join(ROOT, "patches"), exist_ok=True)
latest = {"seq": 0}
changed = threading.Condition()


def now_ms():
    return int(time.time() * 1000)


class H(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *a, **kw):
        super().__init__(*a, directory=ROOT, **kw)

    def log_message(self, fmt, *args):
        pass

    def body(self):
        raw = self.rfile.read(int(self.headers.get("Content-Length", 0)))
        try:
            return json.loads(raw)
        except ValueError:
            return {"raw": raw.decode(errors="replace")}

    def answer(self, code, obj=None):
        data = json.dumps(obj).encode() if obj is not None else b""
        self.send_response(code)
        if obj is not None:
            self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        url = urllib.parse.urlparse(self.path)
        if url.path != "/next":
            return super().do_GET()
        after = int(urllib.parse.parse_qs(url.query).get("after", ["0"])[0])
        with changed:
            changed.wait_for(lambda: latest["seq"] > after, timeout=30)
            notice = dict(latest)
        if notice["seq"] <= after:
            return self.answer(204)
        self.answer(200, notice)

    def do_POST(self):
        rec = self.body()
        if self.path == "/publish":
            rec["publishedAt"] = now_ms()
            with changed:
                latest.clear()
                latest.update(rec)
                changed.notify_all()
            print("PUBLISH", json.dumps(rec), flush=True)
            return self.answer(204)
        rec["at"] = time.strftime("%H:%M:%S")
        rec["receivedAt"] = now_ms()
        with open(os.path.join(ROOT, "reports.jsonl"), "a") as f:
            f.write(json.dumps(rec) + "\n")
        print("REPORT", json.dumps(rec), flush=True)
        self.answer(204)


host = sys.argv[1] if len(sys.argv) > 1 else "0.0.0.0"
port = int(sys.argv[2]) if len(sys.argv) > 2 else 18490
http.server.ThreadingHTTPServer((host, port), H).serve_forever()
