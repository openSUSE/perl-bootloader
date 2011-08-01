use strict;
use Test::More tests => 1;

use lib "./";
use Bootloader::Library;
use Bootloader::Tools;

use Cwd;

$ENV{PERL_BOOTLOADER_TESTSUITE_PATH} = getcwd()."/fake_root1/";

my $core = Bootloader::Core->new();

#FIXME broken
#is(getcwd()."/fake_root1/boot", $core->ResolveCrossDeviceSymlinks(getcwd()."/fake_root1/boot/boot"));


#test heuristic for fitting sections
my %debug_section = (
                'original_name' => 'linux',
                'type' => 'image',
                'image' => '/boot/vmlinuz-2.6.25.4-10-debug',
                'initrd' => '/boot/initrd-2.6.25.4-10-debug',
                'name' => 'Debug -- openSUSE 11.0 - 2.6.25.4-10',
                'append' => 'resume=/dev/sda1 splash=silent showopts console=ttyS0,38400n52r'
    );
my %failsafe_section = (
                'original_name' => 'failsafe',
                'type' => 'image',
                'image' => '/boot/vmlinuz-2.6.25.4-10-default',
                'initrd' => '/boot/initrd-2.6.25.4-10-default',
                'name' => 'Default -- openSUSE 11.0 - 2.6.25.4-10 - Failsafe',
                'append' => 'resume=/dev/sda1 splash=silent showopts really secure option'
    );
my %default_section = (
                'original_name' => 'linux',
                'type' => 'image',
                'image' => '/boot/vmlinuz-2.6.25.4-10-default',
                'initrd' => '/boot/initrd-2.6.25.4-10-default',
                'name' => 'Default -- openSUSE 11.0 - 2.6.25.4-10',
                'append' => 'resume=/dev/sda1 splash=silent showopts'
    );
my %xen_section = (
                "type" => 'xen',
                "append" => 'resume=/dev/sda1 splash=silent showopts console=ttyS0,38400n52r',
                "image" => '/boot/vmlinuz-2.6.25.4-10-xen',
                "initrd" => '/boot/initrd-2.6.25.4-10-xen',
                "name" => 'XEN',
                "root" => '/dev/sda2',
                "xen" => '/boot/xen.gz',
                "xen_append" => 'console=com1 com1=38400n52r testparam=ok',
                "vgamode" => '0x332'
    );
my %non_image_section = (
                'original_name' => 'linux',
                'type' => 'other',
                'chainloader' => '/dev/fd0',
                'name' => 'FloppyDefault -- openSUSE 11.0 - 2.6.25.4-10',
                'append' => 'resume=/dev/sda1 splash=silent showopts'
    );

is( undef, Bootloader::Tools::GetFittingSection("linux","/boot/vmlinuz-default","image",[\%non_image_section]));
is( \%default_section, Bootloader::Tools::GetFittingSection("linux","/boot/vmlinuz-default","image",[\%non_image_section,\%default_section]));
is( \%xen_section, Bootloader::Tools::GetFittingSection("linux","/boot/vmlinuz-default","xen",[\%non_image_section,\%default_section,\%xen_section]));
is( \%default_section, Bootloader::Tools::GetFittingSection("linux","/boot/vmlinuz-default","image",[\%non_image_section,\%debug_section,\%default_section,\%xen_section,%failsafe_section]));
is( \%debug_section, Bootloader::Tools::GetFittingSection("linux","/boot/vmlinuz-debug","image",[\%non_image_section,\%debug_section,\%default_section,\%xen_section,\%failsafe_section]));
is( \%failsafe_section, Bootloader::Tools::GetFittingSection("linux failsafe","/boot/vmlinuz-default","image",[\%non_image_section,\%debug_section,\%default_section,\%xen_section,\%failsafe_section]));
