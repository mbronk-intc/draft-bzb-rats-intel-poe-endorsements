#!/usr/bin/env bash
#
# test-cddl.sh -- instance-level conformance test for the POE profile.
#
# Where scripts/validate-cddl.sh checks that the *grammar* is well-formed and
# composes with base CoRIM, this script checks that concrete *instances* behave:
# a base-correct POE CoRIM is accepted by both the authoritative base decoder and
# this profile, a forward-compatible one is still accepted, and a deliberately
# malformed one is rejected (guarding the guard). It is wired into `make test`.
#
# Engines, in order of authority:
#   1. conformance gate -- the Ruby `cddl` reference implementation run against
#                    BOTH roots: the base CoRIM grammar
#                    (cddl/imports/corim-autogen.cddl) concatenated with this
#                    profile, AND this profile's own root. Conformance is
#                    the CONJUNCTION -- the profile states only what POE
#                    constrains, so where it says `any` base still binds.
#                    Validating against the profile alone is insufficient by
#                    construction: it is self-contained, so base rules it never
#                    references -- `$profile-type-choice` among them -- are
#                    unreachable and cannot contradict it.
#   2. identifier recognition -- a direct CBOR structural assertion that
#                    `profile` (key 3) is `#6.32(tstr)` carrying the exact
#                    identifier. "The CoRIM was accepted" must not stand in
#                    for "the profile was recognized": a lenient decoder files
#                    an unrecognized key-3 in the extension bucket and still
#                    reports success.
#   3. pycddl     -- Rust-backed CDDL validator. Cannot parse the base grammar
#                    (it rejects base's `.b64u` control operator) and cannot
#                    validate the COSE_Sign1 envelope, so it validates the
#                    extracted CoRIM *payload* against this profile's grammar
#                    rooted at `poe-tagged-unsigned-corim-map`.
#   4. corim-cli  -- Rust CoRIM decoder (Azure/corim). Envelope smoke check
#                    only, not a gate. Observed at v0.2.0 (9fd3384):
#                    the strict path returns once the header decodes and so
#                    does not reach the CoMID (a bare `measurement-map` in
#                    place of `[+ measurement-map]` is accepted), and
#                    `--diagnose` flags the tagged `#6.32(tstr)` profile as an
#                    error -- it models the prelude type `uri` as a bare tstr
#                    (`ProfileChoice::Uri`). At that version it can gate
#                    neither the profile field nor the payload structure.
#   5. scripts/validate-cddl.sh -- grammar well-formedness, the RFC 8610 prelude
#                    guard, and the base-restatement allow-list.
#
# All tools are provisioned by the devcontainer; see .devcontainer. Engine 1
# requires the Ruby `cddl` gem and the base CoRIM grammar (fetched by
# scripts/validate-cddl.sh into cddl/imports/); without them the suite FAILS
# rather than silently degrading, because it is the authoritative gate. The
# optional engines are reported and skipped when absent.
#
# Usage:
#   scripts/test-cddl.sh            # run the full instance conformance suite
#   scripts/test-cddl.sh -h         # help
#
# Env overrides:
#   PROFILE_CDDL   profile grammar         (default: cddl/exports/intel-poe-profile.cddl)
#   FIXTURES_DIR   fixtures directory      (default: cddl/fixtures)
#   CORIM_CLI      corim-cli binary        (default: corim-cli on PATH)
#   PYCDDL_PY      python with pycddl+cbor2 (default: ~/.local/share/poe-tools/cddlvenv/bin/python)
#   ROOT_RULE      profile root rule       (default: poe-signed-corim)
#   PAYLOAD_RULE   payload root rule       (default: poe-tagged-unsigned-corim-map)
#   PROFILE_ID     expected profile identifier
#   BASE_CDDL      assembled base CoRIM grammar (default: cddl/imports/corim-autogen.cddl)
#
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$here"

