#!/usr/bin/env bash
# mise-tasks/lib/sim-app.sh — shared iOS-Simulator + Tuist-build helpers.
#
# SOURCED, never executed: `source "$(dirname "${BASH_SOURCE[0]}")/../lib/sim-app.sh"`
# from a mise task that already set `set -euo pipefail` and `REPO_ROOT`.
# Extracted from mise-tasks/ui/tour (#1054) so ui:tour, test:ui and the new
# store:capture task share one implementation of: app scheme/bundle lookup,
# the #863 unresolved-xcconfig gate, simulator resolve/boot/create, the
# Debug/Release Tuist build, BGM muting and the #1054 status-bar override.
# Callers must define REPO_ROOT before sourcing (check_plist_resolved's
# error text references it) and must not rely on any function here printing
# to stdout except the documented "echoes <value>" return.
#
# bash 3.2 compatible (macOS system /bin/bash — no associative arrays, no
# `${var,,}`, no `mapfile`).

# ── App identity ────────────────────────────────────────────────────────────

app_scheme_for() { case "$1" in sudoku) echo "Sudoku";; minesweeper) echo "Minesweeper";; *) echo "";; esac; }
app_bundle_for() { case "$1" in sudoku) echo "com.wei18.sudoku";; minesweeper) echo "com.wei18.minesweeper";; *) echo "";; esac; }

# ── Machine-load gate (#1054 P-A) ───────────────────────────────────────────

# read_load_1m — echoes the 1-minute load average from `sysctl -n vm.loadavg`
# (format "{ 1.23 4.56 7.89 }" — first figure only).
read_load_1m() {
  sysctl -n vm.loadavg | awk '{gsub(/[{}]/, ""); print $1}'
}

# check_load_gate <max_load> <max_wait_sec> <label> — reads the 1-minute load
# average and, if it exceeds <max_load>, polls every 15s (printing each wait)
# until it drops back under the threshold or <max_wait_sec> elapses. On
# timeout it fails LOUDLY (never silently proceeds over-threshold): "machine
# busy: load X > max Y". Always prints the load value on the fast path too,
# so every build/relaunch/identity-check log line carries a load number
# (#1054 P-A spec item 1). Shared by every call site in mise-tasks/store/capture
# that builds or relaunches a simulator app.
check_load_gate() {
  local max_load="$1" max_wait="$2" label="$3" waited=0 load
  load="$(read_load_1m)"
  if awk -v l="$load" -v m="$max_load" 'BEGIN{exit !(l>m)}'; then
    echo "    [$label] load=$load > max=$max_load — waiting for it to drop (max wait ${max_wait}s)"
    while awk -v l="$load" -v m="$max_load" 'BEGIN{exit !(l>m)}'; do
      if (( waited >= max_wait )); then
        echo "error: machine busy: load $load > max $max_load (waited ${waited}s, --load-wait ${max_wait}s exhausted) [$label]" >&2
        return 1
      fi
      sleep 15
      waited=$((waited + 15))
      load="$(read_load_1m)"
      echo "    [$label] load=$load (waited ${waited}s/${max_wait}s)"
    done
  fi
  echo "    [$label] load=$load (max=$max_load) OK"
}

