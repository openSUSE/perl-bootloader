test:
	@cp -r ../../../src/* Bootloader/
	cp -rf backup/fake_root1 .
	cp -rf backup/fake_root2 .
	perl -w grub1-test.pl
	perl -w elilo1-test.pl
	perl -w plilo1-test.pl
	perl -w zipl1-test.pl
	perl -w grub-trusted-test.pl
	rm -rf Bootloader/*
	rm -rf fake_root[12]

#usefull target after failed test
clean: 
	@rm -rf Bootloader/*
	rm -rf fake_root*
	cp -rf backup/fake_root1 .
	cp -rf backup/fake_root2 .
