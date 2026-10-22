#!/usr/bin/env python3
# Debug hot-swap watcher. On each save of Scripts/hotswap/Live.swift it compiles the file as a fresh
# module (Live_<seq>) against the Debug build of the Flipcash app, signs it with the app's own
# signing identity, publishes it to server.py and prints where the time went.
#
#   ./watch.py <codesign identity sha1> [port]
#   ./watch.py --once <codesign identity sha1>
#
# --once is for loupe's hotswap extension: it builds Live.swift as Live_<HOTSWAP_SEQ> into
# HOTSWAP_PATCHES, publishes nothing, and prints the notice JSON as its last stdout line.
#
# Needs a Debug device build in .build/dd (see Scripts/hotswap/flags.sh for how the compile flags
# are recovered from it) and `server.py` running on the same port.
import json, os, shutil, subprocess, sys, threading, time, urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "../.."))
SRC = os.path.join(HERE, "Live.swift")
PRODUCTS = os.path.join(REPO, ".build/dd/Build/Products/Debug-iphoneos")
BASE = os.path.join(REPO, ".build/hotswap")
OUT = os.path.join(BASE, "out")
SERVE = os.environ.get("HOTSWAP_PATCHES") or os.path.join(BASE, "serve/patches")
REPORTS = os.path.join(BASE, "serve/reports.jsonl")
LOOP = os.path.join(BASE, "serve/loop.jsonl")
FLAGS = os.path.join(BASE, "flags.txt")
ONCE = "--once" in sys.argv
argv = [a for a in sys.argv[1:] if a != "--once"]
identity = argv[0]
port = argv[1] if len(argv) > 1 else "18490"


def ms():
    return int(time.time() * 1000)


def build(seq):
    name = f"live-{seq}.dylib"
    out = os.path.join(OUT, name)
    flags = open(FLAGS).read().split("\n")
    flags = [f for f in flags if f]
    t0 = ms()
    r = subprocess.run(["xcrun", "--sdk", "iphoneos", "swiftc", "-emit-library", "-Onone",
                        "-module-name", f"Live_{seq}", *flags,
                        "-Xlinker", "-install_name", "-Xlinker", f"@rpath/{name}",
                        os.path.join(PRODUCTS, "Flipcash.app/Flipcash.debug.dylib"),
                        SRC, "-o", out], capture_output=True, text=True)
    t1 = ms()
    if r.returncode:
        print(r.stderr.strip(), file=sys.stderr if ONCE else sys.stdout, flush=True)
        return None
    subprocess.run(["codesign", "-f", "-s", identity, out], check=True, capture_output=True)
    t2 = ms()
    shutil.copy(out, os.path.join(SERVE, name + ".tmp"))
    os.replace(os.path.join(SERVE, name + ".tmp"), os.path.join(SERVE, name))
    return name, t1 - t0, t2 - t1


def report_for(seq, timeout=15):
    deadline = time.time() + timeout
    while time.time() < deadline:
        if os.path.exists(REPORTS):
            for line in reversed(open(REPORTS).read().splitlines()):
                rec = json.loads(line)
                if rec.get("event") == "patch" and rec.get("seq") == seq:
                    return rec
        time.sleep(0.02)
    return None


def finish(seq, name, saved, detect, compile_ms, sign_ms, published):
    rep = report_for(seq)
    row = {"seq": seq, "name": name, "detectMs": detect, "compileMs": compile_ms,
           "signMs": sign_ms, "macMs": published - saved}
    if rep:
        row.update({k: rep.get(k) for k in ("ok", "bytes", "downloadMs", "loadMs", "shownMs", "error")})
        # receivedAt is when the phone's report reached the Mac: an upper bound on save-to-screen.
        row["saveToReportMs"] = rep["receivedAt"] - saved
    else:
        row["error"] = "no report in 15s"
    with open(LOOP, "a") as f:
        f.write(json.dumps(row) + "\n")
    print(json.dumps(row), flush=True)


os.makedirs(OUT, exist_ok=True)
os.makedirs(SERVE, exist_ok=True)
if ONCE:
    seq = int(os.environ["HOTSWAP_SEQ"])
    saved = os.stat(SRC).st_mtime_ns // 1_000_000
    built = build(seq)
    if not built:
        sys.exit(1)
    name, compile_ms, sign_ms = built
    print(json.dumps({"name": name, "savedAt": saved, "compileMs": compile_ms, "signMs": sign_ms}), flush=True)
    sys.exit(0)
seq = int(time.time())
last = os.stat(SRC).st_mtime_ns
print("watching", SRC, flush=True)
while True:
    time.sleep(0.02)
    m = os.stat(SRC).st_mtime_ns
    if m == last:
        continue
    last = m
    saved = m // 1_000_000
    seq += 1
    detect = ms() - saved
    built = build(seq)
    if not built:
        continue
    name, compile_ms, sign_ms = built
    published = ms()
    urllib.request.urlopen(urllib.request.Request(
        f"http://127.0.0.1:{port}/publish", method="POST",
        data=json.dumps({"seq": seq, "name": name, "savedAt": saved}).encode(),
        headers={"Content-Type": "application/json"}))
    threading.Thread(target=finish, args=(seq, name, saved, detect, compile_ms, sign_ms, published),
                     daemon=True).start()
