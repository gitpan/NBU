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
  $VERSION =	 do { my @r=(q$Revision: 1.8 $=~/\d+/g); sprintf "%d."."%02d"x$#r,@r };
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
    }
  }
  return $class;
}

sub populate {
  shift;

  NBU::Pool->populate;

  my $pipe = NBU->cmd("bpcllist -allclasses -L |");
  my $class;
  while (<$pipe>) {

    if (/^$/) {
      $class = undef;
    }
    if (/^Class Name:[\s]+([\S]+)/) {
      $class = NBU::Class->new($1);
    }

    if (/^Class Type:[\s]+([\S]+)/) {
      $class->type($1);
    }
    if (/^Active:[\s]+([\S]+)/) {
      $class->active($1 eq "yes");
    }
    if (/^Client Compress:[\s]+([\S]+)/) {
      $class->clientCompressed($1 eq "yes");
    }
    if (/^Follow NFS Mnts:[\s]+([\S]+)/) {
      $class->followNFSMounts($1 eq "yes");
    }
    if (/^Cross Mnt Points:[\s]+([\S]+)/) {
      $class->crossMountPoints($1 eq "yes");
    }
    if (/^Collect TIR Info:[\s]+([\S]+)/) {
      $class->TIR($1 eq "yes");
    }
    if (/^Block Incremental:[\s]+([\S]+)/) {
      $class->BLIB($1 eq "yes");
    }
    if (/^Mult\. Data Stream:[\s]+([\S]+)/) {
      $class->multipleDataStreams($1 eq "yes");
    }
    if (/^Class Priority:[\s]+([\d]+)/) {
      $class->priority($1);
    }
    if (/^Max Jobs\/Class:[\s]+([\d]+)/) {
      $class->maxJobs($1);
    }
    if (/^Disaster Recovery:[\s]+([\d]+)/) {
      $class->DR($1 eq "yes");
    }
    if (/^Keyword:[\s]+(.*$)/) {
      $class->keywords($1)
        if ($1 ne "(none specified)");
    }
    if (/^Client Ecnrypt:[\s]+([\S]+)/) {
      $class->clientEncrypted($1 eq "yes");
    }
    if (/^Residence:[\s]+(.*)/) {
      foreach my $r (split(/[\s]+/, $1)) {
        if ($r ne "-") {
          $class->residence($r);
        }
      }
    }
    if (/^Volume Pool:[\s]+(.*)/) {
      foreach my $pn (split(/[\s]+/, $1)) {
        if ($pn ne "-") {
          $class->pool(NBU::Pool->byName($pn));
        }
      }
    }
    if (/^Client\/HW\/OS\/Pri:[\s]+(.*)/) {
      my ($name, $hw, $os, $pri) = split(/[\s]+/, $1);
      my $client = NBU::Host->new($name);

      $class->loadClient($client);
      $client->loadClass($class);
    }
    if (/^Include:[\s]+(.*)/) {
      $class->include($1);
    }
    if (/^Exclude:[\s]+(.*)/) {
      $class->exclude($1);
    }
    if (/^Schedule:[\s]+([\S]+)/) {
      $class->loadSchedule(NBU::Schedule->new($1));
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

sub clientList {
  my $self = shift;

  my $clientListR = $self->{CLIENTS};
  return (defined($clientListR) ? (@$clientListR) : undef);
}

sub exclude {
  my $self = shift;

  if (@_) {
    if (!defined($self->{EXCLUDE})) {
      $self->{EXCLUDE} = [];
    }
    my $excludeListR = $self->{EXCLUDE};
    my $newExclude = shift;

    push @$excludeListR, $newExclude;
  }
  my $excludeListR = $self->{EXCLUDE};
  
  return (defined($excludeListR) ? (@$excludeListR) : undef);
}

sub include {
  my $self = shift;

  if (@_) {
    if (!defined($self->{INCLUDE})) {
      $self->{INCLUDE} = [];
    }
    my $includeListR = $self->{INCLUDE};
    my $newInclude = shift;

    push @$includeListR, $newInclude;
  }
  my $includeListR = $self->{INCLUDE};
  
  return (defined($includeListR) ? (@$includeListR) : undef);
}

sub pool {
  my $self = shift;

  if (@_) {
    print $self->name." already has a pool: ".$self->{POOL}."\n" if ($self->{POOL});
    $self->{POOL} = shift;
  }

  return $self->{POOL};
}

sub residence {
  my $self = shift;

  if (@_) {
    print $self->name." already has a residence: ".$self->{RESIDENCE}."\n" if ($self->{RESIDENCE});
    $self->{RESIDENCE} = shift;
  }

  return $self->{RESIDENCE};
}

sub type {
  my $self = shift;

  if (@_) {
    $self->{TYPE} = shift;
  }
  return $self->{TYPE};
}

sub keywords {
  my $self = shift;

  if (@_) {
    $self->{KEYWORDS} = shift;
  }
  return $self->{KEYWORDS};
}

sub DR {
  my $self = shift;

  if (@_) {
    $self->{DR} = shift;
  }
  return $self->{DR};
}

sub maxJobs {
  my $self = shift;

  if (@_) {
    $self->{MAXJOBS} = shift;
  }
  return $self->{MAXJOBS};
}

sub priority {
  my $self = shift;

  if (@_) {
    $self->{PRIORITY} = shift;
  }
  return $self->{PRIORITY};
}

sub multipleDataStreams {
  my $self = shift;

  if (@_) {
    $self->{MDS} = shift;
  }
  return $self->{MDS};
}

sub BLIB {
  my $self = shift;

  if (@_) {
    $self->{BLIB} = shift;
  }
  return $self->{BLIB};
}

sub TIR {
  my $self = shift;

  if (@_) {
    $self->{TIR} = shift;
  }
  return $self->{TIR};
}

sub crossMountPoints {
  my $self = shift;

  if (@_) {
    $self->{CROSS} = shift;
  }
  return $self->{CROSS};
}

sub followNFSMounts {
  my $self = shift;

  if (@_) {
    $self->{FOLLOW} = shift;
  }
  return $self->{FOLLOW};
}

sub clientCompressed {
  my $self = shift;

  if (@_) {
    $self->{COMPRESSED} = shift;
  }
  return $self->{COMPRESSED};
}

sub clientEncrypted {
  my $self = shift;

  if (@_) {
    $self->{ENCRYPTED} = shift;
  }
  return $self->{ENCRYPTED};
}

sub active {
  my $self = shift;

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

  if (@_) {
    $self->{COVERS} = shift;
  }

  return $self->{COVERS};
}

1;

__END__
