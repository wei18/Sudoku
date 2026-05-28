// Project workflow: phase-todo-sweep
// Mandatory pre-phase-close sweep (methodology.md §派發契約 item 7).
// Scans Packages/<target>/Sources/ for TODO|FIXME|XXX|HACK|stub|placeholder|
// "Phase N Part" markers, classifies each match (Resolved / Backlog /
// Intentional), suggests §Backlog routing per topic, and optionally drafts
// `gh issue create` commands for follow-ups.
//
// Invoke via:
//   Workflow({name: "phase-todo-sweep", args: {
//     target: "Packages/SudokuKit/Sources/Persistence",
//     phaseId: "phase-5",
//     draftIssues: true,        // emit gh issue create lines (does not run them)
//     date: "2026-05-28"        // REQUIRED when draftIssues=true (for Date header / Migrated footer)
//   }})

export const meta = {
  name: 'phase-todo-sweep',
  description: 'Mandatory phase-close sweep: rg TODO/FIXME/stub markers in target Sources/, classify Resolved/Backlog/Intentional, suggest §Backlog routing + gh issue stubs',
  whenToUse: 'Before merging a phase-completion PR. Leader-only — methodology §派發契約 item 7 says this is Leader\'s job, not subagent\'s.',
  phases: [
    { title: 'Scan', detail: 'rg over target Sources/' },
    { title: 'Classify', detail: 'LLM judges each match: Resolved / Backlog routing / Intentional' },
    { title: 'Emit', detail: 'markdown checklist + optional gh issue create stubs' },
  ],
}

if (!args || !args.target) throw new Error('phase-todo-sweep requires args.target (path under repo, e.g. "Packages/SudokuKit/Sources/Persistence")')
// Guard against `..` traversal / shell metachars (target is interpolated into bash via agent prompts)
if (!/^[A-Za-z0-9_./-]+$/.test(args.target) || args.target.includes('..')) {
  throw new Error(`phase-todo-sweep: target "${args.target}" contains forbidden characters or '..' (allowed: A-Za-z0-9_./-)`)
}
const target = args.target
const phaseId = args.phaseId || null
const draftIssues = args.draftIssues === true
const repo = args.repo || '/Users/zw/GitHub/Wei18/Sudoku-spec'
const today = args.date || null  // YYYY-MM-DD for issue Date header / Migrated footer; required if draftIssues=true

if (draftIssues && !today) {
  throw new Error('phase-todo-sweep: when draftIssues=true, args.date (YYYY-MM-DD) is required for issue Date header + Migrated footer (Workflow scripts cannot call new Date()).')
}

// Issue convention learned from existing gh issues (#67, #79, #80, #156, #158, #170 etc.):
//   - Label set is small and stable. Many issues have no labels — that's OK for ambiguous ones.
//   - Title prefix uses conventional-commits style: fix(ci) / feat(X) / ops(infra) / M## (architecture)
//   - Body has Date header + **Source**: meetings/X.md cite + sectioned body
//   - Backlog-migrated entries append _Migrated from <doc> §Backlog on YYYY-MM-DD._
const KNOWN_LABELS = ['backlog', 'ci', 'testing', 'devx', 'bug', 'architecture', 'documentation', 'modules', 'v2-audit']
const TITLE_PREFIX_HINTS = ['fix(ci)', 'fix(itms)', 'feat(<area>)', 'ops(infra)', 'refactor(<area>)', 'M## (architecture)', 'docs', 'test']

// ── Phase 1: Scan ─────────────────────────────────────────────────────────
phase('Scan')

const SCAN_SCHEMA = {
  type: 'object',
  required: ['matches', 'scannedFiles', 'targetExists'],
  properties: {
    targetExists: { type: 'boolean' },
    scannedFiles: { type: 'integer' },
    matches: {
      type: 'array',
      items: {
        type: 'object',
        required: ['file', 'line', 'marker', 'snippet'],
        properties: {
          file: { type: 'string', description: 'path relative to repo root' },
          line: { type: 'integer' },
          marker: { type: 'string', description: 'which marker matched: TODO / FIXME / XXX / HACK / stub / placeholder / Phase N Part' },
          snippet: { type: 'string', description: 'the matched line, trimmed' },
        },
      },
    },
  },
}

