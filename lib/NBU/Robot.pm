#
# Copyright (c) 2002 Paul Winkeler.  All Rights Reserved.
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.
#
package NBU::Robot;

use strict;
use Carp;

BEGIN {
  use Exporter   ();
  use AutoLoader qw(AUTOLOAD);
  use vars       qw(%robotLevel);
  use vars       qw($VERSION @ISA @EXPORT @EXPORT_OK %EXPORT_TAGS $AUTOLOAD);
  $VERSION =	 do { my @r=(q$Revision: 1.13 $=~/\d+/g); sprintf "%d."."%02d"x$#r,@r };
  @ISA =         qw();
  @EXPORT =      qw(%robotLevel);
  @EXPORT_OK =   qw();
  %EXPORT_TAGS = qw();
}

my @farm;

my %robotTypes = (
  1 => 'ACS',
  2 => 'TS8',
  3 => 'TC8',
  5 => 'ODL',
  6 => 'TL8',
  7 => 'TL4',
  8 => 'TLD',
  9 => 'TC4',
  10 => 'TSD',
  11 => 'TSH',
  12 => 'TLH',
  13 => 'TLM',
  17 => 'LMF',
  0 => 'NONE',
);

sub new {
  my $Class = shift;
  my $robot = {};


  if (@_) {
    my $id = shift;

    my $type = shift;
    if ($type =~ /^[\d]+$/) {
      if (!exists($robotTypes{$type}) || ($type == 0)) {
        return undef;
      }
      else {
	$type = $robotTypes{$type};
      }
      $robot->{TYPE} = $robotTypes{$type};
    }
    else {
      $robot->{TYPE} = $type;
    }


    if ($farm[$id]) {
      $robot =  $farm[$id];
    }
    else {
      bless $robot, $Class;
      $robot->{ID} = $id;
      $farm[$id] = $robot;

      $robot->{DEVICEPATH} = undef;
      $robot->{MAILSLOTSIZE} = 14;
      $robot->{SLOTS} = {};
      $robot->{DRIVES} = [];
    }

    if (defined(my $hostName = shift)) {
      $robot->{CONTROLHOST} = NBU::Host->new($hostName);
    }
  }

  return $robot;
}

sub populate {
  my $self = shift;

  my $lastSlot;

  my $type = $self->type;
  $type =~ tr/A-Z/a-z/;

  my $pipe = NBU->cmd("vmcheckxxx ".
	" -rt $type".
	" -rn ".$self->id.
	" -rh ".$self->host->name.
	" -list |");

  if ($self->host->NBUVersion eq "3.2.0") {
    while (<$pipe>) {
      if (/^Slot = [\s]*([\d]+), Barcode = ([\S]+)$/) {
	$self->insert($1, NBU::Media->byBarcode($2));
	$lastSlot = $1;
      }
      elsif (/^Slot = [\s]*([\d]+), <EMPTY>/) {
	$lastSlot = $1;
      }
      else {
        print STDERR "Ignoring $_";
      }
    }
  }
  elsif ($self->host->NBUVersion eq "3.4.0") {
    while (<$pipe>) {
      last if (/^===/);
    }
    while (<$pipe>) {
      if (/^[\s]*([\d]+)[\s]+[\S]+[\s]+([\S]+)/) {
	$self->insert($1, NBU::Media->byBarcode($2));
	$lastSlot = $1;
      }
      elsif (/^[\s]*([\d]+)[\s]+No/) {
	$lastSlot = $1;
      }
      else {
        print STDERR "Ignoring $_";
      }
    }
  }
  else {
    print STDERR "Unknown NetBackup version \"".$self->host->NBUVersion."\"\n";
    $lastSlot = 0;
  }

  $self->{CAPACITY} = $lastSlot;
}

sub byID {
  my $class = shift;
  my $id = shift;

  return $farm[$id];
}

sub id {
  my $self = shift;

  return $self->{ID};
}

sub type {
  my $self = shift;

  return $self->{TYPE};
}

sub host {
  my $self = shift;

  return $self->{CONTROLHOST};
}

sub controlDrive {
  my $self = shift;
  my $drive = shift;


  my $driveList = $self->{DRIVES};
  push @$driveList, $drive;

  return $drive;
}

sub drives {
  my $self = shift;

  my $driveList = $self->{DRIVES};
  return @$driveList;
}

sub insert {
  my $self = shift;
  my $slotList = $self->{SLOTS};
  my ($position, $volume) = @_;

  if (exists($$slotList{$position}) && ($$slotList{$position} != $volume)) {
    print STDERR "Slot $position in ".$self->id." already filled; no room for ".$volume->id."\n";
  }
  else {
    $$slotList{$position} = $volume;
  }
  return $$slotList{$position};
}

sub slot {
  my $self = shift;
  my $slotList = $self->{SLOTS};
  my $position = shift;

  if (@_) {
    return $self->insert($position, shift);
  }
  return $$slotList{$position};
}

sub capacity {
  my $self = shift;

  if (!defined($self->{CAPACITY})) {
    $self->populate;
  }

  return $self->{CAPACITY};
}

sub slotList {
  my $self = shift;
  my $slotList = $self->{SLOTS};
  my @list;

  # slot 0 is not used but PERL arrays default to 0 based indexing...
  push @list, undef;
  for my $s (1..$self->capacity) {
    push @list, $$slotList{$s};
  }

  return @list;
}

sub mediaList {
  my $self = shift;
  my $slotList = $self->{SLOTS};

  return (values %$slotList);
}

sub farm {
  my $Class = shift;

  return (@farm);
}

sub importCAP {
  my $self = shift;

# vmupdate -rn <number> -rt <type> -interactive -empty_ie
}

sub updateInventory {
  my $self = shift;

# vmupdate -rn <number> -rt <type> -M $master -mt $density -use_barcode_rules -rh $jukebox_robot_host{$jukebox} -vh $master" ;
}

1;

__END__