# ── Post-build unresolved-xcconfig gate (#863) ──────────────────────────────
# A hand-created worktree missing gitignored Tuist/*.xcconfig (see
# .worktreeinclude — the automatic copy only runs for HARNESS-created
# worktrees) still builds fine: `#include?` treats a missing xcconfig as
# empty, not an error. What that does to the Info.plist substitution
# $(ADMOB_BANNER_UNIT_ID) depends on WHICH xcconfig is missing (empirically
# verified #863):
#   - Tuist/Signing.xcconfig present but Tuist/AdMob.xcconfig absent:
#     Signing.xcconfig `#include`s AdMob.xcconfig NON-optionally, so this
#     combination hard-FAILS the xcodebuild step itself — safe already.
#   - Both files absent (the actual hand-worktree scenario — neither ever
#     got copied): the build SUCCEEDS and xcodebuild resolves the undefined
#     macro to an EMPTY STRING, not the literal "$(...)" text.
# So the runtime guard this mirrors (MakeGameApp.swift ~138-149, which covers
# GADBannerUnitID only — GADApplicationIdentifier is validated by the AdMob
# SDK itself at launch, no app-code precondition) checks BOTH `.isEmpty` and
# `.hasPrefix("$(")` — this gate checks both KEYS defensively since either
# empty value crashes at launch. The literal-"$("
# scan stays generic (any string value, not just the two known keys, per
# #863's ask — catches a FUTURE substituted key left unresolved by some
# other xcconfig combination); the emptiness check is scoped to the two
# keys we know are build-injected, since "empty" alone is not inherently
# wrong for arbitrary Info.plist strings.
check_plist_resolved() {
  local app_path="$1" plist="$1/Info.plist"
  if [[ ! -f "$plist" ]]; then
    echo "error: no Info.plist found at $plist — cannot verify xcconfig substitution." >&2
    return 1
  fi
  local unresolved problems=()
  unresolved="$(plutil -p "$plist" | grep -oE '\$\([A-Za-z0-9_]+\)' | sort -u || true)"
  if [[ -n "$unresolved" ]]; then
    while IFS= read -r var; do problems+=("unresolved literal: $var"); done <<<"$unresolved"
  fi
  for key in GADApplicationIdentifier GADBannerUnitID; do
    local val
    val="$(/usr/libexec/PlistBuddy -c "Print :$key" "$plist" 2>/dev/null || true)"
    [[ -z "$val" ]] && problems+=("empty (missing xcconfig substitution): $key")
  done
  if [[ ${#problems[@]} -gt 0 ]]; then
    echo "────────────────────────────────────────────────────────────────" >&2
    echo " UNRESOLVED/MISSING BUILD-TIME VALUE(S) in $plist:" >&2
    printf '   %s\n' "${problems[@]}" >&2
    echo "" >&2
    echo " A gitignored Tuist/*.xcconfig is missing from this checkout ($app_path) —" >&2
    echo " likely a hand-created worktree (git worktree add) that never got" >&2
    echo " .worktreeinclude's automatic copy. Remedy: from the MAIN checkout run" >&2
    echo "   mise run worktree:seed $REPO_ROOT" >&2
    echo " (that's THIS worktree's path — worktree:seed copies Tuist/*.xcconfig" >&2
    echo " + secrets/ into it) — or build from the main checkout instead." >&2
    echo " Refusing to install a launch-crashing app onto the shared simulator." >&2
    echo "────────────────────────────────────────────────────────────────" >&2
    return 1
  fi
}

# ── Simulator resolve / boot / create ───────────────────────────────────────

# sim_wait_booted <udid> — poll until <udid> reports booted, or fail after 30
# tries (60s). Extracted from test:ui's timeout-hardened wait loop (the
# original ui:tour loop had no timeout — applying the guard everywhere is a
# strict safety improvement, not a behavior change on the normal path).
sim_wait_booted() {
  local udid="$1" waits=0
  until xcrun simctl list devices booted | grep -q "$udid"; do
    sleep 2
    waits=$((waits + 1))
    (( waits < 30 )) || { echo "error: simulator $udid did not finish booting" >&2; return 1; }
  done
}

# sim_pick_booted_or_boot <device-name> — echoes a UDID: the first already-
# booted simulator if one exists, else boots the named AVAILABLE device type
# (matched by simctl's "<device-name> (" listing prefix, same as the
# pre-extraction ui:tour/test:ui logic) and waits for it. Used when the
# caller is happy to reuse whatever is already booted (ui:tour, test:ui) —
# NOT for store:capture, which always wants its own named simulator
# (see sim_create_or_reuse_named).
sim_pick_booted_or_boot() {
  local device_name="$1" udid
  udid="$(xcrun simctl list devices booted 2>/dev/null | grep -Eo '[0-9A-F-]{36}' | head -1 || true)"
  if [[ -z "$udid" ]]; then
    udid="$(xcrun simctl list devices available | grep -E "${device_name} \(" | grep -Eo '[0-9A-F-]{36}' | head -1)"
    [[ -n "$udid" ]] || { echo "error: no '${device_name}' simulator found in available devices" >&2; return 1; }
    echo "==> booting ${device_name} ($udid)" >&2
    xcrun simctl boot "$udid"
  fi
  sim_wait_booted "$udid"
  echo "$udid"
}

# sim_create_or_reuse_named <name> <device-type> — echoes the UDID of the
# simulator named <name> (simctl accepts either a device-type identifier or
# its plain display name for <device-type>, verified empirically #1054).
# Finds an existing device with that exact name first; only creates one if
# none exists. Never touches a simulator this function did not itself name.
sim_create_or_reuse_named() {
  local name="$1" device_type="$2" udid
  udid="$(xcrun simctl list devices | grep -E "^ *${name} \(" | grep -Eo '[0-9A-F-]{36}' | head -1 || true)"
  if [[ -z "$udid" ]]; then
    echo "==> creating simulator '$name' ($device_type)" >&2
    udid="$(xcrun simctl create "$name" "$device_type")"
  fi
  echo "$udid"
}

# ── Per-launch simulator state ──────────────────────────────────────────────

# sim_mute_bgm <udid> <bundle> — disable the app's background music before
# any interactive/screenshot session (repo convention: sim sessions must not
# play audible BGM on the operator's machine). Keyed off the SAME
# `<bundle>.audio.musicEnabled` UserDefaults key `makeAudioSettings` reads
# (GameAppKit/MakeGameApp+Helpers.swift, keyPrefix = config.audio.keyPrefix
# = the bundle id + ".audio").
sim_mute_bgm() {
  local udid="$1" bundle="$2"
  xcrun simctl spawn "$udid" defaults write "$bundle" "${bundle}.audio.musicEnabled" -bool false
}

# sim_override_status_bar <udid> — pin the status bar to the #1054
# spike-verified byte-identical combination (3 cold boots, 0 differing px)
# so store captures never vary by clock/battery/signal churn.
sim_override_status_bar() {
  local udid="$1"
  xcrun simctl status_bar "$udid" override \
    --time 9:41 --batteryLevel 100 --batteryState discharging \
    --wifiBars 3 --cellularBars 4 --cellularMode active --dataNetwork wifi
}

# ── Build + install ──────────────────────────────────────────────────────────

# _SIM_APP_GENERATE_MARKER guards `tuist install`/`tuist generate` to run at
# most once per process even when build_sim_app is called for multiple apps
# or configs in the same task run (generate is workspace-wide, not
# per-scheme). A FILE marker, not an in-memory flag: callers that capture
# build_sim_app's stdout via `x="$(build_sim_app ...)"` run it in a bash
# command-substitution SUBSHELL, so a plain variable set inside the function
# would be silently lost on return (verified #1054 — the in-memory version
# re-ran `tuist generate` on every call). `$$` is the top-level script's PID
# even inside a subshell, so the marker path is stable across calls within
# one task run and distinct across concurrent runs.
_SIM_APP_GENERATE_MARKER="${TMPDIR:-/tmp}/mise-sim-app-generated-$$"

# build_sim_app <scheme> <Debug|Release> <derived> — tuist install+generate
# (once per process) then an iphonesimulator build of <scheme>/<config> into
# <derived>. Callers decide whether to call this at all (the --no-build flag
# lives in the calling task, not here) — this function always builds when
# invoked. Prints the built .app path's PRODUCTS dir convention to stdout:
# "<derived>/Build/Products/<config>-iphonesimulator".
build_sim_app() {
  local scheme="$1" config="$2" derived="$3"
  if [[ ! -f "$_SIM_APP_GENERATE_MARKER" ]]; then
    echo "==> tuist generate (workspace is gitignored)" >&2
    mise exec -- tuist install >/dev/null 2>&1
    mise exec -- tuist generate --no-open >/dev/null 2>&1
    : >"$_SIM_APP_GENERATE_MARKER"
  fi
  echo "==> build $scheme ($config, iphonesimulator)" >&2
  xcodebuild -workspace Game.xcworkspace -scheme "$scheme" \
    -sdk iphonesimulator -configuration "$config" \
    -destination "generic/platform=iOS Simulator" \
    -derivedDataPath "$derived" build >/dev/null
  echo "$derived/Build/Products/$config-iphonesimulator"
}

# sim_install <udid> <app-path> — simctl install, thin wrapper kept for
# call-site symmetry with the other sim_* verbs.
sim_install() {
  local udid="$1" app_path="$2"
  xcrun simctl install "$udid" "$app_path"
}