PROFILE_CDDL="${PROFILE_CDDL:-cddl/exports/intel-poe-profile.cddl}"
FIXTURES_DIR="${FIXTURES_DIR:-cddl/fixtures}"
CORIM_CLI="${CORIM_CLI:-corim-cli}"
PYCDDL_PY="${PYCDDL_PY:-$HOME/.local/share/poe-tools/cddlvenv/bin/python}"
ROOT_RULE="${ROOT_RULE:-poe-signed-corim}"
PAYLOAD_RULE="${PAYLOAD_RULE:-poe-tagged-unsigned-corim-map}"
PROFILE_ID="${PROFILE_ID:-tag:intel.com,2026:tee.poe#1.0}"
BASE_CDDL="${BASE_CDDL:-cddl/imports/corim-autogen.cddl}"

# Positives MUST be accepted by base CoRIM and by this profile.
POSITIVES="poe-golden poe-golden-tstr-id poe-golden-leaf-only poe-golden-fwdcompat poe-golden-es384-legacy poe-golden-kid-unprotected"
# Negatives MUST be rejected by the PAIR. Either side may be the one that catches
# it -- poe-negative-base-binds is caught by base alone, which is the point.
NEGATIVES="poe-negative-bare poe-negative-untagged-profile poe-negative-base-binds"

golden="$FIXTURES_DIR/poe-golden.cbor"
fwd="$FIXTURES_DIR/poe-golden-fwdcompat.cbor"
neg="$FIXTURES_DIR/poe-negative-bare.cbor"
tstrid="$FIXTURES_DIR/poe-golden-tstr-id.cbor"
leaf="$FIXTURES_DIR/poe-golden-leaf-only.cbor"

case "${1:-}" in
  -h|--help) grep -E '^#( |$)' "$0" | sed -E 's/^# ?//'; exit 0 ;;
esac

fail=0
note() { printf '%s\n' "$*"; }
ok()   { printf '  OK:   %s\n' "$*"; }
bad()  { printf '  FAIL: %s\n' "$*"; fail=1; }

for f in $POSITIVES $NEGATIVES; do
  [[ -f "$FIXTURES_DIR/$f.cbor" ]] \
    || { echo "error: missing fixture $FIXTURES_DIR/$f.cbor (run 'make fixtures')" >&2; exit 2; }
done

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

# --- Engine 1: conformance gate (AUTHORITATIVE) ---------------------------------
#
# Only a root declaration is prepended -- the socket plugs that make base accept
# POE's private code points ship in the profile itself, so this validates the
# artifact consumers actually get, not a doctored copy.
command -v cddl >/dev/null 2>&1 || {
  echo "error: 'cddl' not found; it is the authoritative gate. Install: gem install cddl" >&2
  exit 127
}
[[ -f "$BASE_CDDL" ]] || {
  echo "base CoRIM grammar not cached; fetching into cddl/imports/ ..."
  scripts/update-cddl-imports.sh >/dev/null 2>&1 || true
}
[[ -f "$BASE_CDDL" ]] || {
  echo "error: base CoRIM grammar missing: $BASE_CDDL" >&2
  echo "       populate it with scripts/update-cddl-imports.sh (or set BASE_CDDL)." >&2
  exit 2
}

compose() {
  echo 'poe-conformance-base-root = tagged-unsigned-corim-map'
  echo
  cat "$BASE_CDDL"
  echo
  cat "$PROFILE_CDDL"
}
compose > "$work/base.cddl"
{ echo "poe-payload-root = $PAYLOAD_RULE"; echo; cat "$PROFILE_CDDL"; } > "$work/profile.cddl"

