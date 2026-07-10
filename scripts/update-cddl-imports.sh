#!/usr/bin/env bash
#
# update-cddl-imports.sh -- populate/refresh the grammar fetch cache under cddl/imports/.
#
# This profile is a *narrowing* of base CoRIM. To validate it (scripts/validate-cddl.sh,
# `make check-cddl`) the assembled base CoRIM grammar is needed as a cross-check input.
# It is not vendored in the repo: validate-cddl.sh fetches it ad-hoc. This script is an
# optional convenience that caches a copy under cddl/imports/ (git-ignored) for offline
# or repeated runs, fetched from the upstream release artifact.
#
# The base CoRIM grammar is published as a single self-contained `corim-autogen.cddl`
# release asset, tagged `cddl-draft-ietf-rats-corim-<nn>` (see that repo's
# RELEASE_CDDL.md). We pin the revision matching this draft's normative reference.
#
# Usage:
#   scripts/update-cddl-imports.sh            # fetch the default pinned revision
#   scripts/update-cddl-imports.sh -r 11      # fetch a specific CoRIM revision
#   scripts/update-cddl-imports.sh -n         # dry-run: show what would be fetched
#   scripts/update-cddl-imports.sh -h         # help
#
# Env overrides:
#   CORIM_REV         CoRIM CDDL release revision <nn>   (default: 10)
#   INTEL_PROFILE_TAG Intel Profile CDDL release tag      (default: cddl-56686b6)
#   IMPORTS_DIR       destination directory              (default: cddl/imports)
#
# After running, review the diff and commit the updated import(s). If the base
# revision changes, also bump CORIM_REV in scripts/validate-cddl.sh and the
# {{CoRIM}} normative reference in the draft so everything stays in lock-step.
#
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$here"

CORIM_REV="${CORIM_REV:-10}"
INTEL_PROFILE_TAG="${INTEL_PROFILE_TAG:-cddl-56686b6}"
IMPORTS_DIR="${IMPORTS_DIR:-cddl/imports}"
dry_run=0

while getopts ":r:nh" opt; do
  case "$opt" in
    r) CORIM_REV="$OPTARG" ;;
    n) dry_run=1 ;;
    h) grep -E '^#( |$)' "$0" | sed -E 's/^# ?//'; exit 0 ;;
    *) echo "usage: $0 [-r corim_rev] [-n] [-h]" >&2; exit 2 ;;
  esac
done

# Each import: "<destination-filename>=<source-url>". Add more lines here if the
# validation ever needs additional pinned base grammars.
base_tag="cddl-draft-ietf-rats-corim-${CORIM_REV}"
base_url="https://github.com/ietf-rats-wg/draft-ietf-rats-corim/releases/download/${base_tag}/corim-autogen.cddl"
# The Intel Profile's self-contained assembled Intel-CoRIM grammar (declares the
# shared tee.platform-instance-id = -101 that this profile reuses); used only by
# validate-cddl.sh's Intel conformance cross-check. Published on the Intel
# Profile repo's CDDL release (commit-pinned tag).
intel_url="https://github.com/fchinchilla/draft-cds-rats-intel-corim-profile/releases/download/${INTEL_PROFILE_TAG}/icorim-autogen.cddl"
imports=(
  "corim-autogen.cddl=${base_url}"
  "icorim-autogen.cddl=${intel_url}"
)

command -v curl >/dev/null 2>&1 || {
  echo "error: 'curl' not found (needed to fetch imports)" >&2
  exit 127
}

mkdir -p "$IMPORTS_DIR"
echo "refreshing grammar imports (CoRIM rev ${CORIM_REV}, Intel Profile ${INTEL_PROFILE_TAG}) into ${IMPORTS_DIR}/"

rc=0
for entry in "${imports[@]}"; do
  name="${entry%%=*}"
  url="${entry#*=}"
  dest="$IMPORTS_DIR/$name"

  if [[ "$dry_run" -eq 1 ]]; then
    echo "  would fetch: $url -> $dest"
    continue
  fi

  tmp="$(mktemp)"
  if curl -fsSL "$url" -o "$tmp"; then
    if [[ -f "$dest" ]] && cmp -s "$tmp" "$dest"; then
      echo "  unchanged:   $dest"
      rm -f "$tmp"
    else
      mv "$tmp" "$dest"
      echo "  updated:     $dest ($(wc -l < "$dest") lines)"
    fi
  else
    echo "  ERROR:       failed to fetch $url" >&2
    rm -f "$tmp"
    rc=1
  fi
done

exit "$rc"
