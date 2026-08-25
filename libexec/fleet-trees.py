"""fleet trees — list/inspect/remove git worktrees across configured roots."""
import json, os, subprocess, sys

HOME = os.path.expanduser("~")
def short(p): return p.replace(HOME, "~")

def sh(args, cwd=None):
    try:
        return subprocess.run(args, cwd=cwd, capture_output=True, text=True, timeout=15).stdout
    except Exception:
        return ""

def repos(roots):
    for root in roots:
        if not os.path.isdir(root): continue
        for name in sorted(os.listdir(root)):
            d = os.path.join(root, name)
            if os.path.isdir(os.path.join(d, ".git")) or os.path.isfile(os.path.join(d, ".git")):
                yield d

def worktrees(repo):
    out, cur = [], {}
    for line in sh(["git", "worktree", "list", "--porcelain"], cwd=repo).splitlines():
        if line.startswith("worktree "): cur = {"path": line[9:]}
        elif line.startswith("branch "):  cur["branch"] = line[7:].replace("refs/heads/", "")
        elif line.startswith("detached"): cur["branch"] = "(detached)"
        elif line.startswith("prunable"): cur["prunable"] = True
        elif not line.strip() and cur:    out.append(cur); cur = {}
    if cur: out.append(cur)
    return out

def state(path, main_path):
    if not os.path.isdir(path):
        return "GONE", ""
    dirty = bool(sh(["git", "status", "--porcelain"], cwd=path).strip())
    ahead = sh(["git", "rev-list", "--count", "@{u}..HEAD"], cwd=path).strip() or "0"
    merged = ""
    if path != main_path:
        base = ""
        for cand in ("origin/main", "origin/master", "origin/develop", "main", "master", "develop"):
            if sh(["git", "rev-parse", "--verify", "--quiet", cand], cwd=path).strip():
                base = cand; break
        if base:
            unmerged = sh(["git", "log", "--oneline", f"{base}..HEAD"], cwd=path).strip()
            if not unmerged: merged = "merged"
    flags = []
    if dirty: flags.append("dirty")
    if ahead not in ("0", ""): flags.append(f"+{ahead}")
    if merged: flags.append(merged)
    return ("dirty" if dirty else "clean"), " ".join(flags)

def agents_by_cwd():
    try:
        out = sh(["herdr", "agent", "list"])
        data = json.loads(out)["result"]["agents"]
        return {a["cwd"]: a for a in data}
    except Exception:
        return {}

def main():
    roots = [r for r in os.environ.get("FLEET_ROOTS", os.path.join(HOME, "dev")).split(":") if r]
    roots = [os.path.expanduser(r) for r in roots]
    show_all = "--all" in sys.argv
    ag = agents_by_cwd()
    rows = []
    for repo in repos(roots):
        wts = worktrees(repo)
        main_path = wts[0]["path"] if wts else repo
        for w in wts:
            is_linked = w["path"] != main_path
            st, flags = state(w["path"], main_path)
            a = ag.get(w["path"])
            rows.append({
                "repo": os.path.basename(repo),
                "branch": w.get("branch", "?"),
                "path": w["path"],
                "linked": is_linked,
                "state": st, "flags": flags,
                "agent": (a["agent"] + ":" + a["agent_status"]) if a else "",
                "prunable": w.get("prunable", False) or st == "GONE",
            })
    linked = [r for r in rows if r["linked"]]
    mains  = [r for r in rows if not r["linked"]]
    shown  = rows if show_all else linked

    if not shown:
        print("  no task worktrees")
        print(f"  ({len(mains)} repos on their main checkout — fleet trees --all to list them)")
        return

    wr = max(len(r["repo"]) for r in shown)
    wb = max(len(r["branch"]) for r in shown)
    for r in sorted(shown, key=lambda r: (not r["linked"], r["repo"])):
        mark = "└" if r["linked"] else " "
        note = " ".join(x for x in [r["flags"], r["agent"]] if x)
        warn = "  ⚠ stale" if r["prunable"] else ""
        print(f" {mark} {r['repo']:<{wr}}  {r['branch']:<{wb}}  {note:<24}{warn}")

    stale = [r for r in shown if r["prunable"]]
    if stale: print(f"\n  {len(stale)} stale — clear with: fleet trees --prune")
    if linked and not show_all:
        print(f"\n  {len(linked)} task worktree(s). Remove one with: fleet trees --rm <branch>")
    if not show_all:
        print(f"  ({len(mains)} repos on their main checkout — fleet trees --all to list them)")

main()
