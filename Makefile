# $Id$
PKG=perl-Bootloader
SUBMIT_DIR=/work/src/done/STABLE
SUBMIT_DIR2=/work/src/done/SLES10
#BUILD_DIST=ppc
ifeq ($(BUILD_DIST),ppc)
BUILD=powerpc32 /work/src/bin/build
else
BUILD=/work/src/bin/build
endif
BUILD_ROOT=/abuild/buildsystem.$$HOST.$$LOGNAME
BUILD_DIR=$(BUILD_ROOT)/usr/src/packages/RPMS
SVNREP=.
DISTMAIL=/work/src/bin/distmail

.PHONY:	export build submit rpm clean

all:
	@echo "Choose one target out of 'export', 'build', 'submit', 'rpm' or 'clean'"
	@echo

export:	.exportdir

build:	.built

rpm:	.built
	@cp -av $(BUILD_ROOT)/usr/src/packages/RPMS/*/$(PKG)* .
	
submit:	.submitted


# worker targets

.exportdir:	$(PKG).changes
	@rm -f .built .submitted
	set -e ; set -x ;\
	export LANG=C ; export LC_ALL=C ; export TZ=UTC ; \
	tmpdir=`mktemp -d /tmp/temp.XXXXXX`/$(PKG) ; \
	lv=`cat version` ; \
	svn export $(SVNREP) $$tmpdir ; \
	cd $$tmpdir ; \
	chmod -R a+rX .. ; \
	mv -v $(PKG) $(PKG)-$$lv ; \
	tar cfvj $(PKG)-$$lv.tar.bz2 $(PKG)-$$lv ; \
	mv $(PKG).spec $(PKG).spec.in ; \
	sed "s/^Version:.*/Version: $$lv/" < $(PKG).spec.in > $(PKG).spec ; \
	rm -rf version Makefile $(PKG)-$$lv $(PKG).spec.in; \
	pwd ; \
	ls -la ; \
	if /work/src/bin/check_if_valid_source_dir; then cd -; echo $$tmpdir > $@; else exit 1 ; fi


.built:	.exportdir
	@rm -f .submitted
	@echo "Trying to compile $(PKG) package under $$(<.exportdir)"
	mypwd=`pwd` ; \
	if { cd $$(<.exportdir); \
	    export $(if $(BUILD_DIST),BUILD_DIST=$(BUILD_DIST)) BUILD_ROOT=$(BUILD_ROOT); sudo $(BUILD); }; \
	then \
	    touch $${mypwd}/$@; \
	else \
	    echo Compile failed; exit 1; \
	fi

.submitted: .built
	@echo "Target 'submit' will copy $$(<.exportdir) to $(SUBMIT_DIR)"
	@echo "Please confirm or abort"
	@select s in submit abort;do [ "$$s" == submit ] && break || exit 1; done
	cp -av $$(<.exportdir) $(SUBMIT_DIR)
	@cd $(SUBMIT_DIR)/$(PKG); $(DISTMAIL)
ifneq ($(SUBMIT_DIR2),)
	cp -av $$(<.exportdir) $(SUBMIT_DIR2)
	@cd $(SUBMIT_DIR2)/$(PKG); $(DISTMAIL)
endif
	@touch $@

clean:
	rm -f .exportdir .built .submitted
