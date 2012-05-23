#! /usr/bin/perl -w
#
# Bootloader configuration base library
#

=head1 NAME

Bootlader::Core::GRUB2EFI - library for blank configuration


=head1 PREFACE

This package is the GRUB2EFI library of the bootloader configuration

=head1 SYNOPSIS

use Bootloader::Core::GRUB2EFI;

C<< $obj_ref = Bootloader::Core::GRUB2EFI->new (); >>

C<< $files_ref = Bootloader::Core::GRUB2EFI->ListFiles (); >>

C<< $status = Bootloader::Core::GRUB2EFI->ParseLines (\%files, $avoid_reading_device_map); >>

C<< $files_ref = Bootloader::Core::GRUB2EFI->CreateLines (); >>

C<< $settings_ref = Bootloader::Core::GRUB2EFI->GetSettings (); >>

C<< $status = Bootloader::Core::GRUB2EFI->SetSettings (\%settings); >>

C<< $glob_info = Bootloader::Core::GRUB2EFI->Global2Info (\@glob_lines, \@section_names); >>

C<< $lines_ref = Bootloader::Core::GRUB2EFI->Info2Global (\%section_info, \@section_names); >>

C<< $status = Bootloader::Core::GRUB2EFI->UpdateBootloader (); >>

C<< $status = Bootloader::Core::GRUB2EFI->InitializeBootloader (); >>


=head1 DESCRIPTION

=over 2

=cut

package Bootloader::Core::GRUB2EFI;

use strict;

use Bootloader::Core;
our @ISA = ('Bootloader::Core');
use Bootloader::Path;

use Data::Dumper;

#module interface

=item
C<< $obj_ref = Bootloader::Core::GRUB2EFI->new (); >>

Creates an instance of the Bootloader::Core::GRUB2EFI class.

=cut

sub new {
    my $self = shift;
    my $old = shift;

    my $loader = $self->SUPER::new ($old);
    bless ($loader);

    $loader->l_milestone ("GRUB2EFI::new: Created GRUB2EFI instance");
    return $loader;
}



=item
C<< $files_ref = Bootloader::Core::GRUB2EFI->ListFiles (); >>

Returns the list of the configuration files of the bootloader
Returns undef on fail

=cut

# list<string> ListFiles ()
sub ListFiles {
    my $self = shift;

    return [ Bootloader::Path::Grub2_defaultconf(),
             Bootloader::Path::Grub2_eficonf() ];
}


=item
C<< $status = Bootloader::Core::GRUB2EFI->ParseLines (\%files, $avoid_reading_device_map); >>

Parses the contents of all files and stores the settings in the
internal structures. As first argument, it takes a hash reference, where
keys are file names and values are references to lists, each
member is one line of the file. As second argument, it takes a
boolean flag that, if set to a true value, causes it to skip
updating the internal device_map information. Returns undef on
fail, defined nonzero value on success.

=cut

