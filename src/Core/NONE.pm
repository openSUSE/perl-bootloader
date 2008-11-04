#! /usr/bin/perl -w
#
# Bootloader configuration base library
#

=head1 NAME

Bootlader::Core::NONE - library for blank configuration


=head1 PREFACE

This package is the NONE library of the bootloader configuration

=head1 SYNOPSIS

use Bootloader::Core::NONE;

C<< $obj_ref = Bootloader::Core::NONE->new (); >>

C<< $files_ref = Bootloader::Core::NONE->ListFiles (); >>

C<< $status = Bootloader::Core::NONE->ParseLines (\%files, $avoid_reading_device_map); >>

C<< $files_ref = Bootloader::Core::NONE->CreateLines (); >>

C<< $settings_ref = Bootloader::Core::NONE->GetSettings (); >>

C<< $status = Bootloader::Core::NONE->SetSettings (\%settings); >>

C<< $status = Bootloader::Core::NONE->InitializeBootloader (); >>


=head1 DESCRIPTION

=over 2

=cut


package Bootloader::Core::NONE;

use strict;

use Bootloader::Core;
our @ISA = ('Bootloader::Core');
use Bootloader::Path;

#module interface

sub GetMetaData() {
    my $loader = shift;

    my %exports;

    $exports{"global_options"} = {};

    $exports{"section_options"} = {};

    $loader->{"exports"}=\%exports;
    return \%exports;
}

=item
C<< $obj_ref = Bootloader::Core::NONE->new (); >>

Creates an instance of the Bootloader::Core::NONE class.

=cut

sub new {
    my $self = shift;
    my $old = shift;

    my $loader = $self->SUPER::new ($old);
    bless ($loader);

    $loader->l_milestone ("NONE::new: Created NONE instance");
    return $loader;
}

=item
C<< $files_ref = Bootloader::Core::NONE->ListFiles (); >>

Returns the list of the configuration files of the bootloader

=cut

# list<string> ListFiles ()
sub ListFiles {
    return []; 
}

=item
C<< $status = Bootloader::Core::NONE->ParseLines (\%files, $avoid_reading_device_map); >>

Simulate parsing lines. Do nothing. Return non-zero for success.

=cut

# void ParseLines (map<string,list<string>>, boolean)
sub ParseLines {
    return 1;
}


=item
C<< $files_ref = Bootloader::Core::NONE->CreateLines (); >>

Simulate creating lines and return empty lines hash structure.

=cut

# map<string,list<string>> CreateLines ()
sub CreateLines {
    return { };
}

=item
C<< $settings_ref = Bootloader::Core::NONE->GetSettings (); >>

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
C<< $status = Bootloader::Core::NONE->SetSettings (\%settings); >>

Do nothing, as none bootloader cannot change internal settings.

=cut

# void SetSettings (map<string,any> settings)
sub SetSettings {
    my $self = shift;
    return  1;
}

=item
C<< $status = Bootloader::Core::NONE->InitializeBootloader (); >>

Simulate initializing bootloader. Allways success.

=cut

# boolean InitializeBootloader ()
sub InitializeBootloader {
    my $self = shift;
    return 1;
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
