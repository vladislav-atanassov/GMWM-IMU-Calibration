"""UserPromptSubmit hook: when a prompt mentions committing, give Claude the commit check.

Runs `python experiments/run.py --check` (the same check as the git pre-commit hook) and adds
its report to Claude's context, with a reminder of what only reading can check: that each
experiment's README still describes its outputs. Never blocks the prompt.
"""
import json
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]

# "commit", "committing", "commited", and typos such as "comit" or "commtiitng"
MENTIONS_COMMIT = re.compile(r"\bcom+[it]{2}", re.IGNORECASE)

REMINDER = """Before saying anything is ready to commit, also check by reading what the script cannot:
- Each experiment README's Conclusion, Findings and Results describe the outputs in its out/.
- Its Setup matches config.json and main.m.
- The main README, data/README.md and experiments/README.md describe the repository as it is:
  what each part does and what the results are. They do not narrate edits, earlier runs, or plans.
Report what is stale and the command or edit that fixes it; do not commit (the user commits)."""


def main():
    try:
        prompt = json.load(sys.stdin).get("prompt", "")
    except ValueError:
        return
    if not MENTIONS_COMMIT.search(prompt):
        return
    try:
        result = subprocess.run([sys.executable, "experiments/run.py", "--check"], cwd=ROOT,
                                capture_output=True, text=True, timeout=60)
        report = (result.stdout + result.stderr).strip()
    except (OSError, subprocess.TimeoutExpired) as e:
        report = f"[!] The check could not run: {e}"
    context = f"Commit check (python experiments/run.py --check):\n{report}\n\n{REMINDER}"
    print(json.dumps({"hookSpecificOutput": {"hookEventName": "UserPromptSubmit", "additionalContext": context}}))


if __name__ == "__main__":
    main()
