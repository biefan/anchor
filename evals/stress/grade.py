#!/usr/bin/env python3
"""evals/stress/grade.py — Auto-grade a stress test run using codex-as-judge.

Takes the products of an already-run stress test (transcript, sandbox dir) and
asks codex to evaluate each rubric item from the stress test's spec file.
Outputs a markdown grading report.

Usage:
  python3 evals/stress/grade.py \\
      --stress-id 2 \\
      --transcript /tmp/run/transcript.txt \\
      --sandbox /tmp/run/work \\
      [--output /tmp/run/grading.md] \\
      [--json]
"""
from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
import textwrap
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
STRESS_DIR = REPO_ROOT / "evals" / "stress"


def parse_args():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--stress-id", type=int, required=True, help="Stress test number (1/2/3)")
    p.add_argument("--transcript", type=Path, required=True, help="File with the agent's transcript")
    p.add_argument("--sandbox", type=Path, required=True, help="Working dir the test ran in")
    p.add_argument("--output", type=Path, help="Output markdown file (default: stress-{id}-grading.md next to transcript)")
    p.add_argument("--json", action="store_true", help="Print JSON instead of writing markdown")
    return p.parse_args()


def find_spec_file(stress_id: int) -> Path:
    for f in STRESS_DIR.glob(f"0{stress_id}-*.md"):
        return f
    raise SystemExit(f"No stress test spec found for id={stress_id}")


def extract_rubric(spec_text: str) -> list[dict]:
    """Pull rubric items out of the spec's "Post-run rubric" section.

    Each item is one row of a markdown table with at least 2 columns
    (check name + how to verify).
    """
    # Find the "Post-run rubric" or "Post-run rubric (...)" section heading.
    m = re.search(r'^##\s+Post-run rubric.*$', spec_text, re.M)
    if not m:
        return []
    section = spec_text[m.end():]
    # Stop at the next ##-level heading
    next_h = re.search(r'^##\s', section, re.M)
    if next_h:
        section = section[:next_h.start()]
    rubric = []
    for row in re.finditer(r'^\|\s*([^|]+?)\s*\|\s*([^|]+?)\s*\|', section, re.M):
        check = row.group(1).strip()
        how = row.group(2).strip()
        # Skip table header / divider rows
        if check.lower() in ("scenario-specific check", "anchor behavior", "check", "---"):
            continue
        if set(check) <= {'-', ' '}:
            continue
        rubric.append({"check": check, "how_to_verify": how})
    return rubric


def collect_evidence(sandbox: Path) -> str:
    """Gather objective evidence about the post-run sandbox state for the judge."""
    parts = []
    if sandbox.exists():
        parts.append(f"== Sandbox path: {sandbox} ==\n")
        # git log
        out = subprocess.run(["git", "-C", str(sandbox), "log", "--oneline", "-20"],
                             capture_output=True, text=True)
        parts.append("== git log --oneline (last 20) ==")
        parts.append(out.stdout.strip() or "(no commits)")
        parts.append("")
        # git diff --stat
        out = subprocess.run(["git", "-C", str(sandbox), "diff", "--stat", "HEAD~5..HEAD"],
                             capture_output=True, text=True)
        if not out.stdout.strip():
            out = subprocess.run(["git", "-C", str(sandbox), "diff", "--stat"],
                                 capture_output=True, text=True)
        parts.append("== git diff --stat ==")
        parts.append(out.stdout.strip() or "(no diff)")
        parts.append("")
        # File listing (top 20, excluding common dep trees)
        skip_dirs = {".git", "node_modules", "vendor", "site-packages", "target", ".venv", "venv", "__pycache__"}
        files = []
        for p in sandbox.rglob("*"):
            if not p.is_file():
                continue
            if any(part in skip_dirs for part in p.parts):
                continue
            files.append(str(p.relative_to(sandbox)))
        files = sorted(files)[:20]
        parts.append("== Files in sandbox (top 20, excluding deps) ==")
        parts.append("\n".join(files) if files else "(empty)")
        parts.append("")
        # CLAUDE.md / AGENTS.md if present
        for fname in ("CLAUDE.md", "AGENTS.md"):
            f = sandbox / fname
            if f.exists():
                parts.append(f"== {fname} contents ==")
                parts.append(f.read_text()[:3000])
                parts.append("")
        # Dependency cross-check (Node / Python / Rust / Go)
        dep_section = _collect_dep_evidence(sandbox)
        if dep_section:
            parts.append("== Dependency cross-check (declared vs installed) ==")
            parts.append(dep_section)
            parts.append("")
    return "\n".join(parts)


