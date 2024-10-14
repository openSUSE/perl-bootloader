PACKAGE_NAME := $(shell if [ -f PACKAGE_NAME ] ; then cat PACKAGE_NAME ; else echo update-bootloader ; fi)
GIT2LOG := $(shell if [ -x ./git2log ] ; then echo ./git2log --update ; else echo true ; fi)
GITDEPS := $(shell [ -d .git ] && echo .git/HEAD .git/refs/heads .git/refs/tags)
VERSION := $(shell $(GIT2LOG) --version VERSION ; cat VERSION)
PREFIX  := $(PACKAGE_NAME)-$(VERSION)

SBINDIR ?= /usr/sbin
ETCDIR  ?= /usr/etc

.PHONY:	clean doc install test tests

all:
	@echo "Choose target: clean, doc, install, test"

changelog: $(GITDEPS)
	$(GIT2LOG) --changelog changelog

install:
	@for bl in include grub2 grub2-efi grub2-bls systemd-boot u-boot; do install -m 755 -D -t $(DESTDIR)/usr/lib/bootloader/$$bl $$bl/* ; done
	@install -D -m 755 pbl.sh $(DESTDIR)$(SBINDIR)/pbl
	@perl -pi -e 's/0\.0/$(VERSION)/ if /VERSION ?=/' $(DESTDIR)$(SBINDIR)/pbl
	@ln -snf pbl $(DESTDIR)$(SBINDIR)/update-bootloader
	@ln -rsnf $(DESTDIR)$(SBINDIR)/pbl $(DESTDIR)/usr/lib/bootloader/bootloader_entry
	@install -D -m 644 boot.readme $(DESTDIR)/usr/share/doc/packages/$(PACKAGE_NAME)/boot.readme
	@install -D -m 644 pbl.logrotate $(DESTDIR)$(ETCDIR)/logrotate.d/pbl
	@install -D -m 755 kexec-bootloader $(DESTDIR)$(SBINDIR)/kexec-bootloader
	@install -d -m 755 $(DESTDIR)/usr/share/man/man8

%.8: %_man.adoc
	asciidoctor -b manpage -a version=$(VERSION) -a soversion=${MAJOR_VERSION} $<

doc: pbl.8 bootloader_entry.8 update-bootloader.8 kexec-bootloader.8

test: tests
tests:
	@./run_tests

clean:
	rm -rf package
	rm -f VERSION changelog *.8 *~ */*~ */*/*~
	rm -f tests/*/*.{bash,ksh,busybox} tests/testresults*.diff
	rm -rf tests/{real_,}root
