#
# Copyright (c) 2002 Paul Winkeler.  All Rights Reserved.
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.
#
package NBU::Class;

use strict;
use Carp;

use NBU::Host;
use NBU::Schedule;

my %classList;

BEGIN {
  use Exporter   ();
  use AutoLoader qw(AUTOLOAD);
  use vars       qw($VERSION @ISA @EXPORT @EXPORT_OK %EXPORT_TAGS $AUTOLOAD);
  $VERSION =	 do { my @r=(q$Revision: 1.12 $=~/\d+/g); sprintf "%d."."%02d"x$#r,@r };
  @ISA =         qw();
  @EXPORT =      qw();
  @EXPORT_OK =   qw();
  %EXPORT_TAGS = qw();
}

sub new {
  my $Class = shift;
  my $class;

  if (@_) {
    my $name = shift;

    if (!($class = $classList{$name})) {
      $class = {
        CLIENTS => [],
      };
      bless $class, $Class;

      $classList{$class->{NAME} = $name} = $class;
      $class->{TYPE} = shift;
    }
  }
  return $class;
}

my %classTypes = (
  0 => "Standard",
  3 => "Apollo_WBAK",
  4 => "Oracle",
  6 => "Informix",
  7 => "Sybase",
  10 => "NetWare",
  11 => "BackTrack",
  12 => "Auspex_Fastback",
  13 => "Windows_NT",
  14 => "OS2",
  15 => "SQL_Server",
  16 => "Exchange",
  17 => "SAP",
  18 => "DB2",
  19 => "NDMP",
  20 => "FlashBackup",
  21 => "SplitMirror",
  22 => "AFS",
);

sub populate {
  my $proto = shift;
  my $self = ref($proto) ? $proto : undef;;

  NBU::Pool->populate;

  my $source = $self ? $self->name : "-allclasses";
  my $pipe = NBU->cmd("bpcllist $source -l |");

  my $class;
  my $schedule;
  while (<$pipe>) {
    chop;
    if (/^CLASS/) {
      my ($tag, $name, $ptr1, $u1, $u2, $u3, $ptr2) = split;
      $class = NBU::Class->new($name);
      $class->{LOADED} = 1;
      next;
    }
    if (/^NAMES/) {
      next;
    }
    if (/^INFO/) {
      my ($tag, $type, $networkDrives, $clientCompression, $priority, $ptr1,
	  $u2, $u3, $maxJobs, $crossMounts, $followNFS,
	  $inactive, $TIR, $u6, $u7, $restoreFromRaw, $multipleDataStreams, $ptr2) = split;
      $class->{TYPE} = $type;
      $class->{NETWORKDRIVES} = $networkDrives;
      $class->{COMPRESSION} = $clientCompression;
      $class->{PRIORITY} = $priority;
      $class->{MAXJOBS} = $maxJobs;
      $class->{CROSS} = $crossMounts;
      $class->{FOLLOW} = $followNFS;
      $class->{ACTIVE} = !$inactive;
      $class->{TIR} = $TIR;
      $class->{RESTOREFROMRAW} = $restoreFromRaw;
      $class->{MDS} = $multipleDataStreams;
      next;
    }
    if (/^KEY/) {
      my ($tag, @keys) = split;;
      $class->{KEYS} = \@keys unless ($keys[0] eq "*NULL*");
      next;
    }
    if (/^BCMD/) {
      next;
    }
    if (/^RCMD/) {
      next;
    }
    if (/^RES/) {
      my ($tag, @residences) = split;
      $class->{RESIDENCE} = $residences[0] unless ($residences[0] eq "*NULL*");
      next;
    }
    if (/^POOL/) {
      my ($tag, @pools) = split;
      $class->{POOL} = NBU::Pool->byName($pools[0]) unless ($pools[0] eq "*NULL*");
      next;
    }
    if (/^CLIENT/) {
      my ($tag, $name, $platform, $os) = split;
      my $client = NBU::Host->new($name);
      $class->loadClient($client);
      $client->loadClass($class);
      next;
    }
    if (/^INCLUDE/) {
      my ($tag, $path) = split;
      $class->include($path);
      next;
    }
    if (/^EXCLUDE/) {
      my ($tag, $path) = split;
      $class->exclude($path);
      next;
    }
    if (/^SCHED/) {
      my ($tag, $name, $type) = split;
      $schedule = $class->loadSchedule(NBU::Schedule->new($class, $name, $type));
      next;
    }
    if (/^SCHEDWIN/) {
      next;
    }
    if (/^SCHEDRES/) {
      next;
    }
    if (/^SCHEDPOOL/) {
      next;
    }
  }
  close($pipe);
}

sub byName {
  my $Class = shift;
  my $name = shift;

  if (my $class = $classList{$name}) {
    return $class;
  }
  return undef;
}

sub list {
  my $Class = shift;

  return (values %classList);
}

sub loadClient {
  my $self = shift;
  my $newClient = shift;

  my $clientListR = $self->{CLIENTS};
  push @$clientListR, $newClient;

  return $newClient;
}

sub loadSchedule {
  my $self = shift;
  my $newSchedule = shift;

  if (!defined($self->{SCHEDULES})) {
    $self->{SCHEDULES} = [];
  }

  my $scheduleListR = $self->{SCHEDULES};
  push @$scheduleListR, $newSchedule;

  return $newSchedule;
}

sub clients {
  my $self = shift;

  $self->populate if (!defined($self->{LOADED}));
  my $clientListR = $self->{CLIENTS};
  return (defined($clientListR) ? (@$clientListR) : undef);
}

sub exclude {
  my $self = shift;

  $self->populate if (!defined($self->{LOADED}));
  if (@_) {
    if (!defined($self->{EXCLUDE})) {
      $self->{EXCLUDE} = [];
    }
    my $excludeListR = $self->{EXCLUDE};
    my $newExclude = shift;

    push @$excludeListR, $newExclude;
  }
  my $excludeListR = $self->{EXCLUDE};
  
  return (defined($excludeListR) ? (@$excludeListR) : ());
}

sub include {
  my $self = shift;

  $self->populate if (!defined($self->{LOADED}));
  if (@_) {
    if (!defined($self->{INCLUDE})) {
      $self->{INCLUDE} = [];
    }
    my $includeListR = $self->{INCLUDE};
    my $newInclude = shift;

    push @$includeListR, $newInclude;
  }
  my $includeListR = $self->{INCLUDE};
  
  return (defined($includeListR) ? (@$includeListR) : ());
}

sub pool {
  my $self = shift;

  $self->populate if (!defined($self->{LOADED}));
  if (@_) {
    print $self->name." already has a pool: ".$self->{POOL}."\n" if ($self->{POOL});
    $self->{POOL} = shift;
  }

  return $self->{POOL};
}

sub residence {
  my $self = shift;

  $self->populate if (!defined($self->{LOADED}));
  if (@_) {
    print $self->name." already has a residence: ".$self->{RESIDENCE}."\n" if ($self->{RESIDENCE});
    $self->{RESIDENCE} = shift;
  }

  return $self->{RESIDENCE};
}

sub type {
  my $self = shift;

  $self->populate if (!defined($self->{LOADED}));
  if (@_) {
    $self->{TYPE} = shift;
  }
  return $classTypes{$self->{TYPE}};
}

sub keywords {
  my $self = shift;

  $self->populate if (!defined($self->{LOADED}));
  if (@_) {
    $self->{KEYWORDS} = shift;
  }
  return $self->{KEYWORDS};
}

sub DR {
  my $self = shift;

  $self->populate if (!defined($self->{LOADED}));
  if (@_) {
    $self->{DR} = shift;
  }
  return $self->{DR};
}

sub maxJobs {
  my $self = shift;

  $self->populate if (!defined($self->{LOADED}));
  if (@_) {
    $self->{MAXJOBS} = shift;
  }
  return $self->{MAXJOBS};
}

sub priority {
  my $self = shift;

  $self->populate if (!defined($self->{LOADED}));
  if (@_) {
    $self->{PRIORITY} = shift;
  }
  return $self->{PRIORITY};
}

sub multipleDataStreams {
  my $self = shift;

  $self->populate if (!defined($self->{LOADED}));
  if (@_) {
    $self->{MDS} = shift;
  }
  return $self->{MDS};
}

sub BLIB {
  my $self = shift;

  $self->populate if (!defined($self->{LOADED}));
  if (@_) {
    $self->{BLIB} = shift;
  }
  return $self->{BLIB};
}

#
# TIR codes are:
# 0	off
# 1	on
# 2	on with move detection
sub TIR {
  my $self = shift;

  $self->populate if (!defined($self->{LOADED}));
  if (@_) {
    $self->{TIR} = shift;
  }
  return $self->{TIR};
}

sub crossMountPoints {
  my $self = shift;

  $self->populate if (!defined($self->{LOADED}));
  if (@_) {
    $self->{CROSS} = shift;
  }
  return $self->{CROSS};
}

sub followNFSMounts {
  my $self = shift;

  $self->populate if (!defined($self->{LOADED}));
  if (@_) {
    $self->{FOLLOW} = shift;
  }
  return $self->{FOLLOW};
}

sub clientCompression {
  my $self = shift;

  $self->populate if (!defined($self->{LOADED}));
  if (@_) {
    $self->{COMPRESSION} = shift;
  }
  return $self->{COMPRESSION};
}

sub clientEncrypted {
  my $self = shift;

  $self->populate if (!defined($self->{LOADED}));
  if (@_) {
    $self->{ENCRYPTION} = shift;
  }
  return $self->{ENCRYPTION};
}

sub active {
  my $self = shift;

  $self->populate if (!defined($self->{LOADED}));
  if (@_) {
    $self->{ACTIVE} = shift;
  }
  return $self->{ACTIVE};
}

sub name {
  my $self = shift;

  if (@_) {
    if (defined($self->{NAME})) {
      delete $classList{$self->{NAME}};
    }
    $self->{NAME} = shift;
    $classList{$self->{NAME}} = $self;
  }
  return $self->{NAME};
}

sub providesCoverage {
  my $self = shift;

  $self->populate if (!defined($self->{LOADED}));
  if (@_) {
    $self->{COVERS} = shift;
  }

  return $self->{COVERS};
}

#
# Load the list of images of this class
sub loadImages {
  my $self = shift;

  NBU::Image->loadImages(NBU->cmd("bpimmedia -l -class ".$self->name." |"));
}

sub images {
  my $self = shift;

  if (!defined($self->{IMAGES})) {
    $self->loadImages;

    my @images;
    for my $client ($self->clients) {
      for my $image ($client->images) {
	push @images, $image  if ($image->class == $self);
      }
    }

    $self->{IMAGES} = \@images;
  }
  my $imageListR = $self->{IMAGES};

  return (@$imageListR);
}

1;

__END__