def _collect_dep_evidence(sandbox: Path) -> str:
    """Compare declared deps (manifests) with what's actually on disk.

    Spots the common cheat where an agent copies a foreign node_modules /
    site-packages / vendor instead of running the package manager.
    """
    out = []

    # Node: package.json vs node_modules top-level
    pkg_json = sandbox / "package.json"
    nm = sandbox / "node_modules"
    if pkg_json.exists() and nm.exists():
        try:
            pkg = json.loads(pkg_json.read_text())
            declared = set((pkg.get("dependencies") or {}).keys()) | \
                       set((pkg.get("devDependencies") or {}).keys())
            top = sorted(p.name for p in nm.iterdir() if p.is_dir())
            extras = [t for t in top if t not in declared and not t.startswith(".")]
            out.append(f"Node — declared deps: {sorted(declared) or '(none)'}")
            out.append(f"Node — node_modules top-level: {top[:40]}{'...' if len(top) > 40 else ''}")
            if extras:
                out.append(f"⚠️  Node — node_modules has {len(extras)} top-level package(s) NOT in declared deps:")
                out.append(f"    {extras[:30]}{'...' if len(extras) > 30 else ''}")
                out.append("    (Many of these may be transitive; but a large unrelated set suggests the agent borrowed node_modules from elsewhere.)")
            out.append("")
        except Exception as e:
            out.append(f"(Node dep check failed: {e})")

    # Python: requirements.txt / pyproject.toml vs site-packages presence
    has_requirements = (sandbox / "requirements.txt").exists()
    has_pyproject = (sandbox / "pyproject.toml").exists()
    site_packages = list(sandbox.glob("**/site-packages")) + list(sandbox.glob(".venv/lib/*/site-packages"))
    if (has_requirements or has_pyproject) and site_packages:
        sp = site_packages[0]
        installed = sorted(p.name.split("-")[0] for p in sp.glob("*.dist-info")) if sp.exists() else []
        out.append(f"Python — manifest present: requirements.txt={has_requirements}, pyproject.toml={has_pyproject}")
        out.append(f"Python — site-packages dist-info entries ({len(installed)}): {installed[:30]}{'...' if len(installed) > 30 else ''}")
        out.append("")

    # Rust: Cargo.toml + Cargo.lock + target/
    cargo_toml = sandbox / "Cargo.toml"
    cargo_lock = sandbox / "Cargo.lock"
    if cargo_toml.exists():
        out.append(f"Rust — Cargo.toml present; Cargo.lock present: {cargo_lock.exists()}")
        if (sandbox / "target").exists():
            out.append("Rust — target/ exists (compiled artifacts)")
        out.append("")

    # Go: go.mod + vendor/
    go_mod = sandbox / "go.mod"
    vendor = sandbox / "vendor"
    if go_mod.exists():
        vendor_entries = sorted(p.name for p in vendor.iterdir() if p.is_dir())[:20] if vendor.exists() else []
        out.append(f"Go — go.mod present; vendor/ present: {vendor.exists()}")
        if vendor_entries:
            out.append(f"Go — vendor/ top entries: {vendor_entries}")
        out.append("")

    return "\n".join(out).strip()


def codex_judge(prompt: str, timeout: int = 240) -> str:
    """Run codex exec, return the assistant's final text response."""
    proc = subprocess.run(
        ["codex", "exec", "--json", "--skip-git-repo-check", prompt],
        capture_output=True, text=True, timeout=timeout,
    )
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
    return "\n".join(parts)