const scan = await agent(
  `Scan ${repo}/${target}/ for phase-close TODO markers.\n\n` +
  `Commands:\n` +
  `  test -d ${repo}/${target} && echo EXISTS || echo MISSING\n` +
  `  rg -n --no-heading -i --type swift -g '!**/Tests/**' -e 'TODO|FIXME|XXX|HACK|\\bstub\\b|\\bplaceholder\\b|Phase [0-9]+ Part' ${repo}/${target}/ 2>/dev/null || true\n` +
  `  rg -l --type swift -g '!**/Tests/**' '' ${repo}/${target}/ 2>/dev/null | wc -l   # scannedFiles count (same filter as matches)\n\n` +
  `Parse rg output (format: path:line:content). Strip the absolute repo prefix so 'file' is relative (e.g. "Packages/SudokuKit/Sources/Persistence/Foo.swift"). ` +
  `For 'marker', pick the FIRST keyword the snippet contains (case-insensitive), preserving its case from the source. ` +
  `Trim snippet whitespace. Return JSON matching schema. ` +
  `If target dir missing, return targetExists=false, empty matches.`,
  { label: 'scan', schema: SCAN_SCHEMA }
)

if (!scan.targetExists) {
  return { status: 'TARGET_MISSING', target, guidance: `Directory ${target} does not exist. Check args.target.` }
}

log(`Scanned ${scan.scannedFiles} file(s), found ${scan.matches.length} marker(s)`)

if (scan.matches.length === 0) {
  return {
    status: 'CLEAN',
    target,
    phaseId,
    scannedFiles: scan.scannedFiles,
    guidance: `Sweep clean — phase close unblocked${phaseId ? ` for ${phaseId}` : ''}.`,
  }
}

// ── Phase 2: Classify ─────────────────────────────────────────────────────
phase('Classify')

const CLASSIFY_SCHEMA = {
  type: 'object',
  required: ['classifications', 'blockers'],
  properties: {
    blockers: { type: 'integer', description: 'count needing Leader judgment / cannot auto-classify' },
    classifications: {
      type: 'array',
      items: {
        type: 'object',
        required: ['file', 'line', 'marker', 'snippet', 'disposition', 'rationale'],
        properties: {
          file: { type: 'string' },
          line: { type: 'integer' },
          marker: { type: 'string' },
          snippet: { type: 'string' },
          disposition: {
            type: 'string',
            enum: ['Resolved', 'Backlog', 'Intentional', 'NeedsLeader'],
            description: 'Resolved = already fixed by current phase; Backlog = route to §Backlog; Intentional = stay with documented reason; NeedsLeader = ambiguous, Leader must decide',
          },
          rationale: { type: 'string', description: '1-2 sentence reason for the chosen disposition' },
          backlogTarget: {
            type: 'string',
            enum: ['docs/design.md', 'docs/foundations.md', 'docs/plan.md', 'docs/methodology.md', 'meeting-log', ''],
            description: 'when disposition=Backlog: which file\'s §Backlog. Per methodology backlog-routing-by-topic.',
          },
          backlogEntry: {
            type: 'string',
            description: 'when disposition=Backlog: proposed §Backlog entry text (cite source file:line)',
          },
          issueTitle: { type: 'string', description: 'when disposition=Backlog and worth a GH issue: short title' },
          issueBody: { type: 'string', description: 'when disposition=Backlog and worth a GH issue: body' },
          issueLabels: { type: 'array', items: { type: 'string' } },
        },
      },
    },
  },
}

