use strict;
use Test::More tests => 13;

use lib "./";
use Bootloader::Library;

use Cwd;

$ENV{PERL_BOOTLOADER_TESTSUITE_PATH} = getcwd()."/fake_root1/";

my $lib_ref = Bootloader::Library->new();

ok($lib_ref->SetLoaderType("grub"));
$lib_ref->InitializeBootloader(); #this is expected fail, because it check real hardware
ok($lib_ref->ReadSettings());
my $dev_map = $lib_ref->GetDeviceMapping ();
ok ($dev_map);
is($dev_map->{'/dev/sda'},"hd0");
is($dev_map->{'/dev/hdb'},"hd1");
is($dev_map->{'/dev/hda'},"hd2");
is($dev_map->{'/dev/sdc'},"hd3");
is($dev_map->{'/dev/sdb'},"hd4");
is($dev_map->{'/dev/fd0'},"fd0");
my $globals = $lib_ref->GetGlobalSettings();
ok($globals);
is($globals->{'default'},'openSUSE 11.0 - 2.6.25.4-10');
is($globals->{"timeout"},"8");
is($globals->{"gfxmenu"},"(hd0,1)/boot/message");