# void ParseLines (map<string,list<string>>, boolean)
sub ParseLines {
    my $self = shift;
    my %files = %{+shift};
    my $avoid_reading_device_map = shift;

    # and now proceed with /etc/default/grub
    my @defaultconf = @{$files{Bootloader::Path::Grub2_defaultconf()} || []};
    $self->l_milestone ("GRUB2::Parselines: input from default conf :\n'" .
                        join("'\n' ", @defaultconf) . "'");

    # prefix commented config with '@' instread of '#'
    # this is to new notation for "commented config" and
    # need to process saparately
    foreach my $conf (@defaultconf) {
        if ($conf =~ m/^\s*#\s*GRUB_/) {
            $conf =~ s/^\s*#/@/;
        }
    }

    (my $glob_ref, my $sect_ref) = $self->ParseMenuFileLines (
        "=",
        [],
        \@defaultconf
    );

    my @confs = @{$files{Bootloader::Path::Grub2_eficonf()} || []};
    my @entries = ();
    foreach my $conf (@confs) {
        if ($conf =~ /^menuentry\s+['"](.*)['"]\s+/) {
	    push @entries, { "menuentry" =>  $1 };
        }
    }

    $self->{"global"} = $glob_ref;
    $self->{"sections"} = \@entries;

    return 1;
}

=item
C<< $files_ref = Bootloader::Core::GRUB2EFI->CreateLines (); >>

creates contents of all files from the internal structures.
Returns a hash reference in the same format as argument of
ParseLines on success, or undef on fail.

=cut

# map<string,list<string>> CreateLines ()
sub CreateLines {
    my $self = shift;
    my $global = $self->{"global"};

    if (defined $global->{"__lines"}) {
        foreach my $line (@{$global->{"__lines"}}) {
             if (defined $line->{"value"} && $line->{"value"} eq "" ) {
                 $line->{"value"} = '""';
             }
        }
    }

    my $grub2_defaultconf = $self->PrepareMenuFileLines (
        [],
        $global,
        "",
        "="
    );

    foreach my $conf (@{$grub2_defaultconf}) {
        if ($conf =~ m/^\s*@\s*GRUB_/) {
            $conf =~ s/^\s*@/#/;
        }
    }

    return { Bootloader::Path::Grub2_defaultconf() => $grub2_defaultconf };
}

=item
C<< $glob_info = $Bootloader::Core::GRUB2EFI->Global2Info (\@glob_lines, \@section_names); >>

Gets the general information from the global section of the menu file. This information
usually means the default section, graphical menu, timeout etc. As argument it takes
a reference to the list of hashes representing lines of the section, returns a reference
to a hash containing the important information.

=cut

# map<string,string> Global2Info (list<map<string,any>> global, list<string>sections)

sub Global2Info {
    my $self = shift;
    my @lines = @{+shift};
    my @sections = @{+shift};

    my %ret = ();
    $ret{"__lines"} = \@lines;

    my $timeout;
    my $hidden_timeout;

    foreach my $line_ref (@lines) {
        my $key = $line_ref->{"key"};
        my $val = $line_ref->{"value"};

        # Check if key is defined to prevent perl warnings
        next if (!defined($key));

        if ($key =~ m/@?GRUB_CMDLINE_LINUX_DEFAULT$/)
        {
            if ($val =~ /^(?:(.*)\s+)?vga=(\S+)(?:\s+(.*))?$/)
            {
                $ret{"vgamode"} = $2 if $2 ne "";
                $val = $self->MergeIfDefined ($1, $3);
            }

            $ret{"append"} = $val;
        } elsif ($key =~ m/@?GRUB_TIMEOUT$/) {
            $timeout = $val;
        } elsif ($key =~ m/@?GRUB_HIDDEN_TIMEOUT$/) {
            $hidden_timeout = $val;
        } elsif ($key =~ m/@?GRUB_TERMINAL/) {
            if ($val =~ m/^(serial|console|gfxterm)$/) {
                $ret{"terminal"} = $val;
            }
        } elsif ($key =~ m/@?GRUB_SERIAL_COMMAND/) {
            $ret{"serial"} = $val;
        } elsif ($key =~ m/@?GRUB_GFXMODE/) {
            $ret{"gfxmode"} = $val;
        } elsif ($key =~ m/@?GRUB_BACKGROUND/) {
            $ret{"gfxbackground"} = $val;
        }
    }

    if (defined $timeout) {
        if ($timeout == 0) {
            if (defined $hidden_timeout) {
                $ret{"timeout"} = $hidden_timeout;
                $ret{"hiddenmenu"} = "true";
            } else {
                $ret{"timeout"} = $timeout;
                $ret{"hiddenmenu"} = "true";
            }
        } else {
            $ret{"timeout"} = $timeout;
            $ret{"hiddenmenu"} = "false";
        }
    }

    return \%ret;
}

=item
C<< $lines_ref = Bootloader::Core::GRUB2EFI->Info2Global (\%section_info, \@section_names); >>

Takes the info about the global options and uses it to construct the list of lines.
The info about global option also contains the original lines.
As parameter, takes the section info (reference to a hash) and a list of sectino names,
returns the lines (a list of hashes).

=cut

# list<map<string,any>> Info2Global (map<string,string> info, list<string>sections)

sub Info2Global {
    my $self = shift;
    my %globinfo = %{+shift};
    my $sections_ref = shift;

    my @lines = @{$globinfo{"__lines"} || []};

    # my $sysconf =  Bootloader::Tools::GetSysconfigValue("DEFAULT_APPEND");
    # allow to keep the section unchanged
    return \@lines unless $globinfo{"__modified"} || 0;

    if (scalar (@lines) == 0)
    {
        @lines = (
            {
                'key' => 'GRUB_DISTRIBUTOR',
                'value' => '"openSUSE"',
                'comment_before' => [
                  '# If you change this file, run \'grub2-mkconfig -o /boot/grub2/grub.cfg\' afterwards to update',
                  '# /boot/grub2/grub.cfg.'
                ],
            },
            {
                'key' => 'GRUB_DEFAULT',
                'value' => 'saved',
            },
            {
                'key' => 'GRUB_HIDDEN_TIMEOUT',
                'value' => '0',
            },
            {
                'key' => 'GRUB_HIDDEN_TIMEOUT_QUIET',
                'value' => 'true',
            },
            {
                'key' => 'GRUB_TIMEOUT',
                'value' => '10',
            },
            {
                'key' => 'GRUB_CMDLINE_LINUX_DEFAULT',
                'value' => 'quiet splash=silent',
            },
            {
                'key' => 'GRUB_CMDLINE_LINUX',
                'value' =>  '""',
            },
            {
                'key' => '@GRUB_BADRAM',
                'value' => '"0x01234567,0xfefefefe,0x89abcdef,0xefefefef"',
                'comment_before' => [
                  '# Uncomment to enable BadRAM filtering, modify to suit your needs',
                  '# This works with Linux (no patch required) and with any kernel that obtains',
                  '# the memory map information from GRUB (GNU Mach, kernel of FreeBSD ...)'
                ],
            },
            {
                'key' => '@GRUB_TERMINAL',
                'value' => 'console',
                'comment_before' => [
                  '# Uncomment to disable graphical terminal (grub-pc only)'
                ],
            },
            {
                'key' => '@GRUB_GFXMODE',
                'value' => '640x480',
                'comment_before' => [
                  '# The resolution used on graphical terminal',
                  '# note that you can use only modes which your graphic card supports via VBE',
                  '# you can see them in real GRUB with the command `vbeinfo\''
                ],
            },
            {
                'key' => '@GRUB_DISABLE_LINUX_UUID',
                'value' => 'true',
                'comment_before' => [
                  '# Uncomment if you don\'t want GRUB to pass "root=UUID=xxx" parameter to Linux'
                ],
            },
            {
                'key' => '@GRUB_DISABLE_LINUX_RECOVERY',
                'value' => 'true',
                'comment_before' => [
                  '# Uncomment to disable generation of recovery mode menu entries'
                ],
            },
            {
                'key' => '@GRUB_INIT_TUNE',
                'value' => '480 440 1',
                'comment_before' => [
                  '# Uncomment to get a beep at grub start'
                ],
            },
        );

    }

    # We don't need to set root= as grub2-mkconfig
    # already detect that for us ..
    # my $root = delete $globinfo{"root"} || "";
    my $vga = delete $globinfo{"vgamode"} || "";
    my $append = delete $globinfo{"append"} || "";
    my $timeout = delete $globinfo{"timeout"} || "";
    my $hiddenmenu = delete $globinfo{"hiddenmenu"} || "";
    my $terminal = delete $globinfo{"terminal"} || "";
    my $serial = delete $globinfo{"serial"} || "";
    my $gfxmode = delete $globinfo{"gfxmode"} || "";
    my $gfxbackground = delete $globinfo{"gfxbackground"} || "";
    # $root = " root=$root" if $root ne "";
    $vga = " vga=$vga" if $vga ne "";
    $append = " $append" if $append ne "";

    my $hidden_timeout = "$timeout";
    if ("$hiddenmenu" eq "true") {
        $timeout = "0" if "$timeout" ne "";
    } else {
        $hidden_timeout = "0" if "$hidden_timeout" ne "";
    }

    @lines = map {
        my $line_ref = $_;
        my $key = $line_ref->{"key"};
        if ($key =~ m/@?GRUB_CMDLINE_LINUX_DEFAULT$/)
        {
            $line_ref->{"value"} = "$append$vga" if "$append$vga" ne "";
            $append = "";
            $vga = "";
        } elsif ($key =~ m/@?GRUB_TIMEOUT$/) {
            $line_ref->{"value"} = "$timeout" if "$timeout" ne "";
            $timeout = "";
        } elsif ($key =~ m/@?GRUB_HIDDEN_TIMEOUT$/) {
            $line_ref->{"value"} = "$hidden_timeout" if "$hidden_timeout" ne "";
            $hidden_timeout = "";
        } elsif ($key =~ m/@?GRUB_SERIAL_COMMAND/) {
            if ($serial eq "") {
                $line_ref->{"key"} = '@GRUB_SERIAL_COMMAND';
            } else {
                $line_ref->{"key"} = "GRUB_SERIAL_COMMAND";
                $line_ref->{"value"} = $serial;
                $serial = "";
            }
        } elsif ($key =~ m/@?GRUB_GFXMODE/) {
            if ($gfxmode ne "") {
                $line_ref->{"key"} = "GRUB_GFXMODE";
                $line_ref->{"value"} = $gfxmode;
            }
            $gfxmode = "";
        } elsif ($key =~ m/@?GRUB_BACKGROUND/) {
            if ($gfxbackground ne "") {
                $line_ref->{"key"} = "GRUB_BACKGROUND";
                $line_ref->{"value"} = $gfxbackground;
            } else {
                $line_ref = undef;
            }
            $gfxbackground = "";
        } elsif ($key =~ m/@?GRUB_TERMINAL/) {
            if ($terminal eq "") {
                $line_ref->{"key"} = '@GRUB_TERMINAL';
                $line_ref->{"value"} = "console";
            } else {
                $line_ref->{"key"} = "GRUB_TERMINAL";
                if ($terminal =~ m/^(serial|console|gfxterm)$/) {
                    $line_ref->{"value"} = "$terminal" if "$terminal" ne "";
                }
                $terminal = "";
            }
        }
        defined $line_ref ? $line_ref : ();
    } @lines;

    if ("$append$vga" ne "") {
        push @lines, {
            "key" => "GRUB_CMDLINE_LINUX_DEFAULT",
            "value" => "$append$vga",
        }
    }

    if ("$timeout" ne "") {
        push @lines, {
            "key" => "GRUB_TIMEOUT",
            "value" => "$timeout",
        }
    }

    if ("$hidden_timeout" ne "") {
        push @lines, {
            "key" => "GRUB_HIDDEN_TIMEOUT",
            "value" => "$hidden_timeout",
        }
    }

    if ($terminal ne "") {
        push @lines, {
            "key" => "GRUB_TERMINAL",
            "value" => "$terminal",
        }
    }

    if ($serial ne "") {
        push @lines, {
            "key" => "GRUB_SERIAL_COMMAND",
            "value" => "$serial",
        }
    }

    if ($gfxmode ne "") {
        push @lines, {
            "key" => "GRUB_GFXMODE",
            "value" => "$gfxmode",
        }
    }

    if ($gfxbackground ne "") {
        push @lines, {
            "key" => "GRUB_BACKGROUND",
            "value" => "$gfxbackground",
        }
    }

    return \@lines;
}

=item
C<< $settings_ref = Bootloader::Core::GRUB2EFI->GetSettings (); >>

returns the complete settings in a hash. Does not read the settings
from the system, but returns internal structures.

=cut

# map<string,any> GetSettings ()
sub GetSettings {
    my $self = shift;
    my $ret = $self->SUPER::GetSettings ();

    my $sections = $ret->{"sections"};
    my $globals = $ret->{"global"};
    my $saved_entry = `/usr/bin/grub2-efi-editenv list|sed -n '/^saved_entry=/s/.*=//p'`;

    chomp $saved_entry;
    if ($saved_entry ne "") {
        if ($saved_entry =~ m/^\d+$/) {
            my $sect = $sections->[$saved_entry];

            if (defined $sect) {
                $globals->{"default"} = $sect->{"menuentry"};
            }
        } else {
            $globals->{"default"} = $saved_entry;
        }
    }

    return $ret;
}

=item
C<< $status = Bootloader::Core::GRUB2EFI->SetSettings (\%settings); >>

Stores the settings in the given parameter to the internal
structures. Does not touch the system.
Returns undef on fail, defined nonzero value on success.

=cut

# void SetSettings (map<string,any> settings)
sub SetSettings {
    my $self = shift;
    my %settings = %{+shift};

    my $default  = delete $settings{"global"}->{"default"};

    if (defined $default and $default ne "") {
        $self->RunCommand (
            "/usr/sbin/grub2-efi-set-default '$default'",
            "/var/log/YaST2/y2log_bootloader"
        );
    }

    return $self->SUPER::SetSettings (\%settings);
}


=item
C<< $status = Bootloader::Core::GRUB2EFI->UpdateBootloader (); >>

Updates the settings in the system. Backs original configuration files
up and replaces them with the ones with the '.new' suffix. Also performs
operations needed to make the change effect (run '/sbin/elilo').
Returns undef on fail, defined nonzero value on success.

=cut

# boolean UpdateBootloader ()
sub UpdateBootloader {
    my $self = shift;
    my $avoid_init = shift;

    # backup the config file
    # it really did nothing for now
    my $ret = $self->SUPER::UpdateBootloader ();

    return undef unless defined $ret;

    if (! $avoid_init)
    {
        return $self->InitializeBootloader ();
    }

    return 0 == $self->RunCommand (
        "/usr/sbin/grub2-efi-mkconfig -o /boot/grub2-efi/grub.cfg",
        "/var/log/YaST2/y2log_bootloader"
    );
}


=item
C<< $status = Bootloader::Core::GRUB2EFI->InitializeBootloader (); >>

Initializes the firmware to boot the bootloader.
Returns undef on fail, defined nonzero value otherwise

=cut

# boolean InitializeBootloader ()
sub InitializeBootloader {
    my $self = shift;

    my $ret = $self->RunCommand (
        "/usr/sbin/grub2-efi-install",
        "/var/log/YaST2/y2log_bootloader"
    );

    return 0 if (0 != $ret);

    return 0 == $self->RunCommand (
        "/usr/sbin/grub2-efi-mkconfig -o /boot/grub2-efi/grub.cfg",
        "/var/log/YaST2/y2log_bootloader"
    );
}

1;

#
# Local variables:
#     mode: perl
#     mode: font-lock
#     mode: auto-fill
#     fill-column: 78
# End:
#

