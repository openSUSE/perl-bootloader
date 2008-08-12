use strict;
use Test::More tests => 24;

use lib "./";
use Bootloader::Library;
use Bootloader::Tools;

use Cwd;

$ENV{PERL_BOOTLOADER_TESTSUITE_PATH} = getcwd()."/fake_root1/";

my $lib_ref = Bootloader::Library->new();

ok($lib_ref->SetLoaderType("grub"));
$lib_ref->InitializeBootloader(); #this is expected fail, because it check real hardware
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
is($globals->{"gfxmenu"},"(hd0,1)/boot/message");

#test sections
my @sections = @{$lib_ref->GetSections()};
ok(@sections);
foreach my $section (@sections) {
  if ( $section->{'original_name'} eq "linux" ){

  } 
  elsif ( $section->{'original_name'} eq "linux-2.6.25.4-10-default" )
  {
  }
  elsif ( $section->{'original_name'} eq "failsafe" )
  {
  }
  elsif ( $section->{'original_name'} eq "Linux other 1 (/dev/sda4)" )
  {
    is( $section->{'chainloader'}, '/dev/sda4' );
    is( $section->{'blockoffset'}, '1' );
    is( $section->{'name'}, 'Linux other 1 (/dev/sda4)' );
    ok( $section->{'noverifyroot'});
    is( $section->{'type'}, 'other' );
  }
  elsif ( $section->{'original_name'} eq "floppy" )
  {
    is( $section->{'chainloader'}, '/dev/fd0' );
    is( $section->{'blockoffset'}, '1' );
    is( $section->{'name'}, 'Floppy' );
    ok( $section->{'noverifyroot'});
    is( $section->{'type'}, 'other' );
  }
}

Bootloader::Tools::DumpLog( $lib_ref );
