LIBDIR := lib
-include $(LIBDIR)/main.mk

$(LIBDIR)/main.mk:
ifneq (,$(shell grep "path *= *$(LIBDIR)" .gitmodules 2>/dev/null))
	git submodule sync
	git submodule update --init
else
ifneq (,$(wildcard $(ID_TEMPLATE_HOME)))
	ln -s "$(ID_TEMPLATE_HOME)" $(LIBDIR)
else
	git clone -q --depth 10 -b main \
	    https://github.com/martinthomson/i-d-template $(LIBDIR)
endif
endif

## POE profile CDDL validation.
##
## Repository CDDL layout:
##   cddl/exports/  -- the single, self-contained profile grammar; it is what the
##                     draft appendix `{::include}`s and what ships as the
##                     downloadable release asset.
##   cddl/imports/  -- a build-time fetch cache for the grammars the profile is
##                     validated against: the base CoRIM grammar and the Intel
##                     Profile grammar (git-ignored, never committed or shipped).
##
## Validate the standalone profile grammar (cddl/exports/intel-poe-profile.cddl)
## against the base CoRIM grammar on every `make check`. Reuses
## scripts/validate-cddl.sh, which fetches the base release artifact ad-hoc
## (using a cached copy under cddl/imports/ if one is present).
##
## FUTURE OPTION (intentionally not done yet): today the grammar is one
## hand-maintained file. If it grows, we may split it into several smaller
## per-topic source fragments and add a build step that assembles (and optionally
## compiles / normalises) them into the single exports file -- keeping the draft
## appendix and the download a single artifact either way. Revisit only if the
## size/complexity warrants it.
POE_CDDL := cddl/exports/intel-poe-profile.cddl
POE_FIXTURES := cddl/fixtures

.PHONY: check-cddl
check-cddl: $(POE_CDDL)
	scripts/validate-cddl.sh

check:: check-cddl

## Instance-level conformance test (separate from the grammar `check-cddl`).
##
## `make test` validates concrete fixtures: a base-correct POE CoRIM is accepted
## by the authoritative base decoder (Microsoft's corim-cli, draft-ietf-rats-corim
## -10) AND by this profile; a forward-compatible one (with optional/unknown
## top-level keys) is still accepted; and a deliberately malformed one is rejected
## -- proving the profile is a genuine subset of base CoRIM and guarding against
## regressions. Wired into the default `check` flow and CI. The three-engine setup
## (corim-cli + pycddl + the Ruby cddl grammar check) is provisioned by the
## devcontainer.
.PHONY: test
test: $(POE_CDDL)
	scripts/test-cddl.sh

check:: test

## (Re)generate the conformance fixtures from cddl/fixtures/make-fixtures.py.
## Run after any wire-shape change, then commit the regenerated *.cbor. Uses the
## devcontainer's cbor2-provisioned Python (override with FIXTURES_PY=...).
FIXTURES_PY ?= $(firstword $(wildcard $(HOME)/.local/share/poe-tools/cddlvenv/bin/python) python3)
.PHONY: fixtures
fixtures:
	$(FIXTURES_PY) $(POE_FIXTURES)/make-fixtures.py

## Manual-only grammar fuzz (NOT part of `check`/CI). Generates random valid
## instances and reports how the decoders react; noisy by design -- a breadth aid,
## never a gate.
.PHONY: fuzz
fuzz: $(POE_CDDL)
	scripts/fuzz-cddl.sh

