---
name: adversarial-review
description: >
  Multi-agent adversarial review using scored finder/adversary/referee pattern.
  Exploits sycophancy by giving each agent opposing incentives. Triggers on:
  "adversarial review", "adversarial audit", "/adversarial-review", "find all
  bugs", "deep review", "three-agent review", "scored review", "find issues in",
  or when the user wants high-fidelity issue detection in code, content, or
  deliverables. Takes a target (file path, directory, or description) as argument.
argument-hint: "<file, directory, or description of what to review>"
allowed-tools:
  - Bash
  - Read
  - Glob
  - Grep
  - Write
  - Edit
  - Agent
  - AskUserQuestion
user-invocable: true
---

# Adversarial Review — Scored Multi-Agent Verification

Spawns three agents with opposing incentives to produce high-fidelity issue detection. Exploits the design limitation of sycophancy — each agent WANTS to please, so you give them contradictory goals. The intersection of their outputs is close to ground truth.

## Why This Works

Single-agent review has two failure modes:
1. **False positives**: You say "find bugs" and the agent manufactures bugs to please you
2. **False negatives**: You say "is this correct?" and the agent says yes to please you

Both fail because sycophancy biases the agent toward whatever outcome you implied. The adversarial pattern eliminates this by making three agents compete:

- **Finder** is rewarded for finding issues → over-reports (superset of possible issues)
- **Adversary** is rewarded for disproving issues → over-dismisses (subset of real issues)
- **Referee** is rewarded for accuracy → calibrates between them (close to ground truth)

The overlap between what the Finder found AND the Adversary couldn't disprove AND the Referee confirmed ≈ the actual issues.

## Arguments

`$ARGUMENTS` = what to review. Can be:
- A file path (`src/auth/middleware.ts`)
- A directory (`src/auth/`)
- A description ("the new payment flow I just built")
- A deliverable ("the consulting proposal for GridBank")
- A vague pointer ("this folder", "what I just changed") — resolve it from context (cwd, recent git changes, etc.)

If `$ARGUMENTS` is empty or unclear and you can't resolve it from context, use
AskUserQuestion — never print a manual text prompt. But try to resolve first:
`git diff --name-only HEAD~1` or `ls` the cwd often gives you the answer.

## Process

### Phase 1: Scope the Review

1. **Identify the target files** — list the files to review (use `ls`, `find`, `git diff --name-only`). Do NOT read the files yourself — that bloats your context. Build a file list and pass it to the sub-agents. They'll read the files in their own context.
2. **Determine review type** — this changes the scoring and agent prompts:

| Review Type | Finder Looks For | Adversary Challenges |
|-------------|-----------------|---------------------|
| **Code** | Bugs, security issues, logic errors, edge cases, performance | Whether each "bug" is actually a bug given the context |
| **Content** | Unclear writing, missing explanations, factual errors, weak hooks | Whether each "issue" actually matters to the target audience |
| **Architecture** | Design flaws, scalability issues, tight coupling, missing abstractions | Whether each "flaw" is relevant given the project's actual scale and goals |
| **Deliverable** | Gaps in requirements, unclear specs, missing edge cases, scope issues | Whether each "gap" is in-scope and whether it actually matters |

3. **Prepare the context** — gather the files/content that all three agents need to see
4. **Measure total LOC** — count lines across all target files (`wc -l`). This determines whether to use single-Finder or parallel-Finder mode (see Phase 2).

### Phase 2: Spawn the Finder(s)

**Choose mode based on codebase size:**

| Total LOC | Mode | Why |
|-----------|------|-----|
| < 1500 | **Single Finder** — one agent reads everything | Fits comfortably in one context. Parallelizing adds overhead without benefit. |
| 1500-5000 | **Parallel Finders** — 2-4 chunk agents + 1 cross-cutting agent | Too much for one agent to hold in context with full attention. Splitting prevents the agent from skimming later files after context fills up. |
| > 5000 | **Parallel Finders** — 4-6 chunk agents + 1 cross-cutting agent | One agent would exhaust context or lose detail. Must parallelize. |

#### Single Finder Mode (< 1500 LOC)

Launch one Opus agent with the standard Finder prompt (see Finder Prompt Template below).

#### Parallel Finder Mode (>= 1500 LOC)

Apply the same MECE decomposition principle from deep-research: split files into non-overlapping chunks, spawn parallel Finder agents, then merge.

**Step 1: MECE Decomposition**

Split target files into chunks using natural boundaries. Each chunk:
- Does NOT overlap with any other chunk (no file appears in two chunks)
- Together they cover every target file
- Is small enough for one agent to read with full attention (~500-1500 LOC per chunk)
- Groups related files together (same module/directory) so the agent has enough context to spot intra-module bugs

Good chunk boundaries for code reviews:
- By directory/module (`trader/execution/`, `trader/forecast/`, etc.)
- By concern (state management files, API integration files, test files)
- By data flow stage (input parsing → processing → output)

**Step 2: Spawn Parallel Chunk Finders**

