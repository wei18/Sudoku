// Project workflow: cr-threshold-gate
// Standalone Code Reviewer threshold check. Evaluates the current branch's
// diff vs base against the OR rule from methodology.md §派發契約 item 8:
//   - LOC > 50 (added + modified) → CR required
//   - OR any changed file falls under a core module → CR required
// Returns boolean + which trigger fired. Pure mechanical gate.
//
// Codifies the "rule is OR not AND" feedback that Leader has been misapplying.
//
// Invoke via:
//   Workflow({name: "cr-threshold-gate", args: {baseBranch?: "main", headRef?: "HEAD"}})

export const meta = {
  name: 'cr-threshold-gate',
  description: 'Mechanical Code Reviewer threshold check (OR rule): LOC > 50 OR core-module hit. Returns required:yes/no + triggers.',
  whenToUse: 'When Leader wants a quick CR-required check outside the full dispatch-cycle. Especially useful for ad-hoc dev work that bypassed the workflow.',
  phases: [{ title: 'Evaluate' }],
}

const baseBranch = (args && args.baseBranch) || 'main'
const headRef = (args && args.headRef) || 'HEAD'
const repo = (args && args.repo) || '.'

// SSOT: methodology.md §派發契約 item 8. Keep in sync with dispatch-prep.js (predictor) and methodology.md.
// Updated after PR #176 (Stage 3) extracted PersistenceKit + GameCenterKit from SudokuKit.
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
const LOC_THRESHOLD = 50

phase('Evaluate')

const GATE_SCHEMA = {
  type: 'object',
  required: ['locChanged', 'changedFiles', 'baseRef', 'headRef'],
  properties: {
    locChanged: { type: 'integer', description: 'added + removed across all changed files in range' },
    changedFiles: { type: 'array', items: { type: 'string' } },
    baseRef: { type: 'string' },
    headRef: { type: 'string' },
    diffEmpty: { type: 'boolean' },
  },
}

const diff = await agent(
  `Compute branch diff stats in ${repo}.\n\n` +
  `Run:\n` +
  `  git -C ${repo} diff --shortstat origin/${baseBranch}...${headRef}\n` +
  `  git -C ${repo} diff --name-only origin/${baseBranch}...${headRef}\n\n` +
  `Parse shortstat: locChanged = insertions + deletions (0 if line is empty / no changes). ` +
  `changedFiles = list of file paths (one per line). Set diffEmpty=true when both insertions and deletions are 0.`,
  { label: 'collect-diff', schema: GATE_SCHEMA }
)

// Derive diffEmpty in JS rather than trusting LLM — diff.diffEmpty was optional in schema
const diffEmpty = (diff.locChanged === 0) && !(diff.changedFiles && diff.changedFiles.length)
if (diffEmpty) {
  return {
    status: 'NO_DIFF',
    required: false,
    triggers: [],
    base: `origin/${baseBranch}`,
    head: headRef,
    guidance: `No diff vs origin/${baseBranch}. Nothing to gate.`,
  }
}

const coreHits = []
for (const f of diff.changedFiles) {
  for (const m of CORE_MODULES) {
    if (f.startsWith(m) || f === m) { coreHits.push({ file: f, module: m }); break }
  }
}

const locFires = diff.locChanged > LOC_THRESHOLD
const coreFires = coreHits.length > 0
const required = locFires || coreFires  // OR — methodology §派發契約 item 8

const triggers = []
if (locFires) triggers.push(`LOC ${diff.locChanged} > ${LOC_THRESHOLD}`)
if (coreFires) triggers.push(`core modules: ${[...new Set(coreHits.map(h => h.module))].join(', ')}`)

log(`CR gate: ${required ? 'REQUIRED' : 'not required'} — ${triggers.join('; ') || 'no triggers'}`)

return {
  status: required ? 'CR_REQUIRED' : 'CR_NOT_REQUIRED',
  required,
  triggers,
  rule: 'OR — either condition alone fires (methodology.md §派發契約 item 8)',
  locChanged: diff.locChanged,
  locThreshold: LOC_THRESHOLD,
  changedFiles: diff.changedFiles,
  coreHits,
  base: `origin/${baseBranch}`,
  head: headRef,
  guidance: required
    ? `CR is REQUIRED before commit/PR. Triggered by: ${triggers.join('; ')}. Dispatch Code Reviewer subagent, or pass through dispatch-cycle.`
    : `CR not required (LOC ≤ ${LOC_THRESHOLD} AND no core-module hit). Leader self-review (read impl-notes + diff + focused build/test) is sufficient.`,
}
