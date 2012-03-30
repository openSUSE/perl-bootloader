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

    return [];
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
    return {};
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