const classify = await agent(
  `Classify ${scan.matches.length} phase-close TODO markers in ${repo}/${target}/.\n\n` +
  `For each match, decide disposition per methodology §派發契約 item 7:\n` +
  `  - **Resolved**: the marker is stale — surrounding code shows the work is already done. Read 5-10 lines around each match if unsure (use \`sed -n 'L1,L2p' file\` or Read tool on specific path).\n` +
  `  - **Backlog**: real follow-up work; route by topic per backlog-routing-by-topic skill:\n` +
  `      product / feature gaps → docs/design.md §Backlog\n` +
  `      engineering / tooling / infra → docs/foundations.md §Backlog\n` +
  `      implementation step / phase work → docs/plan.md §Backlog\n` +
  `      collaboration / process → docs/methodology.md §Backlog\n` +
  `      truly unclassifiable → meeting-log (today's §未決)\n` +
  `  - **Intentional**: marker is deliberate (e.g. "TODO when iOS 19 ships", "placeholder until USD price tier decided") — must include rationale.\n` +
  `  - **NeedsLeader**: ambiguous; Leader must decide.\n\n` +
  `For Backlog: write the proposed §Backlog entry text citing source (file:line). If the work merits a GitHub issue ${draftIssues ? '(draftIssues=true)' : '(draftIssues=false, skip issue fields)'}, draft issueTitle/issueBody/issueLabels following the repo's existing convention (see below).\n\n` +
  `## GitHub issue convention (learned from existing issues)\n` +
  `Title prefix (conventional-commits-like). Pick one that fits:\n${TITLE_PREFIX_HINTS.map(p => `  - ${p}`).join('\n')}\n\n` +
  `Body structure:\n` +
  `  **Date**: ${today || 'YYYY-MM-DD'}\n` +
  `  \n` +
  `  **Source**: \`<file:line>\` (the rg match)\n` +
  `  \n` +
  `  ## Problem\n  (1-3 sentences from the snippet + surrounding code)\n` +
  `  \n` +
  `  ## Proposal / Fix\n  (concrete next steps if you can infer them)\n` +
  `  \n` +
  `  ## Acceptance\n  (verifiable condition; "rg returns 0 hits" style)\n` +
  `  \n` +
  `  ## Out of scope\n  (optional)\n\n` +
  `Labels — choose from this stable set only (omit when unsure; empty is fine):\n${KNOWN_LABELS.map(l => `  - ${l}`).join('\n')}\n` +
  `Always include 'backlog' for Backlog-disposition issues.\n` +
  `Topic-derived labels: design.md→(none specific) · foundations.md→(ci|devx|architecture|modules pick best) · plan.md→(testing|architecture pick best) · methodology.md→documentation\n\n` +
  `## Same-file consolidation\n` +
  `If multiple matches in the same file describe the same concern (e.g. 3 TODOs in Foo.swift all relating to "wire telemetry"), produce a SINGLE issue stub for them:\n` +
  `  - Pick the first match's file:line as the anchor for issueTitle/issueBody/Source\n` +
  `  - Reference the other lines inside issueBody as additional call-sites\n` +
  `  - The other classifications still appear in the output (so the checklist shows every marker), but only the anchor entry carries issueTitle/issueBody/issueLabels; others set issueTitle="" to signal \"covered by anchor\"\n` +
  `Do this consolidation only when the markers are genuinely the same concern; different concerns in the same file stay separate.\n\n` +
  `Be conservative: when in doubt, prefer NeedsLeader over guessing. Count NeedsLeader into 'blockers'.\n\n` +
  `Matches:\n${JSON.stringify(scan.matches, null, 2)}`,
  { label: 'classify', schema: CLASSIFY_SCHEMA }
)

// ── Phase 3: Emit ─────────────────────────────────────────────────────────
phase('Emit')

const groups = { Resolved: [], Backlog: [], Intentional: [], NeedsLeader: [] }
for (const c of classify.classifications) (groups[c.disposition] || groups.NeedsLeader).push(c)

const checklist = [
  `# Phase TODO sweep${phaseId ? ` — ${phaseId}` : ''}`,
  `Target: \`${target}\`  ·  ${scan.matches.length} marker(s)  ·  ${classify.blockers} blocker(s)`,
  ``,
  `## Resolved (${groups.Resolved.length})`,
  ...(groups.Resolved.length === 0 ? ['_none_'] : groups.Resolved.map(c =>
    `- [x] \`${c.file}:${c.line}\` [${c.marker}] ${c.snippet}\n  - ${c.rationale}`
  )),
  ``,
  `## Backlog (${groups.Backlog.length})`,
  ...(groups.Backlog.length === 0 ? ['_none_'] : groups.Backlog.flatMap(c => [
    `- [ ] \`${c.file}:${c.line}\` [${c.marker}] → **${c.backlogTarget || '?'}**`,
    `  - snippet: \`${c.snippet}\``,
    `  - proposed §Backlog entry: ${c.backlogEntry || '(none drafted)'}`,
    ...(c.issueTitle ? [`  - draft issue: **${c.issueTitle}** ${(c.issueLabels || []).map(l => '`' + l + '`').join(' ')}`] : []),
  ])),
  ``,
  `## Intentional (${groups.Intentional.length})`,
  ...(groups.Intentional.length === 0 ? ['_none_'] : groups.Intentional.map(c =>
    `- [ ] \`${c.file}:${c.line}\` [${c.marker}] — _intentional_\n  - ${c.rationale}\n  - must be cited in phase meeting log per methodology`
  )),
  ``,
  `## Needs Leader (${groups.NeedsLeader.length})`,
  ...(groups.NeedsLeader.length === 0 ? ['_none_'] : groups.NeedsLeader.map(c =>
    `- [ ] \`${c.file}:${c.line}\` [${c.marker}] ${c.snippet}\n  - ${c.rationale}`
  )),
].join('\n')

