#
# Copyright (c) 2002 Paul Winkeler.  All Rights Reserved.
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.
#
package NBU::Pool;

use strict;
use Carp;

BEGIN {
  use Exporter   ();
  use AutoLoader qw(AUTOLOAD);
  use vars       qw($VERSION @ISA @EXPORT @EXPORT_OK %EXPORT_TAGS $AUTOLOAD);
  $VERSION =	 do { my @r=(q$Revision: 1.4 $=~/\d+/g); sprintf "%d."."%02d"x$#r,@r };
  @ISA =         qw();
  @EXPORT =      qw();
  @EXPORT_OK =   qw();
  %EXPORT_TAGS = qw();
}

my $wet;
my %poolIDs;
my %poolNames;

sub new {
  my $Class = shift;
  my $Pool = {
  };

  bless $Pool, $Class;

  if (@_) {
    my $id = $Pool->{ID} = shift;
    my $name = $Pool->{NAME} = shift;

    $poolIDs{$id} = $Pool;
    $poolNames{$name} = $Pool;
  }
  return $Pool;
}

sub populate {
  my $Class = shift;

  return $wet if (defined($wet));

  my @masters = NBU->masters;  my $master = $masters[0];

  die "Could not open pool pipe\n" unless my $pipe = NBU->cmd("vmpool -h ".$master->name." -listall |");
  $wet = 0;
  my $number;
  my ($name, $host, $user, $group, $description);
  while (<$pipe>) {
    chop;
    if (/^=================/) {
      if ($number) {
	$Class->new($number, $name);
      }
      $number = undef;
    }
    $number = $1 if (/^pool number:[\s]+([\d]+)/);
    $name = $1 if (/^pool name:[\s]+([\S]+)/);
    $host = $1 if (/^pool host:[\s]+([\S]+)/);
    $user = $1 if (/^pool user:[\s]+([\S]+)/);
    $group = $1 if (/^pool group:[\s]+([\S]+)/);
    $description = $1 if (/^pool description:[\s]+([\S].*)/);

    $wet += 1;
  }
  close($pipe);
  return $wet;
}

sub byName {
  my $Class = shift;
  my $name = shift;

  $Class->populate if (!$wet);
  return $poolNames{$name};
}

sub byID {
  my $Class = shift;
  my $id = shift;

  $Class->populate if (!$wet);
  return $poolIDs{$id};
}

sub name {
  my $self = shift;

  return $self->{NAME};
}

sub id {
  my $self = shift;

  return $self->{ID};
}

sub list {
  my $Class = shift;

  $Class->populate if (!$wet);
  return (values %poolIDs);
}

1;

__END__
