// Project workflow: dispatch-prep
// Scaffold-only variant of dispatch-cycle. Runs preflight (detect + report),
// stamps impl-notes skeleton, predicts CR threshold from targetFiles, and
// emits a ready-to-paste dispatch prompt. Does NOT call Developer / Code
// Reviewer — Leader does that manually in main chat.
//
// Invoke via:
//   Workflow({name: "dispatch-prep", args: {topic, date, task, targetFiles,
//     skills, returnFormat, verification, baseBranch}})
//
// Codifies docs/methodology.md §派發契約 items 1-9 (dispatch 5-element contract,
// impl-notes log, CR threshold, Leader preflight).

export const meta = {
  name: 'dispatch-prep',
  description: 'Scaffold-only — preflight + impl-notes skeleton + CR prediction + ready-to-paste dispatch prompt. Does NOT call any subagent. For full automated loop, use dispatch-cycle.',
  whenToUse: 'When Leader wants to dispatch the Developer subagent manually in main chat but still benefit from the preflight + scaffold automation. Lighter and more controllable than dispatch-cycle.',
  phases: [
    { title: 'Preflight', detail: 'detect dirty state, orphan procs, rebase need' },
    { title: 'Stamp', detail: 'create meetings/{date}_{topic}.impl-notes.md skeleton' },
    { title: 'Predict CR', detail: 'evaluate CR threshold against target files' },
    { title: 'Emit', detail: 'assemble dispatch prompt with 5 required elements' },
  ],
}

// ── arg validation ─────────────────────────────────────────────────────────
if (!args || typeof args !== 'object') {
  throw new Error('dispatch-prep requires args. See meta for shape.')
}
const REQ = ['topic', 'date', 'task', 'skills', 'returnFormat', 'verification']
for (const k of REQ) {
  if (!args[k]) throw new Error(`dispatch-prep: missing required arg "${k}"`)
}
const topic = args.topic
const date = args.date
const task = args.task
const targetFiles = args.targetFiles || []
const skills = Array.isArray(args.skills) ? args.skills : [args.skills]
const returnFormat = args.returnFormat
const verification = args.verification
const baseBranch = args.baseBranch || 'main'

// ── CR threshold prediction (pure JS, methodology §派發契約 item 8) ────────
// SSOT for CORE_MODULES + matcher = cr-threshold-gate.js. Keep this list and
// the matcher arm in sync. (Prediction-only here because targetFiles are
// declared pre-work; cr-threshold-gate measures the actual post-dispatch diff.)
const CORE_MODULES = [
  'Packages/PersistenceKit/Sources/Persistence/',
  'Packages/GameCenterKit/Sources/GameCenterClient/',
  'Packages/SudokuKit/Sources/AppComposition/',
  'Packages/AppMonetizationKit/Sources/MonetizationCore/',
  'Packages/AppMonetizationKit/Sources/AdsAdMob/',
  'Packages/AppMonetizationKit/Sources/IAPStoreKit2/',
  'Project.swift',
  'Package.swift',
  'App/Resources/PrivacyInfo.xcprivacy',
]

function predictCR(files) {
  const hits = []
  for (const f of files) {
    for (const m of CORE_MODULES) {
      // Matcher arm identical to cr-threshold-gate.js — do NOT add f.endsWith() here without updating SSOT
      if (f.startsWith(m) || f === m) {
        hits.push({ file: f, module: m })
        break
      }
    }
  }
  return {
    coreHits: hits,
    coreLikelyRequiresCR: hits.length > 0,
    note: hits.length > 0
      ? `Core module hit predicted — CR will be REQUIRED post-dispatch regardless of LOC.`
      : `No core module hit predicted from targetFiles. CR will fire only if final diff > 50 LOC.`,
  }
}

// ── Phase 1: Preflight ────────────────────────────────────────────────────
phase('Preflight')

const PREFLIGHT_SCHEMA = {
  type: 'object',
  required: ['dirty', 'unpushedAhead', 'rebaseBehind', 'orphans', 'currentBranch', 'mountedWorktrees'],
  properties: {
    dirty: { type: 'boolean', description: 'git status --porcelain non-empty' },
    dirtyFiles: { type: 'array', items: { type: 'string' } },
    unpushedAhead: { type: 'integer', description: 'commits ahead of remote on current branch' },
    rebaseBehind: { type: 'integer', description: 'commits current branch is behind ' + baseBranch },
    orphans: {
      type: 'array',
      description: 'orphan swift-test / swiftpm-testing-helper / mise exec processes',
      items: { type: 'object', properties: { pid: { type: 'string' }, cmd: { type: 'string' } } },
    },
    currentBranch: { type: 'string' },
    mountedWorktrees: { type: 'array', items: { type: 'string' }, description: 'output of git worktree list' },
    miseTrustOK: { type: 'boolean', description: 'best-effort: whether current dir .mise.toml is trusted (null if unknown)' },
  },
}

