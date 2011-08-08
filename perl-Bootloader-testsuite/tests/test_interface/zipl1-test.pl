use strict;
use Test::More tests => 44;

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
  elsif ( $section->{'original_name'} eq "noroot" )
  {
    is( $section->{'type'}, 'image' );
    is( $section->{'image'}, '/boot/image-2.6.16.60-0.4-default' );
    is( $section->{'initrd'}, '/boot/initrd-2.6.16.60-0.4-default' );
    is( $section->{'name'}, 'noroot' );
    ok( not defined $section->{'vgamode'} );
    is( $section->{'append'}, 'TERM=dumb 3' );
    ok( not exists $section->{'root'} );
    $section->{'__modified'} = "1";
    $section->{'append'} = "term=dumb 5";
  } 
  elsif ( $section->{'original_name'} eq "withroot" )
  {
    is( $section->{'type'}, 'image' );
    is( $section->{'image'}, '/boot/image-2.6.16.60-0.4-default' );
    is( $section->{'initrd'}, '/boot/initrd-2.6.16.60-0.4-default' );
    is( $section->{'name'}, 'withroot' );
    ok( not defined $section->{'vgamode'} );
    is( $section->{'append'}, 'TERM=dumb 3' );
    is($section->{'root'},"/dev/sda2" );
    $section->{'__modified'} = "1";
    $section->{'append'} = "term=dumb 5";
  } 
}

ok($lib_ref->SetSections(\@sections));
ok($lib_ref->WriteSettings());
ok($lib_ref->UpdateBootloader(1));


my $res = qx:grep -c 'parameters = "term=dumb 5"' ./fake_root1/etc/zipl.conf:;
chomp($res);
is( $res, 1); #test if floppy is correctly repammer for root

my $res = qx:grep -c 'parameters = "root=/dev/sda2 term=dumb 5"' ./fake_root1/etc/zipl.conf:;
chomp($res);
is( $res, 1); #test if floppy is correctly repammer for root

my $res = qx:grep -c '1 = noroot' ./fake_root1/etc/zipl.conf:;
chomp($res);
is( $res, 1); #test if floppy is correctly repammer for root

my $res = qx:grep -c '2 = withroot' ./fake_root1/etc/zipl.conf:;
chomp($res);
is( $res, 1); #test if floppy is correctly repammer for root

my $res = qx:grep -c '3 = Failsafe' ./fake_root1/etc/zipl.conf:;
chomp($res);
is( $res, 1); #test if floppy is correctly repammer for root

my $res = qx:grep -c '4 = ' ./fake_root1/etc/zipl.conf:;
chomp($res);
is( $res, 0); #test if floppy is correctly repammer for root

Bootloader::Tools::DumpLog( $lib_ref );
