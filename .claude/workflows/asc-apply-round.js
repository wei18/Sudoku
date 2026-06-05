// Project workflow: asc-apply-round
// One round of the ASC apply retry loop. Each invocation:
//   1. Runs `swift run ASCRegister apply <credentialsArgs>` (or `plan` for dry-run)
//   2. If 2xx → returns SUCCESS
//   3. If 4xx → decodes ENTITY_ERROR.<CODE>, looks up known fix recipe OR
//      asks an agent to propose a Config.swift patch with file:line +
//      acceptance criterion + draft "round N" issue body
//   4. Returns proposal to Leader — does NOT auto-apply, does NOT auto-commit
//
// Per-round design (not a JS loop) because ASC mutations are real Apple API
// calls; Leader keeps the OK/apply step.
//
// Codifies the 8-round pattern seen in issues #17 #19 #22 #24 #26 #31 #37 #40.
//
// Invoke via:
//   Workflow({name: "asc-apply-round", args: {
//     credentialsArgs: "--key $HOME/.../ASC.p8 --key-id ABC --issuer DEF --app-id 123 --xcstrings App/Resources/...xcstrings",
//     mode: "plan",         // DEFAULT. "apply" requires confirmApply: true (live Apple API write).
//     confirmApply: true,   // REQUIRED when mode === "apply". Acknowledges live-mutation risk.
//     roundNumber: 5,       // for issue body header
//     date: "2026-05-28"    // for Date header in issue body
//   }})
//
// IMPORTANT — credential hygiene:
//   credentialsArgs flows into Bash via the workflow. Use $HOME or absolute paths
//   (not ~ — tilde expansion depends on the agent shell). The workflow redacts
//   --key/--key-id/--issuer before composing LLM prompts, return values, and
//   issueBody — but DO NOT paste credentialsArgs into chat / commit messages.

export const meta = {
  name: 'asc-apply-round',
  description: 'One round of ASCRegister apply/plan: run CLI, decode ENTITY_ERROR, propose Config.swift patch + round-N issue body. Leader applies + re-invokes for next round.',
  whenToUse: 'After registering / updating leaderboards / achievements via ASCRegister and hitting a 4xx — instead of hand-decoding the error, run this for a structured proposal.',
  phases: [
    { title: 'Run', detail: 'invoke ASCRegister apply/plan, capture stdout+stderr+exit' },
    { title: 'Decode', detail: 'parse ENTITY_ERROR + propose fix' },
  ],
}

if (!args || !args.credentialsArgs) {
  throw new Error('asc-apply-round requires args.credentialsArgs (the --key/--key-id/--issuer/--app-id/--xcstrings string the user assembles)')
}
const credentialsArgs = args.credentialsArgs
// Default to plan (dry-run). 'apply' performs a live Apple API write and demands explicit confirmation.
const mode = (args.mode === 'apply') ? 'apply' : 'plan'
if (mode === 'apply' && args.confirmApply !== true) {
  throw new Error(
    'asc-apply-round: mode="apply" performs a LIVE App Store Connect mutation. ' +
    'Pass confirmApply: true to acknowledge. To dry-run, omit mode (defaults to "plan") ' +
    'or pass mode: "plan".'
  )
}
const roundNumber = args.roundNumber || null
const date = args.date || null
const repo = args.repo || '.'
const packagePath = args.packagePath || 'Packages/ASCRegisterKit'
// Guard packagePath against shell metachars / traversal (interpolated into bash via agent prompts)
if (!/^[A-Za-z0-9_./-]+$/.test(packagePath) || packagePath.includes('..')) {
  throw new Error(`asc-apply-round: packagePath "${packagePath}" contains forbidden characters or '..' (allowed: A-Za-z0-9_./-)`)
}

