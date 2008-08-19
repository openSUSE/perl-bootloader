use strict;
use Test::More tests => 21;

use lib "./";
use Bootloader::Library;
use Bootloader::Tools;

use Cwd;

$ENV{PERL_BOOTLOADER_TESTSUITE_PATH} = getcwd()."/fake_root1/";

my $lib_ref = Bootloader::Library->new();

ok($lib_ref->SetLoaderType("zipl"));
$lib_ref->InitializeBootloader(); #this is expected fail, because it check real hardware
my %mount_points = ( '/' => '/dev/sda2' );
ok($lib_ref->DefineMountPoints(\%mount_points));
ok($lib_ref->ReadSettings());


#test globals
my $globals = $lib_ref->GetGlobalSettings();
ok($globals);
is($globals->{'default'},'menu');

#test sections
my @sections = @{$lib_ref->GetSections()};
ok(@sections);
foreach my $section (@sections) {
  if ( not exists $section->{'original_name'} ) #menu
  {
    is( $section->{'default'}, "1" );
    is( $section->{'timeout'}, "10" );
    is( $section->{'prompt'}, "true" );
    is( $section->{'list'}, "ipl, Failsafe" );
    is( $section->{'type'}, 'menu' );
  }
  elsif ( $section->{'original_name'} eq "dump" )
  {
    is( $section->{'type'}, 'dump' );
    is( $section->{'target'}, '/boot/zipl' );
    is( $section->{'dumpto'}, '/dev/sda2' );
  } 
  elsif ( $section->{'original_name'} eq "failsafe" )
  {
    is( $section->{'type'}, 'image' );
    is( $section->{'image'}, '/boot/image-2.6.16.60-0.4-default' );
    is( $section->{'initrd'}, '/boot/initrd-2.6.16.60-0.4-default' );
    is( $section->{'name'}, 'Failsafe' );
    ok( not defined $section->{'vgamode'} );
    is( $section->{'append'}, 'TERM=dumb 3' );
    ok( not exists $section->{'console'} );
  } 
}

Bootloader::Tools::DumpLog( $lib_ref );
