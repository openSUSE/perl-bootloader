all: test

test: clean
	mkdir -p Bootloader
	@cp -r ../../../src/* Bootloader/
	@cp -r backup/fake_root1 .
	@cp -r backup/fake_root2 .
	@mkdir -p fake_root{1,2}/var/log/YaST2

	perl -w grub1-test.pl
	perl -w lilo1-test.pl
	perl -w elilo1-test.pl
	perl -w plilo1-test.pl
	perl -w zipl1-test.pl
	perl -w grub-trusted-test.pl
	perl -w none-test.pl
	perl -w multipath-test.pl
	perl -w md-raid-test.pl
	perl -w core-test.pl

clean: 
	@rm -f *~
	@rm -rf Bootloader fake_root*