// Credential scrubber — applied before any credentialsArgs / stdout flows into an LLM prompt
// or a returned value. Matches the --key/--key-id/--issuer/--app-id pattern with either
// `=value` or `<space>value` separators.
function redactCredentials(s) {
  if (!s || typeof s !== 'string') return s
  return s
    .replace(/(--key)([= ])([^\s]+)/g, '$1$2<REDACTED>')
    .replace(/(--key-id)([= ])([^\s]+)/g, '$1$2<REDACTED>')
    .replace(/(--issuer)([= ])([^\s]+)/g, '$1$2<REDACTED>')
    .replace(/(--app-id)([= ])([^\s]+)/g, '$1$2<REDACTED>')
}

// Known ENTITY_ERROR → fix recipe map, derived from issues #17 #19 #22 #24 #26 #31 #37 #40.
// Each recipe is a hint, not a guarantee — the agent must still verify against current Config.swift.
const KNOWN_RECIPES = {
  LOCALE_INVALID: {
    summary: 'Apple rejects the leaderboard/achievement locale code.',
    likelyFix: "In Strings/*.xcstrings + Config.swift locale lists: use zh-Hant (no region) not zh-Hant-TW; use en (no region) where applicable.",
    pastRounds: '#31 #37',
  },
  INVALID_POINTS_RANGE: {
    summary: 'Apple enforces achievement points in 0-100 range.',
    likelyFix: 'Config.swift: clamp every achievement points value to 0-100 (do not use raw centisecond / large counts).',
    pastRounds: '#40',
  },
  RECURRENCE_RULE_INVALID: {
    summary: 'Apple wants RFC 5545 RRULE format, not plain "DAILY".',
    likelyFix: 'Config.swift recurrenceRule: "DAILY" → "FREQ=DAILY;INTERVAL=1". Update ConfigConsistencyTests.',
    pastRounds: '#26',
  },
  RECURRENCE_START_CANNOT_BE_PAST: {
    summary: 'recurrenceStartDate must be future-only.',
    likelyFix: 'Config.swift: ensure recurrenceStartDate uses LeaderboardConfig.nextRecurrenceStartDateUTC() (returns tomorrow UTC 00:00, today + 86400s). Verify NextRecurrenceStartDateTests covers the edge case at 23:59 UTC.',
    pastRounds: '#26',
  },
  RECURRENCE_DURATION_INVALID: {
    summary: 'recurrenceDuration needs ISO 8601 "with time components".',
    likelyFix: 'Config.swift: "P1D" → "PT24H". Update tests.',
    pastRounds: '#24',
  },
  RECURRENCE_START_DATE_REQUIRED: {
    summary: 'recurrenceStartDate + recurrenceDuration both required.',
    likelyFix: 'Config.swift: ensure recurring leaderboards include both fields; add to ConfigConsistencyTests assertions.',
    pastRounds: '#22',
  },
  SCORE_SORT_TYPE_INVALID: {
    summary: 'scoreSortType invalid value OR submissionType missing.',
    likelyFix: 'ASCClient request body: scoreSortType ∈ {ASCENDING, DESCENDING}; submissionType ∈ {RECURRING, MANUAL}. Verify request shape.',
    pastRounds: '#19',
  },
}

// ── Phase 1: Run ──────────────────────────────────────────────────────────
phase('Run')

const RUN_SCHEMA = {
  type: 'object',
  required: ['exitCode', 'stdout', 'stderr'],
  properties: {
    exitCode: { type: 'integer' },
    stdout: { type: 'string' },
    stderr: { type: 'string' },
    command: { type: 'string' },
    httpStatus: { type: ['integer', 'null'], description: 'parsed HTTP status if visible in output' },
    entityErrors: {
      type: 'array',
      description: 'parsed ENTITY_ERROR codes/fields/messages from output',
      items: {
        type: 'object',
        required: ['code'],
        properties: {
          code: { type: 'string', description: 'e.g. RECURRENCE_RULE_INVALID' },
          field: { type: 'string', description: 'e.g. recurrenceRule' },
          message: { type: 'string' },
        },
      },
    },
  },
}

