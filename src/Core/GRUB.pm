#! /usr/bin/perl -w
#
# Bootloader configuration base library
#

=head1 NAME

Bootlader::Core::GRUB - GRUB library for bootloader configuration


=head1 PREFACE

This package is the GRUB library of the bootloader configuration

=head1 SYNOPSIS

use Bootloader::Core::GRUB;

C<< $obj_ref = Bootloader::Core::GRUB->new (); >>

C<< $unquoted = Bootloader::Core::GRUB->Unquote ($text); >>

C<< $quoted = Bootloader::Core::GRUB->Quote ($text, $when); >>

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

C<< $mountpoint = Bootloader::Core::GRUB->GrubDev2MountPoint ($grub_dev); >>


=head1 DESCRIPTION

=over 2

=cut


package Bootloader::Core::GRUB;

use strict;

use Bootloader::Path;
use Bootloader::Core;

our @ISA = qw ( Bootloader::Core );

# Internal metadata only for checking of valid values, doesn't affect any yast
sub GetOptions{
  my $loader = shift;
  
  my %options;
  $options{"global_options"} = {
        boot     => "",
        activate => "bool",
        color => "",
        timeout  => "",
        default  => "",
        generic_mbr => "bool",
        boot_custom => "",
        boot_mbr => "bool",
        boot_root => "bool",
        boot_boot => "bool",
        boot_extended => "bool",
        serial => "",
        terminal => "",
        fallback => "",
        hiddenmenu => "bool",
        gfxmenu => "path",
        password => "",
        debug => "bool",
        configfile => "path",
        setkeys => ""
  };

  $options{"section_options"} = {
	image_name     => "",
	image_image       => "path",
	image_root        => "",
	image_vgamode     => "",
	image_append      => "",
	image_initrd      => "path",
	image_noverifyroot=> "bool",

	other_lock        => "bool",
	other_chainloader => "",
	other_noverifyroot=> "bool",
	other_makeactive  => "bool",
	other_blockoffset => "",

	xen_xen => "",
	xen_xen_append    => "",
	xen_image         => "path",
	xen_root          => "",
	xen_vgamode       => "",
	xen_append        => "",
	xen_initrd        => "path",

	menu_root         => "",
	menu_configfile   => "path"
  };
  $loader->{"options"}=\%options;
}

#end of internal metadata


=item
C<< $obj_ref = Bootloader::Core::GRUB->new (); >>

Creates an instance of the Bootloader::Core::GRUB class.

=cut


sub new
{
  my $self = shift;
  my $ref = shift;
  my $old = shift;

  my $loader = $self->SUPER::new($ref, $old);
  bless($loader);

  $loader->GetOptions();

  $loader->milestone("Created GRUB instance");

  return $loader;
}


# internal routines

=item
C<< $unquoted = Bootloader::Core::GRUB->Unquote ($text); >>

Just override of Bootloader::Core->Unquote function, returning the first parameter.

=cut

# string Unquote (string text)
sub Unquote {
    my $self = shift;
    my $text = shift;

    return $text;
}

=item
C<< $quoted = Bootloader::Core::GRUB->Quote ($text, $when); >>

Just override of Bootloader::Core->Quote function, returning the first parameter.

=cut

# string Quote (string text, string when)
sub Quote {
    my $self = shift;
    my $text = shift;
    my $when = shift;

    return $text;
}

=item
C<< $allow_afterline_empty = Bootloader::Core->AllowCommentAfterText(); >>

checks if bootloader configuration allow comments after text on line,
returns a scalar (1 if true, 0 otherwise).

=cut

# boolean MenuFileLineEmpty (string line)
sub AllowCommentAfterText {
  return 0;
}


sub GetKernelDevice
{
  my $self = shift;
  my $orig = shift;

  my $dev = $self->{cache}{kerneldevice}{$orig};
  if(defined $dev) {
    $self->milestone("(cached): $orig => $dev");
    return $dev;
  }

  if(defined $self->{udevmap}) {
    $dev = $self->{udevmap}{$orig};
  }
  else {
    $self->warning("udev mapping is not set");
  }

  $dev = $orig if !defined $dev;

  $self->{cache}{kerneldevice}{$orig} = $dev;

  $self->milestone("$orig => $dev");

  return $dev;
}


=item
C<< $unix_dev = Bootloader::Core::GRUB->GrubDev2UnixDev ($grub_dev); >>

Translates the GRUB device (eg. '(hd0,0)') to UNIX device (eg. '/dev/hda1').
As argument takes the GRUB device, returns the UNIX device (both strings)
or argument if translate fail.

=cut

# string GrubDev2UnixDev (string grub_dev)
sub GrubDev2UnixDev
{
  my $self = shift;
  my $dev = shift;
  my $u_dev;
  local $_;

  $self->milestone("device = $dev");

  if($dev eq "") {
    $self->error("empty device to translate");
    return $dev;
  }

  if($dev !~ /^\(.*\)$/) {
    $self->warning("not a grub device: $dev");
    return $dev;
  }

  my $original = $dev;

  $u_dev = $self->{cache}{grub2unix}{$original};
  if(defined $u_dev) {
    $self->milestone("translated (cached): $original => $u_dev");
    return $u_dev;
  }

  my $partition = undef;

  # check if $dev consists of something like (hd0,0), thus a grub device
  if($dev =~ /\(([^,]+),([^,]+)\)/) {
    $dev = $1;
    $partition = $2 + 1;
  }
  elsif ($dev =~ /\(([^,]+)\)/) {
    $dev = $1;
  }

  for(keys %{$self->{device_map}}) {
    if($self->{device_map}{$_} eq $dev) {
      $u_dev = $self->GetKernelDevice($_);
      last;
    }
  }

  if(!defined $u_dev) {
    $self->error("$dev not in device map");
  }
  elsif(defined $partition) {
    my $part_ok;
    for(@{$self->{partitions}}) {
      if($_->[1] eq $u_dev && $_->[2] == $partition) {
        $u_dev = $_->[0];
        $part_ok = 1;
        last;
      }
    }
    if(!$part_ok) {
      # partition not found, making something up...
      if($dev =~ m#^/dev/(?:vx|das|[ehpsvx])d[a-z]{1,2}$#) {
        $u_dev .= "";
      }
      elsif($dev =~ m#^/dev/disk/#) {
        $u_dev .= "-part";
      }
      elsif($original =~ m#^/dev(?:/[^/]+){1,2}$#) {
        $u_dev .= "p";
      }
      $u_dev .= $partition;

      $self->warning("partition $partition not found, guessing $u_dev");
    }
  }

  $u_dev = $self->Member2MD($u_dev) if defined $u_dev;

  # FIXME: returning original value, is that really sensible?
  $u_dev = $original if !defined $u_dev;

  $self->{cache}{grub2unix}{$original} = $u_dev;

  $self->milestone("translated: $original => $u_dev");

  return $u_dev;
}


=item
C<< $grub_dev = Bootloader::Core::GRUB->UnixDev2GrubDev ($unix_dev); >>

Translates the UNIX device (eg. '/dev/hda1') to GRUB device (eg. '(hd0,0)').
As argument takes the UNIX device, returns the GRUB device (both strings).

=cut

# Pattern for grub device specification. Please note that this does not work
# with BSD labeled disks which use things like "hd0,b"
# The pattern matches disk or floppy or network or cd
my $grubdev_pattern = "(?:hd\\d+(?:,\\d+)?|fd\\d+|nd|cd)";

