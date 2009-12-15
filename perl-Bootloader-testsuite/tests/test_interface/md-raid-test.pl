use strict;
use Test::More tests => 86;

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
my %udevmap = ();
ok($lib_ref->DefineUdevMapping(\%udevmap));
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
is($globals->{"boot_md_mbr"},"/dev/sda,/dev/sdc");
$globals->{"setkeys"}->{"b"} = "c";
$globals->{"setkeys"}->{"c"} = "a";
$globals->{"boot_md_mbr"} = "/dev/sda,/dev/sdc,/dev/sdb";
$globals->{"__modified"} = 1;
ok($lib_ref->SetGlobalSettings($globals));

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
    is( $section->{'append'}, 'resume=/dev/sda1 splash=silent showopts console=ttyS0,38400n52r' );
  } 
  elsif ( $section->{'original_name'} eq "linux-2.6.25.4-10-default" )
  {
    is( $section->{'type'}, 'image' );
    is( $section->{'image'}, '/boot/vmlinuz-2.6.25.4-10-default' );
    is( $section->{'initrd'}, '/boot/initrd-2.6.25.4-10-default' );
    is( $section->{'name'}, 'openSUSE 11.0 - 2.6.25.4-10' );
    is( $section->{'vgamode'}, '0x31a' );
    is( $section->{'append'}, 'resume=/dev/sda####1 splash=silent showopts' );
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
    is( $section->{"append"}, 'resume=/dev/sda1 splash=silent showopts console=ttyS0,38400n52r' );
    is( $section->{"image"}, '/boot/vmlinuz-2.6.25.4-10-xen' );
    is( $section->{"initrd"}, '/boot/initrd-2.6.25.4-10-xen' );
    is( $section->{"name"}, 'XEN' );
    is( $section->{"root"}, '/dev/sda2' );
    is( $section->{"xen"}, '/boot/xen.gz' );
    is( $section->{"xen_append"}, 'console=com1 com1=38400n52r testparam=ok' );
    is( $section->{"vgamode"}, '0x332' );
    $section->{'append'} = $lib_ref->UpdateSerialConsole( $section->{'append'},'ttyS1,9600n52r'); #test change console
    $section->{'__modified'} = '1';
  }
  elsif ( $section->{'original_name'} eq "console" )
  {
    is($section->{'append'},'console=tty0 console=ttyS0,57600 sysrq_always_enabled panic=100 resume=/dev/sda1 splash=silent crashkernel=0M-:0M@16M showopts');
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
  } elsif (  $section->{'original_name'} eq "menu" )
  {
    is( $section->{'type'}, 'menu' );
    is( $section->{'name'}, 'menu' );
    is( $section->{'configfile'}, '/boot/grub/menu.lst' );
    $section->{'__modified'} = "1";
    $section->{'root'} = "/dev/fd0";
  }
}

my $new_section = {(
  'type' => 'menu',
  'original_name' => 'menu2',
  'configfile' => '/grub/menu.lst',
  'root' => '/dev/sda2',
  'name' => 'menu2',
  '__modified' => '1',
  )};

#memtest test
my $new_section2 = {(
  'type' => 'image',
  "__auto"=>"true",
  "__changed" => "true",
  "__modified"=>"1",
  "image"=>"/boot/memtest.bin",
  "name"=>"Memory Test",
  "original_name"=>"memtest86",
  )};

push @sections, $new_section;
push @sections, $new_section2;

print "set new sections \n";
ok($lib_ref->SetSections(\@sections));
ok($lib_ref->WriteSettings());
ok($lib_ref->UpdateBootloader(1));

my $res = qx:grep -c "kernel /boot/xen.gz vga=mode-0x332 console=com2 com2=9600n52r testparam=ok" ./fake_root2/boot/grub/menu.lst:;
chomp($res);
is( $res, 1); #test correct created xen append

$res = qx:grep -c "kernel .*/boot/memtest.bin" ./fake_root2/boot/grub/menu.lst:;
chomp($res);
is( $res, 1); #test correct created memtest

$res = qx:grep -c "rootnoverify (fd0)" ./fake_root2/boot/grub/menu.lst:;
chomp($res);
is( $res, 1); #test if floppy is correctly repammer for root

$res = qx:grep -c "makeactive" ./fake_root2/boot/grub/menu.lst:;
chomp($res);
is( $res, 0); #test if floppy is correctly repammer for root

$res = qx:grep -c "setkey b a" ./fake_root2/boot/grub/menu.lst:;
chomp($res);
is( $res, 0); #test if floppy is correctly repammer for root

$res = qx:grep -c "setkey b c" ./fake_root2/boot/grub/menu.lst:;
chomp($res);
is( $res, 1); #test if floppy is correctly repammer for root

$res = qx:grep -c "setkey c a" ./fake_root2/boot/grub/menu.lst:;
chomp($res);
is( $res, 1); #test if floppy is correctly repammer for root

$res = qx:grep -c "configfile /boot/grub/menu.lst" ./fake_root2/boot/grub/menu.lst:;
chomp($res);
is( $res, 1); #test configfile rewrite

$res = qx:grep -c "configfile /grub/menu.lst" ./fake_root2/boot/grub/menu.lst:;
chomp($res);
is( $res, 1); #test configfile new write

$res = qx:grep -n 'module .*/boot/vmlinuz-2.6.30-xen' ./fake_root2/boot/grub/menu.lst:;
my $imagepos;
if ( $res =~ m/(\d+):.*/ )
{
  $imagepos = $1;
}
$res = qx:grep -n 'modulenounzip .*/boot/initrd-2.6.30-xen' ./fake_root2/boot/grub/menu.lst:;
my $initrdpos;
if ( $res =~ m/(\d+):.*/ )
{
  $initrdpos = $1;
}
ok($initrdpos>$imagepos);

$res = qx:grep -c 'setup --stage2=/boot/grub/stage2 --force-lba (hd0) (hd0,1)' ./fake_root2/etc/grub.conf:;
chomp $res;
is( $res, 1); #test boot_md_mbr correctness

$res = qx:grep -c 'setup --stage2=/boot/grub/stage2 --force-lba (hd3) (hd3,1)' ./fake_root2/etc/grub.conf:;
chomp $res;
is( $res, 1); #test boot_md_mbr correctness

$res = qx:grep -c 'setup --stage2=/boot/grub/stage2 --force-lba (hd4) (hd4,1)' ./fake_root2/etc/grub.conf:;
chomp $res;
is( $res, 1); #test boot_md_mbr correctness


Bootloader::Tools::DumpLog( $lib_ref );
