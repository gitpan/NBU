#
# Copyright (c) 2002 Paul Winkeler.  All Rights Reserved.
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.
#
package NBU::StorageUnit;

use strict;
use Carp;

use NBU::Media;

BEGIN {
  use Exporter   ();
  use AutoLoader qw(AUTOLOAD);
  use vars       qw($VERSION @ISA @EXPORT @EXPORT_OK %EXPORT_TAGS $AUTOLOAD);
  $VERSION =	 do { my @r=(q$Revision: 1.11 $=~/\d+/g); sprintf "%d."."%02d"x$#r,@r };
  @ISA =         qw();
  @EXPORT =      qw();
  @EXPORT_OK =   qw();
  %EXPORT_TAGS = qw();
}

my %stuList;
my $populated;

my %types = (
  1 => "Disk",
  2 => "Media Manager",
  3 => "NDMP",
);

sub new {
  my $proto = shift;
  my $stu = {};

  bless $stu, $proto;

  if (@_) {
    $stu->{LABEL} = shift;
    my $type;
    if (@_ && exists($types{$type = shift})) {
      $stu->{TYPE} = $types{$type};
    }
    else {
      $stu->{TYPE} = $type;
    }
  }

  $stuList{$stu->{LABEL}} = $stu;
  return $stu;
}

sub populate {
  my $proto = shift;

  $populated = 0;
  my $pipe = NBU->cmd("bpstulist |");
  while (<$pipe>) {
    my ($label, $type, $hostName,
	$robotType, $robotNumber, $density,
	$numberOfDrives,
	$initialMPX,
	$path,
	$maxFragmentSize, $onDemandOnly, $maxMPXperDrive,
	$ndmpAttachHostName,
    ) = split;

    my $stu;
    if (!defined($stu = NBU::StorageUnit->byLabel($label))) {
      $stu = NBU::StorageUnit->new($label, $type);
    }

    $stu->{HOST} = NBU::Host->new($hostName);

    $stu->{ROBOT} = NBU::Robot->new($robotNumber, $robotType, undef);

    $stu->{DRIVECOUNT} = $numberOfDrives;
    $stu->{DENSITY} = $NBU::Media::densities{$density};

    $populated += 1;
  }
  close($pipe);

}

sub list {
  my $proto = shift;

  return (values %stuList);
}

sub byLabel {
  my $proto = shift;
  my $label = shift;

  $proto->populate if (!defined($populated));

  if (!exists($stuList{$label})) {
    return $proto->new($label);
  }
  return $stuList{$label};
}

sub host {
  my $self = shift;

  return $self->{HOST};
}

sub type {
  my $self = shift;

  return $self->{TYPE};
}

sub density {
  my $self = shift;

  return $self->{DENSITY};
}

sub driveCount {
  my $self = shift;

  return $self->{DRIVECOUNT};
}

sub label {
  my $self = shift;

  return $self->{LABEL};
}

sub robot {
  my $self = shift;

  return $self->{ROBOT};
}

1;
__END__
