"""fleet todo — open markdown checkbox tasks from your notes."""
import os, re, sys, subprocess

HOME = os.path.expanduser("~")
TASK = re.compile(r"^\s*[-*]\s\[ \]\s+(.+?)\s*$")
KEY  = re.compile(r"\b([A-Z][A-Z0-9]{1,9}-\d+)\b")

def roots():
    raw = os.environ.get("FLEET_TODO_PATHS") or os.path.join(HOME, "base")
    return [os.path.expanduser(p) for p in raw.split(":") if p]

def collect(show_all):
    out = []
    for root in roots():
        if not os.path.isdir(root): continue
        for dirpath, dirnames, files in os.walk(root):
            dirnames[:] = [d for d in dirnames if d not in (".git", "node_modules", ".loom")]
            for fn in files:
                if not fn.endswith(".md"): continue
                path = os.path.join(dirpath, fn)
                try:
                    mtime = os.path.getmtime(path)
                    with open(path, errors="replace") as f:
                        for n, line in enumerate(f, 1):
                            m = TASK.match(line)
                            if m:
                                out.append({"file": path, "line": n, "text": m.group(1),
                                            "mtime": mtime,
                                            "key": (KEY.search(m.group(1)) or [None, None])[1]
                                                   if KEY.search(m.group(1)) else None})
                except Exception:
                    continue
    out.sort(key=lambda t: (-t["mtime"], t["file"], t["line"]))
    return out

def main():
    show_all = "--all" in sys.argv
    tasks = collect(show_all)
    if not tasks:
        print("  no open tasks found in: " + ", ".join(r.replace(HOME, "~") for r in roots()))
        return
    shown = tasks if show_all else tasks[:20]
    cur = None
    for t in shown:
        f = t["file"].replace(HOME, "~")
        if f != cur:
            print(f"\n  {f}")
            cur = f
        tag = f"[{t['key']}] " if t["key"] else ""
        print(f"    {tag}{t['text'][:96]}")
    if not show_all and len(tasks) > len(shown):
        print(f"\n  ({len(tasks) - len(shown)} more — fleet todo --all)")

main()
