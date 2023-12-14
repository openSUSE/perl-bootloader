GIT2LOG := $(shell if [ -x ./git2log ] ; then echo ./git2log --update ; else echo true ; fi)
GITDEPS := $(shell [ -d .git ] && echo .git/HEAD .git/refs/heads .git/refs/tags)
VERSION := $(shell $(GIT2LOG) --version VERSION ; cat VERSION)
PREFIX  := perl-Bootloader-$(VERSION)

SBINDIR ?= /usr/sbin
ETCDIR  ?= /usr/etc

.PHONY:	clean test install doc

all:
	@echo "Choose one target out of 'install', 'doc', 'test', or 'clean'"
	@echo

changelog: $(GITDEPS)
	$(GIT2LOG) --changelog changelog

install:
	@install -d -m 755 $(DESTDIR)/usr/lib/bootloader/grub2
	@install -m 755 grub2/install $(DESTDIR)/usr/lib/bootloader/grub2
	@install -m 755 grub2/config $(DESTDIR)/usr/lib/bootloader/grub2
	@install -m 755 grub2/add-option $(DESTDIR)/usr/lib/bootloader/grub2
	@install -m 755 grub2/del-option $(DESTDIR)/usr/lib/bootloader/grub2
	@install -m 755 grub2/get-option $(DESTDIR)/usr/lib/bootloader/grub2
	@install -m 755 grub2/default-settings $(DESTDIR)/usr/lib/bootloader/grub2

	@install -d -m 755 $(DESTDIR)/usr/lib/bootloader/grub2-efi
	@install -m 755 grub2-efi/install $(DESTDIR)/usr/lib/bootloader/grub2-efi
	@install -m 755 grub2/config $(DESTDIR)/usr/lib/bootloader/grub2-efi
	@install -m 755 grub2/add-option $(DESTDIR)/usr/lib/bootloader/grub2-efi
	@install -m 755 grub2/del-option $(DESTDIR)/usr/lib/bootloader/grub2-efi
	@install -m 755 grub2/get-option $(DESTDIR)/usr/lib/bootloader/grub2-efi
	@install -m 755 grub2/default-settings $(DESTDIR)/usr/lib/bootloader/grub2-efi

	@install -d -m 755 $(DESTDIR)/usr/lib/bootloader/u-boot
	@install -m 755 u-boot/config $(DESTDIR)/usr/lib/bootloader/u-boot

	@install -d -m 755 $(DESTDIR)/usr/lib/bootloader/systemd-boot
	@install -m 755 systemd-boot/install $(DESTDIR)/usr/lib/bootloader/systemd-boot
	@install -m 755 systemd-boot/config $(DESTDIR)/usr/lib/bootloader/systemd-boot
	@install -m 755 systemd-boot/add-kernel $(DESTDIR)/usr/lib/bootloader/systemd-boot
	@install -m 755 systemd-boot/remove-kernel $(DESTDIR)/usr/lib/bootloader/systemd-boot

	@install -D -m 755 pbl.sh $(DESTDIR)$(SBINDIR)/pbl
	@perl -pi -e 's/0\.0/$(VERSION)/ if /VERSION = /' $(DESTDIR)$(SBINDIR)/pbl
	@ln -snf pbl $(DESTDIR)$(SBINDIR)/update-bootloader
	@ln -rsnf $(DESTDIR)$(SBINDIR)/pbl $(DESTDIR)/usr/lib/bootloader/bootloader_entry
	@install -D -m 644 boot.readme $(DESTDIR)/usr/share/doc/packages/perl-Bootloader/boot.readme
	@install -d -m 755 $(DESTDIR)/usr/share/man/man8
	@install -D -m 644 pbl.logrotate $(DESTDIR)$(ETCDIR)/logrotate.d/pbl

	@install -D -m 755 kexec-bootloader $(DESTDIR)$(SBINDIR)/kexec-bootloader

%.8: %_man.adoc
	asciidoctor -b manpage -a version=$(VERSION) -a soversion=${MAJOR_VERSION} $<

doc: pbl.8 bootloader_entry.8 update-bootloader.8 kexec-bootloader.8

test:
	@./run_tests

clean:
	rm -rf .check .install .package package
	rm -f *.8 *~ */*~ */*/*~
	rm -f tests/*/*.{bash,dash,ksh,busybox} tests/testresults*.diff
	rm -rf tests/{real_,}root
