#
# Copyright (c) 2002 Paul Winkeler.  All Rights Reserved.
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.
#
package NBU::Image;

use strict;
use Carp;

my %imageList;

BEGIN {
  use Exporter   ();
  use AutoLoader qw(AUTOLOAD);
  use vars       qw($VERSION @ISA @EXPORT @EXPORT_OK %EXPORT_TAGS $AUTOLOAD);
  $VERSION =	 do { my @r=(q$Revision: 1.16 $=~/\d+/g); sprintf "%d."."%02d"x$#r,@r };
  @ISA =         qw();
  @EXPORT =      qw();
  @EXPORT_OK =   qw();
  %EXPORT_TAGS = qw();
}

sub new {
  my $proto = shift;
  my $image;

  if (@_) {
    my $backupID = shift;
    if (exists($imageList{$backupID})) {
      $image = $imageList{$backupID};
    }
    else {
      $image = { };
      bless $image, $proto;
      $imageList{$image->id($backupID)} = $image;
    }
  }
  return $image;
}

sub populate {
  my $proto = shift;

  $proto->loadImages(NBU->cmd("bpimmedia -l |"));
}

sub byID {
  my $proto = shift;
  my $backupID = shift;

  if (exists($imageList{$backupID})) {
    return $imageList{$backupID};
  }

  return undef;
}

sub list {
  my $proto = shift;

  return (values %imageList);
}

sub id {
  my $self = shift;

  if (@_) {
    $self->{BACKUPID} = shift;
    # The backup ID of an image in part encodes the time the image was
    # created
    $self->{CTIME} = substr($self->{BACKUPID}, -10);
  }
  return $self->{BACKUPID};
}

sub ctime {
  my $self = shift;

  return $self->{CTIME};
}

sub client {
  my $self = shift;

  if (@_) {
    my $host = shift;
    if (defined($self->{CLIENT})) {
      if ((my $oldHost = $self->{CLIENT}) == $host) {
	return $host;
      }
      else {
#	$oldHost->removeImage($self);
      }
    }
    $host->addImage($self);
    $self->{CLIENT} = $host;
  }
  return $self->{CLIENT};
}

sub class {
  my $self = shift;

  if (@_) {
    $self->{CLASS} = shift;
  }
  return $self->{CLASS};
}

sub schedule {
  my $self = shift;

  if (@_) {
    $self->{SCHEDULE} = shift;
  }
  return $self->{SCHEDULE};
}

sub expires {
  my $self = shift;

  if (@_) {
    $self->{EXPIRES} = shift;
  }
  return $self->{EXPIRES};
}

sub retention {
  my $self = shift;

  if (@_) {
    $self->{RETENTION} = shift;
  }
  return $self->{RETENTION};
}


sub size {
  my $self = shift;
  my $size;

  for my $f ($self->fragments) {
    next unless defined($f);
    $size += $f->size;
  }

  return $size;
}

#
# Add another fragment to this image
sub insertFragment {
  my $self = shift;
  my $fragment = shift;
  
  $self->{FRAGMENTS} = [] if (!defined($self->{FRAGMENTS}));

  my $toc = $self->{FRAGMENTS};

  return $$toc[$fragment->number - 1] = $fragment;
}

sub loadFragments {
  my $self = shift;

  $self->{FRAGMENTS} = [] if (!defined($self->{FRAGMENTS}));

  return $self;
}

sub fragments {
  my $self = shift;
  my $fragment = shift;
  
  if (!defined($self->{FRAGMENTS})) {
    $self->loadFragments;
  }

  my $toc = $self->{FRAGMENTS};
  return @$toc;
}

sub loadImages {
  my $proto = shift;
  my $pipe = shift;

  my $image;
  while (<$pipe>) {
    if (/^IMAGE/) {
      my ($tag, $clientName, $clientVersion, $backupID, $className,
	$classType,
	$scheduleName,
	$scheduleType,
	$retentionLevel, $fileCount, $expires,
	$compressed, $encrypted
      ) = split;

      $image = undef;
      next if ($expires < time);

      $image = NBU::Image->new($backupID);
      $image->{ENCRYPTED} = $encrypted;
      $image->{COMPRESSED} = $compressed;
      $image->{FILECOUNT} = $fileCount;
      $image->{EXPIRES} = $expires;
      $image->{RETENTION} = NBU::Retention->byLevel($retentionLevel);

      my $class = $image->class(NBU::Class->new($className));
      $image->schedule(NBU::Schedule->new($class, $scheduleName, $scheduleType));

      my $host;
      $image->client($host = NBU::Host->new($clientName));
    }
    elsif (/^FRAG/) {
      next if (!defined($image));

      my ($tag, $copy, $number, $size, $removable,
	  $mediaType, $density, $fileNumber,
	  $mediaID, $mmHost,
	  $blockSize, $offset, $allocated, $dwo,
	  $u6, $u7,
	  $expires, $mpx
      ) = split;
      my $volume = NBU::Media->byID($mediaID);
      my $fragment = NBU::Fragment->new($number, $image, $volume, $offset, $size, $dwo, $fileNumber, $blockSize);
      $volume->insertFragment($fileNumber - 1, $fragment);
      $image->insertFragment($fragment);
    }
  }
  close($pipe);
}

sub loadFileList {
  my $self = shift;
  my @fl;
 
  my ($s, $m, $h, $dd, $mon, $year, $wday, $yday, $isdst) = localtime($self->ctime);
  my $mm = $mon + 1;
  my $yy = sprintf("%02d", ($year + 1900) % 100);
  my $pipe = NBU->cmd("bpflist -t ANY".
    " -option GET_ALL_FILES".
    " -client ".$self->client->name.
    " -backupid ".$self->id.
    " -d ${mm}/${dd}/${yy}"." |");
  while (<$pipe>) {
    next if (/^FILES/);
    my ($i, $u1, $u2, $u3, $offset, $u4, $u5, $u6, $u7, $name, $u8, $user, $group, $size, $tm1, $tm2, $tm3) = split;
    next if ($name =~ /(\/|\\)$/);
    push @fl, $name;
  }
  close($pipe);

  $self->{FLIST} = \@fl;
}

sub fileList {
  my $self = shift;

  if (!$self->{FLIST}) {
    $self->loadFileList;
  }

  if (my $flR = $self->{FLIST}) {
    return @$flR;
  }
  return undef;
}

1;

__END__
