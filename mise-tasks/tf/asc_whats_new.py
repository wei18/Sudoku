#!/usr/bin/env python3
"""asc_whats_new.py — poll App Store Connect for a build's processingState,
then create/update its en-US betaBuildLocalization `whatsNew` from a changelog
file. Companion script to `mise-tasks/tf/upload` (issue #704, P2 of #694).

Stdlib-only (urllib, json, base64, hashlib, subprocess+openssl for ES256
signing). No pip installs, no third-party packages — matches the repo's
"no local Homebrew/CocoaPods, no ad-hoc deps" constraint.

JWT construction mirrors Packages/ASCRegisterKit/Sources/ASCRegister/JWT.swift
(header {alg:ES256,kid,typ}, payload {iss,iat,exp,aud:appstoreconnect-v1},
20 min lifetime) — but unlike CryptoKit (which returns raw P1363 R||S
directly), `openssl dgst -sign` on an EC key returns an ASN.1 DER
ECDSA-Sig-Value (SEQUENCE of two INTEGERs). JOSE ES256 needs the raw R||S
concatenation (RFC 7518 §3.4), so this script hand-parses the DER structure
and re-packs each component as an unsigned, zero-padded 32-byte big-endian
value.

Exit codes (bash wrapper decides warn-vs-error per call site):
  0  success — build left PROCESSING (state VALID) and whatsNew was written
     (or, in --dry-run, the payload that WOULD be written was printed).
  1  hard error — bad args, unreadable key, HTTP/auth failure.
  2  timeout — build never appeared / stayed PROCESSING past --timeout.
  3  terminal bad state — build reached FAILED/INVALID (polling more is
     pointless).
"""
from __future__ import annotations  # keeps `dict | None` etc. parseable on the macOS system Python 3.9

import argparse
import base64
import json
import subprocess
import sys
import time
import urllib.error
import urllib.request

API_BASE = "https://api.appstoreconnect.apple.com/v1"
WHATS_NEW_MAX = 4000


def b64url(raw: bytes) -> str:
    return base64.urlsafe_b64encode(raw).rstrip(b"=").decode("ascii")


def der_to_raw_sig(der: bytes) -> bytes:
    """Parse an ASN.1 DER ECDSA-Sig-Value (SEQUENCE { r INTEGER, s INTEGER })
    into the fixed-width 64-byte raw R||S that JOSE ES256 requires. Assumes
    short-form DER lengths throughout — always true for P-256 (r/s are at
    most 33 bytes incl. a leading sign-zero, well under the 128 that would
    force long-form length encoding)."""
    if len(der) < 8 or der[0] != 0x30:
        raise ValueError(f"not a DER SEQUENCE (got byte0=0x{der[0]:02x})")
    if der[1] & 0x80:
        raise ValueError("unexpected long-form SEQUENCE length for a P-256 signature")
    idx = 2
    if der[idx] != 0x02:
        raise ValueError("expected INTEGER (r) tag")
    idx += 1
    rlen = der[idx]
    idx += 1
    r = der[idx:idx + rlen]
    idx += rlen
    if der[idx] != 0x02:
        raise ValueError("expected INTEGER (s) tag")
    idx += 1
    slen = der[idx]
    idx += 1
    s = der[idx:idx + slen]
    idx += slen

    def fixed32(component: bytes) -> bytes:
        component = component.lstrip(b"\x00")
        if len(component) > 32:
            raise ValueError("signature component longer than 32 bytes — not P-256")
        return component.rjust(32, b"\x00")

    return fixed32(r) + fixed32(s)


def make_jwt(key_path: str, key_id: str, issuer_id: str, lifetime_seconds: int = 19 * 60) -> str:
    # 19, not 20, minutes: ASC's documented max is 20min but community reports
    # (developer.apple.com/forums/thread/700653) show exp-iat >= 20*60 can 401 —
    # a fresh token is minted per poll attempt anyway (see poll_until_processed),
    # so the shorter lifetime costs nothing.
    now = int(time.time())
    header = {"alg": "ES256", "kid": key_id, "typ": "JWT"}
    payload = {"iss": issuer_id, "iat": now, "exp": now + lifetime_seconds, "aud": "appstoreconnect-v1"}
    signing_input = b64url(json.dumps(header, separators=(",", ":")).encode()) + "." + \
        b64url(json.dumps(payload, separators=(",", ":")).encode())
    proc = subprocess.run(
        ["openssl", "dgst", "-sha256", "-sign", key_path],
        input=signing_input.encode(),
        capture_output=True,
        check=False,
    )
    if proc.returncode != 0:
        raise RuntimeError(f"openssl signing failed: {proc.stderr.decode(errors='replace').strip()}")
    raw_sig = der_to_raw_sig(proc.stdout)
    return signing_input + "." + b64url(raw_sig)


def asc_request(method: str, path_or_url: str, jwt: str, body: dict | None = None) -> dict:
    url = path_or_url if path_or_url.startswith("http") else f"{API_BASE}{path_or_url}"
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(url, data=data, method=method)
    req.add_header("Authorization", f"Bearer {jwt}")
    req.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            raw = resp.read()
            return json.loads(raw) if raw else {}
    except urllib.error.HTTPError as e:
        detail = e.read().decode(errors="replace")
        raise RuntimeError(f"ASC API {method} {url} -> HTTP {e.code}: {detail}") from e


