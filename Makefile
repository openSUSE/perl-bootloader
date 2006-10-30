# $Id$
PKG=perl-Bootloader
SUBMIT_DIR=/work/src/done/STABLE
#SUBMIT_DIR2=/work/src/done/SLES10
#BUILD_DIST=ppc
ifeq ($(BUILD_DIST),ppc)
BUILD=powerpc32 /work/src/bin/build
else
BUILD=/work/src/bin/build
endif
MBUILD=/work/src/bin/mbuild
MBUILDC=$(MBUILD) -l $(LOGNAME) -d stable
MBUILDQ=$(MBUILD) -q
BUILD_ROOT=/abuild/buildsystem.$(HOST).$(LOGNAME)
BUILD_DIR=$(BUILD_ROOT)/usr/src/packages/RPMS
SVNREP=.
DISTMAIL=/work/src/bin/distmail

.PHONY:	export build mbuild submit rpm clean

all:
	@echo "Choose one target out of 'export', 'build', 'mbuild', 'submit', 'rpm' or 'clean'"
	@echo

export:	.checkexportdir .exportdir

build:	.checkexportdir .built

rpm:	build
	@cp -av $(BUILD_ROOT)/usr/src/packages/RPMS/*/$(PKG)* .

submit:	.submitted


# worker targets
.checkexportdir:
	@[ -f .exportdir ] && [ -d "$$(<.exportdir)" ] || make clean

.exportdir:	$(PKG).changes $(PKG).spec.in version
	ln -sfn src Bootloader
	env PERLLIB=.:$$PERLLIB perl -c ./update-bootloader
	@rm -f .built .submitted Bootloader
	set -e ; set -x ;\
	export LANG=C ; export LC_ALL=C ; export TZ=UTC ; \
	exportdir=`mktemp -d /tmp/temp.XXXXXX` ; \
	tmpdir=$$exportdir/$(PKG) ; \
	lv=`cat version` ; \
	svn export $(SVNREP) $$tmpdir ; \
	cd $$tmpdir ; \
	chmod -R a+rX .. ; \
	mkdir $(PKG)-$$lv; \
	mkdir $(PKG)-$$lv/lib; \
	mv COPYING $(PKG)-$$lv/; \
	mv src $(PKG)-$$lv/lib/Bootloader; \
	tar cfvj $(PKG)-$$lv.tar.bz2 $(PKG)-$$lv ; \
	sed "s/^Version:.*/Version: $$lv/" < $(PKG).spec.in > $(PKG).spec ; \
	rm -rf version Makefile $(PKG)-$$lv $(PKG).spec.in; \
	pwd ; \
	ls -la ; \
	if /work/src/bin/check_if_valid_source_dir; then cd -; echo $$exportdir > $@; else exit 1 ; fi


.built:	.exportdir
	@rm -f .submitted
	@echo "Trying to compile $(PKG) package under $$(<.exportdir)/$(PKG)"
	mypwd=`pwd` ; \
	if { cd $$(<.exportdir)/$(PKG); \
	    export $(if $(BUILD_DIST),BUILD_DIST=$(BUILD_DIST)) BUILD_ROOT=$(BUILD_ROOT); sudo $(BUILD); }; \
	then \
	    touch $${mypwd}/$@; \
	else \
	    echo Compile failed; exit 1; \
	fi

mbuild: .checkexportdir .exportdir
	@if [ -f .mbuild_id -a .exportdir -ot .mbuild_id ]; then \
	    $(MBUILDQ) $$(<.mbuild_id); \
	else \
	   sudo $(MBUILDC) $$(<.exportdir)/$(PKG) | tee .message | grep jobid | cut -d\' -f2 > .mbuild_id; \
	   cat .message; rm -f .message; \
	fi

.submitted: .built
	@echo "Target 'submit' will copy $$(<.exportdir)/$(PKG) to $(SUBMIT_DIR)"
	@echo "Please confirm or abort"
	@select s in submit abort;do [ "$$s" == submit ] && break || exit 1; done
	cp -av $$(<.exportdir)/$(PKG) $(SUBMIT_DIR)
	@cd $(SUBMIT_DIR)/$(PKG); $(DISTMAIL)
ifneq ($(SUBMIT_DIR2),)
	cp -av $$(<.exportdir)/$(PKG) $(SUBMIT_DIR2)
	@cd $(SUBMIT_DIR2)/$(PKG); $(DISTMAIL)
endif
	@touch $@

clean:
	if [ -f .exportdir ] && [ -d "$$(<.exportdir)" ]; then echo "$$(<.exportdir)"; rm -rf "$$(<.exportdir)"; fi
	rm -f .exportdir .built .submitted
