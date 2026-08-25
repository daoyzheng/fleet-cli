"""fleet handoff — print an agent's full final report from its session transcript."""
import json, os, sys, glob

def transcript_for(cwd):
    # Claude Code slugifies the cwd: every "/" and "." becomes "-"
    slug = cwd.replace("/", "-").replace(".", "-")
    d = os.path.expanduser(f"~/.claude/projects/{slug}")
    files = sorted(glob.glob(os.path.join(d, "*.jsonl")), key=os.path.getmtime, reverse=True)
    return files[0] if files else None

def texts(path):
    """Yield assistant text blocks in order."""
    out = []
    with open(path, errors="replace") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                rec = json.loads(line)
            except Exception:
                continue
            msg = rec.get("message") or {}
            if rec.get("type") != "assistant" and msg.get("role") != "assistant":
                continue
            content = msg.get("content")
            if isinstance(content, str):
                out.append(content)
            elif isinstance(content, list):
                for b in content:
                    if isinstance(b, dict) and b.get("type") == "text" and b.get("text"):
                        out.append(b["text"])
    return out

def main():
    cwd = sys.argv[1]
    n = int(sys.argv[2]) if len(sys.argv) > 2 else 1
    t = transcript_for(cwd)
    if not t:
        print(f"no transcript found for {cwd}", file=sys.stderr)
        print("(only Claude Code sessions keep one; Cursor agents do not)", file=sys.stderr)
        sys.exit(2)
    blocks = [b for b in texts(t) if b.strip()]
    if not blocks:
        print("transcript has no assistant messages yet", file=sys.stderr); sys.exit(3)
    for b in blocks[-n:]:
        print(b)
        print()

main()
