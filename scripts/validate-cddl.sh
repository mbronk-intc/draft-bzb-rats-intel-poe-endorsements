#!/usr/bin/env bash
#
# validate-cddl.sh -- validate the POE CoRIM profile CDDL appendix.
#
# The POE profile (Appendix "CDDL") is a *narrowing* of base CoRIM: to check it,
# the base CoRIM grammar must be concatenated with the profile fragment extracted
# from the draft, and the combined grammar fed to a CDDL tool. This is
# make-independent: it only needs the `cddl` gem (present in the devcontainer)
# plus `wget`/`curl` for the base grammar.
#
# NOTE ON THE BASE GRAMMAR: the CoRIM repo's `cddl/corim.cddl` is only a 4-line
# *root stub*; the real grammar lives in ~140 per-rule fragment files that the
# upstream build assembles (via `cddlc`) into a single file. Per that repo's
# RELEASE_CDDL.md, the assembled grammar is published as a release artifact named
# `corim-autogen.cddl` under a `cddl-draft-ietf-rats-corim-<nn>` tag. We consume
# that self-contained artifact directly, so no fragment reassembly is needed.
#
# Usage:
#   scripts/validate-cddl.sh                 # extract profile CDDL, fetch base, validate grammar
#   scripts/validate-cddl.sh -i example.cbor # also validate a CBOR/EDN instance against it
#   scripts/validate-cddl.sh -g              # generate a sample instance from the grammar
#
# Env overrides:
#   DRAFT       path to the draft .md              (default: the repo's single draft-*.md)
#   CORIM_REV   CoRIM CDDL release revision <nn>   (default: 10, i.e. draft-ietf-rats-corim-10)
#   BASE_CDDL   path/URL to assembled base CDDL    (default: the corim-autogen.cddl release artifact)
#   ROOT_RULE   top-level CDDL rule                (default: poe-signed-corim)
#
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$here"

ROOT_RULE="${ROOT_RULE:-poe-signed-corim}"
# Base CoRIM CDDL. The draft's normative reference is draft-ietf-rats-corim-10, so
# we default to the matching assembled `corim-autogen.cddl` release artifact.
# Override CORIM_REV to track a different draft revision, or BASE_CDDL to pin a
# local copy / different URL entirely.
CORIM_REV="${CORIM_REV:-10}"
BASE_CDDL_URL_DEFAULT="https://github.com/ietf-rats-wg/draft-ietf-rats-corim/releases/download/cddl-draft-ietf-rats-corim-${CORIM_REV}/corim-autogen.cddl"
BASE_CDDL="${BASE_CDDL:-$BASE_CDDL_URL_DEFAULT}"

# Locate the draft source (single draft-*.md at repo root, or $DRAFT).
DRAFT="${DRAFT:-$(ls -1 draft-*.md 2>/dev/null | head -n1 || true)}"
if [[ -z "${DRAFT:-}" || ! -f "$DRAFT" ]]; then
  echo "error: draft markdown not found (set DRAFT=path/to/draft.md)" >&2
  exit 2
fi

instance=""
generate=0
while getopts ":i:gh" opt; do
  case "$opt" in
    i) instance="$OPTARG" ;;
    g) generate=1 ;;
    h) grep -E '^#( |$)' "$0" | sed -E 's/^# ?//'; exit 0 ;;
    *) echo "usage: $0 [-i instance.cbor] [-g] [-h]" >&2; exit 2 ;;
  esac
done

command -v cddl >/dev/null 2>&1 || {
  echo "error: 'cddl' not found. Install with: gem install cddl" >&2
  exit 127
}

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
profile="$work/poe-profile.cddl"
base="$work/corim.cddl"
combined="$work/combined.cddl"

# --- 1. Extract the profile CDDL fragment from the first ```cddl / ~~~ cddl block.
awk '
  /^[~`]{3,}[[:space:]]*cddl([[:space:]]|$)/ { inblk=1; next }
  inblk && /^[~`]{3,}[[:space:]]*$/          { exit }
  inblk                                      { print }
' "$DRAFT" > "$profile"

if [[ ! -s "$profile" ]]; then
  echo "error: no '~~~ cddl' / '\`\`\`cddl' fenced block found in $DRAFT" >&2
  exit 3
fi
echo "extracted profile CDDL: $(wc -l < "$profile") lines from $DRAFT"

# --- 2. Obtain the base CoRIM CDDL (local file or URL).
if [[ -f "$BASE_CDDL" ]]; then
  cp "$BASE_CDDL" "$base"
  echo "base CoRIM CDDL: local $BASE_CDDL"
else
  echo "fetching base CoRIM CDDL: $BASE_CDDL"
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL "$BASE_CDDL" -o "$base"
  elif command -v wget >/dev/null 2>&1; then
    wget -qO "$base" "$BASE_CDDL"
  else
    echo "error: need curl or wget to fetch base CDDL (or set BASE_CDDL=local path)" >&2
    exit 4
  fi
fi

# --- 3. Concatenate: base first, profile fragment second (profile narrows base).
{
  cat "$base"
  echo
  echo "; ===== POE profile fragment (from $DRAFT) ====="
  cat "$profile"
} > "$combined"

# --- 4. Validate the combined grammar (and optionally an instance / a sample).
if [[ -n "$instance" ]]; then
  echo "validating instance '$instance' against rule '$ROOT_RULE'..."
  cddl "$combined" validate "$instance"
  echo "OK: instance conforms."
elif [[ "$generate" -eq 1 ]]; then
  echo "generating a sample instance for rule '$ROOT_RULE'..."
  cddl "$combined" generate
else
  echo "checking combined grammar is well-formed..."
  # `cddl <grammar> generate` parses the whole grammar; a parse error here means
  # the profile fragment does not compose with the base grammar. It generates
  # from the first rule (base `corim`), so every unreachable rule -- all the
  # `poe-*` profile rules and imported `eatmc.*` rules -- is reported as an
  # "Unused rule" advisory; those are benign, so filter them out while keeping
  # any genuine diagnostics.
  cddl "$combined" generate >/dev/null 2> >(grep -v '^\*\*\* Unused rule ' >&2)
  echo "OK: combined grammar parses (base CoRIM + POE profile fragment)."
  echo "    root rule: $ROOT_RULE"
  echo "    to check an instance: $0 -i path/to/instance.cbor"
fi
