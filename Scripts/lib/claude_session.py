#!/usr/bin/env python3
"""Resolve a Claude Code session to the checkout it is working in.

Usage:
    claude_session.py <repo-root> list
    claude_session.py <repo-root> resolve <query>
    claude_session.py <repo-root> pick [query]

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

`pick` prints the same as `resolve`, but instead of failing it opens an
arrow-key picker on the terminal: over every session when no query is given or
nothing matches, otherwise over the matches. Esc or Ctrl-C cancels with exit 1.
"""

import curses
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


def describe(s, short=False):
    when = datetime.fromtimestamp(s["mtime"]).strftime("%m-%d %H:%M")
    pr = " #" + ",#".join(str(n) for n in sorted(s["prs"])) if s["prs"] else ""
    title = s["title"] or "(untitled)"
    where = os.path.basename(s["cwd"]) if short else s["cwd"]
    return f"  {when}  {s['id'][:8]}  {title}  [{s['branch']}{pr}]  {where}"


def pick(candidates, header):
    """Let the user choose a session with the arrow keys; None when cancelled."""
    rows = [(describe(s, short=True), s) for s in candidates]

    def run(scr):
        curses.curs_set(0)
        # Raw mode delivers Ctrl-C as a key; in cbreak mode it would SIGINT
        # the calling build.sh too.
        curses.raw()
        query, sel, top = "", 0, 0
        while True:
            shown = [r for r in rows if query.lower() in r[0].lower()]
            sel = max(0, min(sel, len(shown) - 1))
            height, width = scr.getmaxyx()
            body = max(1, height - 3)
            top = min(max(top, sel - body + 1), sel)
            scr.erase()
            scr.addnstr(0, 0, header, width - 1, curses.A_BOLD)
            scr.addnstr(1, 0, f"filter: {query}  ({len(shown)}/{len(rows)})", width - 1)
            for i, (text, _) in enumerate(shown[top : top + body]):
                attr = curses.A_REVERSE if top + i == sel else curses.A_NORMAL
                scr.addnstr(2 + i, 0, text.ljust(width - 1), width - 1, attr)
            scr.refresh()

            key = scr.get_wch()
            if key in (curses.KEY_UP, "\x10"):
                sel -= 1
            elif key in (curses.KEY_DOWN, "\x0e"):
                sel += 1
            elif key == curses.KEY_PPAGE:
                sel -= body
            elif key == curses.KEY_NPAGE:
                sel += body
            elif key in ("\n", "\r", curses.KEY_ENTER):
                if shown:
                    return shown[sel][1]
            elif key in ("\x1b", "\x03"):
                return None
            elif key in (curses.KEY_BACKSPACE, "\x7f", "\x08"):
                query = query[:-1]
            elif isinstance(key, str) and key.isprintable():
                query, sel = query + key, 0

    # stdout may be captured by the caller, so draw on the terminal itself and
    # restore stdout before printing the choice.
    os.environ.setdefault("ESCDELAY", "25")
    sys.stdout.flush()
    saved_in, saved_out = os.dup(0), os.dup(1)
    tty = os.open("/dev/tty", os.O_RDWR)
    os.dup2(tty, 0)
    os.dup2(tty, 1)
    try:
        return curses.wrapper(run)
    finally:
        os.dup2(saved_in, 0)
        os.dup2(saved_out, 1)
        os.close(tty)


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
    if len(argv) < 3 or argv[2] not in ("list", "resolve", "pick"):
        print(__doc__, file=sys.stderr)
        return 2
    repo_root = os.path.realpath(argv[1])
    found = sorted(sessions(repo_root), key=lambda s: s["mtime"], reverse=True)

    if argv[2] == "list":
        for s in found:
            print(describe(s))
        return 0

    query = argv[3] if len(argv) > 3 else ""
    hits = match(found, query) if query else []
    dirs = list(dict.fromkeys(s["cwd"] for s in hits))
    if len(dirs) == 1:
        # Hits are newest first, so this is the most recent matching session.
        print(dirs[0], hits[0]["branch"], sep="\t")
        return 0

    if argv[2] == "pick":
        if not query:
            header = "Pick a session to build"
        elif not hits:
            header = f'No session matches "{query}"; pick one'
        else:
            header = f'"{query}" matches {len(dirs)} directories; pick one'
        header += "  (↑/↓ move, type to filter, Enter build, Esc cancel)"
        chosen = pick(hits or found, header)
        if chosen is None:
            return 1
        print(chosen["cwd"], chosen["branch"], sep="\t")
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