Launch N Finder agents **in parallel** (all in one message with multiple Agent tool calls). Each gets the standard Finder prompt BUT with only its chunk of files. Add this to each prompt:

```
IMPORTANT: You are one of {N} parallel Finder agents. You are reviewing ONLY your
assigned chunk. Other agents cover other files. Focus deeply on YOUR files — you
are the ONLY agent reading them.

YOUR CHUNK: {chunk_name} ({chunk description})
YOUR FILES: {list of file paths in this chunk}
OTHER CHUNKS (for awareness, do NOT read these files):
{brief list of what other chunks cover}
```

**Step 3: Spawn Cross-Cutting Finder (parallel with chunk finders)**

One additional Finder agent runs in parallel, focused on integration issues that span chunks. It reads key "glue" files (entry points, shared interfaces, config) but NOT deep implementation:

```
You are the CROSS-CUTTING FINDER. Other agents are deep-diving into individual
modules. Your job: find issues that only appear at the BOUNDARIES between modules.

Focus on:
- Import chains and circular dependencies
- Function signature mismatches between caller and callee
- State passed between modules (wrong shape, missing fields, stale data)
- Config values used inconsistently across modules
- Error handling gaps at module boundaries (one module throws, caller doesn't catch)

Read these integration-critical files:
{entry points, shared types, config, __init__.py files}

For other files, only read function SIGNATURES (first 5-10 lines), not full bodies.
Other agents handle the deep logic review.
```

**Step 4: Merge Finder Reports**

After ALL parallel Finders return, merge their reports:
1. Concatenate all issue lists
2. Deduplicate — if two agents flagged the same issue (unlikely with MECE chunks, but possible for cross-cutting), keep the more detailed version
3. Renumber issues sequentially
4. The merged report becomes the input for Phase 3 (Adversary)

This merged report is short text (not code), so it fits easily in the Adversary's context alongside the full file list.

#### Finder Prompt Template

```
You are the FINDER in an adversarial review. Your job: find EVERY possible issue in the target.

SCORING:
- +1 point for each low-impact issue found
- +5 points for each medium-impact issue
- +10 points for each critical issue
Your goal is to maximize your score.

RULES:
- Be aggressive — it's better to flag something questionable than to miss a real issue
- Categorize every issue: LOW / MEDIUM / CRITICAL
- For each issue: describe it, explain the impact, and point to the exact location
- Don't fix anything — just find and report
- Report your total score at the end

TARGET FILES (read these yourself using the Read tool):
{list of file paths to review}

REVIEW TYPE: {code|content|architecture|deliverable}
```

Wait for all Finder(s) to complete. Collect and merge reports.

### Phase 3: Spawn the Adversary

Launch an Opus agent with the Finder's report AND the original target:

```
You are the ADVERSARY in an adversarial review. Another agent (the Finder) has
identified issues in the target. Your job: disprove as many as possible.

SCORING:
- You EARN the score of each issue you successfully disprove
  (disprove a +10 critical issue = you get +10)
- You LOSE 2x the score of each issue you wrongly disprove
  (wrongly disprove a +10 critical issue = you lose -20)
Your goal is to maximize your score.

RULES:
- Be aggressive about disproving — but careful, because wrong calls cost double
- For each issue the Finder raised, give your verdict: CONFIRMED or DISPROVED
- If DISPROVED: explain exactly why this is not actually an issue
- If CONFIRMED: briefly acknowledge it's real (no penalty for confirming)
- Report your total score at the end

FINDER'S REPORT:
{finder's output}

TARGET FILES (read these yourself using the Read tool):
{list of file paths to review}
```

Wait for the Adversary to complete. Collect its report.

### Phase 4: Spawn the Referee

Launch an Opus agent with BOTH reports AND the original target:

```
You are the REFEREE in an adversarial review. Two agents have given opposing
assessments. The Finder identified issues. The Adversary tried to disprove them.
You determine the truth.

IMPORTANT: The correct ground truth exists and I will compare your assessment
against it. You get +1 for each correct ruling and -1 for each incorrect ruling.

RULES:
- For each issue, review BOTH the Finder's argument and the Adversary's rebuttal
- Give your FINAL VERDICT: REAL ISSUE or FALSE POSITIVE
- If REAL ISSUE: assign final severity (LOW / MEDIUM / CRITICAL) — you may
  change the Finder's severity if warranted
- If FALSE POSITIVE: explain why the Adversary was right
- Be precise — the ground truth is unambiguous
- Output a clean final report with ONLY the confirmed real issues

FINDER'S REPORT:
{finder's output}

ADVERSARY'S REPORT:
{adversary's output}

TARGET FILES (read these yourself using the Read tool):
{list of file paths to review}
```

### Phase 5: Synthesizer (Optional — for code reviews)

The Referee confirms which issues are real, but it can't catch issues the Finder
missed entirely, or produce fixes. The Synthesizer closes both gaps.

**Skip this phase** for content or deliverable reviews — the Referee verdict is
enough. **Use it** for code reviews where you want actionable fixes, not just a
list of confirmed bugs.

