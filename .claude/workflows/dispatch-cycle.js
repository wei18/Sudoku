// Project workflow: dispatch-cycle
// End-to-end Developer dispatch with Code Reviewer loop.
//   1. Preflight (detect+report; HARD BLOCK if dirty/orphans/behind)
//   2. Stamp meetings/{date}_{topic}.impl-notes.md skeleton
//   3. Dispatch Developer (Senior Developer agent)
//   4. CR threshold gate (post-diff, delegates to cr-threshold-gate): hard block unless skipCR + skipCRReason
//   5. If CR required: dispatch Code Reviewer; on REJECT loop back to Developer
//      up to maxRounds; on round-limit pause and return for Leader decision
//   6. Return synthesized result for Leader to commit/PR
//
// Codifies docs/methodology.md §派發契約 items 1-9.
// Honors user prefs: preflight detect-only, CR gate hard block + bypass flag.
//
// Invoke via:
//   Workflow({name: "dispatch-cycle", args: {
//     topic: "fix-toast-race",            // required, kebab-case
//     date: "2026-05-28",                 // required, YYYY-MM-DD (Workflow runtime cannot call Date())
//     task: "Full task description...",   // required
//     skills: ["swiftui-expert-skill"],   // required, string or array
//     returnFormat: "diff + impl-notes",  // required
//     verification: "swift test --filter ToastTests passes",  // required
//     targetFiles: ["Packages/.../Foo.swift"],  // optional, for CR prediction
//     baseBranch: "main",                 // optional, default "main"
//     maxRounds: 3,                       // optional, default 3
//     skipCR: false,                      // optional; if true REQUIRES skipCRReason (audit-trailed)
//     skipCRReason: null,                 // required when skipCR=true
//     developerAgentType: "Senior Developer",  // optional override
//     reviewerAgentType: "Code Reviewer",      // optional override
//   }})
//
// Sibling: dispatch-prep (scaffold-only — same preflight + stamp + CR prediction, but NO agent dispatch).

export const meta = {
  name: 'dispatch-cycle',
  description: 'Full Developer + Code Reviewer loop (dispatches subagents, drives CR rounds). For scaffold-only without dispatch, use dispatch-prep.',
  whenToUse: 'Self-contained Developer task where Leader wants the CR loop driven automatically. Use dispatch-prep instead when Leader prefers to call the Developer subagent manually.',
  phases: [
    { title: 'Preflight', detail: 'detect dirty state, orphan procs, rebase need (HARD BLOCK if any)' },
    { title: 'Stamp', detail: 'create impl-notes skeleton' },
    { title: 'Develop', detail: 'dispatch Developer (loops on CR reject)' },
    { title: 'Gate', detail: 'evaluate CR threshold against actual diff' },
    { title: 'Review', detail: 'dispatch Code Reviewer when required' },
  ],
}

// ── arg validation ─────────────────────────────────────────────────────────
if (!args || typeof args !== 'object') throw new Error('dispatch-cycle requires args')
const REQ = ['topic', 'date', 'task', 'skills', 'returnFormat', 'verification']
for (const k of REQ) if (!args[k]) throw new Error(`dispatch-cycle: missing required arg "${k}"`)

const topic = args.topic
const date = args.date
const task = args.task
const targetFiles = args.targetFiles || []
const skills = Array.isArray(args.skills) ? args.skills : [args.skills]
const returnFormat = args.returnFormat
const verification = args.verification
const baseBranch = args.baseBranch || 'main'
const maxRounds = args.maxRounds || 3
const skipCR = args.skipCR === true
const skipCRReason = args.skipCRReason || null
const developerAgentType = args.developerAgentType || 'Senior Developer'
const reviewerAgentType = args.reviewerAgentType || 'Code Reviewer'

if (skipCR && !skipCRReason) {
  throw new Error('skipCR=true requires skipCRReason (will be appended to impl-notes for audit trail)')
}

// CR threshold logic lives in cr-threshold-gate.js (SSOT). Gate phase below
// delegates via workflow('cr-threshold-gate', ...) — DO NOT inline CORE_MODULES
// or evalCRGate here. Update cr-threshold-gate.js if methodology §派發契約 §8
// changes.

// ── Phase 1: Preflight ────────────────────────────────────────────────────
phase('Preflight')

