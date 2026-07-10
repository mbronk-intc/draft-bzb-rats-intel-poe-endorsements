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

.PHONY: check-cddl
check-cddl: $(POE_CDDL)
	scripts/validate-cddl.sh

check:: check-cddl

