#!/usr/bin/env node
/**
 * jira-milestone-gate.cjs — Stop hook for GSD ↔ Jira milestone + per-phase sync.
 *
 * Runs after each assistant turn. Diffs .planning/STATE.md (milestone, status,
 * phase progress, active phase) against .planning/jira/mapping.json and, when a
 * Jira step is DUE, blocks the Stop with a precise instruction to run the
 * `jira-milestone` skill via the Atlassian MCP (context-injection — no shell-side
 * Jira token).
 *
 * Model: one EPIC per milestone, plus one child STORY per phase. Story lifecycle
 * To Do -> In Progress -> Done. mapping[V] = {
 *   epicKey, status: created|in_progress|completed, created,
 *   phases: { "<phaseNum>": { issueKey, status: todo|in_progress|done, name } }
 * }
 *
 * Triggers (priority): create > complete > start > sync
 *   no mapping entry                    -> create  (epic + all phase Stories)
 *   complete signal in STATE            -> complete (close open Stories + epic)
 *   created + execution started         -> start   (epic -> In Progress)
 *   per-phase drift (created|in_progress) -> sync   (create missing Stories,
 *                                                    active -> In Progress,
 *                                                    completed -> Done)
 *
 * FAIL-OPEN: any error/missing file/unparseable state -> exit 0 (never wedges the
 * session). Disable by removing the Stop hook from .claude/settings.local.json.
 */

'use strict';

const fs = require('fs');
const path = require('path');

function readStdin() {
  try {
    return fs.readFileSync(0, 'utf8');
  } catch {
    return '';
  }
}

function allow() {
  process.exit(0);
}

function block(reason) {
  process.stdout.write(JSON.stringify({ decision: 'block', reason }));
  process.exit(0);
}