# Extract each fixture's CoRIM payload (element [2] of the COSE_Sign1 array).
if [[ -x "$PYCDDL_PY" ]]; then EXTRACT_PY="$PYCDDL_PY"; else EXTRACT_PY="python3"; fi
"$EXTRACT_PY" - "$work" "$FIXTURES_DIR" $POSITIVES $NEGATIVES <<'PY' || extract_rc=$?
import sys, cbor2
work, fixtures, names = sys.argv[1], sys.argv[2], sys.argv[3:]
for n in names:
    env = cbor2.loads(open("%s/%s.cbor" % (fixtures, n), "rb").read())
    open("%s/%s.payload.cbor" % (work, n), "wb").write(env.value[2])
PY
if [[ "${extract_rc:-0}" -ne 0 ]]; then
  echo "error: could not extract fixture payloads (needs cbor2)" >&2
  exit 2
fi

accepts() { cddl "$1" validate "$2" >/dev/null 2>&1; }

note "conformance gate: base CoRIM AND profile [AUTHORITATIVE]:"
for f in $POSITIVES; do
  base_ok=0; prof_ok=0
  accepts "$work/base.cddl" "$work/$f.payload.cbor" && base_ok=1
  accepts "$work/profile.cddl" "$work/$f.payload.cbor" && prof_ok=1
  if [[ $base_ok -eq 1 && $prof_ok -eq 1 ]]; then
    ok "$f accepted by base CoRIM and by the profile"
  elif [[ $base_ok -eq 0 ]]; then
    bad "$f REJECTED by base CoRIM -- not a legal CoRIM"
  else
    bad "$f REJECTED by the profile grammar"
  fi
done
for f in $NEGATIVES; do
  base_ok=0; prof_ok=0
  accepts "$work/base.cddl" "$work/$f.payload.cbor" && base_ok=1
  accepts "$work/profile.cddl" "$work/$f.payload.cbor" && prof_ok=1
  if [[ $base_ok -eq 1 && $prof_ok -eq 1 ]]; then
    bad "$f accepted by both -- the fixture no longer exercises a defect"
  elif [[ $base_ok -eq 0 && $prof_ok -eq 1 ]]; then
    ok "$f rejected (by base only -- proves the suite composes with base)"
  elif [[ $base_ok -eq 1 && $prof_ok -eq 0 ]]; then
    ok "$f rejected (by the profile only)"
  else
    ok "$f rejected by base CoRIM and by the profile"
  fi
done

# --- Engine 1b: COSE header placement -- kid bucket [AUTHORITATIVE] --------------
# The payload engines above extract element [2] and never see the COSE headers, so
# kid's bucket is invisible to them. Validate the FULL envelope against the
# profile's poe-signed-corim root to prove the grammar accepts kid in EITHER
# header map: poe-golden carries it in the protected map,
# poe-golden-kid-unprotected in the unprotected map. (CDDL cannot enforce
# exactly-one-bucket; that is prose.)
note "COSE header placement (kid accepted in either bucket, $ROOT_RULE root):"
{ echo "poe-signed-root = $ROOT_RULE"; echo; cat "$PROFILE_CDDL"; } > "$work/signed.cddl"
for pair in poe-golden:protected poe-golden-kid-unprotected:unprotected; do
  f="${pair%%:*}"; bucket="${pair##*:}"
  if accepts "$work/signed.cddl" "$FIXTURES_DIR/$f.cbor"; then
    ok "$f envelope accepted (kid in $bucket header)"
  else
    bad "$f envelope REJECTED by $ROOT_RULE (kid in $bucket header)"
  fi
done

# --- Engine 2: profile-identifier recognition (AUTHORITATIVE) -------------------
# Decoder-level guard, independent of any CDDL tool's matching order.
# One positive assertion + one negative fixture is the whole guard for this
# encoding; the generator builds key 3 identically for every fixture, so asserting
# it on each of them would add repetition, not coverage.
note "profile identifier recognition (key 3 decodes as a uri):"
PROFILE_ID="$PROFILE_ID" WORK="$work" \
"$EXTRACT_PY" - <<'PY' || fail=1
import os, sys, cbor2
want, work = os.environ["PROFILE_ID"], os.environ["WORK"]
rc = 0
v = cbor2.loads(open("%s/poe-golden.payload.cbor" % work, "rb").read()).value.get(3)
if isinstance(v, cbor2.CBORTag) and v.tag == 32 and v.value == want:
    print("  OK:   golden carries profile as #6.32(%r)" % want)
