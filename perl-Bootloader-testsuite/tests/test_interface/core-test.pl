use strict;
use Test::More tests => 1;

use lib "./";
use Bootloader::Library;
use Bootloader::Tools;

use Cwd;

$ENV{PERL_BOOTLOADER_TESTSUITE_PATH} = getcwd()."/fake_root1/";

my $core = Bootloader::Core->new();

is(getcwd()."/fake_root1/boot", $core->ResolveCrossDeviceSymlinks(getcwd()."/fake_root1/boot/boot"));

