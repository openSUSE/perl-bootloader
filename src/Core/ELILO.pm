#! /usr/bin/perl -w
#
# Bootloader configuration base library
#

=head1 NAME

Bootloader::Core::ELILO - ELILO library for bootloader configuration


=head1 PREFACE

This package is the ELILO library of the bootloader configuration

=head1 SYNOPSIS

use Bootloader::Core::ELILO;

C<< $obj_ref = Bootloader::Core::ELILO->new (); >>

C<< $files_ref = Bootloader::Core::ELILO->ListFiles (); >>

C<< $status = Bootloader::Core::ELILO->ParseLines (\%files); >>

C<< $files_ref = Bootloader::Core::ELILO->CreateLines (); >>

C<< $status = Bootloader::Core::ELILO->UpdateBootloader (); >>

C<< $status = Bootloader::Core::ELILO->InitializeBootloader (); >>

=head1 DESCRIPTION

=over 2

=cut


package Bootloader::Core::ELILO;

use strict;

use Bootloader::Core;
our @ISA = ('Bootloader::Core');

#module interface


sub GetMetaData() {
    my $loader = shift;
    
    # possible global entries
    #
    #     default=value       Name the default image to boot. If not defined ELILO
    #                         will boot the first defined image.
    #     timeout=number      The number of 10th of seconds to wait while in
    #                         interactive mode before auto booting default kernel.
    #                         Default is infinity.
    #     delay=number        The number of 10th of seconds to wait before
    #                         auto booting when not in interactive mode. 
    #                         Default is 0.
    #     prompt              Force interactive mode
    #     verbose=number      Set level of verbosity [0-5]. Default 0 (no verbose)
    #     root=filename       Set global root filesystem for Linux/ia64
    #     read-only           Force root filesystem to be mounted read-only
    #     append=string       Append a string of options to kernel command line
    #     initrd=filename     Name of initrd file
    #     image=filename      Define a new image
    #     chooser=name        Specify kernel chooser to use: 'simple' or 'textmenu'.
    #     message=filename    a message that is printed on the main screen if supported by 
    #                         the chooser.
    #     fX=filename         Some choosers may take advantage of this option to
    #                         display the content of a file when a certain function
    #                         key X is pressed. X can vary from 1-12 to cover 
    #                         function keys F1 to F12.
    #     noedd30             do not force the EDD30 EFI variable to TRUE when FALSE. In other
    #                         words, don't force the EDD30 mode if not set.
    #
    #
    # possible section types:
    #     image
    #
    # image section options:
    #     root=filename       Set root filesystem for kernel
    #     read-only           Force root filesystem to be mounted read-only
    #     append=string       Append a string of options to kernel command line
    #     initrd=filename     Name of initrd file
    #     label=string        Logical name of image (used in interactive mode)
    #     description=string  One line text description of the image.


    my %exports;
    
    my @bootpart;
    my @partinfo = @{$loader->{"partitions"} || []};
    
    # boot from any partition (really?)
    @bootpart = map {
        my ($device, $disk, $nr, $fsid, $fstype, $part_type, $start_cyl, $size_cyl) = @$_;
        $device;
    } @partinfo;
    
    my $boot_partitions = join(":", @bootpart);
    
    my $root_devices = join(":",
        map {
            my ($device, $disk, $nr, $fsid, $fstype, $part_type, $start_cyl, $size_cyl) = @$_;
            # FIXME: weed out non-root partitions
        } @ partinfo,
        keys %{$loader->{"md_arrays"} || {}}
    );
    
    # FIXME: is "arch" export necessary?
    
    $exports{"global_options"} = {
	# maps to either deafult or default_menu
        default => "string:Default Boot Section/Menu:linux",
        #default_menu => "string:Default Boot Menu:",
        #timeout => "int:Timeout in Seconds:5:0:60",
        #prompt => "bool:Show boot menu",
        #target => "path:Target directory for configuration/menu section:/boot/zipl",
    };
    
    my $go = $exports{"global_options"};
    
    $exports{"section_options"} = {
        type_image => "bool:Image Section",
        type_dump => "bool:Dump Section (obsolete)",
        type_menu => "bool:Menu Section",
        # section type image; omitting implicit "label"
        image_target => "path:Target Directory for Configuration Section:/boot/zipl",
        image_image => "path:Kernel Image:/boot/image",
        image_ramdisk => "path:Initial RAM Disk:/boot/initrd",
        image_parameters => "string:Optional Kernel Parameters",
        image_parmfile => "path:Optional Parameter File",
        # section type image; omitting implicit "label"
        dump_target => "path:Target Directory for Dump Section:/boot/zipl",
        dump_dumpto => "path:Dump Device:/dev/dasd",
        dump_dumptofs => "path:SCSI Dump Device:/dev/zfcp",
        # section type image; omitting implicit "label"
        menu_menuname => "string:Menu name:usermenu",
        menu_target => "path:Target Directory for Menu Section:/boot/zipl",
	menu_list => "string:List of Menu Entries:linux:",
	# menu_list => "list:List of Menu Entries:linux:",
	menu_default => "int:Number of Default Entry:1:1:10",
        menu_timeout => "int:Timeout in seconds:5:0:60",
        menu_prompt => "bool:Show boot menu",
        # FIXME: dump section has a target, too
    };
    
    my $so = $exports{"section_options"};
    
    $loader->{"exports"}=\%exports;
    return \%exports;
}


