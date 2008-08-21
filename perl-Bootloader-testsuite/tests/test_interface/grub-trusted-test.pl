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
my %mount_points = ( '/' => '/dev/sda2' );
ok($lib_ref->DefineMountPoints(\%mount_points));
ok($lib_ref->ReadSettings());


#test sections
my @sections = @{$lib_ref->GetSections()};
ok(@sections);
foreach my $section (@sections) {
  if ( $section->{'original_name'} eq "linux" )
  {
    is( $section->{'type'}, 'image' );
    is( $section->{'image'}, '/boot/vmlinuz-2.6.25.4-10-default' );
    is( $section->{'imagepcr'}, '8' );
    is( $section->{'initrd'}, '/boot/initrd-2.6.25.4-10-default' );
    is( $section->{'initrdpcr'}, '8' );
    is( $section->{'name'}, 'openSUSE 11.0 - 2.6.25.4-10' );
    is( $section->{'vgamode'}, '0x31a' );
    is( $section->{'append'}, 'resume=/dev/sda1 splash=silent showopts' );
    ok( not defined $section->{'console'} );
    foreach my $measure ( @{$section->{'measure'}}){
      ok ( $measure eq '/etc/security/selinux/policy.17 9'
        or  $measure eq '/opt/jdk1.4.2/jre/lib/security/java.policy 9' );
    }
    $section->{'__modified'}=1;
    push  @{$section->{'measure'}}, "/opt/jdk1.4.2/jre/lib/security/java.security 8";
    $section->{"imagepcr"} = "7";
    $section->{"initrdpcr"} = "7";
  }
}

ok($lib_ref->SetSections(\@sections));
ok($lib_ref->WriteSettings());
ok($lib_ref->UpdateBootloader(1));

my $res = qx:grep -c 'measure /etc/security/selinux/policy.17 9' ./fake_root2/boot/grub/menu.lst:;
chomp($res);
is( $res, 1); #test correct created measure

$res = qx:grep -c "measure /opt/jdk1.4.2/jre/lib/security/java.policy 9" ./fake_root2/boot/grub/menu.lst:;
chomp($res);
is( $res, 1); #test correct created measure

$res = qx:grep -c "measure /opt/jdk1.4.2/jre/lib/security/java.security 8" ./fake_root2/boot/grub/menu.lst:;
chomp($res);
is( $res, 1); #test correct created measure

$res = qx:grep -c "kernel --pcr=7" ./fake_root2/boot/grub/menu.lst:;
chomp($res);
is( $res, 1); #test correct pcr for image

$res = qx:grep -c "initrd --pcr=7" ./fake_root2/boot/grub/menu.lst:;
chomp($res);
is( $res, 1); #test correct pcr for image

Bootloader::Tools::DumpLog( $lib_ref );