else:
    print("  FAIL: golden profile is %r -- expected #6.32(%r)" % (v, want)); rc = 1
neg = "%s/poe-negative-untagged-profile.payload.cbor" % work
if isinstance(cbor2.loads(open(neg, "rb").read()).value.get(3), cbor2.CBORTag):
    print("  FAIL: the untagged-profile negative is tagged -- fixture is wrong"); rc = 1
else:
    print("  OK:   untagged-profile negative is genuinely untagged")
sys.exit(rc)
PY

# --- Engine 3: pycddl on the extracted CoRIM payload ----------------------------
if [[ -x "$PYCDDL_PY" ]] && "$PYCDDL_PY" -c 'import pycddl, cbor2' 2>/dev/null; then
  note "pycddl (profile payload structural check):"
  # NOTE: this engine validates only the extracted CoRIM *payload*. x5chain lives
  # in the unprotected header, so the leaf-only fixture's payload is identical to
  # golden here -- its bare-bstr shape is exercised by corim-cli below. It is
  # therefore intentionally omitted from this loop.
  PROFILE_CDDL="$PROFILE_CDDL" PAYLOAD_RULE="$PAYLOAD_RULE" WORK="$work" \
  "$PYCDDL_PY" - <<'PY' || fail=1
import os, sys, cbor2, pycddl
prof = open(os.environ["PROFILE_CDDL"]).read()
schema = pycddl.Schema("poe-payload-root = %s\n\n%s" % (os.environ["PAYLOAD_RULE"], prof))
work = os.environ["WORK"]
cases = [("poe-golden", True), ("poe-golden-fwdcompat", True), ("poe-golden-tstr-id", True),
         ("poe-negative-bare", False), ("poe-negative-untagged-profile", False)]
rc = 0
for name, want_ok in cases:
    try:
        schema.validate_cbor(open("%s/%s.payload.cbor" % (work, name), "rb").read())
        got_ok = True
    except pycddl.ValidationError:
        got_ok = False
    verdict = "accepted" if got_ok else "rejected"
    if got_ok == want_ok:
        print("  OK:   %s payload %s" % (name, verdict))
    else:
        print("  FAIL: %s payload %s" % (name, verdict)); rc = 1
sys.exit(rc)
PY
else
  note "pycddl: not available -- skipping payload structural check (optional engine)"
fi

# --- Engine 4: corim-cli envelope smoke check (NOT a gate; see header) ----------
if command -v "$CORIM_CLI" >/dev/null 2>&1; then
  note "corim-cli (COSE envelope smoke check -- NOT a conformance gate):"
  for f in $POSITIVES; do
    "$CORIM_CLI" validate --skip-expiry "$FIXTURES_DIR/$f.cbor" >/dev/null 2>&1 \
      && ok "$f envelope decodes" || bad "$f envelope rejected by corim-cli"
  done
else
  note "corim-cli: not available -- skipping envelope smoke check (optional engine)"
fi

# --- Engine 5: grammar well-formedness + structural guards ----------------------
note "grammar well-formedness and structural guards (validate-cddl.sh):"
if scripts/validate-cddl.sh >/dev/null 2>&1; then
  ok "profile grammar composes with base CoRIM + Intel Profile; no prelude shadowing"
else
  bad "validate-cddl.sh reported a grammar problem"
fi

echo
if [[ "$fail" -eq 0 ]]; then
  echo "PASS: POE profile instance conformance (base-legal, profile recognized, negatives rejected)."
else
  echo "FAIL: POE profile instance conformance -- see failures above." >&2
  exit 1
fi