# string UnixDev2GrubDev (string unix_dev)
sub UnixDev2GrubDev
{
  my $self = shift;
  my $dev = shift;
  my $g_dev;
  local $_;

  $self->milestone("device = $dev");

  if($dev eq "") {
    $self->error("empty device to translate");
    return ""; # return an error
  }

  # seems to be a grub device already 
  if($dev =~ /^\(${grubdev_pattern}\)$/) {
    $self->warning("not a unix device: $dev");
    return $dev;
  }

  # remove parenthesis to be able to handle entries like "(/dev/sda1)" which
  # might be there by error
  $dev =~ s/^\((.*)\)$/$1/;

  # This gives me the devicename, whether $dev is the device or a link!
  # This works for udev (kernel) devices only, devicemapper doesn't 
  # need to be changed here 

  my $original = $dev;

  $g_dev = $self->{cache}{unix2grub}{$original};
  if(defined $g_dev) {
    $self->milestone("translated (cached): $original => $g_dev");
    return $g_dev;
  }

  my $kernel_dev = $self->GetKernelDevice($dev);

  my $partition = undef;

  if($kernel_dev =~ m#/dev/md\d+#) {
    my @members = @{$self->MD2Members ($kernel_dev) || []};
    # FIXME! This only works for mirroring (Raid1)
    $kernel_dev = $self->GetKernelDevice($members[0] || $kernel_dev );
    $self->milestone("first device of MDRaid: $original -> $kernel_dev");
  }

  # fetch the underlying device (sda1 --> sda)
  for(@{$self->{partitions}}) {
    if($_->[0] eq $kernel_dev) {
      $kernel_dev = $_->[1];
      $partition = $_->[2] - 1;
      $self->milestone("device disk part: $_->[0] $_->[1] $_->[2]");
      last;
    }
  }

  for(sort keys %{$self->{device_map}}) {
    if($kernel_dev eq $self->GetKernelDevice($_)) {
      $g_dev = $self->{device_map}{$_};
      last;
    }
  }

  # fallback if translation has failed - this is good enough for many cases
  # FIXME: this is nonsense - we should return an error
  if(!$g_dev) {
    $self->warning("unknown device/partition, using fallback");

    $g_dev = "hd0";
    $partition = undef;

    if(
      $original =~ m#^/dev/(?:vx|das|[ehpsvx])d[a-z]{1,2}(\d+)$# ||
      $original =~ m#^/dev/\S+\-part(\d+)$# ||
      $original =~ m#^/dev(?:/[^/]+){1,2}p(\d+)$#
    ) {
      $partition = $1 - 1;
      $partition = 0 if $partition < 0;
    }
  }

  if(defined $partition) {
    $g_dev = "($g_dev,$partition)";
    $self->milestone("translated partition: $original => $g_dev");
  }
  else {
    $g_dev = "($g_dev)";
    $self->milestone("translated device: $original => $g_dev");
  }

  $self->{cache}{unix2grub}{$original} = $g_dev;

  return $g_dev;
}


=item
C<< $unix_path = Bootloader::Core::GRUB->GrubPath2UnixPath ($grub_path, $grub_dev_prefix); >>

Translates the GRUB path (eg. '(hd0,0)/grub/device.map') to UNIX path (eg.
'/boot/grub/device.map'). If the GRUB path does not contain the device, the one
specified in the argument is used instead.
As arguments, the function takes the GRUB path and the device to be used if not
specified in the GRUB path, and returns the UNIX path (all strings).

=cut

# string GrubPath2UnixPath (string grub_path, string grub_dev_prefix)
sub GrubPath2UnixPath {
    my $self = shift;
    my $path = shift;
    my $dev = shift;

    my $orig_path = $path;
    if ($path =~ /^(\(.+\))(.+)$/) {
	$dev = $1;
	$path = $2;
    }
    else {
	$orig_path = $dev . $path;
    }

    if ($dev eq "") {
	$self->milestone("Path $orig_path in UNIX form, not modifying it");
	return $orig_path;
    }

    #FIXME: sf@ need to check for udev links here as well
    #$dev = $self->GrubDev2UnixDev ($dev);
    #$dev = $self->Member2MD ($dev);

    my $mountpoint;
    if ($dev) {
	 $mountpoint = $self->GrubDev2MountPoint($dev)
    }
    else {
	$mountpoint = $dev;
    }

=cut
    while ((my $mp, my $d) = each (%{$self->{"mountpoints"}})) {
	if ($d eq $dev) {
	    $mountpoint = $mp;
	}
    }
=cut

    # no mount point found 
    if ($mountpoint eq $dev) {
	$self->milestone("Device $dev does not have mount point, keeping GRUB path $orig_path");
	return $orig_path;
    }

    $path = $mountpoint . $path;
    $path = $self->CanonicalPath ($path);
    $self->debug("Translated GRUB->UNIX dev: $dev, path: $orig_path to: $path");

    return $path;
}

=item
C<< $grub_path = Bootloader::Core::GRUB->UnixPath2GrubPath ($unix_path, $grub_dev_prefix); >>

Translates the UNIX path (eg. '/boot/grub/device.map') to GRUB path (eg.
'(hd0,0)/grub/device.map'). If the device (as specified in GRUB configuration
files via the 'root' option) is the same as the device in the resulting path,
the resulting path does not contain the device.
As arguments, the function takes the UNIX path and the device as specified via
'root' option, and returns the GRUB path (all strings).

=cut

# string UnixPath2GrubPath (string unix_path, string grub_dev_prefix)
sub UnixPath2GrubPath {
    my $self = shift;
    my $orig_path = shift;
    my $preset_dev = shift;
    my $dev;
    my $path;

    if ($orig_path =~ /^(\(.*\))(.+)$/) {
	$self->milestone("Path $orig_path looks like in GRUB form, special treatment");
	$dev = $1;
	$path = $2;
    }
    else {
	($dev, $path) = $self->SplitDevPath ($orig_path);
    }

    $dev = $self->UnixDev2GrubDev ($dev);
    if ($dev eq $preset_dev) {
	$dev = "";
    }

    $path = $dev . ($path||"");
    $self->milestone("Translated path: $orig_path, prefix $preset_dev, to: $path");
    return $path;
}

=item
C<< $grub_conf_line_ref = Bootloader::Core::GRUB->CreateGrubConfLine ($target, $discswitch); >>

Creates a hash representing a line of /etc/grub.conf file. As arguments, it takes
the device to install GRUB to, and the discswitch argument ('d' or ''). Returns a
reference to a hash containing info about the 'install' line.

=cut

# map<string,string> CreateGrubConfLine (string target, string discswitch,
# boolean use_setup)
sub CreateGrubConfLine {
    my $self = shift;
    my $target = shift;
    my $discswitch = shift;


    my $line_ref = {
	    'options' => [
		'--stage2=/boot/grub/stage2',
                '--force-lba'
	    ],
	    'device' => $target,
	    'command' => 'setup'
	};
    return $line_ref;
}

sub IsDisc {
  my $self = shift;
  my $disc = shift;
  my $ret = undef;
  foreach my $dev (keys %{$self->{"device_map"}}) {
    if ( $self->GetKernelDevice($disc) eq $self->GetKernelDevice($dev) ){
      $ret = 1;
    }
  }
  return $ret;
}

#external iface

=item
C<< $files_ref = Bootloader::Core::GRUB->ListFiles (); >>

Returns the list of the configuration files of the bootloader
Returns undef on fail

=cut

