#!/usr/local/bin/perl -w

use strict;

use Getopt::Std;
use Time::Local;

my %opts;
getopts('ltsaAdr', \%opts);

use NBU;
NBU->debug($opts{'d'});

sub dispInterval {
  my $i = shift;

  my $seconds = $i % 60;  $i = int($i / 60);
  my $minutes = $i % 60;
  my $hours = int($i / 60);

  my $fmt = sprintf("%02d", $seconds);
  $fmt = sprintf("%02d:", $minutes).$fmt;
  $fmt = sprintf("%02d:", $hours).$fmt;
  return $fmt;
}

sub sortOrder {
  my $result;

  $result = ($b->id <=> $a->id);
  return $result;
}

my %stateCodes = (
  'active' => 'A',
  'done' => 'D',
  'queued' => 'Q',
  're-queued' => 'R',
);

my $totalWritten = 0;

my $asOf = NBU::Job->loadJobs($opts{'r'}, $opts{'l'});
my $mm;  my $dd;  my $yyyy;
  my ($s, $m, $h, $mday, $mon, $year, $wday, $yday, $isdst) = localtime($asOf);
  $year += 1900;
  $mm = $mon + 1;
  $dd = $mday;
  $yyyy = $year;
my $since = timelocal(0, 0, 0, $dd, $mm-1, $yyyy);

my @jl = NBU::Job->list;
for my $job (sort sortOrder (@jl)) {
  if (!$opts{'a'}) {
    next unless ($job->active);
  }
  else {
    next if (!$opts{'A'} && ($job->start < $since));
  }

  {
    my $who = sprintf("%15s", $job->client->name);

    my $classID = $job->class->name;
    my $classIDlength = 23;
    if ($opts{'s'}) {
      $classID .= "/".$job->schedule->name;
      $classIDlength = 40;
    }
    $classID = sprintf("%-".$classIDlength."s", $classID);

    my $jid = sprintf("%7u", $job->id);
    my $state = $stateCodes{$job->state};


    my $startTime = ((time - $job->start) < (24 * 60 * 60)) ?
	  substr(localtime($job->start), 11, 8) :
	  " ".substr(localtime($job->start), 4, 6)." ";

    print "$who $classID $jid $startTime $state ";

    if (my $stu = $job->storageUnit) {
      printf(" %7s ", $stu->label);
    }
    else {
      printf(" %7s ", "");
    }

    if ($state eq "D") {
      printf(" %3d ", $job->status);
      if ($job->status == 0) {
	$totalWritten += ($job->dataWritten / 1024);
      }
      print dispInterval($job->elapsedTime);
    }
    elsif ($state eq "A") {
      my $op = $job->operation;
      print " $op ".dispInterval($job->busy);
    }

    printf(" %7d", $job->filesWritten);
    printf(" %10d", $job->dataWritten);
    printf(" %.2f", ($job->dataWritten / $job->elapsedTime / 1024))
      if ($job->elapsedTime);

    if (($state eq "A") && ($job->volume)) {
      print " ".$job->volume->id;
    }
    print "\n";
  }
}

if ($opts{'t'}) {
  printf("Total volume written: %.2f\n", $totalWritten);
}
