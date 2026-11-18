# COPR's "make srpm" method: COPR clones the repository and runs, in a Fedora build root,
#   make -f .copr/Makefile srpm outdir=DIR spec=SPEC
# This makes the source archive and the source package from packaging/ectoview.spec, its
# release stamped with the commit's date and hash so every rebuild of it keeps them.
# (Ectolens's .copr/Makefile, adapted: Ectoview has no submodule.)
SHELL := /bin/bash
TOP := $(abspath $(dir $(lastword $(MAKEFILE_LIST)))/..)
outdir ?= $(CURDIR)
# COPR passes spec= as the package's Spec File setting, or the checkout folder when that is
# empty: a .spec file named there is used, anything else means ours
SPECFILE := $(if $(filter %.spec,$(spec)),$(spec),$(TOP)/packaging/ectoview.spec)

srpm:
	command -v git >/dev/null && command -v rpmbuild >/dev/null || dnf -y install git rpm-build
	git config --global --add safe.directory '*'
	set -e; work=$$(mktemp -d); cd "$(TOP)"; \
	  ver=$$(sed -n 's/^Version: *//p' "$(SPECFILE)"); name=ectoview-$$ver; \
	  commit=$$(git rev-parse --short=7 HEAD); date=$$(git log -1 --format=%cd --date=format:%Y%m%d); \
	  git archive --prefix=$$name/ -o "$$work/$$name.tar.gz" HEAD; \
	  sed "s/^%{!?snapinfo: %global snapinfo 0}$$/%global snapinfo $$date.git$$commit/" "$(SPECFILE)" > "$$work/ectoview.spec"; \
	  rpmbuild -bs "$$work/ectoview.spec" --define "_sourcedir $$work" --define "_srcrpmdir $(outdir)"