# list<string> ListFiles ()
sub ListFiles {
    my $self = shift;

    return [ Bootloader::Path::Grub_menulst() , 
    Bootloader::Path::Grub_devicemap(),
    Bootloader::Path::Grub_grubconf() ];
}

sub ListMenuFiles {
    my $self = shift;

    return [ Bootloader::Path::Grub_menulst() ];
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
    my $self = shift;
    my %files = %{+shift};
    my $avoid_reading_device_map = shift;

    #first set the device map - other parsing uses it
    my @device_map = @{$files{Bootloader::Path::Grub_devicemap()} || []};

    $self->milestone("device.map (input) =", \@device_map);

    my %devmap = ();
    foreach my $dm_entry (@device_map)
    {
	if ($dm_entry =~ /^\s*\(([^\s#]+)\)\s+(\S+)\s*$/)
	{
          #multipath handling, multipath need real device, because multipath
          # device have broken geometry (bnc #448110)
          if (defined $self->{"multipath"} && defined $self->{"multipath"}->{$self->GetKernelDevice($2)}){
            $devmap{ $self->{"multipath"}->{$self->GetKernelDevice($2)} } = $1;
          } else {
      	    $devmap{$2} = $1;
          }
	}
    };

    $self->milestone("avoided_reading device map.") if ($avoid_reading_device_map );

    $self->{"device_map"} = \%devmap	if (! $avoid_reading_device_map);

    $self->milestone("device_map (parsed) =", $self->{device_map});

    # and now proceed with menu.lst
    my @menu_lst = @{$files{Bootloader::Path::Grub_menulst()} || []};

    $self->milestone("menu.lst (input) =", \@menu_lst);

    (my $glob_ref, my $sect_ref) = $self->ParseMenuFileLines (
	0,
	["title"],
	\@menu_lst
    );

    # and finally get the location from /etc/grub.conf
    my @grub_conf_lines = @{$files{Bootloader::Path::Grub_grubconf()} || []};

    $self->milestone("grub.conf (input) =", \@grub_conf_lines);

    my $grub_root = "";
    my @grub_conf = ();
    my @devices = ();

    $self->milestone("global boot setting already found: ". 
			 join( ", ", grep { m/^boot_/; } keys %$glob_ref));
    #parse grub conf only if mount points is set (hack for generating autoyast profile bnc #464098)
    if (not exists $self->{"mountpoints"}{'/'})
    {
        $self->milestone("Mount points doesn't have '/', skipped parsing grub.conf");
    }
    else
    {
      foreach my $line (@grub_conf_lines)
      {
  	next unless $line =~ /^\s*(\S+)(\s+(\S+.*))?$/;

	my $key = $1;
	my $value = $3;
	
	last if $key eq "quit";
	next if substr ($key, 0, 1) eq "#";

	if ($key eq "root" || $key eq "rootnoverify")
	{
	    $grub_root = $value;
	}
	elsif ($key eq "setup") {
	    my @options = ();
	    my %grub_conf_item = ();
	    $grub_conf_item{"command"} = $key;
	    my @entries = split /\s+/, $value;
	    my $tmp = shift @entries;
	    while (substr ($tmp, 0, 2) eq "--")
	    {
		push @options, $tmp;
		$tmp = shift @entries;
	    }
	    $grub_conf_item{"options"} = \@options;

            $tmp = $self->GrubDev2UnixDev ($tmp);
            push @devices, $tmp;
            $grub_conf_item{"options"} = \@options;
            $grub_conf_item{"device"} = $tmp;

	    push @grub_conf, \%grub_conf_item;
	}
      }

      # FIXME: still incomplete for MD and dmraid devs
      # translate device array to the various boot_* flags else set boot_custom
      # in glob_ref accordingly
      my ($boot_dev,) = $self->SplitDevPath ("/boot");
      my ($root_dev,) = $self->SplitDevPath ("/");
      my $extended_dev = $self->GetExtendedPartition($boot_dev) || "";
      # mbr_dev is the first bios device
      my $mbr_dev =  $self->GrubDev2UnixDev("(hd0)");

      foreach my $dev (@devices) {
	$self->milestone("checking boot device $dev");

	if ($dev eq $mbr_dev) {
	    $glob_ref->{"boot_mbr"} = "true";
	    $self->milestone("detected boot_mbr");
            if (defined $self->{"md_arrays"}
                and ((scalar keys %{$self->{"md_arrays"}}) > 0)){
              if (defined $glob_ref->{"boot_md_mbr"} 
                  and $glob_ref->{"boot_md_mbr"} ne "" ){
                $glob_ref->{"boot_md_mbr"} = $glob_ref->{"boot_md_mbr"}.",".$dev;
              } else {
                $glob_ref->{"boot_md_mbr"} =$dev;
              }
              $self->milestone("detected boot_md_mbr ".$glob_ref->{"boot_md_mbr"});
            }
	}
	elsif ($dev eq $root_dev) {
	    $glob_ref->{"boot_root"} = "true";
	    $self->milestone("detected boot_root");
	}
	elsif ($dev eq $boot_dev) {
	    $glob_ref->{"boot_boot"} = "true";
	    $self->milestone("detected boot_boot");
	}
	elsif ($dev eq $extended_dev) {
	    $glob_ref->{"boot_extended"} = "true";
	    $self->milestone("detected boot_extended");
	}
        elsif ($self->IsDisc($dev) 
          and defined $self->{"md_arrays"}
          and ((scalar keys %{$self->{"md_arrays"}}) > 0)){
          if (defined $glob_ref->{"boot_md_mbr"} and $glob_ref->{"boot_md_mbr"} ne "" ){
            $glob_ref->{"boot_md_mbr"} = $glob_ref->{"boot_md_mbr"}.",".$dev;
          } else {
            $glob_ref->{"boot_md_mbr"} =$dev;
          }
          $self->milestone("detected boot_md_mbr ".$glob_ref->{"boot_md_mbr"});
        }
	else {
	    $glob_ref->{"boot_custom"} = $dev;
	    $self->milestone("set boot_custom");
	}
      }			 
    } 
    # $glob_ref->{"stage1_dev"} = \@devices;

    $self->{global} = $glob_ref;
    $self->{sections} = $sect_ref;
    $self->{grub_conf} = \@grub_conf;

    $self->milestone("global =", $self->{global});
    $self->milestone("sections =", $self->{sections});
    $self->milestone("grub_conf (parsed) =", $self->{grub_conf});

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
    my $self = shift;

    # first create /etc/grub.conf
    my $grub_conf = $self->CreateGrubConfLines();

    # secondly process /boot/grub/menu.lst
    my $menu_lst = $self->PrepareMenuFileLines (
	$self->{"sections"},
	$self->{"global"},
	"    ",
	" "
    );

    # handle 'hidden magic' entries
    map {
	s/^/##YaST - /
	    if /^activate/ or /^generic_mbr/;
    } @{$menu_lst};

    # now process the device map
    my %glob = %{$self->{"global"}};
    my @device_map = ();
    while ((my $unix, my $fw) = each (%{$self->{"device_map"}}))
    {
	my $line = "($fw)\t$unix";
	push @device_map, $line;
    }

    #return all files
    return {
	Bootloader::Path::Grub_menulst() => $menu_lst,
	Bootloader::Path::Grub_devicemap() => \@device_map,
	Bootloader::Path::Grub_grubconf() => $grub_conf,
    }
}


sub CreateGrubConfLines() {
    my $self = shift;

    # process /etc/grub.conf
    my %glob = %{$self->{"global"}};
    my @grub_conf = ();
    my %s1_devices = ();
    # md_discs stores grub discs which should be synchronized (needed for correct stage2 location)
    my $md_discs = {};

    {
	my $dev;
	my $flag;

	# boot_custom => "selectdevice:Custom Boot Partition::"
	$dev = delete($glob{"boot_custom"});
	$s1_devices{$dev} = 1 if (defined $dev and $dev ne "");
	
	# boot_mbr    => "bool:Boot from Master Boot Record:false",
	$flag = delete $glob{"boot_mbr"};
	if (defined $flag and $flag eq "true") {
	    # if /boot mountpoint exists add($disk(/boot) else add disk(/)
	    # mbr_dev is the first bios device
	    $dev =  $self->GrubDev2UnixDev("(hd0)");
	    $s1_devices{$dev} = 1 if defined $dev;
	}

	# boot_md_mbr   synchronize mbr of disc in md raid 
  #(it is little tricky as md raid synchronize only partitions)
	$flag = delete $glob{"boot_md_mbr"};
	if (defined $flag and $flag ne "") {
            my @discs = split(/,/,$flag);
            chomp @discs;
            foreach my $mbr_disc (@discs){
      	      $s1_devices{$mbr_disc} = 1;
              my $gdev = $self->UnixDev2GrubDev($mbr_disc);
              $md_discs->{$gdev} = substr($gdev,1,-1);
	            $self->milestone("md_mbr device: $gdev ");
            }
	}

	# boot_root   => "bool:Boot from Root Partition:true",
	$flag = delete $glob{"boot_root"};
	if (defined $flag and $flag eq "true") {
	    # add partition(/)
	    ($dev,) = $self->SplitDevPath ("/");
	    $s1_devices{$dev} = 1 if defined $dev;
	}
	
	# boot_boot   => "bool:Boot from Boot Partition:true",
	$flag = delete $glob{"boot_boot"};
	if (defined $flag and $flag eq "true") {
	    # add partition(/boot)
	    ($dev,) = $self->SplitDevPath ("/boot");
	    $s1_devices{$dev} = 1 if defined $dev;
	}

	# boot_extended   => "bool:Boot from Extended Partition:true",
	$flag = delete $glob{"boot_extended"};
	if (defined $flag and $flag eq "true") {
	    # add partition(extended)
	    $dev = $self->GetExtendedPartition($self->SplitDevPath("/boot"));
	    $s1_devices{$dev} = 1 if defined $dev;
	}

	# convert any raid1 device entry into multiple member entries
	foreach my $s1dev (keys %s1_devices)
	{
	    if ($s1dev =~ m:/dev/md\d+:) {
		delete $s1_devices{$s1dev};
		# Please note all non-mirror raids are silently deleted here
		my @members = @{$self->MD2Members($s1dev) || []};
		map { $s1_devices{$_} = 1; } @members;
	    }
	}

	# FIXME: convert all impossible configurations to some viable
	# fallback:
	#     boot from primary xfs -> mbr
	#     boot from extended -> set generic_mbr
	# other options ???
    }

    $self->milestone("found s1_devices: " . join(",",keys %s1_devices));

    # keep the first bootloader setup command for every boot device and drop
    # all other
    # FIXME: shouldn't we make comments from that? comment handling here at all?
    my @grub_conf_items = grep {
	my $keep = 1;
	if ($_->{"command"} eq "install"|| $_->{"command"} eq "setup")
	{
	    $keep = defined (delete $s1_devices{$_->{"device"}});
	}
	$keep;
    } @{$self->{"grub_conf"}};

    $self->milestone("remaining s1_devices to create new lines: " . join(",",keys %s1_devices));

    if (scalar (keys (%s1_devices)) > 0)
    {
	my $discswitch = undef;
	foreach my $item_ref (@grub_conf_items)
	{
	    last if defined $discswitch;
	    $discswitch = $item_ref->{"discswitch"}
	}

	unless (defined ($discswitch))
	{
	    $discswitch = "";
	    my ($loc, ) = keys (%s1_devices);
	    if (defined ($loc))
	    {
		my $s1_dev = $loc;
		my ($s2_dev,) = $self->SplitDevPath ("/boot/grub/stage2");
		$s1_dev = $self->Partition2Disk ($s1_dev);
		$s2_dev = $self->Partition2Disk ($s2_dev);
		if ($s1_dev ne $s2_dev)
		{
		    $discswitch = "d";
		}
	    }
	}

	foreach my $new_dev (keys (%s1_devices))
	{
	    my $line = $self->CreateGrubConfLine ($new_dev, $discswitch);
	    $self->milestone("new line created:\n\n' " .
				join("'\n' ",
				     map {
					 $_ . " => '" . $line->{$_} . "'";
				     } keys %$line) . "'\n"
	    			);

	    push @grub_conf_items, $line;
	}
    }

    my $last_root = "";
    (my $stage1dev,) = $self->SplitDevPath ("/boot/grub/stage1");

    # For RAID1 devices, tell grub to read the kernel&stuff from first disk
    # array member
    if ($stage1dev =~ m:/dev/md\d+:) {
	my @members = @{$self->MD2Members ($stage1dev) || []};
	# FIXME! This only works for mirroring (Raid1)
	# FIXME: boot from MBR does not work for RAID1 yet
	$stage1dev = $members[0] || $stage1dev;
    }
    $stage1dev = $self->UnixDev2GrubDev ($stage1dev);

    foreach my $grub_conf_item (@grub_conf_items)
    {
	if ($grub_conf_item->{"command"} eq "setup")
	{
	    my $options = join " ", @{$grub_conf_item->{"options"} || []};
	    my $location = $self->UnixDev2GrubDev ($grub_conf_item->{"device"});
      my $stage_location = $stage1dev || $location;
      if ($md_discs->{$location})
      {
        $self->milestone("detected md_discs $location");
        $stage_location =~ m/\(([^,)]+)(,[^)]+)?\)/;
        my $old_disc = $1;
        my $new_disc = $md_discs->{$location};
        $stage_location =~ s/$old_disc/$new_disc/;
        $self->milestone("resulting location $stage_location");
      }
	    my $line = "setup $options $location " . $stage_location; 
	    push @grub_conf, $line;
	    delete $s1_devices{$grub_conf_item->{"device"}};
	}
    }
    push @grub_conf, "quit";

    return \@grub_conf;
}


=item
C<< $sectin_info_ref = Bootloader::Core::GRUB->Section2Info (\@section_lines); >>

Gets the information about the section. As argument, takes a reference to the
list of lines building the section, returns a reference to a hash containing
information about the section.


=cut

# map<string,string> Section2Info (list<map<string,any>> section)
sub Section2Info {
    my $self = shift;
    my @lines = @{+shift};

    my %ret = ();
    my $grub_root = "";
    my $modules = 0;
    my $type = $self->EvalSectionType (\@lines);
    $ret{"type"} = $type;
    $ret{"nounzip"} = 0 if ($type eq "xen");

    foreach my $line_ref (@lines) {
	my $key = $line_ref->{"key"};
	my $val = $line_ref->{"value"};

	# do mapping of config file names to internal
	if ($type eq "xen") {
            if ($key eq "kernel") {
               $key = "xen";
            }
	    elsif ($line_ref->{"key"} eq "module" ||
              $line_ref->{"key"} eq "modulenounzip") {
		if ($modules == 0) {
		    $key = "kernel";
                    $ret{"nounzip"} |= 1 if $line_ref->{"key"} eq "modulenounzip";
		}
		elsif ($modules == 1) {
		    $key = "initrd";
                    $ret{"nounzip"} |= 2 if $line_ref->{"key"} eq "modulenounzip";
		}
		$modules++;
	    }
	}
	# remapping end, start processing


	# FIXME : check against metadata?

	if ($key eq "root" || $key eq "rootnoverify")
	{
	    if ($type eq "menu") {
		$ret{"root"} = $self->GrubDev2UnixDev ($val);
		# FIXME: do we need to set $grub_root here?
#		$grub_root = $val;
	    }
	    else {
              if ($type eq "other")
              {
                $ret{"chainloader"} = $val;
              }
              $grub_root = $val;
	      $ret{"noverifyroot"} = "true" if ($key eq "rootnoverify");
	    }
	}
	elsif ($key eq "title")
	{
	    $ret{"name"} = $val;
	    my $on = $self->Comment2OriginalName (\%ret, $line_ref->{"comment_before"});
	    $ret{"original_name"} = $on if ($on ne "");
	}
	elsif ($key eq "kernel")
	{
	    # split into loader and parameter, note that the regex does
	    # always match, then split out root= vgamode=,console=  and append= values
	    $val =~ /^\s*(\S+)(?:\s+(.*))?$/;
    
	    $ret{"image"} = $self->GrubPath2UnixPath ($1, $grub_root);
	    $val = $2 || "";

	    if ($val =~ /^(?:(.*)\s+)?root=(\S+)(?:\s+(.*))?$/)
	    {
		$ret{"root"} = $2 if $2 ne "";
		$val = $self->MergeIfDefined ($1, $3);
	    }
	    if ($val =~ /^(?:(.*)\s+)?vga=(\S+)(?:\s+(.*))?$/)
	    {
		$ret{"vgamode"} = $2 if $2 ne "";
		$val = $self->MergeIfDefined ($1, $3);
	    }
	    if ($val =~ /console=ttyS(\d+),(\w+)/)
	    {
		if ($type eq "xen") {
		    my $console = sprintf("com%d", $1+1);
		    my $speed   = sprintf("%s=%s", $console, $2);
		    if (exists $ret{"xen_append"}) {
		        my $xen_append = $ret{"xen_append"};
		        while ($xen_append =~
			            s/(.*)console=(\S+)\s*(.*)$/$1$3/o) {
		           my $del_console = $2;
      				$xen_append =~
			          s/(.*)${del_console}=\w+\s*(.*)$/$1$2/g;
			      }
            $xen_append =~ s/^\s*(\S*)\s*$/$1/;
      			$ret{"xen_append"} = "console=$console $speed $xen_append";
		    } else {
		        $ret{"xen_append"} = "console=$console $speed";
		    }
		}
            }
	    $ret{"append"} = $val;
	}
	elsif ($key eq "xen")
	{
	    if ($val =~ /^(?:(.*)\s+)?vga=mode-(\S+)(?:\s+(.*))?$/)
	    {
		    $ret{"vgamode"} = $2 if $2 ne "";
    		$val = $self->MergeIfDefined ($1, $3);
	    }
	    # split into loader and parameter, note that the regex does
	    # always match
	    $val =~ /^\s*(\S+)(?:\s+(.*))?$/;

	    $ret{"xen"} = $self->GrubPath2UnixPath ($1, $grub_root);
	    $ret{"xen_append"} = $2 if defined $2;
	}
	elsif ($key eq "configfile" || $key eq "initrd")
	{
	    $ret{$key} = $self->GrubPath2UnixPath ($val, $grub_root);
	}
	elsif ($key eq "chainloader")
	{
	    if ($val =~ /^(.*)\+(\d+)/)
	    {
		$val = $1;
		$ret{"blockoffset"} = $2;
		if ($val eq "")
		{
		    $val = $grub_root;
		}
		$val = $self->GrubDev2UnixDev ($val);
	    }
	    else
	    {
		$val = $self->GrubPath2UnixPath ($val, $grub_root);
	    }
	    $ret{$key} = $val;
	}
        # recognize remapping both is shrink to one remap return
        elsif ($key eq "map")
        {
          $ret{"remap"} = "true";
        }
        elsif ($key eq "makeactive")
        {
          $ret{"makeactive"} = "true";
        }
        else {
          $ret{"__broken"} = "true"; #unknown key
        }
    }

    $ret{"__lines"} = \@lines;
    return \%ret;
}


=item
C<< $dev = Bootloader::Core::GRUB->GetCommonDevice (@paths); >>

Checks all paths given as arguments if they are on the same device. If so,
returns the common device, otherwise returns empty string.

=cut

#string GetCommonDevice (string path1, string path2, ...)
sub GetCommonDevice {
    my $self = shift;
    my @paths = @_;

    my $common_device = undef;
    my $occurrences = 0;

    foreach my $path (@paths)
    {
	(my $dev, $path) = $self->SplitDevPath ($path || "");
	if (defined ($dev))
	{
	    if (! defined ($common_device))
	    {
		$common_device = $dev;
		$occurrences = 1;
	    }
	    elsif ($common_device eq $dev)
	    {
		$occurrences = $occurrences + 1;
	    }
	    else
	    {
		return "";
	    }
	}
    }
    return $occurrences == scalar @paths ? $common_device : "";
}

=item
C<< $line = Bootloader::Core::GRUB->CreateKernelLine (\%sectingo, $grub_root); >>

Creates a line with the kernel command for GRUB's menu.lst. As arguments.
it takes a hash containing information about the section and the root
device specified by the GRUB's root command. Returns the line to be written
to menu.lst (without the leading kernel keyword).

=cut

#string CreateKernelLine (map sectinfo, string grub_root)
sub CreateKernelLine {
    my $self = shift;
    my $sectinfo_ref = shift;
    my $grub_root = shift || "";

    my $root = $sectinfo_ref->{"root"} || "";
    my $vga = $sectinfo_ref->{"vgamode"} || "";
    my $append = $sectinfo_ref->{"append"} || "";
    my $image = $sectinfo_ref->{"image"} || "";
    $root = " root=$root" if $root ne "";
    $vga = " vga=$vga" if $vga ne "";
    $append = " $append" if $append ne "";

    $image = $self->UnixPath2GrubPath ($image, $grub_root);
    return "$image$root$append$vga";
}

=item
C<< $line = Bootloader::Core::GRUB->CreateChainloaderLine (\%sectinfo, $grub_root); >>

Creates a line with the chainloader command for GRUB's menu.lst. As arguments.
it takes a hash containing information about the section and the root
device specified by the GRUB's root command. Returns the line to be written
to menu.lst (without the leading chainloader keyword).

=cut

#string CreateChainloaderLine (map sectinfo, string grub_root)
sub CreateChainloaderLine {
    my $self = shift;
    my $sectinfo_ref = shift;
    my $grub_root = shift || "";

    my $sectors = $sectinfo_ref->{"blockoffset"} || "";
    my $chain = $sectinfo_ref->{"chainloader"};

    if (substr ($chain, 0, 5) eq "/dev/" && $sectors eq "")
    {
	$sectors = "1";
    }
    $sectors = "+$sectors" if $sectors ne "";
    $chain = "" if $sectors ne ""; #chainloader with blockoffset no

    return "$sectors";
}


=item
C<< $disk = Bootloader::Core::Grub->Partition2Disk ($partition); >>

Gets the disk a partition resides on. As argument, it takes the partition
device node (eg. C<'/dev/hda3'>), returns the device node of the disk
holding the partition (eg. C</dev/hda>), or undef if checking failed.

=cut

# string Partition2Disk (string partition)
sub Partition2Disk {
    my $self = shift;
    my $partition = shift;

    foreach my $dev_ref (@{$self->{"partitions"}})
    {
	if ($dev_ref->[0] eq $partition)
	{
	    return $dev_ref->[1];
	}
    }

    # FIXME:
    # check in device mapping as a fallback

    return $partition; 
}

sub EvalSectionType {
    my $self = shift;
    my @lines = @{+shift};

    my $modules = 0;
    my $kernel_xen = 0;
    my $chainloader = 0;
    my $configfile = 0;
    my $image = 0;

    foreach my $line_ref (@lines) {
	if ($line_ref->{"key"} eq "module") {
	    $modules++;
	}
        elsif ($line_ref->{"key"} eq "kernel" or $line_ref->{"key"} eq "image")
        {
          # kernel name contain xen it should be xen, but also image section in xen enviroment
          if ( $line_ref->{"value"} =~ m/xen/ )
          {
            $kernel_xen = 1;
          }
          $image = 1;
        }
	elsif ($line_ref->{"key"} eq "chainloader") {
	    $chainloader = 1;
	}
	elsif ($line_ref->{"key"} eq "configfile") {
	    $configfile = 1;
	}
    }
    if ($configfile) {
	return "menu";
    }
    elsif ($modules > 0 and $kernel_xen and not $chainloader) {
	return "xen";
    }
    elsif ($chainloader and $modules == 0 and $kernel_xen == 0) {
	return "other";
    }
    elsif ($image) {
        return "image";
    }

    # return "custom" type as a fallback (for unknown or custom section types)
    return "custom";
}

=item
C<< $lines_ref = Bootloader::Core::GRUB->Info2Section (\%section_info); >>

Takes the info about the section and uses it to construct the list of lines.
The info about the section also contains the original lines.
As parameter, takes the section info (reference to a hash), returns
the lines (a list of hashes).

=cut

# list<map<string,any>> Info2Section (map<string,string> info)
sub Info2Section {
    my $self = shift;
    my %sectinfo = %{+shift};

    my @lines = @{$sectinfo{"__lines"} || []};
    my $type = $sectinfo{"type"} || "";
    my $so = $self->{'options'}{'section_options'};
    my $modules = 0;

    # allow to keep the section unchanged
    if (! ($sectinfo{"__modified"} || 0))
    {
	return $self->FixSectionLineOrder (
	    \@lines,
	    ["title"]);
    }

    #if section type is not known, don't touch it.
    if ($type ne "image" and $type ne "other" and $type ne "xen" and $type ne "menu")
    {
	return \@lines;
    }


    # remap the first disk to the chainloader if requested
    # store the information about remapped disk
    my $remap_device = undef;
    if (defined ($sectinfo{"remap"}) && $sectinfo{"remap"} eq "true" && defined ($sectinfo{"chainloader"}))
    {
	$self->milestone("Remapping the device map");
	$remap_device = $sectinfo{"chainloader"};
	$remap_device = $self->UnixDev2GrubDev ($remap_device);
        if ($remap_device =~ /\(([^,]+),([^,]+)\)/) {
	    $remap_device = "$1";
	}
	elsif ($remap_device =~ /\(([^,]+)\)/) {
	    $remap_device = "$1";
	}
	else {
	    $self->error("Not valid device $remap_device");
	}
	$self->milestone("Device to remap: $remap_device");
    }

    my $grub_root = "";
    if (defined ($sectinfo{"image"}) && defined ($sectinfo{"initrd"}))
    {
	$grub_root = $self->GetCommonDevice ($sectinfo{"image"}, $sectinfo{"initrd"});
	$grub_root = $self->UnixDev2GrubDev ($grub_root);
	$self->milestone("Set GRUB's root to $grub_root");
    }
    elsif ($type eq "menu" or $type eq "other") {
	# FIXME: using the boot device of the current installation as the
	# "root" parameter in sections for other installations does not make
	# sense to me -- are there cases where this does make sense?
	my ($boot_dev,) = $self->SplitDevPath ("/boot");
	$grub_root = $self->UnixDev2GrubDev (
	    exists $sectinfo{"root"} ? delete($sectinfo{"root"}) : $boot_dev
        );
	$self->milestone("Set GRUB's root to $grub_root");
	# FIXES the above - maybe: To make makeactive without parameter work,
	# one needs to pass the chainloader device
	if (exists $sectinfo{"chainloader"}) {
	    $self->milestone("Setting GRUB's root to $grub_root ($sectinfo{\"chainloader\"})");
	    $grub_root = $self->UnixDev2GrubDev ($sectinfo{"chainloader"});
	}
    }

    if ($type eq "xen") {
#handle kernel console, if redefined in console use it and if not then parse from append line
	if ( exists($sectinfo{"append"}) and
	    ($sectinfo{"append"} =~ /console=ttyS(\d+),(\w+)/) )
	{
	    # merge console and speed into xen_append
	    my $console = sprintf("com%d", $1+1);
	    my $speed   = sprintf("%s=%s", $console, $2);
	    if (exists $sectinfo{"xen_append"}) {
		my $xen_append = $sectinfo{"xen_append"};
		while ($xen_append =~
		       s/(.*)console=(\S+)\s*(.*)$/$1$3/o) {
		    my $del_console = $2;
		    $xen_append =~
			s/(.*)${del_console}=\w+\s*(.*)$/$1$2/g;
		}
		$sectinfo{"xen_append"} = "console=$console $speed $xen_append";
	    } else {
		$sectinfo{"xen_append"} = "console=$console $speed";
	    }
	}
    }

    @lines = map {
	my $line_ref = $_;
	my $key = $line_ref->{"key"};

	if ($key eq "title")
	{
	    $line_ref = $self->UpdateSectionNameLine ($sectinfo{"name"}, $line_ref, $sectinfo{"original_name"});
	    delete ($sectinfo{"name"});
	}
        elsif ($key eq "configfile")
        {
          if (exists $sectinfo{"configfile"})
          {
            $line_ref->{"value"} = $sectinfo{"configfile"};
            delete ($sectinfo{"configfile"});
          }
          else
          {
            $line_ref = undef;
          }
        }
        #entries which must be recreated due to hard check if valid or order
	elsif ($key eq "module" or $key eq "modulenounzip"
            or $key eq "root" or $key eq "rootnoverify"
            or $key eq "map")
        {
	    $line_ref = undef;
	}
        elsif ($key eq "makeactive")
        {
            if( exists $sectinfo{"makeactive"} 
              and $sectinfo{"makeactive"} eq "true")
            {
              delete $sectinfo{"makeactive"};
            } else {
              $line_ref = undef;
            }
        }
	elsif ($key eq "kernel") {
	    if ($type eq "xen") {
        my $xen = $self->UnixPath2GrubPath (delete($sectinfo{"xen"}), $grub_root);
        my $append = (delete($sectinfo{"xen_append"}) || "");
        my $vga = delete ($sectinfo{"vgamode"}) || "";
        $vga = "vga=mode-$vga " if $vga ne "";
        $line_ref->{"value"} = "$xen $vga$append";
	    }
	    elsif ($type eq "image") {
		$line_ref->{"value"} = $self->CreateKernelLine (\%sectinfo, $grub_root);
		delete ($sectinfo{"root"});
		delete ($sectinfo{"vgamode"});
		delete ($sectinfo{"append"});
		delete ($sectinfo{"image"});
	    }
	}
	elsif ($key eq "initrd")
	{
	    if ($type eq "other" or not defined ($sectinfo{$key})) {
		$line_ref = undef;
	    }
	    elsif( defined $sectinfo{$key} &&  $sectinfo{$key} ne "") {
		$line_ref->{"value"} = $self->UnixPath2GrubPath ($sectinfo{$key}, $grub_root);
	    }
	    delete ($sectinfo{$key});
	}
	elsif ($key eq "chainloader")
	{
	    # This handles chainloader lines that specify a device name only --
	    # a single block offset may have been passed down in our internal
	    # variable "blockoffset": this will be added to the constructed
	    # "chainloader" line.
	    #
	    # The general case, i.e. translating between
	    # "/dev/disk/by-label/testlabel/boot/grub/stage1" and
	    # "(hd0,1)/boot/grub/stage1" cannot be handled with our device name
	    # translation scheme. There is no reliable way to find the end of
	    # the device name in the above string, esp. since the device does
	    # not necessarily exist yet.
	    #
	    # Probably a different interface is needed to reliably pass
	    # "converted GRUB paths" that include UNIX device names between us
	    # and the upper layers.
	    # 
	    # The same problem exists e.g. for "configfile" entries, but there
	    # we have no "common simple case" that we could still handle (as we
	    # do in the "chainloader" case). We usually would need to translate
	    # between "/dev/disk/by-label/testlabel/boot/grub/menu.lst" and
	    # "(hd0,3)/boot/grub/menu.lst". We rather choose to require the
	    # device in the "root" key and do not expect and handle UNIX device
	    # names in the "configfile" value at all.
	    $line_ref = undef;
	}
	defined $line_ref ? $line_ref : ();
    } @lines;

    # prepend a root/rootnoverify line where appropriate
    # handle noverify flag and do never verify on chainloader sections
    my $noverify = ($type eq "other");
    if ( exists $sectinfo{"noverifyroot"} and
	 defined $sectinfo{"noverifyroot"})
    {
	$noverify = ($noverify or ($sectinfo{"noverifyroot"} eq "true"));
	delete($sectinfo{"noverifyroot"});
    }
    if ($grub_root ne "" or $noverify) {
        my $value = undef;
        my $blockoffset = $sectinfo{"blockoffset"} || "";
        if ($type eq "other" && $blockoffset ne "")
        {
          $value = $self->UnixDev2GrubDev($sectinfo{"chainloader"});
        }
        else
        {
          $value = $grub_root if $grub_root ne "";
        }

        $value = "(hd0)" if not defined($value);

	unshift @lines, {
	    "key" => $noverify ? "rootnoverify" : "root",
	    "value" => $value,
	};
    }

    # keep a hard order for the following three entries
    if (exists $sectinfo{"xen"} && $type eq "xen") {
      my $xen = $self->UnixPath2GrubPath (delete($sectinfo{"xen"}), $grub_root);
      my $append = (delete($sectinfo{"xen_append"}) || "");
      my $vga = $sectinfo{"vgamode"} || "";
      $vga = "vga=mode-$vga " if $vga ne "";
      my $value = "$xen $vga$append";
      push @lines, {
      	"key" => "kernel",
        "value" => $value,
      };
    }
    if (exists $sectinfo{"image"} && ($type eq "image" || $type eq "xen")) {
	my $val = $self->CreateKernelLine (\%sectinfo, $grub_root);
        my $key = "kernel";
        if ($type eq "xen")
        {
          if (defined $sectinfo{"nounzip"} && (($sectinfo{"nounzip"} & 1) == 1))
          {
            $key = "modulenounzip";
          }
          else
          {
            $key = "module";
          }
        }
	push @lines, {
	    "key" => $key,
	    "value" => $val,
	};
    }
    if (exists $sectinfo{"initrd"} && $sectinfo{"initrd"} ne "" && ($type eq "image" || $type eq "xen")) {
      my $value =  $self->UnixPath2GrubPath ($sectinfo{"initrd"}, $grub_root);
      my $key = "initrd";
      if ($type eq "xen")
      {
        if (defined $sectinfo{"nounzip"} && (($sectinfo{"nounzip"} & 2) == 2))
        {
          $key = "modulenounzip";
        }
        else
        {
          $key = "module";
        }
      }
	push @lines, {
	    "key" => $key,
	    "value" => $value,
	};
    }

    # adapt entries if the menu.lst uses different key names etc.
    while ((my $key, my $value) = each (%sectinfo))
    {
	if ($key eq "name")
	{
	    my $line_ref = $self->UpdateSectionNameLine ($value, {}, $sectinfo{"original_name"});
	    $line_ref->{"key"} = "title";
	    unshift @lines, $line_ref;
	}
	elsif ($key eq "chainloader" && $type eq "other")
	{
	    # is this necessary? It seems this is already handled in a
	    # loop above (where the sectinfo stuff for chainloader is deleted).
            # JR: yes it is necessary if in previous lines hasn't been chainloader line (or lines is empty)
	    push @lines, {
		"key" => $key,
		"value" => $self->CreateChainloaderLine (\%sectinfo, $grub_root), 
	    };
	}
	elsif ($key eq "configfile" && $type eq "menu")
	{
	    push @lines, {
		"key" => $key,
		"value" => $value,
	    };
	}
        elsif ($key eq "remap" and $value eq "true" and $type eq "other" )
        {
            unshift @lines, {
                "key" => "map",
                "value" => "(hd0) ($remap_device)",
            };
            unshift @lines, {
                "key" => "map",
                "value" => "($remap_device) (hd0)",
            };
        }
        elsif ($key eq "makeactive" and $value eq "true" and $type eq "other")
        {
          push @lines, {
              "key" => "makeactive",
              "value" => "",
          };
        }
    }

    my $ret = $self->FixSectionLineOrder (\@lines,
	["title"]);

    return $ret;
}

=item
C<< $glob_info = $Bootloader::Core::GRUB->Global2Info (\@glob_lines, \@section_names); >>

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
    my $go = $self->{"options"}{"global_options"};

    my %ret = ();
    my $grub_root = "";

    foreach my $line_ref (@lines) {
	my $key = $line_ref->{"key"};
	my $val = $line_ref->{"value"};

	# Check if key is defined to prevent perl warnings
	if (!defined($key)) {
	    next;
	}

	my $type = $go->{$key}||"";

	if ($key eq "root" or $key eq "rootnoverify") {
	    $grub_root = $val;
	    $ret{"verifyroot"} = ($key eq "root");
	}
	elsif ($key eq "default") {
	    # cast $val to integer. That means that if no valid default has
	    # been given, we'll take the first section as default.
	    no warnings "numeric"; # this is neccessary to avoid to trigger a perl bug
	    my $defindex = 0+ $val;
	    $ret{"default"} = $sections[$defindex];

	    # Parse RemovedDefault image out of comment
	    my $ff = $self->Comment2RemovedDefault ($line_ref->{"comment_before"});
	    $ret{"removed_default"} = 1 if ($ff == 1);


	}
	elsif (defined ($type) and $type eq "path") {
	    $ret{$key} = $self->GrubPath2UnixPath ($val, $grub_root);
	}
	elsif (defined ($type) and $type eq "bool") {
	    $ret{$key} = "true";
	}
        elsif ($key eq "setkey")
        {
          my @parts = split(" ",$val);

          if (exists $ret{"setkeys"}){
            $ret{"setkeys"}->{$parts[0]} = $parts[1];
          }
          else
          {
            my %setkey_array = ( $parts[0] => $parts[1] );
            $ret{'setkeys'} = \%setkey_array;
          }
        }
	elsif ($key =~ m/^boot_/) {
	    # boot_* parameters are handled else where but should not happen!
	    $self->milestone("Wrong item here $key, ignored");
	}
	else {
	    $ret{$key} = $val;
            unless (defined $go->{$key}){
              $self->warning("Unknown global key $key");
              $ret{"__broken"}="true";
            }
	}
    }
    $ret{"__lines"} = \@lines;
    return \%ret;
}

=item
C<< $lines_ref = Bootloader::Core::GRUB->Info2Global (\%section_info, \@section_names); >>

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
    my $go = $self->{'options'}{"global_options"};
  
    # allow to keep the section unchanged
    return \@lines unless $globinfo{"__modified"} || 0;

    if (scalar (@lines) == 0)
    {
	@lines = (
	    { "key" => "color", "value" => "white/blue black/light-gray" },
	    { "key" => "default", "value" => 0 },
	    { "key" => "timeout", "value" => 8 },
	);
    }

    #remove gfxmenu in trusted grub due to security
    if (defined $globinfo{"trusted_grub"} && $globinfo{"trusted_grub"} eq "true") {
      delete ($globinfo{"trusted_grub"});
      delete ($globinfo{"gfxmenu"});
    }

    @lines = map {
	my $line_ref = $_;
	my $key = $line_ref->{"key"};
	my ($type) = $go->{$key} || "";

	# only accept known global options :-)
	if ( !exists $go->{$key} ) {
		$line_ref = undef;
	}
	elsif (!defined ($globinfo{$key}))
	{
	    $line_ref = undef;
	}
        elsif ($key eq "setkey")
        {
          $line_ref->{"value"} =~ m/^(\s+)\S+(\s+)$/;
          if (defined $globinfo{"setkeys"}->{$1})
          {
            $line_ref->{"value"} = delete $globinfo{"setkeys"}->{"$key"};
          }
          else
          {
            $line_ref = undef;
          }
        }
	elsif ($key eq "default")
	{
	    $line_ref->{"value"} = $self->IndexOfSection (
		delete $globinfo{$key}, $sections_ref) || 0;

            #reset all information before default
            my @empty;
            $line_ref->{"comment_before"} = \@empty;

            $line_ref = $self->CreateRemovedDefaultLine (
                         $line_ref ) if
                         delete ($globinfo{"removed_default"});


	}
	elsif ($key eq "password")
	{
	    # FIXME: Do md5 encryption
	    $line_ref->{"value"} = delete $globinfo{$key};
	}
	elsif ($type eq "path")
	{
	    $line_ref->{"value"} = $self->UnixPath2GrubPath (delete $globinfo{$key}, "");
	}
	# bool values appear in a config file or not. there might be types
	# like 'yesno' or 'truefalse' in the future which behave differently
	elsif ($type eq "bool") {
	    if (delete $globinfo{$key} ne "true") {
		$line_ref = undef;
	    }
	    else {
		$line_ref->{"value"} = "";
	    }
	}
	else
	{
	    $line_ref->{"value"} = delete $globinfo{$key};
	}
	defined $line_ref ? $line_ref : ();
    } @lines;


    while ((my $key, my $value) = each (%globinfo))
    {
	# only accept known global options :-)
	next unless exists $go->{$key};
	next if $key =~ m/^boot_/; # handled else where
	my $type = $go->{$key} || "";

	if ($key eq "default") {
	    $value = $self->IndexOfSection ($value, $sections_ref) || 0;
	}
        elsif ($key eq "setkeys")
        {
          while (my ($k,$v) = each (%{$globinfo{"setkeys"}}))
          {
	    push @lines, {
	    "key" => "setkey",
	    "value" => "$k $v",
	    }
          }
          next;
        }
  elsif ($key eq "serial"){
    my $index = 0;
    foreach my $i (@lines) {
        last if ($i->{"key"} eq "terminal"); #force order of terminal/serial bnc#650150
        $index++;
    }
    splice @lines, $index, 0, { "key" => $key, "value" => $value };
    next;
  }
	# bool values appear in a config file or not
	elsif ($type eq "bool") {
	    next if $value ne "true";
	    $value = "";
	}
	elsif ($type eq "path")
	{
	    $value = $self->UnixPath2GrubPath ($value, "");
	}

	push @lines, {
	    "key" => $key,
	    "value" => $value,
	}
    }

    return \@lines;
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
    foreach my $key ("grub_conf")
    {
	if (defined ($self->{$key}))
	{
	    $ret->{$key} = $self->{$key};
	}
    }
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
    my %settings = %{+shift};

    foreach my $key ("grub_conf")
    {
	if (defined ($settings{$key}))
	{
	    $self->{$key} = $settings{$key};
	}
    }
    return $self->SUPER::SetSettings (\%settings);
}

