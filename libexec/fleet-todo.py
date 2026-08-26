"""fleet todo — open tasks from a Loom vault (or any markdown notes)."""
import os, re, sys, datetime

HOME = os.path.expanduser("~")
TODAY = datetime.date.today()

# Loom: - [ ] open, - [/] in progress, - [x] done, - [-] cancelled
TASK = re.compile(r"^\s*[-*]\s\[(?P<st>[ /])\]\s+(?P<body>.+?)\s*$")
DUE  = re.compile(r"📅\s*(\d{4}-\d{2}-\d{2})")
TAG  = re.compile(r"#([A-Za-z0-9_/-]+)")
KEY  = re.compile(r"\b([A-Z][A-Z0-9]{1,9}-\d+)\b")
PRIO = {"⏫": (0, "urgent"), "🔼": (1, "high"), "🔽": (3, "low")}
LINK  = re.compile(r"\[([^\]]+)\]\((?:[^)]*)\)")
STRIP = re.compile(r"(⏱️\s*\S+|▶️\s*\S+|📅\s*\S+|⏰\s*\S+|🆔\s*\S+|[⏫🔼🔽]|#[A-Za-z0-9_/-]+)")

def roots():
    raw = os.environ.get("FLEET_TODO_PATHS") or os.path.join(HOME, "Documents/loom")
    return [os.path.expanduser(p) for p in raw.split(":") if p]

def collect():
    out = []
    for root in roots():
        if not os.path.isdir(root): continue
        for dirpath, dirnames, files in os.walk(root):
            dirnames[:] = [d for d in dirnames
                           if d not in (".git", "node_modules", ".loom", "assets", "templates", "data")]
            for fn in files:
                if not fn.endswith(".md"): continue
                if "(conflict)" in fn: continue     # Loom sync artefacts
                path = os.path.join(dirpath, fn)
                try:
                    mtime = os.path.getmtime(path)
                    with open(path, errors="replace") as f:
                        for n, line in enumerate(f, 1):
                            m = TASK.match(line)
                            if not m: continue
                            body = m.group("body")
                            tags = TAG.findall(body)
                            due = DUE.search(body)
                            prio = next(((v[0], v[1]) for g, v in PRIO.items() if g in body), (2, ""))
                            k = KEY.search(body)
                            out.append({
                                "file": path, "line": n, "mtime": mtime,
                                "inprog": m.group("st") == "/",
                                "text": re.sub(r"\s{2,}", " ", STRIP.sub("", LINK.sub(r"\1", body))).strip(" -"),
                                "tags": tags, "key": k.group(1) if k else None,
                                "due": datetime.date.fromisoformat(due.group(1)) if due else None,
                                "prio": prio[0], "prio_name": prio[1],
                            })
                except Exception:
                    continue
    return out

def main():
    show_all = "--all" in sys.argv
    tasks = collect()
    if not show_all:
        # backlog is not today's work
        tasks = [t for t in tasks if "status/backlog" not in t["tags"]]
    if not tasks:
        print("  no open tasks in: " + ", ".join(r.replace(HOME, "~") for r in roots()))
        return

    # Carryover repeats a task across daily notes; keep the freshest copy of each.
    seen, deduped = set(), []
    for t in sorted(tasks, key=lambda x: -x["mtime"]):
        norm = re.sub(r"\W+", "", t["text"].lower())[:70]
        if norm in seen: continue
        seen.add(norm); deduped.append(t)
    tasks = deduped

    def rank(t):
        overdue = 0 if (t["due"] and t["due"] <= TODAY) else 1
        return (overdue, 0 if t["inprog"] else 1, t["prio"], -t["mtime"])
    tasks.sort(key=rank)

    shown = tasks if show_all else tasks[:15]
    for t in shown:
        marks = []
        if t["inprog"]: marks.append("in-progress")
        if t["due"]:
            marks.append("DUE " + t["due"].isoformat() if t["due"] <= TODAY else "due " + t["due"].isoformat())
        if t["prio_name"]: marks.append(t["prio_name"])
        work = [g for g in t["tags"] if g.startswith(("work/", "p/"))]
        if work: marks.append(" ".join("#" + w for w in work))
        tag = f"[{t['key']}] " if t["key"] else ""
        txt = t["text"]
        if t["key"] and txt.startswith(t["key"]):
            txt = txt[len(t["key"]):].lstrip(" :-")
        suffix = ("   " + " · ".join(marks)) if marks else ""
        print(f"  {tag}{txt[:88]}{suffix}")
        print(f"      {t['file'].replace(HOME, '~')}:{t['line']}")
    hidden = len(tasks) - len(shown)
    if not show_all and hidden > 0:
        print(f"\n  ({hidden} more, incl. backlog — fleet todo --all)")

main()
