# Releasing the POE profile CDDL

The POE profile grammar lives in a standalone file,
[`cddl/exports/intel-poe-profile.cddl`](cddl/exports/intel-poe-profile.cddl), and
is pulled into the draft via a kramdown-rfc `{::include}` directive. This file
can be published as a downloadable artefact, using the same convention as base
CoRIM
([ietf-rats-wg/draft-ietf-rats-corim](https://github.com/ietf-rats-wg/draft-ietf-rats-corim/blob/main/RELEASE_CDDL.md))
and the Intel CoRIM profile
([fchinchilla/draft-cds-rats-intel-corim-profile](https://github.com/fchinchilla/draft-cds-rats-intel-corim-profile)).

## `cddl/` layout

- `cddl/exports/intel-poe-profile.cddl` — the single, self-contained profile
  grammar. This is what the draft appendix `{::include}`s and what is published
  as the downloadable release asset.
- `cddl/fixtures/` — checked-in conformance fixtures (`poe-golden.cbor`,
  `poe-golden-fwdcompat.cbor`, `poe-negative-bare.cbor`) and their deterministic
  generator [`make-fixtures.py`](cddl/fixtures/make-fixtures.py). Used by
  `make test` to prove the profile is a genuine subset of base CoRIM.
  Regenerate with `make fixtures` after any wire-shape change.
- `cddl/imports/` — a build-time fetch cache for the grammars `make check-cddl`
  validates the profile against: `corim-autogen.cddl` (base CoRIM) and
  `icorim-autogen.cddl` (the Intel Profile's assembled Intel-CoRIM grammar, used
  by the Intel conformance / code-point drift check). The cache is git-ignored,
  never committed or shipped. `scripts/validate-cddl.sh` fetches each release
  artifact ad-hoc when it is absent (skip the Intel check with `-I`);
  populate/refresh the cache explicitly with
  [`scripts/update-cddl-imports.sh`](scripts/update-cddl-imports.sh) (use
  `-r <nn>` for a specific CoRIM revision).

## Validating the profile

Two complementary checks, both wired into `make check` and CI:

- **`make check-cddl`** ([`scripts/validate-cddl.sh`](scripts/validate-cddl.sh))
  — *grammar*-level: the profile grammar is well-formed and composes with (narrows)
  base CoRIM, plus an Intel Profile code-point drift guard.
- **`make test`** ([`scripts/test-cddl.sh`](scripts/test-cddl.sh)) —
  *instance*-level subset conformance over the `cddl/fixtures/`: the golden and
  forward-compatible CoRIMs are accepted, and the deliberately malformed negative
  is rejected, by three engines — Microsoft's `corim-cli` (Azure/corim, the
  authoritative `draft-ietf-rats-corim-10` decoder and the consumer of POE data),
  a `pycddl` payload check, and the Ruby `cddl` grammar check. The conformance
  tools are provisioned by the devcontainer
  ([`.devcontainer/provision-cddl-tools.sh`](.devcontainer/provision-cddl-tools.sh))
  and by the *CDDL Conformance* GitHub Action.

`make fuzz` ([`scripts/fuzz-cddl.sh`](scripts/fuzz-cddl.sh)) is an optional,
manual-only breadth aid (generates random valid instances and reports how the
decoders react); it is deliberately **not** part of `make check` or CI because
its results are non-deterministic.

The CDDL is published to a GitHub Release two ways:

1. **Automatically, alongside each draft version.** When a `draft-*` tag is
   pushed (the normal I-D publication flow), the *Publish New Draft Version*
   workflow attaches `cddl/exports/intel-poe-profile.cddl` to that draft's
   release. No extra action is needed.
2. **On demand, as a standalone `cddl-*` release** (described below), when you
   want to publish the grammar independently of a draft submission.

## Create a git tag

To trigger the "Release CDDL" action, the tag must start with `cddl-`.

### CDDL for a given I-D version

When releasing the CDDL associated with a specific draft version, use:

```sh
git tag -a cddl-draft-bzb-rats-intel-poe-endorsements-<nn>
```

where `<nn>` is the draft version number.

### CDDL for the current HEAD

```sh
git tag -a cddl-$(git rev-parse --short HEAD)
```

## Push the tag to origin

```sh
git push origin cddl-...
```

Pushing the tag triggers the associated GitHub Action, which validates the
grammar (`make check-cddl`) and uploads the file.

## Inspect the release files

If everything goes as planned, `intel-poe-profile.cddl` is downloadable from:

```
https://github.com/mbronk-intc/draft-bzb-rats-intel-poe-endorsements/releases/download/cddl-.../intel-poe-profile.cddl
```