=item
C<< $status = Bootloader::Core::GRUB->InitializeBootloader (); >>

Initializes the firmware to boot the bootloader.
Returns undef on fail, defined nonzero value otherwise

=cut

# boolean InitializeBootloader ()
sub InitializeBootloader {
    my $self = shift;

    # FIXME: activate
    # call parted if activate set

    # FIXME: generic_mbr
    # write generic_mbr in case

    my $log = Bootloader::Path::BootCommandLogname();
    my $grub = Bootloader::Path::Grub_grub();
    my $grubconf = Bootloader::Path::Grub_grubconf();
    my $devicemap = Bootloader::Path::Grub_devicemap();
    my $ret = $self->RunCommand (
	"cat $grubconf | $grub --device-map=$devicemap --batch",
	$log
    );
    if ($ret == 0)
    {
	open (LOG, $log) || return $ret;
	while (my $line = <LOG>)
	{
	    if ($line =~ /Error [0-9]*:/)
	    {
		return undef;
	    }
	}
	close (LOG);
    }
    return $ret == 0;
}

=item
C<< $mountpoint = Bootloader::Core::GRUB->GrubDev2MountPoint (); >>

creates the mountpoint from a Grub Device (hdX,Y), be it
a udev device, a udev link or a device mapper device

returns the mountpoint or the grub device, if it couldn't be resolved

