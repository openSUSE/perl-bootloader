#! /usr/bin/perl -w
#
# Bootloader configuration base library
#

=head1 NAME

Bootloader::Core::PowerLILO - LILO library for bootloader configuration on POWER


=head1 PREFACE

This package is the LILO library of the bootloader configuration on POWER

=head1 SYNOPSIS

use Bootloader::Core::PowerLILO;

C<< $obj_ref = Bootloader::Core::PowerLILO->new (); >>

C<< $files_ref = Bootloader::Core::PowerLILO->ListFiles (); >>

C<< $status = Bootloader::Core::PowerLILO->ParseLines (\%files); >>

C<< $files_ref = Bootloader::Core::PowerLILO->CreateLines (); >>

C<< $status = Bootloader::Core::PowerLILO->UpdateBootloader ($avoid_init); >>

C<< $status = Bootloader::Core::PowerLILO->InitializeBootloader (); >>

=head1 DESCRIPTION

=over 2

=cut


package Bootloader::Core::PowerLILO;

use strict;

use Bootloader::Core;
our @ISA = ('Bootloader::Core');

#module interface

=item
C<< $obj_ref = Bootloader::Core::PowerLILO->new (); >>

Creates an instance of the Bootloader::Core::PowerLILO class.

=cut

sub new {
    my $self = shift;


# possible global entries:
#
#	boot (might be more than one)
#	clone
#	activate
#	force_fat
#	force
#	progressbar
#	bootfolder
#	timeout
#	default
#	append
#	initrd
#
#
# per section entries
#	image
#	other
#	root
#	copy
#	label
#	append
#	sysmap
#	initrd





    my $loader = $self->SUPER::new ();
    $loader->{"default_global_lines"} = [
	{ "key" => "activate", "value" => "" },
	{ "key" => "boot", "value" => "/dev/sda" },
	{ "key" => "default", "value" => "linux" },
    ];
    bless ($loader);
    $loader->l_milestone ("PowerLILO::new: Created PowerLILO instance");
    return $loader;
}

=item
C<< $files_ref = Bootloader::Core::PowerLILO->ListFiles (); >>

Returns the list of the configuration files of the bootloader
Returns undef on fail

=cut

# list<string> ListFiles ();
sub ListFiles {
    my $self = shift;

    return [ "/etc/lilo.conf" ];
}

# TODO document

sub FixSectionName {
    my $self = shift;
    my $label = shift;
    my $names_ref = shift;

    my $orig_label = $label;

    # first fix length
    if (length ($label) > 11 && substr (lc ($label), 0, 6) eq "linux-")
    {
	$label = substr ($label, 6);
    }
    if (length ($label) > 11)
    {
	$label = substr ($label, 0, 11);
    }

    # then check not allowed chars
    $label =~ s/[^a-zA-Z0-9_.-]/_/g;

    # and make the label unique
    if (scalar (grep {$_ eq $label} @$names_ref) > 1)
    {
	while (length ($label) > 5 && scalar (grep {$_ eq $label} @$names_ref) != 0)
	{
	    $label = substr ($label, 0, length ($label) - 1);
	}
	my $short_label = $label;
	my $index = 1;
	while (scalar (grep {$_ eq $label} @$names_ref) != 0)
	{
	    $label = $short_label . "_" . $index;
	    $index = $index + 1;
	}
    }

    # update list of section names
    for (my $i = 0; $i < $#$names_ref; $i++)
    {
	my $name = $names_ref->[$i];
	if ($name eq $orig_label)
	{
	    $names_ref->[$i] = $label;
	    last;	# stop it we're done
	}
    }

    return $label;
}

=item
C<< $status = Bootloader::Core::PowerLILO->ParseLines (\%files); >>

Parses the contents of all files and stores the settings in the
internal structures. As argument, it takes a hash reference, where
keys are file names and values are references to lists, each member is
one line of the file. Returns undef on fail, defined nonzero value on
success.

=cut

# void ParseLines (map<string,list<string>>)
sub ParseLines {
    my $self = shift;
    my %files = %{+shift};

    # the only file is /etc/lilo.conf
    my @lilo_conf = @{$files{"/etc/lilo.conf"} || []};
    (my $glob_ref, my $sect_ref) = $self->ParseMenuFileLines (
	"=",
	["image", "other"],
	\@lilo_conf
    );

    $self->{"sections"} = $sect_ref;
    $self->{"global"} = $glob_ref;
    return 1;
}


=item
C<< $files_ref = Bootloader::Core::PowerLILO->CreateLines (); >>

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
	    push @out_lines, $line_ref;
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
C<< $status = Bootloader::Core::PowerLILO->UpdateBootloader ($avoid_init); >>

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
C<< $status = Bootloader::Core::PowerLILO->InitializeBootloader (); >>

Initializes the firmware to boot the bootloader.
Returns undef on fail, defined nonzero value otherwise

=cut

# boolean InitializeBootloader ()
sub InitializeBootloader {
    my $self = shift;

    return 0 == $self->RunCommand (
	"/sbin/lilo",
	"/var/log/YaST2/y2log_tool_lilo"
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