const PREFLIGHT_SCHEMA = {
  type: 'object',
  required: ['dirty', 'rebaseBehind', 'orphans', 'currentBranch'],
  properties: {
    dirty: { type: 'boolean' },
    dirtyFiles: { type: 'array', items: { type: 'string' } },
    rebaseBehind: { type: 'integer' },
    unpushedAhead: { type: 'integer' },
    orphans: { type: 'array', items: { type: 'object', properties: { pid: { type: 'string' }, cmd: { type: 'string' } } } },
    currentBranch: { type: 'string' },
    miseTrustOK: { type: ['boolean', 'null'] },
  },
}

const pre = await agent(
  `Pre-dispatch preflight in .. DETECT ONLY — do NOT kill / rebase / push / fetch.\n\n` +
  `Run and report:\n` +
  `  git -C . status --porcelain\n` +
  `  git -C . rev-parse --abbrev-ref HEAD\n` +
  `  git -C . rev-list --count HEAD..origin/${baseBranch} 2>/dev/null || echo 0\n` +
  `  git -C . rev-list --count @{u}..HEAD 2>/dev/null || echo 0\n` +
  `  ps -ax -o pid=,command= | grep -E 'swift-test|swiftpm-testing-helper|mise exec' | grep -v grep || true\n` +
  `  mise -C . trust --show 2>&1 | head -5 || true\n\n` +
  `Return JSON matching schema.`,
  { label: 'preflight', schema: PREFLIGHT_SCHEMA }
)

const blockers = []
if (pre.dirty) blockers.push(`dirty (${(pre.dirtyFiles || []).length} files)`)
if (pre.rebaseBehind > 0) blockers.push(`${pre.rebaseBehind} behind origin/${baseBranch}`)
if (pre.orphans && pre.orphans.length > 0) blockers.push(`${pre.orphans.length} orphan procs`)
if (pre.miseTrustOK === false) blockers.push(`mise trust missing`)

if (blockers.length > 0) {
  return {
    status: 'PREFLIGHT_BLOCKED',
    blockers,
    preflight: pre,
    guidance: `Preflight detect-only: Leader must resolve before re-running. Blockers: ${blockers.join('; ')}`,
  }
}
log(`Preflight clean: branch=${pre.currentBranch}`)

// ── Phase 2: Stamp impl-notes ─────────────────────────────────────────────
phase('Stamp')

const implNotesPath = `meetings/${date}_${topic}.impl-notes.md`
const skeleton = `# ${topic}

Status: WIP
Branch: ${pre.currentBranch}
Date: ${date}
Dispatcher: Leader (via dispatch-cycle workflow)

## 任務 scope
${task}

## 設計決定
## 偏離 spec
## 折衷
## 未決

## Files changed
| File | + | − | Note |
|---|---|---|---|

## Verification
- [ ] ${verification}
`

await agent(
  `Create ./${implNotesPath} with this content (if it already exists, leave it alone — return either way):\n\n${skeleton}`,
  { label: 'stamp', schema: { type: 'object', required: ['ok'], properties: { ok: { type: 'boolean' }, alreadyExisted: { type: 'boolean' } } } }
)
log(`impl-notes ready: ${implNotesPath}`)

// ── Phase 3-5: Develop → Gate → Review loop ───────────────────────────────
const devPromptBase = [
  `# Task: ${topic}`,
  ``,
  `## Scope`,
  task,
  ``,
  `## Required reads`,
  `- docs/methodology.md §派發契約 (items 6, 10, 11, 12)`,
  `- ${implNotesPath}  ← update during work; mark Status: COMPLETE before returning`,
  ...(targetFiles.length ? [`- Target files:`, ...targetFiles.map(f => `  - ${f}`)] : []),
  ``,
  `## Skills`,
  ...skills.map(s => `- ${s}`),
  `- agent-impl-notes-log (mandatory)`,
  ``,
  `## Return format`,
  returnFormat,
  ``,
  `## Verification`,
  verification,
  ``,
  `## Sandbox`,
  `- No cd outside worktree, no rebase/merge/push, no kill/pkill`,
  `- swift test default: --filter <Name>; full suite via timeout 600 swift test 2>&1 | tail -50`,
  `- Hang → abort + report PIDs, do NOT retry`,
  `- Commit-early on large chunks (--no-verify WIP allowed; final must pass hooks)`,
].join('\n')

