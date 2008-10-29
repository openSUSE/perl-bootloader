#! /usr/bin/perl -w
#
# Bootloader configuration base library
#

=head1 NAME

Bootlader::Core::NONE - library for blank configuration


=head1 PREFACE

This package is the NONE library of the bootloader configuration

=head1 SYNOPSIS

use Bootloader::Core::GRUB;

C<< $obj_ref = Bootloader::Core::GRUB->new (); >>

C<< $unquoted = Bootloader::Core::GRUB->Unquote ($text); >>

C<< $quoted = Bootloader::Core::GRUB->Quote ($text, $when); >>

C<< $unix_dev = Bootloader::Core::GRUB->UnixFile2UnixDev ($unix_file); >>

C<< $unix_dev = Bootloader::Core::GRUB->GrubDev2UnixDev ($grub_dev); >>

C<< $grub_dev = Bootloader::Core::GRUB->UnixDev2GrubDev ($unix_dev); >>

C<< $unix_path = Bootloader::Core::GRUB->GrubPath2UnixPath ($grub_path, $grub_dev_prefix); >>

C<< $grub_path = Bootloader::Core::GRUB->UnixPath2GrubPath ($unix_path, $grub_dev_prefix); >>

C<< $grub_conf_line_ref = Bootloader::Core::GRUB->CreateGrubConfLine ($target, $discswitch); >>

C<< $files_ref = Bootloader::Core::GRUB->ListFiles (); >>

C<< $status = Bootloader::Core::GRUB->ParseLines (\%files, $avoid_reading_device_map); >>

C<< $files_ref = Bootloader::Core::GRUB->CreateLines (); >>

C<< $dev = Bootloader::Core::GRUB->GetCommonDevice (@paths); >>

C<< $line = Bootloader::Core::GRUB->CreateKernelLine (\%sectingo, $grub_root); >>

C<< $line = Bootloader::Core::GRUB->CreateChainloaderLine (\%sectinfo, $grub_root); >>

C<< $disk = Bootloader::Core::GRUB->Partition2Disk ($partition); >>

C<< $sectin_info_ref = Bootloader::Core::GRUB->Section2Info (\@section_lines); >>

C<< $lines_ref = Bootloader::Core::GRUB->Info2Section (\%section_info); >>

C<< $glob_info = $Bootloader::Core::GRUB->Global2Info (\@glob_lines, \@section_names); >>

C<< $lines_ref = Bootloader::Core::GRUB->Info2Global (\%section_info, \@section_names); >>

C<< $settings_ref = Bootloader::Core::GRUB->GetSettings (); >>

C<< $status = Bootloader::Core::GRUB->SetSettings (\%settings); >>

C<< $status = Bootloader::Core::GRUB->InitializeBootloader (); >>

C<< $opt_types_ref = BootGrub->GetOptTypes (); >>

C<< $mountpoint = Bootloader::Core::GRUB->GrubDev2MountPoint ($grub_dev); >>


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
C<< $obj_ref = Bootloader::Core::GRUB->new (); >>

Creates an instance of the Bootloader::Core::GRUB class.

=cut

sub new {
    my $self = shift;
    my $old = shift;

    my $loader = $self->SUPER::new ($old);
    bless ($loader);

    $loader->l_milestone ("GRUB::new: Created NONE instance");
    return $loader;
}

=item
C<< $files_ref = Bootloader::Core::GRUB->ListFiles (); >>

Returns the list of the configuration files of the bootloader
Returns undef on fail

=cut

# list<string> ListFiles ()
sub ListFiles {
    return []; 
}

sub ListMenuFiles {
    return [];
}

=item
C<< $status = Bootloader::Core::GRUB->ParseLines (\%files, $avoid_reading_device_map); >>

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
C<< $files_ref = Bootloader::Core::GRUB->CreateLines (); >>

creates contents of all files from the internal structures.
Returns a hash reference in the same format as argument of
ParseLines on success, or undef on fail.

=cut

# map<string,list<string>> CreateLines ()
sub CreateLines {
    return { };
}

=item
C<< $settings_ref = Bootloader::Core::GRUB->GetSettings (); >>

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
C<< $status = Bootloader::Core::GRUB->SetSettings (\%settings); >>

Stores the settings in the given parameter to the internal
structures. Does not touch the system.
Returns undef on fail, defined nonzero value on success.

=cut

# void SetSettings (map<string,any> settings)
sub SetSettings {
    my $self = shift;
    return  1;
}

=item
C<< $status = Bootloader::Core::GRUB->InitializeBootloader (); >>

Initializes the firmware to boot the bootloader.
Returns undef on fail, defined nonzero value otherwise

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
