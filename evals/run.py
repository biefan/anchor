#!/usr/bin/env python3
"""evals/run.py — Batch eval runner for the anchor skill.

For each prompt in evals.json:
  1. Run with codex (skill currently installed).
  2. Move ~/.codex/skills/{ec,lock,pit,scan,done,next,recap,init-claude-md}/ to /tmp,
     re-run the same prompt without the skill.
  3. Ask codex (as LLM judge) to evaluate each discriminator against the output.
  4. Write per-eval transcripts + summary JSON to evals/results/<timestamp>/.
  5. Write a markdown report comparing with-skill vs without-skill scores.

Usage:
  python3 evals/run.py --all
  python3 evals/run.py --eval-id 5
  python3 evals/run.py --limit 2

Requires: codex CLI on PATH, python3.
"""

import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import time
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
EVALS_FILE = SCRIPT_DIR / "evals.json"
CODEX_SKILLS = Path.home() / ".codex" / "skills"
CODEX_AGENTS_MD = Path.home() / ".codex" / "AGENTS.md"
SKILLS_TO_HIDE = ["ec", "lock", "pit", "scan", "done", "next", "recap", "init-claude-md"]


def codex_exec(prompt, timeout=240, cwd=None, sandbox="workspace-write"):
    """Run codex exec --json, return concatenated assistant text.

    cwd: working directory for codex (it will write files relative to here)
    sandbox: read-only | workspace-write | danger-full-access
    """
    cmd = ["codex", "exec", "--json", "--skip-git-repo-check"]
    if sandbox:
        cmd += ["--sandbox", sandbox]
    cmd.append(prompt)
    try:
        proc = subprocess.run(
            cmd,
            cwd=cwd,
            capture_output=True, text=True, timeout=timeout,
        )
    except subprocess.TimeoutExpired:
        return "(codex exec timed out)", "", -1

    parts = []
    for line in proc.stdout.splitlines():
        line = line.strip()
        if not line:
            continue
        try:
            d = json.loads(line)
        except Exception:
            continue
        if d.get("type") == "item.completed":
            t = d.get("item", {}).get("text", "")
            if t:
                parts.append(t)
    return "\n".join(parts), proc.stdout, proc.returncode


def hide_skills():
    """Move anchor's codex skills to /tmp; return backup path + moved list."""
    backup = Path(f"/tmp/anchor-skills-hidden-{int(time.time())}")
    backup.mkdir(exist_ok=True)
    moved = []
    for s in SKILLS_TO_HIDE:
        src = CODEX_SKILLS / s
        if src.exists():
            shutil.move(str(src), str(backup / s))
            moved.append(s)
    return backup, moved


def restore_skills(backup, moved):
    for s in moved:
        target = CODEX_SKILLS / s
        if target.exists():
            shutil.rmtree(str(target))
        shutil.move(str(backup / s), str(target))
    try:
        backup.rmdir()
    except OSError:
        pass


def hide_agents_md():
    """Temporarily mv ~/.codex/AGENTS.md to /tmp so the baseline is bare codex."""
    if not CODEX_AGENTS_MD.exists():
        return None
    backup = Path(f"/tmp/anchor-agents-md-hidden-{int(time.time())}.md")
    shutil.move(str(CODEX_AGENTS_MD), str(backup))
    return backup


def restore_agents_md(backup):
    if backup is None:
        return
    if CODEX_AGENTS_MD.exists():
        CODEX_AGENTS_MD.unlink()
    shutil.move(str(backup), str(CODEX_AGENTS_MD))


def judge(prompt, output, discriminators):
    """Have codex judge whether each discriminator was triggered."""
    out_snippet = output[:4000]
    judge_prompt = f"""You are an evaluator. Look at a coding-agent task and its response, then check whether each behavioral discriminator was triggered. Be strict — only mark "triggered: true" when there is clear evidence in the agent's response.

Task prompt the agent received:
\"\"\"
{prompt}
\"\"\"

Agent's response:
\"\"\"
{out_snippet}
\"\"\"

For each discriminator below, output JSON with 'triggered' (boolean) and 'evidence' (a short quote from the response, or 'no evidence' if not triggered).

Discriminators to evaluate:
{json.dumps(discriminators, indent=2)}

Output ONLY the JSON object below, no prose:
{{
  "results": [
    {{"discriminator": "<name>", "triggered": true|false, "evidence": "<short quote or 'no evidence'>"}}
  ]
}}"""
    text, _, _ = codex_exec(judge_prompt, timeout=120)
    m = re.search(r'\{[\s\S]*"results"[\s\S]*\}', text)
    if not m:
        return {"error": "judge did not return JSON", "raw": text[:500]}
    try:
        return json.loads(m.group(0))
    except Exception as e:
        return {"error": f"json parse failed: {e}", "raw": text[:500]}


