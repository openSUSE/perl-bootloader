# $Id$
PKG=perl-Bootloader
SUBMIT_DIR=/work/src/done/STABLE
#SUBMIT_DIR=/work/src/done/10.2
#SUBMIT_DIR2=/work/src/done/SLES10
#BUILD_DIST=ppc
ifeq ($(BUILD_DIST),ppc)
BUILD=powerpc32 /work/src/bin/build
else
BUILD=/work/src/bin/build --target=i586
endif
MBUILD=/work/src/bin/mbuild
MBUILDC=$(MBUILD) -l $(LOGNAME) -d stable
MBUILDQ=$(MBUILD) -q
ABUILD=/work/src/bin/abuild
BUILD_ROOT=/tmp/buildsystem.$(HOST).root
BUILD_DIR=$(BUILD_ROOT)/usr/src/packages/RPMS
SVNREP=.
DISTMAIL=/work/src/bin/distmail
BRANCH=SLE11-SP2

.PHONY:	export build mbuild submit rpm clean package test package-local install check

all:
	@echo "Choose one target out of 'export', 'build', 'abuild', 'mbuild', 'submit', 'test', 'test_clean', 'docs', 'rpm' or 'clean'"
	@echo

check: $(PM_FILES)
	@rm -rf .check
	@mkdir -p .check
	@cp -a src .check/Bootloader
	@cd .check ; find -name *.pm -exec perl -I. -c '{}' ';'

install: check
	@rm -rf .install
	@mkdir -p .install/lib
	@cp -a src .install/lib/Bootloader
	@rm -f `find .install/lib/Bootloader -name '*~'`
	@perl -pi -e 's/0\.000/$(VERSION)/ if /VERSION = /' .install/lib/Bootloader/Library.pm
	@cd .install ; \
	touch Makefile.PL ; \
	perl -Ilib -MExtUtils::MakeMaker -e 'WriteMakefile (NAME => "Bootloader", VERSION_FROM => "lib/Bootloader/Library.pm" )' ; \
	make install_vendor
	@mkdir -p $(DESTDIR)/sbin
	@install -m 755 update-bootloader $(DESTDIR)/sbin
	@install -d -m 755 $(DESTDIR)/usr/lib/bootloader
	@install -m 755 bootloader_entry $(DESTDIR)/usr/lib/bootloader
	@install -m 755 bootloader_fix_xen $(DESTDIR)/usr/lib/bootloader
	@install -d -m 755 $(DESTDIR)/boot
	@install -m 644 boot.readme $(DESTDIR)/boot/
	@install -d -m 755 $(DESTDIR)/usr/share/man/man8/
	@pod2man update-bootloader >$(DESTDIR)/usr/share/man/man8/update-bootloader.8
	@chmod 644 $(DESTDIR)/usr/share/man/man8/update-bootloader.8

package-local:
	rm -rf package .package
	mkdir -p .package
	read lv < version ; \
	mkdir .package/${PKG}-$${lv} ; \
	cp -a * .package/${PKG}-$${lv} ; \
	mkdir package ; \
	tar -C .package -zcf package/${PKG}-$${lv}.tar.bz2 ${PKG}-$${lv} ; \
	sed "s/--autoversion--/$$lv/" < $(PKG).spec.in > package/$(PKG).spec ; \
	cp $(PKG).changes package ; \
	rm -rf .package

package: test
	rm -rf package
	mkdir -p package
	read lv < version ; \
	git archive --prefix=${PKG}-$${lv}/ $(BRANCH) | bzip2 > package/${PKG}-$${lv}.tar.bz2; \
	sed "s/--autoversion--/$$lv/" < $(PKG).spec.in > package/$(PKG).spec ; \
	cp $(PKG).changes bootloader_entry bootloader_fix_xen boot.readme update-bootloader package/

export:	.checkexportdir .exportdir

docs:
	cd doc/ && make

build:	.checkexportdir .built

rpm:	build
	@cp -av $(BUILD_DIR)/*/$(PKG)* .

diff:	export
	@/work/src/bin/tools/diff_new_pac /work/SRC/all/$(PKG) $$(<.exportdir)/$(PKG) | less

submit:	.submitted

test:
	cd perl-Bootloader-testsuite/tests/test_interface/ && make

test_clean:
	cd perl-Bootloader-testsuite/tests/test_interface/ && make clean

# worker targets
.checkexportdir:
	@[ -f .exportdir ] && [ -d "$$(<.exportdir)" ] || make clean

.exportdir:	$(PKG).changes $(PKG).spec.in version
	ln -sfn src Bootloader
	env PERLLIB=.:$$PERLLIB perl -c ./update-bootloader
	@rm -fr .built .submitted Bootloader
	set -e ; set -x ;\
	export LANG=C ; export LC_ALL=C ; export TZ=UTC ; \
	exportdir=`mktemp -d /tmp/temp.XXXXXX` ; \
	tmpdir=$$exportdir/$(PKG) ; \
	read lv < version ; \
	svn export $(SVNREP) $$tmpdir ; \
	cd $$tmpdir ; \
	chmod -R a+rX .. ; \
	mkdir $(PKG)-$$lv; \
	mkdir $(PKG)-$$lv/lib; \
	mv COPYING $(PKG)-$$lv/; \
	mv src $(PKG)-$$lv/lib/Bootloader; \
	tar cfvj $(PKG)-$$lv.tar.bz2 $(PKG)-$$lv ; \
	sed "s/--autoversion--/$$lv/" < $(PKG).spec.in > $(PKG).spec ; \
	rm -rf version Makefile $(PKG)-$$lv $(PKG).spec.in perl-Bootloader-testsuite doc; \
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

abuild: .checkexportdir .exportdir
	sudo ${ABUILD} $$(<.exportdir)/$(PKG)

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
	rm -rf .check .install .package package
	rm -f .exportdir .built .submitted *~ */*~ */*/*~
