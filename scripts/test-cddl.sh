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
# Engines (defence in depth -- see RELEASE_CDDL.md):
#   1. corim-cli  -- Microsoft's Rust CoRIM decoder (Azure/corim), targets
#                    draft-ietf-rats-corim-10. Validates the FULL signed COSE_Sign1
#                    envelope. This is the AUTHORITATIVE base-conformance gate: the
#                    consumer of POE data uses this decoder, so its acceptance is
#                    the most meaningful signal.
#   2. pycddl     -- Rust-backed CDDL validator. Cannot validate the COSE_Sign1
#                    envelope (tool limitation), so it validates the extracted
#                    CoRIM *payload* against this profile's grammar rooted at
#                    `poe-tagged-unsigned-corim-map` -- this exercises the CoMID /
#                    triples / measurement structure precisely.
#   3. scripts/validate-cddl.sh -- the Ruby `cddl` grammar/well-formedness check.
#
# All three tools are provisioned by the devcontainer; see .devcontainer. Missing
# tools are reported and (for the optional engines) skipped, not fatal, so the
# test degrades gracefully outside the container.
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

golden="$FIXTURES_DIR/poe-golden.cbor"
fwd="$FIXTURES_DIR/poe-golden-fwdcompat.cbor"
neg="$FIXTURES_DIR/poe-negative-bare.cbor"

case "${1:-}" in
  -h|--help) grep -E '^#( |$)' "$0" | sed -E 's/^# ?//'; exit 0 ;;
esac

fail=0
note() { printf '%s\n' "$*"; }
ok()   { printf '  OK:   %s\n' "$*"; }
bad()  { printf '  FAIL: %s\n' "$*"; fail=1; }

for f in "$golden" "$fwd" "$neg"; do
  [[ -f "$f" ]] || { echo "error: missing fixture $f (run 'make fixtures')" >&2; exit 2; }
done

# --- Engine 1: corim-cli (authoritative, full signed envelope) ------------------
if command -v "$CORIM_CLI" >/dev/null 2>&1; then
  note "corim-cli (authoritative base draft-10 decoder):"
  "$CORIM_CLI" validate --skip-expiry "$golden" >/dev/null 2>&1 \
    && ok "golden accepted"            || bad "golden rejected by corim-cli"
  "$CORIM_CLI" validate --skip-expiry "$fwd" >/dev/null 2>&1 \
    && ok "forward-compat accepted"    || bad "forward-compat rejected by corim-cli"
  if "$CORIM_CLI" validate --skip-expiry "$neg" >/dev/null 2>&1; then
    bad "negative (bare measurement) WRONGLY accepted by corim-cli"
  else
    ok "negative rejected"
  fi
else
  echo "error: corim-cli not found (the authoritative gate); install per .devcontainer" >&2
  exit 127
fi

# --- Engine 2: pycddl on the extracted CoRIM payload ----------------------------
if [[ -x "$PYCDDL_PY" ]] && "$PYCDDL_PY" -c 'import pycddl, cbor2' 2>/dev/null; then
  note "pycddl (profile payload structural check):"
  PROFILE_CDDL="$PROFILE_CDDL" PAYLOAD_RULE="$PAYLOAD_RULE" \
  GOLDEN="$golden" FWD="$fwd" NEG="$neg" "$PYCDDL_PY" - <<'PY' || fail=1
import os, sys, cbor2, pycddl
prof = open(os.environ["PROFILE_CDDL"]).read()
schema = pycddl.Schema("poe-payload-root = %s\n\n%s" % (os.environ["PAYLOAD_RULE"], prof))
def payload(fn):
    env = cbor2.loads(open(fn, "rb").read())     # Tag(18, [prot, unprot, payload, sig])
    return env.value[2]
rc = 0
for label, fn, want_ok in [("golden", os.environ["GOLDEN"], True),
                           ("forward-compat", os.environ["FWD"], True),
                           ("negative", os.environ["NEG"], False)]:
    try:
        schema.validate_cbor(payload(fn)); got_ok = True
    except pycddl.ValidationError:
        got_ok = False
    if got_ok == want_ok:
        print("  OK:   %s payload %s" % (label, "accepted" if got_ok else "rejected"))
    else:
        print("  FAIL: %s payload %s" % (label, "accepted" if got_ok else "rejected")); rc = 1
sys.exit(rc)
PY
else
  note "pycddl: not available -- skipping payload structural check (optional engine)"
fi

# --- Engine 3: grammar well-formedness ------------------------------------------
note "grammar well-formedness (validate-cddl.sh):"
if scripts/validate-cddl.sh >/dev/null 2>&1; then
  ok "profile grammar composes with base CoRIM + Intel Profile"
else
  bad "validate-cddl.sh reported a grammar problem"
fi

echo
if [[ "$fail" -eq 0 ]]; then
  echo "PASS: POE profile instance conformance (golden accepted, forward-compat accepted, negative rejected)."
else
  echo "FAIL: POE profile instance conformance -- see failures above." >&2
  exit 1
fi
