// Project workflow: admob-isolation-audit
// Enforces the AdMob SDK isolation invariant (docs/v2/plan.md, repeated 3×):
//   Exactly ONE file in Packages/ may `import GoogleMobileAds`:
//     Packages/AppMonetizationKit/Sources/AdsAdMob/LiveAdMobBridge.swift
// Any other hit indicates a breach of the third-party SDK isolation contract
// (monetization-sdk-integration skill).
//
// Invoke via:
//   Workflow({name: "admob-isolation-audit"})
//   Workflow({name: "admob-isolation-audit", args: {expectedFile: "..."}})

export const meta = {
  name: 'admob-isolation-audit',
  description: 'Assert exactly one `import GoogleMobileAds` in Packages/ (the live bridge file). Any other hit breaches AdMob SDK isolation.',
  whenToUse: 'Pre-PR check when touching AppMonetizationKit; periodic audit; release gate for monetization changes.',
  phases: [{ title: 'Scan' }],
}

const repo = (args && args.repo) || '.'
const expectedFile = (args && args.expectedFile) || 'Packages/AppMonetizationKit/Sources/AdsAdMob/LiveAdMobBridge.swift'

phase('Scan')

const SCAN_SCHEMA = {
  type: 'object',
  required: ['hits', 'scannedRoot'],
  properties: {
    scannedRoot: { type: 'string' },
    hits: {
      type: 'array',
      items: {
        type: 'object',
        required: ['file', 'line', 'snippet'],
        properties: {
          file: { type: 'string', description: 'path relative to repo root' },
          line: { type: 'integer' },
          snippet: { type: 'string' },
        },
      },
    },
  },
}

const scan = await agent(
  `Audit AdMob SDK isolation in ${repo}/Packages/.\n\n` +
  `Run TWO scans:\n` +
  `  # Primary: any import GoogleMobileAds (including @_exported / @testable / @_implementationOnly / @preconcurrency / fileprivate / package)\n` +
  `  rg -n --no-heading -e '^[[:space:]]*(@[A-Za-z_]+[[:space:]]+)*(internal |private |public |fileprivate |package )*import[[:space:]]+GoogleMobileAds\\b' ${repo}/Packages/ 2>/dev/null || true\n` +
  `  # Secondary (WARN class): canImport(GoogleMobileAds) — a soft dependency that still pulls the SDK into the type graph\n` +
  `  rg -n --no-heading -e 'canImport\\([[:space:]]*GoogleMobileAds[[:space:]]*\\)' ${repo}/Packages/ 2>/dev/null || true\n\n` +
  `Parse output (format: path:line:content). Strip the absolute repo prefix from each path so 'file' is relative (e.g. "Packages/AppMonetizationKit/Sources/.../X.swift"). ` +
  `Combine both scans into the 'hits' array — for canImport-only matches, prefix the snippet with "[canImport] " so the caller can distinguish. ` +
  `Trim whitespace from snippet. Return JSON matching schema (hits=[] when none found).`,
  { label: 'rg-admob', schema: SCAN_SCHEMA }
)

const violations = scan.hits.filter(h => h.file !== expectedFile)
const expectedFound = scan.hits.some(h => h.file === expectedFile)

let status
let guidance
if (violations.length === 0 && expectedFound && scan.hits.length === 1) {
  status = 'PASS'
  guidance = `Exactly 1 hit, in the expected file. Isolation contract intact.`
} else if (violations.length === 0 && !expectedFound) {
  status = 'WARN_BRIDGE_MISSING'
  guidance = `No hits at all. Expected exactly 1 hit in ${expectedFile}. Either the bridge file moved/renamed (update expectedFile arg) or AdMob is currently not wired (likely intentional during certain builds).`
} else {
  status = 'FAIL'
  guidance = `Isolation breach. ${violations.length} unauthorized \`import GoogleMobileAds\` outside ${expectedFile}. Move the SDK access behind LiveAdMobBridge per monetization-sdk-integration skill.`
}

log(`AdMob isolation: ${status} (${scan.hits.length} total hit(s), ${violations.length} violation(s))`)

return {
  status,
  expectedFile,
  totalHits: scan.hits.length,
  violations,
  expectedFound,
  allHits: scan.hits,
  guidance,
}
