#!/bin/bash
# Recovers the Flipcash target's Swift compile flags from an xcodebuild log into
# .build/hotswap/flags.txt, one per line, for watch.py. Run after a Debug build:
#   xcodebuild build ... > .build/build.log; Scripts/hotswap/flags.sh .build/build.log
# A second argument names the output instead, e.g. .build/hotswap/flags-iphonesimulator.txt for a
# simulator build (watch.py with HOTSWAP_SDK=iphonesimulator reads that one).
# Drops what a patch must not inherit: the file list, coverage, index and batch flags.
set -euo pipefail
cd "$(dirname "$0")/../.."
mkdir -p .build/hotswap
grep -m1 -- "swiftc -module-name Flipcash " "${1:-.build/build.log}" | python3 -c '
import shlex, sys
a = shlex.split(sys.stdin.read().replace("\\=", "="))
a = a[a.index("-Onone") + 1:]
skip1 = {"-c", "-enable-batch-mode", "-profile-coverage-mapping", "-profile-generate", "-emit-localized-strings", "-enable-testing", "-g"}
skip2 = {"-index-store-path", "-emit-localized-strings-path", "-module-name"}
out, i = [], 0
while i < len(a):
    x = a[i]
    if x.startswith("@") or x.startswith("-j"): i += 1; continue
    if x in skip1: i += 1; continue
    if x in skip2: i += 2; continue
    if x == "-Xfrontend" and a[i + 1] in ("-serialize-debugging-options", "-enable-implicit-dynamic"): i += 2; continue
    out.append(x); i += 1
print("\n".join(out))
' > "${2:-.build/hotswap/flags.txt}"
wc -l "${2:-.build/hotswap/flags.txt}"
