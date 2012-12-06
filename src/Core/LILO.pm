#! /usr/bin/perl -w
#
# Bootloader configuration base library
#

=head1 NAME

Bootloader::Core::LILO - LILO library for bootloader configuration


=head1 PREFACE

This package is the LILO library of the bootloader configuration

=head1 SYNOPSIS

use Bootloader::Core::LILO;

C<< $obj_ref = Bootloader::Core::LILO->new (); >>

C<< $files_ref = Bootloader::Core::LILO->ListFiles (); >>

C<< $status = Bootloader::Core::LILO->ParseLines (\%files, $avoid_reading_device_map); >>

C<< $files_ref = Bootloader::Core::LILO->CreateLines (); >>

C<< $status = Bootloader::Core::LILO->UpdateBootloader ($avoid_init); >>

C<< $status = Bootloader::Core::LILO->InitializeBootloader (); >>

=head1 DESCRIPTION

=over 2

=cut


package Bootloader::Core::LILO;

use strict;

use Bootloader::Path;
use Bootloader::Core;

our @ISA = qw ( Bootloader::Core );

#module interface

=item
C<< $obj_ref = Bootloader::Core::LILO->new (); >>

Creates an instance of the Bootloader::Core::LILO class.

=cut

sub new
{
  my $self = shift;
  my $ref = shift;
  my $old = shift;

  my $loader = $self->SUPER::new($ref, $old);
  bless($loader);

  $loader->{default_global_lines} = [
    { key => "menu-scheme", value => "Wb:kw:Wb:Wb" },
    { key => "timeout", value => 80 },
    { key => "lba32", value => "" },
    { key => "change-rules", value => "" },
    { key => "reset", value => "" },
    { key => "prompt", value => "" },
  ];

  $loader->milestone("Created LILO instance");

  return $loader;
}


=item
C<< $files_ref = Bootloader::Core::LILO->ListFiles (); >>

Returns the list of the configuration files of the bootloader
Returns undef on fail

=cut

# list<string> ListFiles ();
sub ListFiles {
    my $self = shift;

    return [ Bootloader::Path::Lilo_conf() ];
}

# TODO document

sub FixSectionName {
    my $self = shift;
    my $name = shift;
    my $names_ref = shift;

    my $orig_name = $name;

    # label tag for lilo.conf has a restricted valid character set and limited
    # allowed string length

    # Limit length to 11 characters:
    # cut off linux- prefix if found
    $name =~ s/^linux-//i 
	if length ($name)>11;

    while (length($name)>11) {
	# cut off last word, break if no more found
	last unless $name =~ s/ \S*$//;
    }
    
    $name = substr ($name, 0, 11)
	if length($name)>11;

    # then check not allowed chars
    $name =~ s/[^\w.-]/_/g;

    # and make the section name unique
    $name = $self->SUPER::FixSectionName($name, $names_ref, $orig_name);

    return $name;
}


=item
C<< $status = Bootloader::Core::LILO->ParseLines (\%files, $avoid_reading_device_map); >>

Parses the contents of all files and stores the settings in the
internal structures. As first argument, it takes a hash reference,
where keys are file names and values are references to lists, each
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

    # the only file is /etc/lilo.conf
    my @lilo_conf = @{$files{Bootloader::Path::Lilo_conf()} || []};
    (my $glob_ref, my $sect_ref) = $self->ParseMenuFileLines (
	"=",
	["image", "other"],
	\@lilo_conf
    );
    # get the device mapping from global options
    my %devmap = ();
    my $disk = undef;
    foreach my $opt_ref (@{$glob_ref->{"__lines"}|| []})
    {
	my $key = $opt_ref->{"key"};
	my $val = $opt_ref->{"value"};
	if ($key eq "disk")
	{
	    $disk = $val;
	}
	elsif ($key eq "bios" && defined ($disk))
	{
	    $val = oct ($val) - 0x80;
	    $val = "hd$val";
	    $devmap{$disk} = $val;
	    $disk = undef;
	}
    }

    $self->{"sections"} = $sect_ref;
    $self->{"global"} = $glob_ref;
    $self->{"device_map"} = \%devmap if (! $avoid_reading_device_map &&
					 scalar (keys (%devmap)) > 0);
    return 1;
}

sub BiosName2ID {
    my $self = shift;
    my $fw = shift;

    $fw = substr ($fw, 2);
    $fw = $fw + 0x80;
    $fw = sprintf ("0x\%x", $fw);
    return $fw;
}

=item
C<< $files_ref = Bootloader::Core::LILO->CreateLines (); >>

creates contents of all files from the internal structures.
Returns a hash reference in the same format as argument of
ParseLines on success, or undef on fail.

=cut

# map<string,list<string>> CreateLines ()
sub CreateLines {
    my $self = shift;

    if ($self->{"global"}{"__modified"} || 0)
    {
	my @lines = @{$self->{"global"}{"__lines"} || []};
	my @out_lines = ();
	foreach my $line_ref (@lines) {
	    if ($line_ref->{"key"} eq "disk")
	    {
		push @out_lines, $line_ref;
		my $sys = $line_ref->{"value"};
		if (exists ($self->{"device_map"}{$sys}))
		{
		    my $bios = $self->BiosName2ID ($self->{"device_map"}{$sys});
		    push @out_lines, {
			"key" => "bios",
			"value" => $bios,
		    };
		    delete ($self->{"device_map"}{$sys});
		}
	    }
	    elsif ($line_ref->{"key"} ne "bios")
	    {
		push @out_lines, $line_ref;
	    }
	}
	$self->{"global"}{"__lines"} = \@out_lines;
    }

    # create /etc/lilo.conf lines
    my $lilo_conf = $self->PrepareMenuFileLines (
	$self->{"sections"},
	$self->{"global"},
	"    ",
	" = "
    );
    if (! defined ($lilo_conf))
    {
	return undef;
    }

    return {
	"/etc/lilo.conf" => $lilo_conf,
    }
}

=item
C<< $status = Bootloader::Core::LILO->UpdateBootloader ($avoid_init); >>

Updates the settings in the system. Backs original configuration files
up and replaces them with the ones with the '.new' suffix. Also performs
operations needed to make the change effect (run '/sbin/lilo').
Returns undef on fail, defined nonzero value on success.

=cut

# boolean UpdateBootloader (boolean avoid_init)
sub UpdateBootloader {
    my $self = shift;
    my $avoid_init = shift;

    my $ret = $self->SUPER::UpdateBootloader ();
    if (! defined ($ret))
    {
	return undef;
    }
    if (! $avoid_init)
    {
	$ret = $self->InitializeBootloader ();
    }
    return $ret;
}

=item
C<< $status = Bootloader::Core::LILO->InitializeBootloader (); >>

Initializes the firmware to boot the bootloader.
Returns undef on fail, defined nonzero value otherwise

=cut

# boolean InitializeBootloader ()
sub InitializeBootloader {
    my $self = shift;

    return 0 == $self->RunCommand (
	Bootloader::Path::Lilo_lilo() . " -P ignore -v -v",
	Bootloader::Path::BootCommandLogname()
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
