#!/usr/local/bin/perl -w

use strict;
use lib '/usr/local/lib/perl5';

use Getopt::Std;
use Time::Local;
use Date::Parse;

my %opts;
getopts('rlda:p:M:', \%opts);

use NBU;
NBU->debug($opts{'d'});

my %mediaFailureCodes = (
  83 => 1,
  84 => 1,
  85 => 1,
  86 => 1,
);

my $master;
if ($opts{'M'}) {
  $master = NBU::Host->new($opts{'M'});
}
else {
  my @masters = NBU->masters;  $master = $masters[0];
}

sub dispInterval {
  my $i = shift;

  return "--:--:--" if (!defined($i));

  my $seconds = $i % 60;  $i = int($i / 60);
  my $minutes = $i % 60;
  my $hours = int($i / 60);

  my $fmt = sprintf("%02d", $seconds);
  $fmt = sprintf("%02d:", $minutes).$fmt;
  $fmt = sprintf("%02d:", $hours).$fmt;
  return $fmt;
}
my $period = 1;
if ($opts{'p'}) {
  $period = $opts{'p'};
}

my $asOf = NBU::Job->loadJobs($master, $opts{'r'}, $opts{'l'});
my $mm;  my $dd;  my $yyyy;
  my ($s, $m, $h, $mday, $mon, $year, $wday, $yday, $isdst) = localtime($asOf);
  $year += 1900;
  $mm = $mon + 1;
  $dd = $mday;
  $yyyy = $year;

my $since;
if ($opts{'a'}) {
  $asOf = str2time($opts{'a'});
}
$since = $asOf - ($period *  (24 * 60 * 60));

sub sortByDensity {
  my $result = 0;

  $result = ($a->storageUnit->density cmp $b->storageUnit->density)
    if (defined($a->storageUnit) && defined($b->storageUnit));
  $result = ($b->id <=> $a->id) if ($result == 0);
  return $result;
}

my $successes = 0;
my $failures = 0;
my %failureCodes;
my %mediaFailures;
my %activeClients;
my $MBytes = 0;
my $seconds = 0;

my $lastDensity = undef;

my @jl = (sort sortByDensity NBU::Job->list);
for my $job (@jl) {
  next if ($job->active || $job->queued);

  next if ($job->stop < $since);
  if ($job->start < $since) {
    next unless ($job->stop <= $asOf);
  }
  next if ($job->start > $asOf);
  next if ($job->stop > $asOf);

  next if (!defined($job->storageUnit));

  if (defined($lastDensity) && ($job->storageUnit->density ne $lastDensity)) {
    report("Jobs in the 24hrs since ".localtime($since)." using $lastDensity tapes");

    $successes = 0;
    $failures = 0;
    %failureCodes = ();
    %mediaFailures = ();
    %activeClients = ();
    $MBytes = 0;
    $seconds = 0;
  }

  $lastDensity = $job->storageUnit->density;

  if ($job->state eq 'done') {
    $activeClients{$job->client->name} += 1;
    if ($job->success) {
      if (defined($job->dataWritten)) {
	$MBytes += $job->dataWritten / 1024;
	$seconds += $job->elapsedTime;
      }
      $successes += 1;
    }
    else {
      my $fc = $job->status;
      if (exists($mediaFailureCodes{$fc})) {
	my $ev;
	if (!defined($job->volume)) {
	  # This happens when running NBU 4.5-1 due to broken bpdbjobs data stream
	  $ev = sprintf("R%05u", int(rand(99999)));
	}
	else {
	  $ev = $job->volume->id;
	}
	if (exists($mediaFailures{$ev})) {
	}
	$mediaFailures{$ev} += 1;
      }
      $failureCodes{$fc} += 1;
      $failures += 1;
    }
  }
}

report("Jobs in the 24hrs since ".localtime($since)." using $lastDensity tapes");

sub report {
  my $title = shift;

  my $clientCount = (keys %activeClients);
  my $jobCount = $successes + $failures;
  my $GBytes = sprintf("%.2f", $MBytes / 1024);
  my $elapsedTime = dispInterval($seconds);
  my $masterName = $master->name;
  print <<EOT;
\n\t\t$title
The master scheduler on $masterName ran $jobCount jobs from $clientCount unique clients
$successes were successful:
  writing ${GBytes}Gb to tape over $elapsedTime
$failures terminated prematurely:
EOT
  for my $fc (sort (keys %failureCodes)) {
    print "  $fc: ".$failureCodes{$fc};
    if (exists($mediaFailureCodes{$fc})) {
      print ", caused by ".(keys %mediaFailures)." media failures";
    }
    print "\n";
  }
}
