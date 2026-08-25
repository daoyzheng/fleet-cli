import sys, json, os

mode = sys.argv[1] if len(sys.argv) > 1 else "status"
data = json.load(sys.stdin)["result"]["agents"]
home = os.path.expanduser("~")
MARK = {"working": "◐", "idle": "✓", "blocked": "!", "done": "✓"}

def name(a):
    return a.get("name") or a["pane_id"]

def short(p):
    return p.replace(home, "~")

if mode == "ready":
    # Only agents fleet dispatched (they have a name); interactive panes you
    # opened yourself are always "idle" and are not waiting on anything.
    dispatched = [a for a in data if a.get("name")]
    rows = [a for a in dispatched if a["agent_status"] in ("idle", "blocked", "done")]
    others = len(data) - len(dispatched)
    if not rows:
        print("nothing waiting")
    else:
        w = max(len(name(a)) for a in rows)
        for a in sorted(rows, key=lambda x: x["agent_status"] != "blocked"):
            mark = "!" if a["agent_status"] == "blocked" else "\u2713"
            print("%s %-*s  %-8s %s" % (mark, w, name(a), a["agent_status"], short(a["cwd"])))
    if others:
        print("(%d interactive session%s not shown)" % (others, "" if others == 1 else "s"))
    sys.exit()

if not data:
    print("no agents")
    sys.exit()

w = max(len(name(a)) for a in data)
order = {"blocked": 0, "idle": 1, "done": 1, "working": 2}
for a in sorted(data, key=lambda x: order.get(x["agent_status"], 3)):
    print("%s %-*s  %-7s %-8s %s" % (
        MARK.get(a["agent_status"], "?"), w, name(a),
        a["agent"], a["agent_status"], short(a["cwd"])))