// gh issue create stubs — Leader runs these manually (we don't execute).
// Body format aligns with existing repo convention (Date / Source / Migrated footer).
function buildIssueBody(c) {
  const parts = []
  if (today) parts.push(`**Date**: ${today}`, '')
  parts.push(`**Source**: \`${c.file}:${c.line}\``, '')
  if (c.issueBody && c.issueBody.trim()) parts.push(c.issueBody.trim(), '')
  parts.push(`**Marker**: ${c.marker}`, `**Snippet**: \`${c.snippet}\``)
  // Append "Migrated from" footer when this Backlog entry is routed into a docs/*.md file
  // (matches convention seen in #168/#170/#172 etc.)
  if (c.backlogTarget && c.backlogTarget.startsWith('docs/') && today) {
    parts.push('', '---', `_Migrated from \`${c.backlogTarget}\` §Backlog on ${today}._`)
  }
  return parts.join('\n')
}

// Filter labels through KNOWN_LABELS to enforce the stable label set
function sanitizeLabels(arr, ensureBacklog) {
  const set = new Set((arr || []).filter(l => KNOWN_LABELS.includes(l)))
  if (ensureBacklog) set.add('backlog')
  return [...set]
}

// Heredoc form — robust against newlines / backticks / single-quotes that the LLM may emit in title/body.
// Caller pastes the entire block into a terminal. Title goes via env var; body via process-substitution heredoc.
const ghStubs = draftIssues
  ? groups.Backlog
      .filter(c => c.issueTitle)
      .map(c => {
        const title = c.issueTitle
        const body = buildIssueBody(c)
        const labels = sanitizeLabels(c.issueLabels, true).join(',')
        const labelFlag = labels ? ` --label '${labels.replace(/'/g, "'\\''")}'` : ''
        // Quoted heredoc ('GH_BODY_EOF') disables variable / backtick expansion inside the body
        return [
          `TITLE=${JSON.stringify(title)}`,
          `gh issue create --title "$TITLE"${labelFlag} --body-file <(cat <<'GH_BODY_EOF'`,
          body,
          `GH_BODY_EOF`,
          `)`,
        ].join('\n')
      })
  : []

const phaseClosable = groups.NeedsLeader.length === 0 && groups.Backlog.every(c => c.backlogTarget && c.backlogEntry)

log(`Classifications: Resolved=${groups.Resolved.length} Backlog=${groups.Backlog.length} Intentional=${groups.Intentional.length} NeedsLeader=${groups.NeedsLeader.length}`)

return {
  status: phaseClosable ? 'READY_TO_CLOSE' : 'BLOCKERS_REMAIN',
  target,
  phaseId,
  totals: {
    matches: scan.matches.length,
    resolved: groups.Resolved.length,
    backlog: groups.Backlog.length,
    intentional: groups.Intentional.length,
    needsLeader: groups.NeedsLeader.length,
  },
  checklist,
  ghIssueStubs: ghStubs,
  guidance: phaseClosable
    ? `All markers classified. Leader: (1) Resolved entries are already addressed by phase diff. (2) For each Backlog entry, append to its routed §Backlog file with source cite. (3) Intentional entries must be cited in phase meeting log. ${ghStubs.length ? `(4) ${ghStubs.length} gh issue create stub(s) ready — run from terminal when you want.` : ''} Phase close unblocked.`
    : `${groups.NeedsLeader.length} marker(s) need Leader judgment before phase close. See 'Needs Leader' section. Re-run after resolving.`,
}