=cut

sub GrubDev2MountPoint {
    my $self = shift;
    my $grub_dev = shift;
    my @devices = ();
    my $device = $self->GrubDev2UnixDev($grub_dev);

    return $grub_dev if ($grub_dev eq $device); #immediatelly return if GrubDev2UnixDev fail

    $self->milestone("device: $device");

    # MD-RAID handling: find the corresponding /dev/mdX if any. 
    #FIXME is it needed? isnt't member of array instead of array device error?
    while ((my $md, my $members_ref) = each (%{$self->{"md_arrays"}})) {

	my $members = join ", ", @{$members_ref};
	$self->debug("MD Array: $md ; Members: $members");

	foreach my $md_member (@{$members_ref}) {
	    if ($self->GetKernelDevice($device) eq $self->GetKernelDevice($md_member)) {
	        $self->milestone("find md: $md");
      		push (@devices, $md);
	    }
	}
    }

    push (@devices, $device);

    my $mountpoint = $grub_dev;
    foreach $device (@devices) {
	while ((my $mp, my $d) = each (%{$self->{"mountpoints"}})) {
	    $self->debug("record $mp <-> $d");
	    if ($self->GetKernelDevice($d) eq $self->GetKernelDevice($device)) { 
	      $self->milestone("find mountpoint: $mp");
    	  $mountpoint = $mp;
	    }
	}
    }

    return $mountpoint;  
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