const run = await agent(
  `Run ASCRegister ${mode} from ${repo}.\n\n` +
  `Pre-flight:\n` +
  `  test -d ${repo}/${packagePath} || echo MISSING_PKG_PATH_${packagePath}\n` +
  `If MISSING_PKG_PATH is printed, set exitCode=127 and report the missing path in stdout — do NOT attempt swift run.\n\n` +
  `Otherwise run:\n` +
  `  swift run --package-path ${repo}/${packagePath} ASCRegister ${mode} ${credentialsArgs} 2>&1\n\n` +
  `Note: credentialsArgs should use $HOME or absolute paths — tilde (~) expansion depends on the shell and may silently fail to a misleading auth error.\n\n` +
  `Capture exitCode, stdout+stderr (combine with 2>&1 — pass both as 'stdout' string; leave 'stderr' empty). ` +
  `Parse the output for:\n` +
  `  - HTTP status code (e.g. "HTTP 422" / "status: 409")\n` +
  `  - ENTITY_ERROR.<CODE> tokens (Apple's error code namespace)\n` +
  `  - The 'field: <name>' or 'pointer: ...' associated with each error\n` +
  `  - The human-readable message after each ENTITY_ERROR\n\n` +
  `If multiple ENTITY_ERROR appear, list all. If exitCode=0 and no errors, return empty entityErrors.`,
  { label: `${mode}-run`, schema: RUN_SCHEMA }
)

log(`ASCRegister ${mode}: exit=${run.exitCode}, ${(run.entityErrors || []).length} ENTITY_ERROR`)

if (run.exitCode === 0 && (run.entityErrors || []).length === 0) {
  return {
    status: 'SUCCESS',
    mode,
    roundNumber,
    stdout: run.stdout,
    guidance: mode === 'apply'
      ? `ASCRegister apply succeeded. Leader: verify in ASC console, commit any pending Config.swift / xcstrings changes if not already committed.`
      : `ASCRegister plan succeeded (dry run — no Apple mutations). Re-run with mode="apply" when ready.`,
  }
}

// ── Phase 2: Decode + propose ─────────────────────────────────────────────
phase('Decode')

const errors = run.entityErrors || []
const recipes = errors.map(e => ({
  error: e,
  recipe: KNOWN_RECIPES[e.code] || null,
}))

const PROPOSAL_SCHEMA = {
  type: 'object',
  required: ['proposals', 'overallSummary'],
  properties: {
    overallSummary: { type: 'string', description: '1-2 sentence summary across all errors' },
    proposals: {
      type: 'array',
      items: {
        type: 'object',
        required: ['errorCode', 'fixDescription', 'targetFiles', 'verificationCommand'],
        properties: {
          errorCode: { type: 'string' },
          field: { type: 'string' },
          fixDescription: { type: 'string', description: 'concrete patch — what to change, where (file:line), to what' },
          targetFiles: { type: 'array', items: { type: 'string' }, description: 'files to edit' },
          testsToUpdate: { type: 'array', items: { type: 'string' } },
          verificationCommand: { type: 'string', description: 'how Leader verifies the patch (e.g. "swift test --filter ConfigConsistencyTests")' },
          risk: { type: 'string' },
        },
      },
    },
    issueBody: {
      type: 'string',
      description: 'ready-to-paste body for a "round N" GitHub issue, matching format from #17/#19/#22/#24/#26/#31/#37/#40',
    },
    issueTitle: { type: 'string', description: 'matching title, e.g. "ASC apply round N — <ENTITY_ERROR>"' },
    issueLabels: { type: 'array', items: { type: 'string' }, description: 'optional labels' },
  },
}

const scrubbedStdout = redactCredentials((run.stdout || '').slice(0, 4000))

