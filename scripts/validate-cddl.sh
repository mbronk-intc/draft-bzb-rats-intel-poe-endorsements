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
#   scripts/validate-cddl.sh                 # load profile CDDL, fetch base, validate grammar
#   scripts/validate-cddl.sh -i example.cbor # also validate a CBOR/EDN instance against it
#   scripts/validate-cddl.sh -g              # generate a sample instance from the grammar
#   scripts/validate-cddl.sh -I              # skip the Intel Profile conformance cross-check
#
# By default this runs TWO checks:
#   1. base composition  -- the profile composes with (narrows) base CoRIM.
#   2. Intel conformance -- the profile's reused identifiers (notably the shared
#      tee.platform-instance-id = -101) still agree with the real Intel Profile
#      grammar, by composing the profile against the Intel-CoRIM assembly and
#      parsing from the profile root. Skip it with -I / INTEL_CHECK=0.
#
# Env overrides:
#   PROFILE_CDDL  path to the profile CDDL file    (default: cddl/exports/intel-poe-profile.cddl)
#   DRAFT         path to the draft .md            (default: the repo's single draft-*.md)
#   CORIM_REV     CoRIM CDDL release revision <nn> (default: 10, i.e. draft-ietf-rats-corim-10)
#   BASE_CDDL     path/URL to assembled base CDDL  (default: cddl/imports/corim-autogen.cddl if cached, else fetched from the release artifact URL)
#   INTEL_CHECK   run the Intel conformance check  (default: 1; set 0 or pass -I to skip)
#   INTEL_PROFILE_TAG  Intel Profile CDDL release tag (default: cddl-56686b6)
#   INTEL_PROFILE_CDDL path/URL to the assembled Intel-CoRIM grammar (default: cddl/imports/icorim-autogen.cddl if cached, else fetched from the release artifact URL)
#   ROOT_RULE     top-level CDDL rule              (default: poe-signed-corim)
#
# The profile grammar lives in a standalone file (cddl/exports/intel-poe-profile.cddl),
# which the draft pulls in via a kramdown-rfc `{::include}` directive. This script
# uses that file directly as the source of truth; if it is missing, it falls back
# to extracting the first `~~~ cddl` fenced block from the draft.
#
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$here"

ROOT_RULE="${ROOT_RULE:-poe-signed-corim}"
# Base CoRIM CDDL. The draft's normative reference is draft-ietf-rats-corim-10, so
# we default to the matching assembled `corim-autogen.cddl`. The base grammar is
# not vendored in this repo; by default we fetch the release artifact ad-hoc at
# check time. A local cache under cddl/imports/ (git-ignored, populated by
# scripts/update-cddl-imports.sh) is used automatically when present, for offline
# or repeated runs. Override CORIM_REV to track a different draft revision, or
# BASE_CDDL to point at a local copy / different URL entirely.
#
# To populate the offline cache:
#   scripts/update-cddl-imports.sh          # or, manually:
#   curl -fsSL \
#     https://github.com/ietf-rats-wg/draft-ietf-rats-corim/releases/download/cddl-draft-ietf-rats-corim-10/corim-autogen.cddl \
#     -o cddl/imports/corim-autogen.cddl
CORIM_REV="${CORIM_REV:-10}"
BASE_CDDL_LOCAL_DEFAULT="cddl/imports/corim-autogen.cddl"
BASE_CDDL_URL_DEFAULT="https://github.com/ietf-rats-wg/draft-ietf-rats-corim/releases/download/cddl-draft-ietf-rats-corim-${CORIM_REV}/corim-autogen.cddl"
if [[ -n "${BASE_CDDL:-}" ]]; then
  :  # caller-supplied
elif [[ -f "$BASE_CDDL_LOCAL_DEFAULT" ]]; then
  BASE_CDDL="$BASE_CDDL_LOCAL_DEFAULT"
else
  BASE_CDDL="$BASE_CDDL_URL_DEFAULT"
fi

