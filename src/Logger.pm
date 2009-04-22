#! /usr/bin/perl -w
#
# Bootloader logging class
#

=head1 NAME

Bootloader::Logger - library for logging


=head1 PREFACE

This package is the private logging part. It doesn't use existing logging library, because it must handle logging via yast and also logging during kernel update. Also target is to have minimum dependencies for inst-sys.


=head1 SYNOPSIS

C<< use Bootloader::Logger; >>

C<< $obj_ref = Bootloader::Logger->new (); >>

C<< $status = Bootloader::Library->SetLoaderType ($bootloader); >>

C<< $status = Bootloader::Library->DefineMountPoints (\%mountpoints); >>

C<< $status = Bootloader::Library->DefinePartitions (\@partitions); >>

C<< $status = Bootloader::Library->DefineMDArrays (\%md_arrays); >>

C<< $status = Bootloader::Library->ReadSettings (); >>

C<< $status = Bootloader::Library->WriteSettings (); >>

C<< $status = Bootloader::Library->ReadSettingsTmp ($tmp_dir); >>

C<< $status = Bootloader::Library->WriteSettingsTmp ($tmp_dir); >>

C<< $files_contents_ref = Bootloader::Library->GetFilesContents (); >>

C<< $status = Bootloader::Library->SetFilesContents (\%files_contents); >>

C<< $status = Bootloader::Library->UpdateBootloader ($avoid_init); >>

C<< $status = Bootloader::Library->InitializeBootloader (); >>

C<< $file_list_ref = Bootloader::Library->ListConfigurationFiles (); >>

C<< $settings_ref = Bootloader::Library->GetSettings (); >>

C<< $status Bootloader::Library->SetSettings ($settings_ref); >>

C<< $meta_ref = Bootloader::Library->GetMetaData (); >>

C<< $global_ref = Bootloader::Library->GetGlobalSettings (); >>

C<< $status = Bootloader::Library->SetGlobalSettings ($global_settings_ref); >>

C<< $sections_ref = Bootloader::Library->GetSections (); >>

C<< $status = Bootloader::Library->SetSections ($sections_ref); >>

C<< $device_map_ref = Bootloader::Library->GetDeviceMapping (); >>

C<< $status = Bootloader::Library->SetDeviceMapping ($device_map_ref); >>

C<< $unix_dev = Bootloader::Library->GrubDev2UnixDev ($grub_dev); >>

C<< $result = Bootloader::Library::DetectThinkpadMBR ($disk); >>

C<< $result = Bootloader::Library::WriteThinkpadMBR ($disk); >>

=head1 DESCRIPTION

=over 2

=cut


package Bootloader::Logger;

use strict;

my $singleton_instance;

sub instance {
  $singleton_instance ||= new();
}

=item
C<< $obj_ref = Bootloader::Library->new (); >>

Creates an instance of the Bootloader::Library class.

=cut
sub new {
    my $self = shift;

    my $lib = {};
    $lib->{"logs"} = [];
    $lib->{"log_level"} = 1;
    bless ($lib);
    return $lib;
}

sub SetLogLevel {
    my $self = shift;
    my $level = shift;

    if ($level eq "debug")
    {
       $self->{"log_level"} = 0;
    }
    elsif ($level eq "milestone")
    {
       $self->{"log_level"} = 1;
    }
    elsif ($level eq "warning")
    {
       $self->{"log_level"} = 2;
    }
    elsif ($level eq "error")
    {
       $self->{"log_level"} = 3;
    }
    elsif ($level eq "nolog")
    {
       $self->{"log_level"} = 4;
    }
    else
    {
      return undef;
    }

    return 1;
}

sub GetLogRecords {
    my $self = shift;

    my $ret = $self->{"logs"};
    $self->{"logs"} = [];
    return $ret;
}

sub debug {
  my $self = shift;
  my $message = shift;

  if ($self->{"log_level"}>0){
    return;
  }

  push @{$self->{"logs"}}, {
     "message" => $message,
     "level" => "debug",
  };
}
sub milestone {
  my $self = shift;
  my $message = shift;

  if ($self->{"log_level"}>1){
    return;
  }

  push @{$self->{"logs"}}, {
     "message" => $message,
     "level" => "milestone",
  };
}
sub warning {
  my $self = shift;
  my $message = shift;

  if ($self->{"log_level"}>2){
    return;
  }

  push @{$self->{"logs"}}, {
     "message" => $message,
     "level" => "warning",
  };
}
sub error {
  my $self = shift;
  my $message = shift;

  if ($self->{"log_level"}>3){
    return;
  }

  push @{$self->{"logs"}}, {
     "message" => $message,
     "level" => "error",
  };
}

1;
