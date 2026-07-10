#!/usr/bin/env bash
#
# fuzz-cddl.sh -- OPTIONAL, manual-only fuzz of the POE profile grammar.
#
# NOT wired into `make check` or CI: `cddl generate` produces structurally-valid
# but semantically-random instances (random signer, placeholder signature, random
# optional fields), so downstream decoders give noisy, non-deterministic results.
# It is a breadth aid a maintainer can run by hand (`make fuzz`) to shake out
# shapes the golden fixtures miss -- never a gate.
#
# For each generated sample it: converts the EDN to binary CBOR, then reports how
# the authoritative corim-cli and the pycddl payload check react. Non-zero exits
# are printed, never fatal.
#
# Usage:
#   scripts/fuzz-cddl.sh [-n COUNT]     # default COUNT=20
#   scripts/fuzz-cddl.sh -h
#
# Env overrides: PROFILE_CDDL, CORIM_CLI, PYCDDL_PY, ROOT_RULE, PAYLOAD_RULE.
#
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$here"

PROFILE_CDDL="${PROFILE_CDDL:-cddl/exports/intel-poe-profile.cddl}"
CORIM_CLI="${CORIM_CLI:-corim-cli}"
PYCDDL_PY="${PYCDDL_PY:-$HOME/.local/share/poe-tools/cddlvenv/bin/python}"
ROOT_RULE="${ROOT_RULE:-poe-signed-corim}"
PAYLOAD_RULE="${PAYLOAD_RULE:-poe-tagged-unsigned-corim-map}"
count=20

while getopts ":n:h" opt; do
  case "$opt" in
    n) count="$OPTARG" ;;
    h) grep -E '^#( |$)' "$0" | sed -E 's/^# ?//'; exit 0 ;;
    *) echo "usage: $0 [-n count]" >&2; exit 2 ;;
  esac
done

command -v cddl >/dev/null 2>&1 || { echo "error: 'cddl' gem not found" >&2; exit 127; }
command -v diag2cbor.rb >/dev/null 2>&1 || { echo "error: diag2cbor.rb (cbor-diag) not found" >&2; exit 127; }

work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
printf 'poe-fuzz-root = %s\n\n' "$ROOT_RULE" | cat - "$PROFILE_CDDL" > "$work/prof.cddl"

echo "fuzzing $count generated instances from $ROOT_RULE (non-gating)..."
gen_ok=0 cli_ok=0 cli_rej=0 conv_err=0
for i in $(seq 1 "$count"); do
  if ! cddl "$work/prof.cddl" generate 2>/dev/null > "$work/s.edn"; then conv_err=$((conv_err+1)); continue; fi
  if ! diag2cbor.rb "$work/s.edn" > "$work/s.cbor" 2>/dev/null; then conv_err=$((conv_err+1)); continue; fi
  gen_ok=$((gen_ok+1))
  if command -v "$CORIM_CLI" >/dev/null 2>&1; then
    if "$CORIM_CLI" validate --skip-expiry "$work/s.cbor" >/dev/null 2>&1; then cli_ok=$((cli_ok+1)); else cli_rej=$((cli_rej+1)); fi
  fi
done
echo "  generated+converted: $gen_ok/$count (convert errors: $conv_err)"
echo "  corim-cli accepted:  $cli_ok    rejected: $cli_rej"
echo "  (rejections are expected/noise -- generated samples carry random placeholder values.)"
