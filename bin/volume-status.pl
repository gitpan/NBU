#!/usr/local/bin/perl -w

use strict;
use lib '/usr/local/lib/perl5';

use Getopt::Std;
use Time::Local;

my %opts;
getopts('rdclsgpuUaAfFe:m:', \%opts);

use NBU;
NBU->debug($opts{'d'});

NBU::Media->populate(1);
NBU::Media->loadErrors;

print "\"".join('","',
             "id", "pool", "group", "errors", "mounts", "limit", "expires",
              "robot", "slot").
      "\"\n" if ($opts{'c'});
while (<STDIN>) {
  next if (/^[\s]*\#/);

  chop;
  my $mediaID = $_;
  my $volume = NBU::Media->byID($mediaID);

  my $reportOn = 1;

  my $status = "$mediaID: ";
  if (!defined($volume)) {
    $status .= "? not in volume database!";
    $volume = NBU::Media->new($mediaID);
    $reportOn = 0 unless exists($opts{'U'});
  }
  else {
    $reportOn = 0 if exists($opts{'U'});
  }
  {
    $status .=  sprintf("%3d", $volume->mountCount);
    $status .= sprintf("/%3d", $volume->maxMounts) if ($volume->maxMounts);
    $status .= " mounts: ";
    if ($opts{'p'}) {
      $status = $volume->pool->name.": ".$status;
    }
    if ($opts{'g'}) {
      my $g = defined($volume->group) ? $volume->group : "NONE";
      $status = $g.": ".$status;
    }

    if (exists($opts{'m'})) {
      if ($opts{'m'} >= 0) {
        $reportOn &&= ($volume->mountCount >= $opts{'m'});
      }
      else {
        $reportOn &&= ($volume->mountCount < -$opts{'m'});
      }
    }

    if ($volume->errorCount) {
      $status .= $volume->errorCount." errors: ";
    }
    if (exists($opts{'e'})) {
      if ($opts{'e'} == 0) {
        $reportOn &&= ($volume->errorCount == 0)
      }
      elsif ($opts{'e'} > 0) {
        $reportOn &&= ($volume->errorCount >= $opts{'e'})
      }
      else {
        $reportOn &&= ($volume->errorCount < -$opts{'e'})
      }
    }

    if ($volume->allocated) {
      $status .= "Allocated to ".$volume->mmdbHost->name.": ";
      if ($volume->expires > time) {
        $status .= "Expires ".localtime($volume->expires).": ";
      }
      else {
        $status .= "Expired ".localtime($volume->expires).": ";
      }
      $status .= "Retention level ".$volume->retention->level." " if ($opts{'r'});
    }
    $reportOn &&= $volume->allocated if (exists($opts{'a'}));
    $reportOn &&= !$volume->allocated if (exists($opts{'A'}));

    if ($volume->frozen) {
      $status .= "Frozen: ";
    }
    $reportOn &&= $volume->frozen if (exists($opts{'f'}));
    $reportOn &&= !$volume->frozen if (exists($opts{'F'}));

    if ($volume->robot) {
      $status .= "in R".$volume->robot->id.".".sprintf("%03d", $volume->slot);
    }
    else {
    }
  }

  if ($reportOn) {
    if ($opts{'c'}) {
      print "\"".join('","', $volume->id, $volume->pool->name, $volume->group,
                  $volume->errorCount, $volume->mountCount, $volume->maxMounts,
                  $volume->allocated ? substr(localtime($volume->expires), 4) : "",
                  $volume->robot ? $volume->robot->id : "",
                  $volume->robot ? $volume->slot : "",
            ).
            "\"\n";
    }
    else {
      print "$status\n";
      if ($opts{'l'} && $volume->allocated) {
	my $n = 1;
	foreach my $fragment ($volume->tableOfContents) {
	  printf(" %3u:", $n);

	  my $image = $fragment->image;
	  print "Fragment ".$fragment->id." of ".$image->class->name." from ".$image->client->name.": ";
	  print "Expires ".localtime($image->expires)."\n";

	  $n++;
	}
      }
    }
  }

  if ($opts{'s'} && ($volume->errorCount > 1)) {
    $volume->freeze;
  }
}

=head1 NAME

volume-status.pl - A NetBackup volume attribute analysis tool

=head1 SUPPORTED PLATFORMS

=over 4

=item * 

Any media server platform supported by NetBackup

=back

=head1 SYNOPSIS

    To come...

=head1 DESCRIPTION


=head1 SEE ALSO

=over 4

=item L<volume-list.pl|volume-list.pl>

=item L<toc.pl|toc.pl>

=back

=head1 AUTHOR

Winkeler, Paul pwinkeler@pbnj-solutions.com

=head1 COPYRIGHT

Copyright (C) 2002 Paul Winkeler

=cut
