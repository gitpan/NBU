#
# Copyright (c) 2002 Paul Winkeler.  All Rights Reserved.
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.
#
package NBU::Host;

use strict;
use Carp;

my %hostList;

BEGIN {
  use Exporter   ();
  use AutoLoader qw(AUTOLOAD);
  use vars       qw($VERSION @ISA @EXPORT @EXPORT_OK %EXPORT_TAGS $AUTOLOAD);
  $VERSION =	 do { my @r=(q$Revision: 1.10 $=~/\d+/g); sprintf "%d."."%02d"x$#r,@r };
  @ISA =         qw();
  @EXPORT =      qw();
  @EXPORT_OK =   qw();
  %EXPORT_TAGS = qw();
}

sub new {
  my $Class = shift;
  my $host;

  if (@_) {
    my $name = shift;
    my $keyName = substr($name, 0, 12);

    if (!($host = $hostList{$keyName})) {
      $host = {};
      bless $host, $Class;
      $host->{NAME} = $name;

      $hostList{$keyName} = $host;
    }
  }
  return $host;
}

sub populate {
  my $Class = shift;

  my $pipe = NBU->cmd("bpclclients -allunique -noheader |");
  while (<$pipe>) {
    my ($platform, $os, $name) = split;
    my $host = NBU::Host->new($name);

    $host->os($os);
    $host->platform($platform);
  }
  close($pipe);
}

sub byName {
  my $Class = shift;
  my $name = shift;
  my $keyName = substr($name, 0, 12);

  if (my $host = $hostList{$keyName}) {
    return $host;
  }
  return undef;
}

sub list {
  my $Class = shift;

  return (values %hostList);
}

sub loadClass {
  my $self = shift;
  my $newClass = shift;

  if (!defined($self->{CLASSES})) {
    $self->{CLASSES} = [];
  }

  my $classListR = $self->{CLASSES};
  push @$classListR, $newClass;

  return $newClass;
}

sub classList {
  my $self = shift;

  my $classListR = $self->{CLASSES};
  if (defined($classListR)) {
    return (@$classListR);
  }
  return undef;
}

sub name {
  my $self = shift;

  return $self->{NAME};
}

sub loadConfig {
  my $self = shift;

  return 1 if ($self->{CONFIGLOADED});

  my $pipe = NBU->cmd("bpgetconfig -g ".$self->name." |");
  $_ = <$pipe>;  chop;
  if (/Client of ([\S]+)/) {
    $self->{MASTER} = NBU::Host->new($1);
  }

  # OS on this machine
  $_ = <$pipe>;  chop;
  my ($platform, $os) = split;
  $self->platform($platform);
  $self->os($os);

  # Now get the NetBackup version information
  # All the hosts in the cluster better be running the same version
  # but we're not checking for that at this time.
  $_ = <$pipe>;  chop;
  $self->NBUVersion($_);

  close($pipe);

  $self->{CONFIGLOADED} = 1;

}

sub clientOf {
  my $self = shift;

  $self->loadConfig;
  return $self->{MASTER};
}

sub platform {
  my $self = shift;

  if (@_) {
    $self->{PLATFORM} = shift;
  }
  else {
    $self->loadConfig;
  }

  return $self->{PLATFORM};
}

sub os {
  my $self = shift;

  if (@_) {
    $self->{OS} = shift;
  }
  else {
    $self->loadConfig;
  }

  return $self->{OS};
}

sub NBUVersion {
  my $self = shift;

  if (@_) {
    $self->{NBUVERSION} = shift;
  }
  else {
    $self->loadConfig;
  }

  return $self->{NBUVERSION};
}

sub loadCoverage {
  my $self = shift;
  my $name = $self->name;

  my %coverage;
  my $loadOK;

  my $pipe = NBU->cmd("bpcoverage -c $name -no_cov_header -no_hw_header |");
  while (<$pipe>) {
    if (!$loadOK) {
      if (/^CLIENT: $name/) {
	while (<$pipe>) {
          last if (/Mount Point/ || /Drive Letter/);
	}
        $_ = <$pipe>;
        $loadOK = 1;
      }
    }
    elsif ($loadOK && !(/^$/) && !(/   Exit status/)) {
      my ($mountPoint, @remainder) = split;

      if ($self->os =~ /Solaris/) {
	my ($deviceFile, $className, $status) = @remainder;
        if ($className eq "UNCOVERED") {
	  $coverage{$mountPoint} = undef;
        }
        else {
	  $className =~ s/^\*//;
	  my $clR = $coverage{$mountPoint};
	  if (!$clR) {
	    $coverage{$mountPoint} = $clR = [];
	  }
	  my $class = NBU::Class->byName($className);
	  $class->providesCoverage(1);
          push @$clR, $class;
        }
      }
      elsif ($self->os =~ /Windows(NT|2000)/) {
        my ($className, $status) = @remainder;
        if ($className eq "UNCOVERED") {
	  $coverage{$mountPoint} = undef;
        }
        else {
	  $className =~ s/^\*//;
	  my $clR = $coverage{$mountPoint};
	  if (!$clR) {
	    $coverage{$mountPoint} = $clR = [];
	  }
	  my $class = NBU::Class->byName($className);
	  $class->providesCoverage(1);
          push @$clR, $class;
        }
      }
      else {
        print "coverage from ".$self->os.": $_";
      }
    }
    else {
      last;
    }
  }
  close($pipe);

  $self->{COVERAGE} = \%coverage;
}

sub coverage {
  my $self = shift;

  if (!$self->{COVERAGE}) {
    $self->loadCoverage;
  }

  my $coverageR = $self->{COVERAGE};
  return (%$coverageR);
}

#
# Add an image to a host's list of backup images
sub addImage {
  my $self = shift;
  my $image = shift;
  
  $self->{IMAGES} = [] if (!defined($self->{IMAGES}));

  my $images = $self->{IMAGES};

  push @$images, $image;
}

#
# Load the list of images run against this host
sub loadImages {
  my $self = shift;

  NBU::Image->loadImages(NBU->cmd("bpimmedia -l -client ".$self->name." |"));
  return $self->{IMAGES};
}

sub images {
  my $self = shift;

  if (!defined($self->{IMAGES})) {
    $self->loadImages;
  }

  my $images = $self->{IMAGES};
  return (@$images);
}

1;

__END__
