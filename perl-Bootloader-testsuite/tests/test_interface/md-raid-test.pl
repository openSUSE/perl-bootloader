use strict;
use Test::More tests => 23;

use lib "./";
use Bootloader::Library;
use Bootloader::Tools;

use Cwd;

$ENV{PERL_BOOTLOADER_TESTSUITE_PATH} = getcwd()."/fake_root2/";

my $lib_ref = Bootloader::Library->new();

ok($lib_ref->SetLoaderType("grub"));
$lib_ref->InitializeBootloader(); #this is expected fail, because it check real hardware
my %mount_points = ( '/' => '/dev/md1' );
ok($lib_ref->DefineMountPoints(\%mount_points));
my @partition1 = ( "/dev/hdb1", "/dev/hdb","1","130","","","","","/dev/disk/by-id/test");
my @partition4 = ( "/dev/sda2", "/dev/sda","2","130","","","","","/dev/disk/by-id/test2");
my @partition2 = ( "/dev/sdc2", "/dev/sdc","2","130","","","","");
my @partition3 = ( "/dev/sda1", "/dev/sda","1","130","","","","","/dev/disk/by-id/test3");
my @partitions = ( \@partition1, \@partition2, \@partition3, \@partition4 );
ok($lib_ref->DefinePartitions(\@partitions));
my @md_raid = ("/dev/sda2","/dev/sdc2");
my %md_arrays = ("/dev/md1" => \@md_raid);
ok($lib_ref->DefineMDArrays(\%md_arrays));
ok($lib_ref->ReadSettings());


#test device map
my $dev_map = $lib_ref->GetDeviceMapping ();
ok ($dev_map);
is($dev_map->{'/dev/sda'},"hd0");
is($dev_map->{'/dev/hdb'},"hd1");
is($dev_map->{'/dev/hda'},"hd2");
is($dev_map->{'/dev/sdc'},"hd3");
is($dev_map->{'/dev/sdb'},"hd4");
is($dev_map->{'/dev/fd0'},"fd0");

#test globals
my $globals = $lib_ref->GetGlobalSettings();
ok($globals);
is($globals->{'default'},'XEN');
is($globals->{"timeout"},"8");
is($globals->{"gfxmenu"},"/boot/message");
is($globals->{"boot_md_mbr"},"/dev/sda,/dev/sdc");
$globals->{"setkeys"}->{"b"} = "c";
$globals->{"setkeys"}->{"c"} = "a";
$globals->{"boot_md_mbr"} = "/dev/sda,/dev/sdc,/dev/sdb";
$globals->{"__modified"} = 1;
ok($lib_ref->SetGlobalSettings($globals));

ok($lib_ref->WriteSettings());
ok($lib_ref->UpdateBootloader(1));

my $res = qx:grep -c 'setup --stage2=/boot/grub/stage2 --force-lba (hd0) (hd0,1)' ./fake_root2/etc/grub.conf:;
chomp $res;
is( $res, 1); #test boot_md_mbr correctness

$res = qx:grep -c 'setup --stage2=/boot/grub/stage2 --force-lba (hd3) (hd3,1)' ./fake_root2/etc/grub.conf:;
chomp $res;
is( $res, 1); #test boot_md_mbr correctness

$res = qx:grep -c 'setup --stage2=/boot/grub/stage2 --force-lba (hd4) (hd4,1)' ./fake_root2/etc/grub.conf:;
chomp $res;
is( $res, 1); #test boot_md_mbr correctness


Bootloader::Tools::DumpLog( $lib_ref );