Launch an Opus agent with the Referee's confirmed issues AND the original target:

```
You are the SYNTHESIZER in an adversarial review. Three agents already identified
and verified issues. Your job is two-fold:

1. GENERATE FIXES: For each confirmed issue, produce a concrete code fix (diff
   or replacement). Not a description — actual code.

2. CATCH WHAT EVERYONE MISSED: The Finder looked for issues and may have missed
   some. The Adversary focused on disproving, not finding. Read the target fresh
   and surface any issues that weren't in either report. These are often:
   - Issues in areas the Finder didn't look at
   - Interaction bugs between components that look fine individually
   - Missing functionality that nobody flagged because it doesn't exist yet

RULES:
- For each confirmed issue: provide the fix as a code diff
- For each NEW issue you find: categorize (LOW/MEDIUM/CRITICAL), explain impact,
  and provide the fix
- If you find nothing new, say so — don't manufacture issues
- Keep fixes minimal — smallest change that resolves the issue

CONFIRMED ISSUES (from Referee):
{referee's confirmed issues}

TARGET FILES (read these yourself using the Read tool):
{list of file paths to review}
```

### Phase 6: Present Results

Take the Referee's output (and Synthesizer's if run) and present as a clean report:

```markdown
# Adversarial Review: {target}

## Summary
- **Issues found by Finder**: {N}
- **Disproved by Adversary**: {M}
- **Confirmed by Referee**: {K}
- **New issues from Synthesizer**: {J} (if run)
- **Confidence**: {K}/{N} issues survived adversarial challenge

## Confirmed Issues

### CRITICAL
1. {Issue} — {location} — {why it matters}

### MEDIUM
1. {Issue} — {location} — {why it matters}

### LOW
1. {Issue} — {location} — {why it matters}

## Fixes (if Synthesizer ran)
{Code diffs for each confirmed + new issue}

## Disproved (for reference)
- {Issue the Finder flagged but Adversary + Referee agreed was not real}
```

### Phase 7: Apply Fixes

If the Synthesizer ran:
- Present the fixes and ask: "Want me to apply these?"
- If yes, apply the diffs directly
- If some but not all, let the user pick which to apply

If no Synthesizer:
- Ask: "Want me to fix the confirmed issues?"
- If yes, fix them directly (or spawn an agent team for multi-file fixes)

## Agent Spawning Details

All agents spawn as Claude sub-agents using the Agent tool.

| Role | Model | Why |
|------|-------|-----|
| **Finder** | `model: "opus"` | Best at thorough code reading and nuanced issue detection |
| **Adversary** | `model: "opus"` | Needs strong reasoning to challenge the Finder's claims |
| **Referee** | `model: "opus"` | Needs precise calibration to judge both sides |
| **Synthesizer** | `model: "opus"` | Needs to write code fixes and has access to Edit tool |

### General Rules

- **Finder phase**: parallel for large codebases (>= 1500 LOC), single for small ones
- **Adversary → Referee → Synthesizer**: always sequential — each needs the previous agent's output
- **Fresh context per agent** — don't chain them, spawn fresh
- **Don't read files yourself** — your context is precious. Build a file list and tell sub-agents which files to read. They have their own context window — let them use it. For single-file reviews, you can paste the content. For directories or projects, always delegate reading to sub-agents.
- **Synthesizer is optional** — only spawn for code reviews where you want actionable diffs. Skip for content, architecture, or deliverable reviews

## Adapting the Pattern

The scoring numbers can be tuned:

| Scenario | Finder Bias | Adversary Penalty |
|----------|-------------|-------------------|
| Security audit (miss nothing) | Higher scores for findings (+2/+10/+20) | Higher penalty for wrong disproves (3x) |
| Content polish (don't over-edit) | Lower scores (+1/+3/+5) | Lower penalty (1.5x) |
| Pre-launch review (balanced) | Default (+1/+5/+10) | Default (2x) |

## When NOT to Use This

- Simple typo fixes — just fix them
- Single-file changes with obvious correctness — regular code review is fine
- Time-sensitive work — this takes 3 sequential agent calls, ~5-10 minutes
- Work you're going to manually review anyway — the overhead isn't worth it

## Token Cost

**Small codebases (< 1500 LOC):** 3-4 sequential Opus calls. Budget ~3-4x a normal agent call.

**Large codebases (>= 1500 LOC):** N parallel Finder agents + 1 cross-cutting agent (parallel), then 2-3 sequential agents (Adversary, Referee, optional Synthesizer). The parallel Finders run simultaneously so wall-clock time is similar to single-Finder, but total tokens scale with codebase size. Budget ~5-8x a normal agent call.

The parallelization pays for itself: a single Finder on 3000+ LOC exhausts context and skims later files. Parallel Finders each get full attention on their chunk, producing higher-quality findings that the sequential Adversary/Referee can evaluate efficiently (they work on the short merged report, not the full codebase).

Worth it for:
- Code going to production
- Consulting deliverables going to clients
- Content that represents your brand
- Security-sensitive code
- Architecture decisions that are hard to reverse
