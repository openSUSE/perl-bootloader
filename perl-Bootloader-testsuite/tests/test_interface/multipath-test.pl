use strict;
use Test::More tests => 12;

use lib "./";
use Bootloader::Library;
use Bootloader::Tools;

use Cwd;

$ENV{PERL_BOOTLOADER_TESTSUITE_PATH} = getcwd()."/fake_root1/";

my $lib_ref = Bootloader::Library->new();

ok($lib_ref->SetLoaderType("grub"));
$lib_ref->InitializeBootloader(); #this is expected fail, because it check real hardware
my %mount_points = ( '/' => '/dev/sda2' );
ok($lib_ref->DefineMountPoints(\%mount_points));
my @partition1 = ( "/dev/hdb1", "/dev/hdb","1","130","","","","","/dev/disk/by-id/test");
my @partition2 = ( "/dev/sda2", "/dev/sda","2","130","","","","","/dev/disk/by-id/test2");
my @partitions = ( \@partition1, \@partition2 );
ok($lib_ref->DefinePartitions(\@partitions));
my %multipath = ( '/dev/sda' => '/dev/mapper/test1', '/dev/sdc' => '/dev/mapper/test2' );
ok($lib_ref->DefineMultipath(\%multipath));
ok($lib_ref->ReadSettings());


#test device map
my $dev_map = $lib_ref->GetDeviceMapping ();
ok ($dev_map);
is($dev_map->{'/dev/mapper/test1'},"hd0");
is($dev_map->{'/dev/hdb'},"hd1");
is($dev_map->{'/dev/hda'},"hd2");
is($dev_map->{'/dev/mapper/test2'},"hd3");
is($dev_map->{'/dev/sdb'},"hd4");
is($dev_map->{'/dev/fd0'},"fd0");