=item
C<< $obj_ref = Bootloader::Core::ELILO->new (); >>

Creates an instance of the Bootloader::Core::ELILO class.

=cut

sub new {
    my $self = shift;
    my $old = shift;

    my $loader = $self->SUPER::new ($old);
    $loader->{"default_global_lines"} = [
	{ "key" => "timeout", "value" => 80 },
	{ "key" => "read-only", "value" => "" },
	{ "key" => "relocatable", "value" => "" },
    ];
    bless ($loader);

    $loader->GetMetaData();
    $loader->l_milestone ("ELILO::new: Created ELILO instance");
    return $loader;
}

=item
C<< $files_ref = Bootloader::Core::ELILO->ListFiles (); >>

Returns the list of the configuration files of the bootloader
Returns undef on fail

=cut

my $default_conf = "/etc/elilo.conf";
#$default_conf = "/tmp/elilo.conf";

# list<string> ListFiles ();
sub ListFiles {
    my $self = shift;

    return [ $default_conf ];
}

# TODO document

sub FixSectionName {
    my $self = shift;
    my $name = shift;
    my $names_ref = shift;

    my $orig_name = $name;

    # replace unwanted characters by underscore, normally all printables
    # beside space equal sign and quote signs should be ok, no length limit
    $name =~ s/[^\w.-]/_/g;

    # and make the section name unique
    $name = $self->SUPER::FixSectionName($name, $names_ref, $orig_name);

    return $name;
}


=item
C<< $status = Bootloader::Core::ELILO->ParseLines (\%files); >>

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

    # the only file is /etc/elilo.conf
    my @elilo_conf = @{$files{$default_conf} || []};
    (my $glob_ref, my $sect_ref) = $self->ParseMenuFileLines (
	"=",
	["image"],
	\@elilo_conf
    );

    # handle global append information 
    my $glob_app = undef;
    my $flag = 0;
    foreach my $opt_ref (@{$glob_ref->{"__lines"}|| []})
    {
        my $key = $opt_ref->{"key"};
        my $val = $opt_ref->{"value"};
        if ($key eq "append")
        {
           $flag = 1;
           $glob_app = $val;
#          print STDERR "\nGLOBAL APPEND: $glob_app \n\n"; 
        }
    }
