use strict;
use Test::More tests => 76;

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
my @partitions = ( \@partition1 );
ok($lib_ref->DefinePartitions(\@partitions));
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
is($globals->{'default'},'openSUSE 11.0 - 2.6.25.4-10');
is($globals->{"timeout"},"8");
is($globals->{"gfxmenu"},"/boot/message");
is($globals->{"setkeys"}->{"a"}, "b");
is($globals->{"setkeys"}->{"b"}, "a");
$globals->{"setkeys"}->{"b"} = "c";
$globals->{"setkeys"}->{"c"} = "a";
$globals->{"__modified"} = 1;
$lib_ref->SetGlobalSettings($globals);

#test sections
my @sections = @{$lib_ref->GetSections()};
ok(@sections);
foreach my $section (@sections) {
  if ( $section->{'original_name'} eq "linux" ){
    is( $section->{'type'}, 'image' );
    is( $section->{'image'}, '/boot/vmlinuz-2.6.25.4-10-debug' );
    is( $section->{'initrd'}, '/boot/initrd-2.6.25.4-10-debug' );
    is( $section->{'name'}, 'Debug -- openSUSE 11.0 - 2.6.25.4-10' );
    ok( not defined $section->{'vgamode'} );
    is( $section->{'append'}, 'resume=/dev/sda1 splash=silent showopts' );
    is( $section->{'console'}, 'ttyS0,38400n52r' );
  } 
  elsif ( $section->{'original_name'} eq "linux-2.6.25.4-10-default" )
  {
    is( $section->{'type'}, 'image' );
    is( $section->{'image'}, '/boot/vmlinuz-2.6.25.4-10-default' );
    is( $section->{'initrd'}, '/boot/initrd-2.6.25.4-10-default' );
    is( $section->{'name'}, 'openSUSE 11.0 - 2.6.25.4-10' );
    is( $section->{'vgamode'}, '0x31a' );
    is( $section->{'append'}, 'resume=/dev/sda1 splash=silent showopts' );
    ok( not defined $section->{'console'} );
  }
  elsif ( $section->{'original_name'} eq "failsafe" )
  {
    is( $section->{'type'}, 'image' );
    is( $section->{'image'}, '/boot/vmlinuz-2.6.25.4-10-default' );
    is( $section->{'initrd'}, '/boot/initrd-2.6.25.4-10-default' );
    is( $section->{'name'}, 'Failsafe -- openSUSE 11.0 - 2.6.25.4-10' );
    ok( not defined $section->{'vgamode'} );
    is( $section->{'append'}, 'showopts ide=nodma apm=off acpi=off noresume edd=off x11failsafe' );
    ok( not defined $section->{'console'} );
  }
  elsif ( $section->{'original_name'} eq "xen" )
  {
    is( $section->{"type"}, 'xen' );
    is( $section->{"append"}, 'resume=/dev/sda1 splash=silent showopts' );
    is( $section->{"image"}, '/boot/vmlinuz-2.6.25.4-10-xen' );
    is( $section->{"initrd"}, '/boot/initrd-2.6.25.4-10-xen' );
    is( $section->{"name"}, 'XEN' );
    is( $section->{"root"}, '/dev/disk/by-id/scsi-SATA_ST3250620NS_9QE2JXS8-part2' );
    is( $section->{"xen"}, '/boot/xen.gz' );
    is( $section->{"xen_append"}, 'console=com1 com1=38400n52r testparam=ok' );
    is( $section->{"vgamode"}, '0x332' );
    is( $section->{'console'}, 'ttyS0,38400n52r' );
    $section->{'console'} = 'ttyS1,9600n52r'; #test change console
    $section->{'__modified'} = '1';
  }
  elsif ( $section->{'original_name'} eq "console" )
  {
    is($section->{'console'},"ttyS0,57600");
    is($section->{'append'},'console=tty0 sysrq_always_enabled panic=100 resume=/dev/disk/by-id/ata-Hitachi_HDS721616PLA380_IBM_PVB340Z2U206SF-part2 splash=silent crashkernel=0M-:0M@16M showopts');
  }
  elsif ( $section->{'original_name'} eq "xen2" )
  {
    is($section->{'nounzip'},2);
    $section->{'__modified'} = '1';
  }
  elsif ( $section->{'original_name'} eq "Linux other 1 (/dev/sda4)" )
  {
    is( $section->{'chainloader'}, '/dev/hdb1' );
    is( $section->{'blockoffset'}, '1' );
    is( $section->{'name'}, 'Linux other 1 (/dev/sda4)' );
    ok( $section->{'noverifyroot'});
    is( $section->{'type'}, 'other' );
    ok( $section->{'makeactive'});
    ok( $section->{'remap'} );
    $section->{'__modified'} = "1";
    delete $section->{'makeactive'};
  }
  elsif ( $section->{'original_name'} eq "floppy" )
  {
    is( $section->{'chainloader'}, '/dev/fd0' );
    is( $section->{'blockoffset'}, '1' );
    is( $section->{'name'}, 'Floppy' );
    ok( $section->{'noverifyroot'});
    is( $section->{'type'}, 'other' );
    ok( not exists $section->{'makeactive'});
    ok( not exists $section->{'remap'} );
    $section->{'__modified'} = "1";
  }
}

ok($lib_ref->SetSections(\@sections));
ok($lib_ref->WriteSettings());
ok($lib_ref->UpdateBootloader(1));

my $res = qx:grep -c "kernel /boot/xen.gz console=com2 com2=9600n52r testparam=ok" ./fake_root1/boot/grub/menu.lst:;
chomp($res);
is( $res, 1); #test correct created xen append

$res = qx:grep -c "rootnoverify (fd0)" ./fake_root1/boot/grub/menu.lst:;
chomp($res);
is( $res, 1); #test if floppy is correctly repammer for root

$res = qx:grep -c "makeactive" ./fake_root1/boot/grub/menu.lst:;
chomp($res);
is( $res, 0); #test if floppy is correctly repammer for root

$res = qx:grep -c "setkey b a" ./fake_root1/boot/grub/menu.lst:;
chomp($res);
is( $res, 0); #test if floppy is correctly repammer for root

$res = qx:grep -c "setkey b c" ./fake_root1/boot/grub/menu.lst:;
chomp($res);
is( $res, 1); #test if floppy is correctly repammer for root

$res = qx:grep -c "setkey c a" ./fake_root1/boot/grub/menu.lst:;
chomp($res);
is( $res, 1); #test if floppy is correctly repammer for root

$res = qx:grep -n 'module .*/boot/vmlinuz-2.6.30-xen' ./fake_root1/boot/grub/menu.lst:;
my $imagepos;
if ( $res =~ m/(\d+):.*/ )
{
  $imagepos = $1;
}
$res = qx:grep -n 'modulenounzip .*/boot/initrd-2.6.30-xen' ./fake_root1/boot/grub/menu.lst:;
my $initrdpos;
if ( $res =~ m/(\d+):.*/ )
{
  $initrdpos = $1;
}
ok($initrdpos>$imagepos);


Bootloader::Tools::DumpLog( $lib_ref );