const DEV_SCHEMA = {
  type: 'object',
  required: ['summary', 'filesChanged', 'verificationOutcome'],
  properties: {
    summary: { type: 'string' },
    filesChanged: { type: 'array', items: { type: 'string' } },
    locAdded: { type: 'integer' },
    locRemoved: { type: 'integer' },
    commits: { type: 'array', items: { type: 'string' } },
    verificationOutcome: { type: 'string', description: 'PASS / FAIL / N/A with detail' },
    openQuestions: { type: 'array', items: { type: 'string' } },
  },
}

const REVIEW_SCHEMA = {
  type: 'object',
  required: ['verdict', 'rationale'],
  properties: {
    verdict: { type: 'string', enum: ['APPROVE', 'REJECT', 'APPROVE_WITH_NITS'] },
    rationale: { type: 'string' },
    findings: {
      type: 'array',
      items: {
        type: 'object',
        required: ['severity', 'file', 'detail'],
        properties: {
          severity: { type: 'string', enum: ['blocker', 'major', 'minor', 'nit'] },
          file: { type: 'string' },
          line: { type: 'integer' },
          detail: { type: 'string' },
          suggestion: { type: 'string' },
        },
      },
    },
  },
}

// GATE_SCHEMA removed — Gate phase delegates to cr-threshold-gate workflow.

let round = 0
let lastDev = null
let lastReview = null
let lastGate = null
let everRequiredCR = false  // sticky: once CR fired in any round, stays sticky to prevent escape-hatch on revisions that shrink below threshold

