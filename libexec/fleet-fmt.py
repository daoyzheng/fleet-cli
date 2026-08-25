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
    rows = [a for a in data if a["agent_status"] in ("idle", "blocked", "done")]
    if not rows:
        print("nothing waiting")
    else:
        for a in rows:
            print("%s  %-8s %s" % (name(a), a["agent_status"], short(a["cwd"])))
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