function main() {
  let input = {};
  try {
    input = JSON.parse(readStdin() || '{}');
  } catch {
    input = {};
  }

  // Loop safety: don't re-fire inside a hook-triggered continuation.
  if (input.stop_hook_active === true) allow();

  const projectDir =
    input.cwd || process.env.CLAUDE_PROJECT_DIR || process.cwd();

  const statePath = path.join(projectDir, '.planning', 'STATE.md');
  const mappingPath = path.join(projectDir, '.planning', 'jira', 'mapping.json');

  // Jira integration not set up for this project -> stay silent.
  if (!fs.existsSync(statePath) || !fs.existsSync(mappingPath)) allow();

  let stateText, mapping;
  try {
    stateText = fs.readFileSync(statePath, 'utf8');
    mapping = JSON.parse(fs.readFileSync(mappingPath, 'utf8'));
  } catch {
    allow();
  }

  // --- Parse STATE.md (light regex; avoids a YAML dependency) ---
  const fmMatch = stateText.match(/^---\s*([\s\S]*?)\s*---/);
  const fm = fmMatch ? fmMatch[1] : stateText;
  const grab = (re, src = fm) => {
    const m = src.match(re);
    return m ? m[1].trim().replace(/^["']|["']$/g, '') : null;
  };
  const version = grab(/^milestone:\s*(.+)$/m);
  const status = (grab(/^status:\s*(.+)$/m) || '').toLowerCase();
  const completedPhases = parseInt(grab(/completed_phases:\s*(\d+)/) || '0', 10);
  const totalPhases = parseInt(grab(/total_phases:\s*(\d+)/) || '0', 10);
  const completedPlans = parseInt(grab(/completed_plans:\s*(\d+)/) || '0', 10);
  const percent = parseInt(grab(/percent:\s*(\d+)/) || '0', 10);
  // Active phase number from the STATE body "Phase: N" line (Current Position).
  const currentPhase = grab(/^Phase:\s*(\d+(?:\.\d+)?)\b/m, stateText);

  // Only engage for a real version string (e.g. v0.33.0).
  if (!version || !/^v?\d+\.\d+/.test(version)) allow();

  const milestones = (mapping && mapping.milestones) || {};
  const entry = milestones[version] || null;
  const mStatus = entry ? String(entry.status || '').toLowerCase() : null;
  const epicKey = entry ? entry.epicKey : null;
  const phases =
    entry && entry.phases && typeof entry.phases === 'object'
      ? entry.phases
      : {};
  const phaseKeys = Object.keys(phases);
  const doneCount = phaseKeys.filter(
    (k) => String((phases[k] || {}).status || '').toLowerCase() === 'done'
  ).length;

  const executionStarted =
    completedPlans > 0 || /execut|in.?progress|phase\s*\d/.test(status);
  const completeSignal =
    /milestone[_\s-]*complete|awaiting next milestone|shipped|archived/.test(
      status
    ) && (percent === 100 || (totalPhases > 0 && completedPhases >= totalPhases));

  const SKILL = 'invoke the Skill tool with skill="jira-milestone"';

  // Already fully done.
  if (mStatus === 'completed') allow();

  // CREATE — no epic yet.
  if (!entry) {
    block(
      `🔵 Jira milestone gate — milestone ${version} has no Jira epic yet.\n` +
        `Before ending this turn, ${SKILL} and args="create ${version}". This creates the ` +
        `epic AND one child Story per phase from ROADMAP.md (all To Do, assigned per the ` +
        `assignee policy, parent = the epic), then records ` +
        `milestones["${version}"] = { "epicKey", "status": "created", "created": "<YYYY-MM-DD>", ` +
        `"phases": { "<phaseNum>": { "issueKey", "status": "todo", "name" }, ... } }.\n` +
        `(If an epic for ${version} already exists, record it instead of creating a duplicate.)`
    );
  }

  // COMPLETE — milestone shipped but epic not Done.
  if (completeSignal && mStatus !== 'completed') {
    block(
      `🟢 Jira milestone gate — milestone ${version} is complete but its epic ` +
        `${epicKey || '(unknown)'} is not Done.\n` +
        `Before ending this turn, ${SKILL} and args="complete ${version}": transition any phase ` +
        `Stories still open to Done, post the audit-summary comment on the epic, transition the ` +
        `epic to Done, then set milestones["${version}"].status = "completed".`
    );
  }

  // START — created, execution underway, epic not yet In Progress.
  if (mStatus === 'created' && executionStarted) {
    block(
      `🟡 Jira milestone gate — milestone ${version} execution has begun but epic ` +
        `${epicKey || '(unknown)'} is still not In Progress.\n` +
        `Before ending this turn, ${SKILL} and args="start ${version}" (epic -> In Progress), ` +
        `then set milestones["${version}"].status = "in_progress".`
    );
  }

  // SYNC — per-phase Story reconciliation.
  if (mStatus === 'created' || mStatus === 'in_progress') {
    const missingStories = phaseKeys.length < totalPhases;
    const completionDrift = doneCount < completedPhases;
    const activePhaseObj = currentPhase != null ? phases[currentPhase] : undefined;
    const activeNeedsStart =
      currentPhase != null &&
      (activePhaseObj === undefined ||
        String((activePhaseObj || {}).status || '').toLowerCase() === 'todo');

    if (missingStories || completionDrift || activeNeedsStart) {
      block(
        `🟠 Jira milestone gate — per-phase Stories for milestone ${version} are out of sync ` +
          `(mapped ${phaseKeys.length}/${totalPhases} phases; ${doneCount} done vs ` +
          `${completedPhases} completed in STATE` +
          `${currentPhase ? `; active phase ${currentPhase}` : ''}).\n` +
          `Before ending this turn, ${SKILL} and args="sync ${version}": from ROADMAP.md + STATE, ` +
          `create any missing phase Stories (To Do), transition the active phase's Story to ` +
          `In Progress, and transition each completed phase's Story to Done; update ` +
          `milestones["${version}"].phases accordingly.`
      );
    }
  }

  // Nothing due.
  allow();
}

try {
  main();
} catch {
  // Absolute fail-safe: never block on an unexpected error.
  process.exit(0);
}