while (round < maxRounds) {
  round++
  phase('Develop')
  log(`Round ${round}/${maxRounds}: Developer`)

  const devPrompt = round === 1
    ? devPromptBase
    : devPromptBase + `\n\n## Prior CR feedback (round ${round - 1})\n` +
      `Verdict: ${lastReview.verdict}\nRationale: ${lastReview.rationale}\n` +
      `Findings:\n${(lastReview.findings || []).map(f => `- [${f.severity}] ${f.file}${f.line ? ':' + f.line : ''} — ${f.detail}${f.suggestion ? ' → ' + f.suggestion : ''}`).join('\n')}\n\n` +
      `Address every blocker/major. Defer nits with note in impl-notes.`

  lastDev = await agent(devPrompt, {
    label: `dev:r${round}`,
    schema: DEV_SCHEMA,
    agentType: developerAgentType,
  })

  phase('Gate')
  // Delegate to cr-threshold-gate workflow — SSOT for CORE_MODULES + LOC_THRESHOLD + OR rule
  const gateResult = await workflow('cr-threshold-gate', { baseBranch, headRef: 'HEAD', repo: '.' })
  lastGate = { locChanged: gateResult.locChanged, changedFiles: gateResult.changedFiles }
  // Normalize to the shape the rest of this workflow expects
  const gateRaw = {
    required: gateResult.required,
    triggers: gateResult.triggers || [],
    coreHits: gateResult.coreHits || [],
    locChanged: gateResult.locChanged || 0,
  }
  // Sticky: once CR was required in any prior round, it stays required for the remainder of the cycle —
  // prevents Developer from "shrinking under threshold on the revision" escape-hatch
  if (gateRaw.required) everRequiredCR = true
  const gate = {
    ...gateRaw,
    required: gateRaw.required || everRequiredCR,
    triggers: gateRaw.required ? gateRaw.triggers : (everRequiredCR ? [...gateRaw.triggers, 'sticky: CR required in a prior round'] : gateRaw.triggers),
  }
  log(`CR gate: ${gate.required ? 'REQUIRED' : 'not required'} (${gate.triggers.join('; ') || 'no triggers'})`)

  // CR bypass path
  if (gate.required && skipCR) {
    log(`CR BYPASSED by --skipCR with reason: ${skipCRReason}`)
    await agent(
      `Append to ./${implNotesPath} under §偏離 spec:\n\n` +
      `- CR bypassed via dispatch-cycle skipCR flag. Reason: ${skipCRReason}. ` +
      `CR would have been triggered by: ${gate.triggers.join('; ')}. Acknowledged by Leader.\n`,
      { label: `audit:cr-bypass`, schema: { type: 'object', required: ['ok'], properties: { ok: { type: 'boolean' } } } }
    )
    return {
      status: 'COMPLETE_CR_BYPASSED',
      rounds: round,
      developer: lastDev,
      gate,
      bypassReason: skipCRReason,
      implNotesPath,
    }
  }

  if (!gate.required) {
    return {
      status: 'COMPLETE_NO_CR',
      rounds: round,
      developer: lastDev,
      gate,
      implNotesPath,
      guidance: `CR not required (${gate.triggers.length === 0 ? 'below threshold + no core hit' : ''}). Leader: read impl-notes, verify diff, then commit/PR.`,
    }
  }

  // CR required and not bypassed
  phase('Review')
  log(`Round ${round}: Code Reviewer (${gate.triggers.join('; ')})`)

  const reviewPrompt = [
    `# Code Review: ${topic}`,
    ``,
    `## What to review`,
    `Diff: \`git -C . diff origin/${baseBranch}...HEAD\``,
    `Triggered because: ${gate.triggers.join('; ')}`,
    ``,
    `## Developer's summary`,
    lastDev.summary,
    ``,
    `## Verification claimed by Developer`,
    `${lastDev.verificationOutcome}`,
    ``,
    `## Required reads`,
    `- ${implNotesPath}`,
    `- docs/methodology.md §派發契約`,
    `- ${targetFiles.length ? `Target files: ${targetFiles.join(', ')}` : 'Identify scope from diff'}`,
    ``,
    `## Verdict`,
    `Return verdict APPROVE / APPROVE_WITH_NITS / REJECT plus findings list. ` +
    `REJECT requires ≥1 blocker or major finding. Nits alone → APPROVE_WITH_NITS (Leader will inline-apply).`,
  ].join('\n')

  lastReview = await agent(reviewPrompt, {
    label: `cr:r${round}`,
    schema: REVIEW_SCHEMA,
    agentType: reviewerAgentType,
  })

  log(`CR verdict round ${round}: ${lastReview.verdict}`)

  if (lastReview.verdict === 'APPROVE' || lastReview.verdict === 'APPROVE_WITH_NITS') {
    // Persist nits into impl-notes §未決 so Leader doesn't lose them when the workflow returns
    if (lastReview.verdict === 'APPROVE_WITH_NITS' && (lastReview.findings || []).length > 0) {
      const nitLines = lastReview.findings.map(f =>
        `- [ ] [${f.severity}] ${f.file}${f.line ? ':' + f.line : ''} — ${f.detail}${f.suggestion ? ` → ${f.suggestion}` : ''}`
      ).join('\n')
      await agent(
        `Append to ./${implNotesPath} under §未決 (or create that section if missing):\n\n` +
        `### CR nits (round ${round}, APPROVE_WITH_NITS — Leader to inline-apply)\n${nitLines}\n`,
        { label: `persist:nits`, schema: { type: 'object', required: ['ok'], properties: { ok: { type: 'boolean' } } } }
      )
    }
    return {
      status: lastReview.verdict === 'APPROVE' ? 'COMPLETE_APPROVED' : 'COMPLETE_APPROVED_WITH_NITS',
      rounds: round,
      developer: lastDev,
      review: lastReview,
      gate,
      implNotesPath,
      guidance: lastReview.verdict === 'APPROVE_WITH_NITS'
        ? `Leader: inline-apply the nit findings (now also tracked in ${implNotesPath} §未決), then commit/PR.`
        : `Leader: commit/PR.`,
    }
  }
  // REJECT → loop
}

// Round limit reached — mark impl-notes Status: PAUSED so it doesn't read as in-flight
await agent(
  `Edit ./${implNotesPath}:\n` +
  `  1. Replace the existing 'Status: ...' line near the top with: \`Status: PAUSED (round-limit: ${maxRounds})\`\n` +
  `  2. Append under §未決:\n\n` +
  `### Round-limit pause (after ${round} rounds)\n` +
  `Last CR verdict: ${lastReview ? lastReview.verdict : 'N/A'}\n` +
  `Last CR rationale: ${lastReview ? lastReview.rationale : 'N/A'}\n` +
  `Leader decision pending: (a) raise maxRounds + resume, (b) reformulate task, (c) accept with documented deviation.\n`,
  { label: 'persist:round-limit', schema: { type: 'object', required: ['ok'], properties: { ok: { type: 'boolean' } } } }
)

return {
  status: 'ROUND_LIMIT_REACHED',
  rounds: round,
  developer: lastDev,
  review: lastReview,
  gate: lastGate,
  implNotesPath,
  guidance: `Hit maxRounds=${maxRounds} without CR approval. impl-notes marked PAUSED. Leader: decide (a) raise maxRounds and resume, (b) reformulate task, or (c) accept current state with documented deviation.`,
}