def find_build(jwt: str, app_id: str, build_number: str) -> dict | None:
    path = (f"/builds?filter[app]={app_id}&filter[version]={build_number}"
            f"&fields[builds]=processingState,version,uploadedDate&limit=10")
    body = asc_request("GET", path, jwt)
    items = body.get("data", [])
    if not items:
        return None
    if len(items) > 1:
        print(f"warning: {len(items)} builds matched app={app_id} version={build_number} "
              "(multi-platform app record?) — using the most recently uploaded.", file=sys.stderr)
        items.sort(key=lambda b: b.get("attributes", {}).get("uploadedDate", ""), reverse=True)
    return items[0]


def poll_until_processed(key_path: str, key_id: str, issuer_id: str, app_id: str,
                          build_number: str, timeout_s: int, poll_interval_s: int) -> dict:
    deadline = time.monotonic() + timeout_s
    attempt = 0
    while True:
        attempt += 1
        jwt = make_jwt(key_path, key_id, issuer_id)  # fresh token per attempt — simple, always valid
        try:
            build = find_build(jwt, app_id, build_number)
        except RuntimeError as e:
            print(f"warning: poll attempt {attempt} failed: {e}", file=sys.stderr)
            build = None
        if build is not None:
            state = build.get("attributes", {}).get("processingState", "UNKNOWN")
            print(f"poll attempt {attempt}: build {build['id']} processingState={state}", file=sys.stderr)
            if state == "VALID":
                return build
            if state in ("FAILED", "INVALID"):
                print(f"error: build {build['id']} reached terminal state {state} — will not become VALID.",
                      file=sys.stderr)
                sys.exit(3)
            # PROCESSING (or an unrecognized future state) — keep polling.
        else:
            print(f"poll attempt {attempt}: no build found yet for app={app_id} version={build_number}",
                  file=sys.stderr)
        if time.monotonic() >= deadline:
            print(f"error: timed out after {timeout_s}s waiting for app={app_id} build={build_number} "
                  "to leave PROCESSING (or to appear at all).", file=sys.stderr)
            sys.exit(2)
        time.sleep(min(poll_interval_s, max(1, int(deadline - time.monotonic()))))


def find_existing_localization(jwt: str, build_id: str, locale: str) -> dict | None:
    path = f"/betaBuildLocalizations?filter[build]={build_id}&filter[locale]={locale}"
    body = asc_request("GET", path, jwt)
    items = body.get("data", [])
    return items[0] if items else None


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--key-path", required=True)
    ap.add_argument("--key-id", required=True)
    ap.add_argument("--issuer-id", required=True)
    ap.add_argument("--app-id", required=True, help="ASC numeric app id (ASC_APP_ID_<APP> in secrets/.env)")
    ap.add_argument("--build", required=True, help="CFBundleVersion / build number to match")
    ap.add_argument("--changelog", required=True, help="path to the What-to-Test changelog file")
    ap.add_argument("--locale", default="en-US")
    ap.add_argument("--timeout", type=int, default=900, help="seconds to poll before giving up (default 900 = 15min)")
    ap.add_argument("--poll-interval", type=int, default=20, help="seconds between polls (default 20)")
    ap.add_argument("--dry-run", action="store_true", help="print the payload that WOULD be sent; no write")
    args = ap.parse_args()

    try:
        with open(args.changelog, "r", encoding="utf-8") as f:
            whats_new = f.read().strip()
    except OSError as e:
        print(f"error: cannot read changelog file '{args.changelog}': {e}", file=sys.stderr)
        return 1
    if not whats_new:
        print(f"error: changelog file '{args.changelog}' is empty.", file=sys.stderr)
        return 1
    if len(whats_new) > WHATS_NEW_MAX:
        print(f"warning: changelog is {len(whats_new)} chars, truncating to {WHATS_NEW_MAX} "
              "(ASC whatsNew field limit).", file=sys.stderr)
        whats_new = whats_new[:WHATS_NEW_MAX]

    try:
        build = poll_until_processed(
            args.key_path, args.key_id, args.issuer_id, args.app_id, args.build,
            args.timeout, args.poll_interval,
        )
    except RuntimeError as e:
        print(f"error: {e}", file=sys.stderr)
        return 1

    build_id = build["id"]
    print(f"BUILD_ID={build_id}")
    print(f"STATE=VALID")

    jwt = make_jwt(args.key_path, args.key_id, args.issuer_id)
    try:
        existing = find_existing_localization(jwt, build_id, args.locale)
    except RuntimeError as e:
        print(f"error: {e}", file=sys.stderr)
        return 1

    if existing is not None:
        loc_id = existing["id"]
        method, url = "PATCH", f"/betaBuildLocalizations/{loc_id}"
        payload = {"data": {"type": "betaBuildLocalizations", "id": loc_id,
                             "attributes": {"whatsNew": whats_new}}}
        action = "UPDATE"
    else:
        method, url = "POST", "/betaBuildLocalizations"
        payload = {"data": {"type": "betaBuildLocalizations",
                             "attributes": {"locale": args.locale, "whatsNew": whats_new},
                             "relationships": {"build": {"data": {"type": "builds", "id": build_id}}}}}
        action = "CREATE"

    print(f"ACTION={action}")
    print(f"URL={API_BASE}{url}")
    print(json.dumps(payload, indent=2))

    if args.dry_run:
        print("DRY_RUN=1 — no write performed.", file=sys.stderr)
        return 0

    try:
        asc_request(method, url, jwt, payload)
    except RuntimeError as e:
        print(f"error: {e}", file=sys.stderr)
        return 1
    print(f"==> wrote whatsNew ({len(whats_new)} chars) to build {build_id} locale {args.locale} via {action}.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