const preflight = await agent(
  `You are running pre-dispatch preflight for a Developer subagent in repo .. ` +
  `DETECT ONLY — do NOT auto-fix anything, do NOT run kill / rebase / push / fetch. Just observe and report.\n\n` +
  `Run these commands and report structured findings:\n` +
  `  - git -C . status --porcelain\n` +
  `  - git -C . rev-parse --abbrev-ref HEAD\n` +
  `  - git -C . rev-list --count HEAD..origin/${baseBranch} 2>/dev/null || echo 0   # rebaseBehind\n` +
  `  - git -C . rev-list --count @{u}..HEAD 2>/dev/null || echo 0                    # unpushedAhead\n` +
  `  - git -C . worktree list\n` +
  `  - ps -ax -o pid=,command= | grep -E 'swift-test|swiftpm-testing-helper|mise exec' | grep -v grep || true\n` +
  `  - mise -C . trust --show 2>&1 | head -5 || true   # best-effort trust check\n\n` +
  `Return JSON matching the schema. Empty arrays / zeros are fine. Use miseTrustOK=null if you can't tell.`,
  { label: 'preflight:detect', schema: PREFLIGHT_SCHEMA }
)

const preflightBlockers = []
if (preflight.dirty) preflightBlockers.push(`Working tree dirty (${(preflight.dirtyFiles || []).length} files)`)
if (preflight.rebaseBehind > 0) preflightBlockers.push(`${preflight.rebaseBehind} commits behind origin/${baseBranch} — Leader should rebase before dispatch`)
if (preflight.orphans && preflight.orphans.length > 0) preflightBlockers.push(`${preflight.orphans.length} orphan test/mise procs — Leader should kill`)
if (preflight.miseTrustOK === false) preflightBlockers.push(`mise trust missing for current worktree`)

log(`Preflight: branch=${preflight.currentBranch}, dirty=${preflight.dirty}, behind=${preflight.rebaseBehind}, orphans=${(preflight.orphans || []).length}`)

// ── Phase 2: Stamp impl-notes ─────────────────────────────────────────────
phase('Stamp')

const implNotesPath = `meetings/${date}_${topic}.impl-notes.md`
const skeleton = `# ${topic}

Status: WIP
Branch: ${preflight.currentBranch}
Date: ${date}
Dispatcher: Leader

## 任務 scope
${task}

## 依賴文件
TBD by subagent

## 設計決定
- (subagent fills during work)

## 偏離 spec
- none yet

## 折衷
- none yet

## 未決
- none yet

## Files changed
| File | + | − | Note |
|---|---|---|---|

## Verification
- [ ] ${verification}
`

const STAMP_SCHEMA = {
  type: 'object',
  required: ['written', 'path', 'alreadyExisted'],
  properties: {
    written: { type: 'boolean' },
    path: { type: 'string' },
    alreadyExisted: { type: 'boolean' },
  },
}

const stamp = await agent(
  `Create the file ${implNotesPath} (absolute path: ./${implNotesPath}) with the following content. ` +
  `If the file already exists, do NOT overwrite — set alreadyExisted=true and written=false and return.\n\n` +
  `Content:\n\n${skeleton}\n\nReturn JSON matching the schema.`,
  { label: 'stamp:impl-notes', schema: STAMP_SCHEMA }
)

log(`impl-notes: ${stamp.alreadyExisted ? 'already existed (kept)' : 'written'} → ${stamp.path}`)

// ── Phase 3: CR prediction ────────────────────────────────────────────────
phase('Predict CR')

const crPred = predictCR(targetFiles)
log(`CR prediction: ${crPred.coreLikelyRequiresCR ? 'CORE HIT' : 'depends on final LOC'} (${crPred.coreHits.length} core module(s) hit by targetFiles)`)

// ── Phase 4: Emit dispatch prompt ─────────────────────────────────────────
phase('Emit')

const dispatchPrompt = [
  `# Dispatch: ${topic}`,
  ``,
  `## Task scope`,
  task,
  ``,
  `## Required reads`,
  `- docs/methodology.md §派發契約 (items 6, 10, 11, 12)`,
  `- ${implNotesPath}  ← keep this file updated through the work; mark Status: COMPLETE before returning`,
  ...(targetFiles.length ? [`- Target files:`, ...targetFiles.map(f => `  - ${f}`)] : []),
  ``,
  `## Skills to invoke`,
  ...skills.map(s => `- ${s}`),
  `- agent-impl-notes-log  (mandatory: update ${implNotesPath} during work)`,
  ``,
  `## Return format`,
  returnFormat,
  ``,
  `## Verification`,
  verification,
  ``,
  `## Sandbox reminders (methodology §派發契約 item 11)`,
  `- Do NOT \`cd\` outside your worktree. No \`git rebase\` / \`merge\` / \`push\`. No \`kill\` / \`pkill\`.`,
  `- swift test default: \`swift test --filter <TestName>\`. Full suite only via \`timeout 600 swift test 2>&1 | tail -50\`.`,
  `- Hang on a test → ABORT and report PIDs, do NOT retry (orphan-proc accumulation).`,
  `- Commit-early on large chunks (\`--no-verify\` protective WIP allowed mid-work; final must pass hooks).`,
].join('\n')

return {
  status: preflightBlockers.length > 0 ? 'PREFLIGHT_BLOCKED' : 'READY',
  preflight,
  preflightBlockers,
  implNotesPath,
  implNotesStamped: stamp.written || stamp.alreadyExisted,
  crPrediction: crPred,
  dispatchPrompt,
  guidance: preflightBlockers.length > 0
    ? `Leader: resolve preflight blockers, then re-run dispatch-prep. Blockers above are detect-only — no auto-fix per user rule.`
    : `Leader: paste dispatchPrompt to the Agent tool to dispatch Developer. On return, evaluate diff against CR threshold (use dispatch-cycle if you want this automated).`,
}
