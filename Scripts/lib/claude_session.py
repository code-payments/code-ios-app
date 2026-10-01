#!/usr/bin/env python3
"""Resolve a Claude Code session to the checkout it is working in.

Usage:
    claude_session.py <repo-root> list
    claude_session.py <repo-root> resolve <query>

<repo-root> is the main checkout; sessions in it and in its
.claude/worktrees/* are considered. Sessions whose working directory no longer
exists (removed worktrees) are skipped.

A query matches, in order of preference:
  - a session id prefix, a PR number ("943" or "#943"), or an exact worktree
    directory name or branch name
  - otherwise a case-insensitive substring of the session title, branch, or
    worktree directory name

Titles come from the transcript's custom-title record, which is written once a
session is named. Unnamed sessions still match by branch, worktree, PR, or id.

`resolve` prints the matched directory and the matched session's recorded
branch, tab-separated, on stdout. When nothing or more than one directory
matches, it lists up to MAX_ROWS candidates on stderr and exits 1.
"""

import json
import os
import re
import sys
from datetime import datetime

# Transcripts reach gigabytes; the fields we need are re-appended throughout a
# session, so the tail of each file carries their latest values.
TAIL_BYTES = 512 * 1024

# Candidate listings on a failed resolve stop here; `list` prints everything.
MAX_ROWS = 15

CWD_RE = re.compile(rb'"cwd":"((?:[^"\\]|\\.)*)"')
BRANCH_RE = re.compile(rb'"gitBranch":"((?:[^"\\]|\\.)*)"')
TITLE_RE = re.compile(rb'"type":"custom-title","customTitle":"((?:[^"\\]|\\.)*)"')
PR_RE = re.compile(rb'"type":"pr-link".*?"prNumber":(\d+)')


def encode(path):
    return re.sub(r"[^A-Za-z0-9]", "-", path)


def last(regex, blob):
    found = regex.findall(blob)
    return json.loads(b'"' + found[-1] + b'"') if found else ""


def projects_dir():
    base = os.environ.get("CLAUDE_CONFIG_DIR") or os.path.expanduser("~/.claude")
    return os.path.join(base, "projects")


def sessions(repo_root):
    """Yield one record per session whose working directory still exists."""
    roots = [repo_root]
    wt_dir = os.path.join(repo_root, ".claude", "worktrees")
    if os.path.isdir(wt_dir):
        roots += [os.path.join(wt_dir, d) for d in os.listdir(wt_dir)]

    base = projects_dir()
    for root in roots:
        pdir = os.path.join(base, encode(root))
        if not os.path.isdir(pdir):
            continue
        for name in os.listdir(pdir):
            if not name.endswith(".jsonl"):
                continue
            path = os.path.join(pdir, name)
            size = os.path.getsize(path)
            with open(path, "rb") as f:
                f.seek(max(0, size - TAIL_BYTES))
                blob = f.read()
            # The project dir names where a session started; a session can
            # move into a worktree, so its last cwd is where it is working.
            cwd = last(CWD_RE, blob) or root
            if not os.path.isfile(os.path.join(cwd, "Scripts", "build.sh")):
                continue
            yield {
                "id": name[: -len(".jsonl")],
                "cwd": cwd,
                "title": last(TITLE_RE, blob),
                "branch": last(BRANCH_RE, blob),
                "prs": {int(n) for n in PR_RE.findall(blob)},
                "mtime": os.path.getmtime(path),
            }


def describe(s):
    when = datetime.fromtimestamp(s["mtime"]).strftime("%m-%d %H:%M")
    pr = " #" + ",#".join(str(n) for n in sorted(s["prs"])) if s["prs"] else ""
    title = s["title"] or "(untitled)"
    return f"  {when}  {s['id'][:8]}  {title}  [{s['branch']}{pr}]  {s['cwd']}"


def match(all_sessions, query):
    q = query.strip().lower()
    num = q.lstrip("#")

    def exact(s):
        return (
            (len(q) >= 4 and s["id"].startswith(q))
            or (num.isdigit() and int(num) in s["prs"])
            or q == os.path.basename(s["cwd"]).lower()
            or q == s["branch"].lower()
        )

    def fuzzy(s):
        return any(
            q in field.lower()
            for field in (s["title"], s["branch"], os.path.basename(s["cwd"]))
        )

    return [s for s in all_sessions if exact(s)] or [
        s for s in all_sessions if fuzzy(s)
    ]


def main(argv):
    if len(argv) < 3 or argv[2] not in ("list", "resolve"):
        print(__doc__, file=sys.stderr)
        return 2
    repo_root = os.path.realpath(argv[1])
    found = sorted(sessions(repo_root), key=lambda s: s["mtime"], reverse=True)

    if argv[2] == "list":
        for s in found:
            print(describe(s))
        return 0

    query = argv[3] if len(argv) > 3 else ""
    hits = match(found, query)
    dirs = list(dict.fromkeys(s["cwd"] for s in hits))
    if len(dirs) == 1:
        # Hits are newest first, so this is the most recent matching session.
        print(dirs[0], hits[0]["branch"], sep="\t")
        return 0

    if not hits:
        print(f'error: no live session matches "{query}". Sessions:', file=sys.stderr)
        hits = found
    else:
        print(f'error: "{query}" matches sessions in {len(dirs)} directories:', file=sys.stderr)
    for s in hits[:MAX_ROWS]:
        print(describe(s), file=sys.stderr)
    if len(hits) > MAX_ROWS:
        print(f"  … {len(hits) - MAX_ROWS} more, use --session to list all", file=sys.stderr)
    return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