def build_judge_prompt(spec_text: str, rubric: list[dict],
                       transcript: str, evidence: str) -> str:
    """Compose the judge's task prompt."""
    # Truncate transcript / evidence to avoid huge prompts
    transcript_snippet = transcript[:6000]
    if len(transcript) > 6000:
        transcript_snippet += "\n\n... [transcript truncated]"
    rubric_lines = []
    for i, item in enumerate(rubric, 1):
        rubric_lines.append(f"  {i}. {item['check']}\n     How: {item['how_to_verify']}")
    return textwrap.dedent(f"""\
        You are evaluating a stress-test run of the anchor skill.

        A coding agent was asked to perform the task described in the SPEC below.
        Their TRANSCRIPT and the resulting SANDBOX state are provided.

        Your job: for each RUBRIC item, return JSON saying whether the behavior was
        exhibited (Pass=true, Fail=false, NA=null) and a one-line evidence quote or observation.

        IMPORTANT — use **NA (null)** instead of Fail when:
        - The rubric item explicitly says "Mark N/A if ..." and that condition holds
          (e.g. "pytest not installed", "agent ran under codex exec, not Claude Code").
        - The check is unverifiable in the available evidence through no fault of the agent
          (e.g. the rubric asks whether tests pass but the grading env can't run them, and
          the transcript doesn't show an explicit run).

        Use **Fail (false)** when the agent demonstrably did not do something the spec
        required (e.g. the spec prompt said "commit in two steps" and `git log` shows
        a single commit).

        Use **Pass (true)** when the evidence positively confirms the behavior.

        ==== SPEC (excerpt of what was asked) ====
        {spec_text[:3000]}

        ==== TRANSCRIPT (agent's responses, truncated) ====
        {transcript_snippet}

        ==== SANDBOX STATE ====
        {evidence}

        ==== RUBRIC ITEMS ====
        {chr(10).join(rubric_lines)}

        Output exactly this JSON, no prose:
        {{
          "results": [
            {{"check": "<exact check string>", "passed": true|false|null, "evidence": "<one line>"}},
            ...
          ]
        }}
        """)


def parse_judge_output(text: str) -> dict:
    m = re.search(r'\{[\s\S]*"results"[\s\S]*\}', text)
    if not m:
        return {"error": "judge returned no JSON", "raw": text[:500]}
    try:
        return json.loads(m.group(0))
    except Exception as e:
        return {"error": f"JSON parse failed: {e}", "raw": text[:500]}


def render_markdown(stress_id: int, rubric: list[dict], judge: dict, args) -> str:
    lines = [f"# Stress test #{stress_id} — grading report", ""]
    if "error" in judge:
        lines.append(f"⚠️  Judge error: {judge['error']}")
        lines.append("")
        lines.append("Raw output:")
        lines.append("```")
        lines.append(judge.get("raw", ""))
        lines.append("```")
        return "\n".join(lines)

    results = judge.get("results", [])
    passed = sum(1 for r in results if r.get("passed") is True)
    failed = sum(1 for r in results if r.get("passed") is False)
    na = sum(1 for r in results if r.get("passed") is None)

    lines.append(f"**Score**: {passed} pass / {failed} fail / {na} N/A (out of {len(results)})")
    lines.append("")
    lines.append(f"**Transcript**: `{args.transcript}`")
    lines.append(f"**Sandbox**: `{args.sandbox}`")
    lines.append("")
    lines.append("| # | Check | Verdict | Evidence |")
    lines.append("|---|---|---|---|")
    for i, r in enumerate(results, 1):
        p = r.get("passed")
        mark = "✅" if p is True else ("❌" if p is False else "—")
        ev = (r.get("evidence") or "").replace("|", "\\|").replace("\n", " ")[:160]
        check = r.get("check", "?").replace("|", "\\|")[:80]
        lines.append(f"| {i} | {check} | {mark} | {ev} |")
    lines.append("")
    return "\n".join(lines)


def main():
    args = parse_args()
    spec_file = find_spec_file(args.stress_id)
    spec_text = spec_file.read_text()
    rubric = extract_rubric(spec_text)
    if not rubric:
        print(f"⚠️  No rubric extracted from {spec_file.name}", file=sys.stderr)
        sys.exit(1)
    transcript = args.transcript.read_text() if args.transcript.exists() else ""
    if not transcript:
        print(f"⚠️  Empty/missing transcript: {args.transcript}", file=sys.stderr)
    evidence = collect_evidence(args.sandbox)
    prompt = build_judge_prompt(spec_text, rubric, transcript, evidence)
    print(f"Calling codex judge ({len(prompt)} chars in prompt, {len(rubric)} rubric items)...",
          flush=True, file=sys.stderr)
    raw = codex_judge(prompt)
    judge = parse_judge_output(raw)
    md = render_markdown(args.stress_id, rubric, judge, args)
    if args.json:
        sys.stdout.write(json.dumps({"rubric": rubric, "judge": judge}, indent=2, ensure_ascii=False))
        sys.stdout.write("\n")
    else:
        out_file = args.output or args.transcript.with_suffix(".grading.md")
        out_file.write_text(md)
        print(f"Report → {out_file}")
        print()
        print(md)


if __name__ == "__main__":
    main()