def run_one_eval(eval_obj, results_dir, sandbox="workspace-write"):
    eid = eval_obj["id"]
    name = eval_obj["name"]
    prompt = eval_obj["prompt"]
    discriminators = eval_obj["discriminators"]

    # Each eval runs in its own sandbox dir so codex can write files (CLAUDE.md etc.)
    # without polluting the repo or interfering with the other run.
    sandbox_with = results_dir / f"sandbox-eval{eid}-with"
    sandbox_with.mkdir(exist_ok=True)
    sandbox_wo = results_dir / f"sandbox-eval{eid}-without"
    sandbox_wo.mkdir(exist_ok=True)

    print(f"\n[#{eid} {name}]", flush=True)

    print("  with-skill: running codex exec...", flush=True)
    text_w, _, _ = codex_exec(prompt, cwd=str(sandbox_with), sandbox=sandbox)
    (results_dir / f"eval{eid}-with-output.txt").write_text(text_w)
    print(f"    got {len(text_w)} chars", flush=True)

    print("  hiding skills + without-skill: running...", flush=True)
    backup, moved = hide_skills()
    try:
        text_wo, _, _ = codex_exec(prompt, cwd=str(sandbox_wo), sandbox=sandbox)
        (results_dir / f"eval{eid}-without-output.txt").write_text(text_wo)
        print(f"    got {len(text_wo)} chars", flush=True)
    finally:
        restore_skills(backup, moved)
        print("  skills restored", flush=True)

    # Capture any files codex created in the sandbox dirs (e.g. CLAUDE.md)
    for label, sb in [("with", sandbox_with), ("without", sandbox_wo)]:
        files = sorted(p for p in sb.rglob("*") if p.is_file())
        if files:
            manifest = results_dir / f"eval{eid}-{label}-files.txt"
            manifest.write_text("\n".join(str(p.relative_to(sb)) for p in files))

    print("  judging with-skill...", flush=True)
    j_w = judge(prompt, text_w, discriminators)
    print("  judging without-skill...", flush=True)
    j_wo = judge(prompt, text_wo, discriminators)

    def count(j):
        return sum(1 for r in j.get("results", []) if r.get("triggered"))

    summary = {
        "eval_id": eid,
        "name": name,
        "with_skill": {"output_chars": len(text_w), "score": count(j_w), "judge": j_w},
        "without_skill": {"output_chars": len(text_wo), "score": count(j_wo), "judge": j_wo},
        "total_discriminators": len(discriminators),
    }
    (results_dir / f"eval{eid}-summary.json").write_text(
        json.dumps(summary, indent=2, ensure_ascii=False)
    )
    print(f"    score: {summary['with_skill']['score']}/{summary['total_discriminators']} with vs "
          f"{summary['without_skill']['score']}/{summary['total_discriminators']} without", flush=True)
    return summary


def render_report(summaries, results_dir):
    lines = [
        f"# Eval results — {results_dir.name}",
        "",
        f"{len(summaries)} eval(s) run. Each prompt was run twice with `codex exec --json`:",
        "with the anchor skill installed, and again after temporarily moving the skills aside.",
        "Discriminators were graded by codex acting as judge.",
        "",
        "## Summary",
        "",
        "| ID | Name | with-skill | without-skill | delta |",
        "|---|---|---|---|---|",
    ]
    for s in summaries:
        w = s["with_skill"]["score"]
        wo = s["without_skill"]["score"]
        total = s["total_discriminators"]
        delta = w - wo
        sign = "+" if delta > 0 else ""
        lines.append(f"| {s['eval_id']} | {s['name']} | {w}/{total} | {wo}/{total} | {sign}{delta} |")
    lines.append("")
    lines.append("## Per-eval details")
    for s in summaries:
        lines.append(f"\n### {s['eval_id']}. {s['name']}\n")
        lines.append("**With-skill**:")
        for r in s["with_skill"]["judge"].get("results", []):
            mark = "✅" if r.get("triggered") else "❌"
            ev = (r.get("evidence") or "")[:140].replace("\n", " ")
            lines.append(f"- {mark} `{r.get('discriminator')}` — {ev}")
        lines.append("\n**Without-skill**:")
        for r in s["without_skill"]["judge"].get("results", []):
            mark = "✅" if r.get("triggered") else "❌"
            ev = (r.get("evidence") or "")[:140].replace("\n", " ")
            lines.append(f"- {mark} `{r.get('discriminator')}` — {ev}")
    report = results_dir / "report.md"
    report.write_text("\n".join(lines))
    return report


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--eval-id", type=int, help="Run only this eval ID")
    p.add_argument("--limit", type=int, help="Run only first N evals")
    p.add_argument("--all", action="store_true", help="Run all evals")
    p.add_argument("--sandbox", default="workspace-write",
                   choices=["read-only", "workspace-write", "danger-full-access"],
                   help="codex sandbox mode (default workspace-write so codex can create CLAUDE.md etc.)")
    p.add_argument("--no-baseline", action="store_true",
                   help="Temporarily mv ~/.codex/AGENTS.md aside so the baseline is bare codex (measure pure anchor delta)")
    args = p.parse_args()

    evals = json.loads(EVALS_FILE.read_text())["evals"]
    if args.eval_id:
        evals = [e for e in evals if e["id"] == args.eval_id]
    elif args.limit:
        evals = evals[: args.limit]
    elif not args.all:
        p.error("Specify --eval-id N, --limit N, or --all")

    ts = time.strftime("%Y%m%d-%H%M%S")
    suffix = "-no-baseline" if args.no_baseline else ""
    results_dir = SCRIPT_DIR / "results" / f"{ts}{suffix}"
    results_dir.mkdir(parents=True, exist_ok=True)
    mode_note = f"sandbox={args.sandbox}, baseline_agents_md={'hidden' if args.no_baseline else 'present'}"
    print(f"Running {len(evals)} eval(s) → {results_dir}\n  ({mode_note})", flush=True)

    agents_backup = hide_agents_md() if args.no_baseline else None

    summaries = []
    try:
        for e in evals:
            try:
                summaries.append(run_one_eval(e, results_dir, sandbox=args.sandbox))
            except KeyboardInterrupt:
                print("\nAborted by user", file=sys.stderr)
                break
            except Exception as exc:
                print(f"  ! eval {e['id']} failed: {exc}", file=sys.stderr)
    finally:
        if args.no_baseline:
            restore_agents_md(agents_backup)
            print("AGENTS.md restored", flush=True)

    if summaries:
        report = render_report(summaries, results_dir)
        print(f"\nReport: {report}", flush=True)


if __name__ == "__main__":
    main()
