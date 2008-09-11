use strict;
use Test::More tests => 15;

use lib "./";
use Bootloader::Library;
use Bootloader::Tools;

use Cwd;

$ENV{PERL_BOOTLOADER_TESTSUITE_PATH} = getcwd()."/fake_root1/";

my $lib_ref = Bootloader::Library->new();

ok($lib_ref->SetLoaderType("elilo"));
$lib_ref->InitializeBootloader(); #this is expected fail, because it check real hardware
my %mount_points = ( '/' => '/dev/sda2' );
ok($lib_ref->DefineMountPoints(\%mount_points));
ok($lib_ref->ReadSettings());


#test globals
my $globals = $lib_ref->GetGlobalSettings();
ok($globals);
is($globals->{'default'},'linux');
is($globals->{"timeout"},"8");
is($globals->{"append"},"showopts");

#test sections
my @sections = @{$lib_ref->GetSections()};
ok(@sections);
foreach my $section (@sections) {
  if ( $section->{'original_name'} eq "linux" ){
    is( $section->{'type'}, 'image' );
    is( $section->{'image'}, '/boot/vmlinuz-2.6.25.4-10' );
    is( $section->{'initrd'}, '/boot/initrd-2.6.25.4-10' );
    is( $section->{'name'}, 'linux' );
    ok( not defined $section->{'vgamode'} );
    is( $section->{'append'}, 'resume=/dev/sda1 splash=silent showopts' );
    is( $section->{'console'}, 'ttyS0,38400n52r' );
  } 
}

Bootloader::Tools::DumpLog( $lib_ref );