# Intel Profile conformance cross-check. The POE profile reuses identifiers from
# the Intel Profile for Remote Attestation (notably tee.platform-instance-id =
# -101). To catch drift, we compose the profile against the Intel Profile's
# self-contained assembled Intel-CoRIM grammar (icorim-autogen.cddl) and parse
# from the profile root. As with the base grammar we prefer a local cache under
# cddl/imports/ (git-ignored) and otherwise fetch the release artifact ad-hoc.
# The Intel grammar ships on the Intel Profile repo's CDDL release (commit-pinned
# tag). Disable this check with -I or INTEL_CHECK=0.
INTEL_CHECK="${INTEL_CHECK:-1}"
INTEL_PROFILE_TAG="${INTEL_PROFILE_TAG:-cddl-56686b6}"
INTEL_PROFILE_LOCAL_DEFAULT="cddl/imports/icorim-autogen.cddl"
INTEL_PROFILE_URL_DEFAULT="https://github.com/fchinchilla/draft-cds-rats-intel-corim-profile/releases/download/${INTEL_PROFILE_TAG}/icorim-autogen.cddl"
if [[ -n "${INTEL_PROFILE_CDDL:-}" ]]; then
  :  # caller-supplied
elif [[ -f "$INTEL_PROFILE_LOCAL_DEFAULT" ]]; then
  INTEL_PROFILE_CDDL="$INTEL_PROFILE_LOCAL_DEFAULT"
else
  INTEL_PROFILE_CDDL="$INTEL_PROFILE_URL_DEFAULT"
fi

# Standalone profile CDDL (source of truth; the draft includes it verbatim).
PROFILE_CDDL="${PROFILE_CDDL:-cddl/exports/intel-poe-profile.cddl}"

# Locate the draft source (single draft-*.md at repo root, or $DRAFT) -- used
# only as a fallback when the standalone profile CDDL is absent.
DRAFT="${DRAFT:-$(ls -1 draft-*.md 2>/dev/null | head -n1 || true)}"
if [[ ! -f "$PROFILE_CDDL" && ( -z "${DRAFT:-}" || ! -f "$DRAFT" ) ]]; then
  echo "error: neither profile CDDL ($PROFILE_CDDL) nor draft markdown found" >&2
  exit 2
fi

instance=""
generate=0
while getopts ":i:gIh" opt; do
  case "$opt" in
    i) instance="$OPTARG" ;;
    g) generate=1 ;;
    I) INTEL_CHECK=0 ;;
    h) grep -E '^#( |$)' "$0" | sed -E 's/^# ?//'; exit 0 ;;
    *) echo "usage: $0 [-i instance.cbor] [-g] [-I] [-h]" >&2; exit 2 ;;
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

# --- 1. Obtain the profile CDDL: prefer the standalone file (source of truth),
#        otherwise extract the first ```cddl / ~~~ cddl block from the draft.
if [[ -f "$PROFILE_CDDL" ]]; then
  cp "$PROFILE_CDDL" "$profile"
  echo "profile CDDL: $(wc -l < "$profile") lines from $PROFILE_CDDL"
else
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
fi

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
  echo "; ===== POE profile fragment ====="
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
  # `cddl <grammar> generate` parses the whole grammar and generates a sample
  # from the first rule. A *conflicting* rule (e.g. an incompatible redefinition
  # of a restated base alias) makes it exit non-zero with a "Duplicate rule"
  # error; benign advisories -- unreachable "Unused rule"s and the value-identical
  # `cose-label` restatement -- exit zero. So we trust the exit code and only show
  # stderr when it actually fails. No output filtering.
  if ! cddl "$combined" generate >/dev/null 2>"$work/base.err"; then
    cat "$work/base.err" >&2
    echo "error: profile does not compose with base CoRIM." >&2
    exit 1
  fi
  echo "OK: combined grammar parses (base CoRIM + POE profile fragment)."
  echo "    root rule: $ROOT_RULE"
  echo "    to check an instance: $0 -i path/to/instance.cbor"
fi

