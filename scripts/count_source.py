"""Count implementation code only; never count tests, generated APIs or vendors."""
import argparse
import json
from pathlib import Path

parser = argparse.ArgumentParser()
parser.add_argument("--minimum", type=int, default=0)
args = parser.parse_args()
root = Path(__file__).resolve().parents[1]
counts = {}
for path in sorted(root.rglob("*.mbt")):
    relative = path.relative_to(root)
    if any(part in {".mooncakes", "_build", ".git", "node_modules"} for part in relative.parts):
        continue
    if path.name.endswith(("_test.mbt", "_wbtest.mbt")):
        continue
    counts[str(relative).replace("\\", "/")] = sum(
        bool(line.strip()) and not line.lstrip().startswith("//")
        for line in path.read_text(encoding="utf-8").splitlines()
    )
total = sum(counts.values())
print(json.dumps({"implementation_lines": total, "files": counts}, indent=2))
if total < args.minimum:
    raise SystemExit(f"Implementation has {total} lines; required minimum is {args.minimum}")
