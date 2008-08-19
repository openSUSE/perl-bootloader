test:
	@cp -r ../../../src/* Bootloader/
	perl -w grub1-test.pl
	perl -w elilo1-test.pl
	perl -w plilo1-test.pl
	perl -w zipl1-test.pl
	cp -rf backup/fake_root1 .
	rm -rf Bootloader/*
