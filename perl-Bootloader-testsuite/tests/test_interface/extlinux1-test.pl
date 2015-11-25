use strict;
use Test::More tests => 36;

use lib "./";
use Bootloader::Library;
use Bootloader::Tools;

use Cwd;

$ENV{PERL_BOOTLOADER_TESTSUITE_PATH} = getcwd()."/fake_root1/";

my $lib_ref = Bootloader::Library->new();

ok($lib_ref->SetLoaderType("extlinux"));
$lib_ref->InitializeBootloader(); #this is expected fail, because it check real hardware
ok($lib_ref->ReadSettings());

#test globals
my $globals = $lib_ref->GetGlobalSettings();
ok($globals);
is($globals->{"timeout"},"1000");
is($globals->{"default"},"default");
is($globals->{"ontimeout"},"localboot");
is($globals->{"menu"}->{"title"},"Boot menu");
$globals->{"timeout"} = 999;
$globals->{"menu"}->{"title"} = "BOOT MENU";
$globals->{"__modified"} = 1;
ok($lib_ref->SetGlobalSettings($globals));

#test sections
my @sections = @{$lib_ref->GetSections()};
ok(@sections);
foreach my $section (@sections) {
	if($section->{"name"} eq "default") {
		is( $section->{"menu"}->{"label"}, "Default" );
		is( $section->{"image"}, "/boot/zImage" );
		is( $section->{"type"}, "image" );
		is( $section->{"fdt"}, "exynos5250-snow.dtb" );
		is( $section->{"fdtdir"}, "/boot/dtb/" );
		is( $section->{"initrd"}, "/boot/initrd" );
		is( $section->{"append"}, "root=/dev/disk/by-id/mmc-SL08G_0x01978580-part3 loader=uboot disk=/dev/disk/by-id/mmc-SL08G_0x01978580 resume=/dev/disk/by-id/mmc-SL08G_0x01978580-part4 plymouth.enable=0 console=ttySAC3,115200n8 console=tty" );
		ok( not defined $section->{"localboot"} );
	}
	elsif($section->{"name"} eq "failsafe") {
		is( $section->{"menu"}->{"label"}, "Failsafe" );
		is( $section->{"image"}, "/boot/zImage-4.1.5-exynos_defconfig" );
		is( $section->{"type"}, "image" );
		is( $section->{"fdt"}, "exynos5250-snow.dtb" );
		is( $section->{"fdtdir"}, "/boot/dtb/" );
		is( $section->{"initrd"}, "/boot/initrd-4.1.5-exynos_defconfig" );
		is( $section->{"append"}, "root=/dev/disk/by-id/mmc-SL08G_0x01978580-part3 loader=uboot disk=/dev/disk/by-id/mmc-SL08G_0x01978580 resume=/dev/disk/by-id/mmc-SL08G_0x01978580-part4 plymouth.enable=0 console=ttySAC3,115200n8 console=tty" );
		ok( not defined $section->{"localboot"} );
		$section->{"__modified"} = 1;
		$section->{"append"} = "root=/dev/disk/by-id/mmc-SL08G_0x01978580-part3 loader=uboot disk=/dev/disk/by-id/mmc-SL08G_0x01978580 console=ttySAC3,115200n8 console=tty";
	}
	elsif($section->{"name"} eq "localboot") {
		is( $section->{"type"}, "other" );
		is( $section->{"menu"}->{"label"}, "Local boot script (boot.scr)" );
		is( $section->{"localboot"}, "true");
	}
}

my $new_section = {(
	'original_name' => 'menu2',
	'name' => 'menu2',
	'image' => '/boot/zImage-1.2.3',
	'type' => 'image',
	'initrd' => '/boot/initrd-1.2.3',
	'__modified' => '1',
)};

push @sections, $new_section;

ok($lib_ref->SetSections(\@sections));
ok($lib_ref->WriteSettings());
ok($lib_ref->UpdateBootloader(1));

my $res = qx:grep -c "TIMEOUT 999" ./fake_root1/boot/extlinux/extlinux.conf:;
chomp($res);
is( $res, 1); #test timeout modified

$res = qx:grep -c "MENU TITLE BOOT MENU" ./fake_root1/boot/extlinux/extlinux.conf:;
chomp($res);
is( $res, 1); #test menu title modified

$res = qx:grep -c "        APPEND root=/dev/disk/by-id/mmc-SL08G_0x01978580-part3 loader=uboot disk=/dev/disk/by-id/mmc-SL08G_0x01978580 console=ttySAC3,115200n8 console=tty" ./fake_root1/boot/extlinux/extlinux.conf:;
chomp($res);
is( $res, 1); #test append modified

$res = qx:grep -c "        LINUX /boot/zImage-1.2.3" ./fake_root1/boot/extlinux/extlinux.conf:;
chomp($res);
is( $res, 1); #test new section

$res = qx(grep -c "###Don't change this comment - YaST2 identifier: Original name: menu2###" ./fake_root1/boot/extlinux/extlinux.conf);
chomp($res);
is( $res, 1); #test original_name

Bootloader::Tools::DumpLog( $lib_ref );