#   if(! $flag) {
#     print STDERR "\nNO GLOBAL APPEND!\n\n";
#   } 


    # handle section append information
    foreach my $sect_ref (@{$sect_ref} ) {
        my $sect_app = undef;
        my $sect_title = undef;
        foreach my $opt_ref (@{$sect_ref->{"__lines"}|| []})
        {
          my $key = $opt_ref->{"key"};
          my $val = $opt_ref->{"value"};
          if($key eq "label") {
            $sect_title = $val;
#            print STDERR "label name: $val\n";
          }
          if ($key eq "append") {
            $sect_app = $val;
          }
        }
        if( defined $sect_app ) {
#          print STDERR "SECTION $sect_title has APPEND: $sect_app \n";
	} else {
#          print STDERR "SECTION $sect_title has NO APPEND!\n";
        }
     }

    $self->{"sections"} = $sect_ref;
    $self->{"global"} = $glob_ref;

    return 1;

}

=item
C<< $files_ref = Bootloader::Core::ELILO->CreateLines (); >>

creates contents of all files from the internal structures.
Returns a hash reference in the same format as argument of
ParseLines on success, or undef on fail.

=cut

# map<string,list<string>> CreateLines ()
sub CreateLines {
    my $self = shift;

    if ($self->{"global"}{"__modified"} || 0) {
	my @lines = @{$self->{"global"}{"__lines"} || []};
	my @out_lines = ();
	foreach my $line_ref (@lines) {
	    push @out_lines, $line_ref;
	}
	$self->{"global"}{"__lines"} = \@out_lines;
    }
    foreach my $sect_ref (@{$self->{"sections"}} ) {
	my %sect = %{$sect_ref};
        my $append = undef;
        my $title = undef;
        my $kernel = undef;
#        foreach my $skey (keys %sect) {
#	    printf STDERR "%s: %s\n", $skey, $sect{$skey};
#        }
if(0){
        foreach my $opt_ref (@{$sect_ref->{"__lines"}|| []}) {
          my $key = $opt_ref->{"key"};
          my $val = $opt_ref->{"value"};
#	  print STDERR "$key = '$val'\n";
          if($key eq "image") {
            $kernel = $val;
          } elsif ($key eq "label") {
            $title = $val;
          } elsif ($key eq "append") {
            $append = $val;
          }
        }
}
	next unless defined( $title = $sect{"name"});
#        if( defined( $append) ) {
#          print STDERR "SECTION $title has APPEND: '$append'\n";
#	} else {
#          print STDERR "SECTION $title has NO APPEND!\n";
#        }
#	print STDERR "\n";
     }

    # create /etc/elilo.conf lines
    my $elilo_conf = $self->PrepareMenuFileLines (
	$self->{"sections"},
	$self->{"global"},
	"    ",
	" = "
    );
    if (! defined ($elilo_conf)) {
	return undef;
    }

    return {
	$default_conf => $elilo_conf,
    }
}

=item
C<< $status = Bootloader::Core::ELILO->UpdateBootloader (); >>

Updates the settings in the system. Backs original configuration files
up and replaces them with the ones with the '.new' suffix. Also performs
operations needed to make the change effect (run '/sbin/elilo').
Returns undef on fail, defined nonzero value on success.

=cut

# boolean UpdateBootloader ()
sub UpdateBootloader {
    my $self = shift;

    my $ret = $self->SUPER::UpdateBootloader ();
    return undef unless defined $ret;

    # FIXME: this is good-weather programming: /boot/efi is _always_ a
    #        FAT partition which has to be mounted
    system ("mkdir -p /boot/efi/efi/SuSE") unless -d "/boot/efi/efi/SuSE";
 
    return 0 == $self->RunCommand (
	"/sbin/elilo -v",
	"/var/log/YaST2/y2log_bootloader"
    );
}

=item
C<< $status = Bootloader::Core::ELILO->InitializeBootloader (); >>

Initializes the firmware to boot the bootloader.
Returns undef on fail, defined nonzero value otherwise

=cut

# boolean InitializeBootloader ()
sub InitializeBootloader {
    my $self = shift;

    # FIXME run EFI boot manager
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