# --- 5. Intel Profile conformance cross-check (default mode only; -I / INTEL_CHECK=0
#        to skip). This profile reuses tee.platform-instance-id from the Intel
#        Profile. Because this profile pins *closed* measurement-values maps, the
#        Intel socket rules are unreachable from our root, so merely composing the
#        two grammars does NOT verify the shared code point. We therefore do a
#        targeted drift check: extract the Intel Profile's code point for
#        tee.platform-instance-id and assert it equals ours. We also compose the
#        two grammars as a structural sanity check (catches an incompatible
#        redeclaration of a restated base alias such as `cose-label`).
if [[ "$INTEL_CHECK" == "1" && -z "$instance" && "$generate" -eq 0 ]]; then
  intel="$work/icorim.cddl"
  if [[ -f "$INTEL_PROFILE_CDDL" ]]; then
    cp "$INTEL_PROFILE_CDDL" "$intel"
    echo "Intel Profile CDDL: local $INTEL_PROFILE_CDDL"
  else
    echo "fetching Intel Profile CDDL: $INTEL_PROFILE_CDDL"
    if command -v curl >/dev/null 2>&1; then
      curl -fsSL "$INTEL_PROFILE_CDDL" -o "$intel"
    elif command -v wget >/dev/null 2>&1; then
      wget -qO "$intel" "$INTEL_PROFILE_CDDL"
    else
      echo "error: need curl or wget to fetch Intel Profile CDDL (or set INTEL_PROFILE_CDDL=local path, or -I to skip)" >&2
      exit 4
    fi
  fi

  echo "checking Intel Profile conformance (shared code-point agreement)..."

  # (a) Value agreement -- the drift guard with teeth. The Intel grammar declares
  #     the key as an inline group label: `&(tee.platform-instance-id: <N>)`; this
  #     profile declares it as a plain rule: `tee.platform-instance-id = <N>`.
  #     Extract both and require they match.
  intel_piid="$(grep -oE 'tee\.platform-instance-id:[[:space:]]*-?[0-9]+' "$intel" | grep -oE '\-?[0-9]+' | head -n1 || true)"
  ours_piid="$(grep -oE '^tee\.platform-instance-id[[:space:]]*=[[:space:]]*-?[0-9]+' "$profile" | grep -oE '\-?[0-9]+' | head -n1 || true)"
  if [[ -z "$intel_piid" ]]; then
    echo "error: could not find tee.platform-instance-id code point in the Intel grammar" >&2
    echo "       (Intel Profile tag $INTEL_PROFILE_TAG may have changed shape; check $INTEL_PROFILE_CDDL, or -I to skip)" >&2
    exit 5
  fi
  if [[ -z "$ours_piid" ]]; then
    echo "error: could not find 'tee.platform-instance-id = <N>' in $PROFILE_CDDL" >&2
    exit 5
  fi
  if [[ "$intel_piid" != "$ours_piid" ]]; then
    echo "error: tee.platform-instance-id code point DRIFTED from the Intel Profile" >&2
    echo "       Intel Profile ($INTEL_PROFILE_TAG): $intel_piid" >&2
    echo "       this profile ($PROFILE_CDDL): $ours_piid" >&2
    exit 5
  fi
  echo "    tee.platform-instance-id = $ours_piid matches the Intel Profile ($INTEL_PROFILE_TAG)."

  # (b) Structural sanity -- compose the profile with the Intel-CoRIM grammar and
  #     parse from the profile root. The one restated base alias the profile
  #     shares with the Intel grammar (`cose-label`) is value-identical, so it
  #     composes as a benign identical redefinition; an *incompatible* redefinition
  #     would exit non-zero with a "Duplicate rule" error. As above, we trust the
  #     exit code and only surface stderr on failure -- no rule-dropping, no filter.
  intel_combined="$work/combined.intel.cddl"
  {
    echo "poe-conformance-start = $ROOT_RULE"   # force generation from the profile root
    echo
    cat "$intel"
    echo
    echo "; ===== POE profile fragment ====="
    cat "$profile"
  } > "$intel_combined"

  if ! cddl "$intel_combined" generate >/dev/null 2>"$work/intel.err"; then
    cat "$work/intel.err" >&2
    echo "error: profile does not compose with the Intel Profile grammar." >&2
    exit 5
  fi
  echo "OK: profile composes with the Intel Profile grammar and the shared code point agrees."
fi