const proposal = await agent(
  `ASCRegister ${mode} failed. Propose patches for the encountered ENTITY_ERROR(s).\n\n` +
  `## Context\n` +
  `- Round number: ${roundNumber || 'unknown'}\n` +
  `- Date: ${date || 'unknown'}\n` +
  `- Mode: ${mode}\n` +
  `- Exit code: ${run.exitCode}\n` +
  `- HTTP status: ${run.httpStatus || 'see output'}\n\n` +
  `## Raw output (credentials redacted, truncated)\n\`\`\`\n${scrubbedStdout}\n\`\`\`\n\n` +
  `## ENTITY_ERROR(s) + known recipe\n${JSON.stringify(recipes, null, 2)}\n\n` +
  `## Your task\n` +
  `For each ENTITY_ERROR, propose a concrete patch. If a known recipe exists, USE IT as starting point but VERIFY against the current code (read Packages/ASCRegisterKit/Sources/ASCRegister/Config.swift / ASCClient.swift / Strings/*.xcstrings as needed). If no recipe, propose based on the error message + field.\n\n` +
  `For each proposal:\n` +
  `  - fixDescription: 2-4 sentences, name the file:line and the exact change\n` +
  `  - targetFiles: list of file paths to edit\n` +
  `  - testsToUpdate: any test files whose assertions need updating\n` +
  `  - verificationCommand: e.g. \`swift test --filter ConfigConsistencyTests\` or \`swift run ASCRegister plan ...\`\n` +
  `  - risk: known unknowns / things to confirm post-merge\n\n` +
  `Then write issueTitle + issueBody matching the established format from #17/#19/#22/#24/#26/#31/#37/#40:\n` +
  `  Title format: "ASC apply round ${roundNumber || 'N'} — <ENTITY_ERROR shorthand>"\n` +
  `  Body sections: ## Status (round N facts) / ## Fix (numbered steps per file) / ## Risk / ## Discovery (\`swift run ASCRegister ${mode} <REDACTED credentials>\` ${date || 'YYYY-MM-DD'})\n` +
  `  CRITICAL: do NOT embed any --key, --key-id, --issuer, --app-id values, .p8 path, or other credentials in issueTitle or issueBody. The "Discovery" line MUST use literal "<REDACTED>" in place of the credential flags.\n` +
  `  No labels needed (existing round issues have none).`,
  { label: 'propose-fix', schema: PROPOSAL_SCHEMA }
)

// Defence-in-depth: scrub LLM output too in case it leaked any credential despite the instruction.
const safeIssueTitle = proposal.issueTitle ? redactCredentials(proposal.issueTitle) : null
const safeIssueBody = proposal.issueBody ? redactCredentials(proposal.issueBody) : null

return {
  status: 'FIX_PROPOSED',
  mode,
  roundNumber,
  exitCode: run.exitCode,
  entityErrors: errors,
  overallSummary: proposal.overallSummary,
  proposals: proposal.proposals,
  issueTitle: safeIssueTitle,
  issueBody: safeIssueBody,
  issueLabels: proposal.issueLabels || [],
  // Intentionally NO shell-string ghIssueStub — Leader should use `gh issue create --body-file <(...)`
  // or copy issueTitle/issueBody into the gh CLI manually. Returning a shell string built from
  // LLM output invites injection from any newline/backtick the LLM emits, and the public repo
  // surface area means credentials leaking via this path would persist.
  ghIssueInstructions: safeIssueTitle && safeIssueBody
    ? 'Run: gh issue create --title "$TITLE" --body-file <(cat <<\'EOF\'\n<paste issueBody here>\nEOF\n) — using issueTitle/issueBody from this result.'
    : null,
  // Truncated + scrubbed copy of stdout. Full untruncated stdout NOT returned to prevent credential leak.
  rawOutputScrubbed: scrubbedStdout,
  guidance: `Leader: (1) read each proposal; (2) apply patches via Edit tool; (3) run verificationCommand for each; (4) commit (\`fix(asc): round ${roundNumber || 'N'} — ${(errors[0] && errors[0].code) || 'multi-error'}\`); (5) optionally create gh issue per ghIssueInstructions for audit trail; (6) re-invoke with roundNumber=${(roundNumber || 0) + 1} (mode="plan" first to verify, then mode="apply" + confirmApply:true).`,
}
