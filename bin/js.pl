#!/usr/local/bin/perl -w

use strict;
use lib '/usr/local/lib/perl5';

use Getopt::Std;
use Time::Local;

my %opts;
getopts('seflvaAdrt:p:c:o:C:O:M:', \%opts);

use NBU;
NBU->debug($opts{'d'});

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


sub sortByClient {
  my $result;

  $result = ($a->client->name cmp $b->client->name);
  $result = ($b->id <=> $a->id) if ($result == 0);
  return $result;
}

sub sortByID {
  my $result;

  $result = ($b->id <=> $a->id);
  return $result;
}
$opts{'o'} = 'id' if (!defined($opts{'o'}));
my $sortOrder = ($opts{'o'} eq 'client') ? \&sortByClient : \&sortByID;


my %stateCodes = (
  'active' => 'A',
  'done' => 'D',
  'queued' => 'Q',
  're-queued' => 'R',
);

my $totalWritten = 0;

my $asOf = NBU::Job->loadJobs($master, $opts{'r'}, $opts{'l'});
my $mm;  my $dd;  my $yyyy;
  my ($s, $m, $h, $mday, $mon, $year, $wday, $yday, $isdst) = localtime($asOf);
  $year += 1900;
  $mm = $mon + 1;
  $dd = $mday;
  $yyyy = $year;
#my $since = timelocal(0, 0, 0, $dd, $mm-1, $yyyy);
my $since = $asOf - ($period *  (24 * 60 * 60));

my $hdr = sprintf("%15s", "CLIENT    ");
if ($opts{'v'}) {
  $hdr .= " ".sprintf("%-40s", "             CLASS/SCHEDULE");
}
else {
  $hdr .= " ".sprintf("%-23s", "         CLASS");
}
$hdr .= " ".sprintf("%7s", " JOBID ");
$hdr .= " ".sprintf("%8s", "  START ");
$hdr .= " ".sprintf("%1s", "R");
$hdr .= " ".sprintf("%-8s", "  STU");
$hdr .= " ".sprintf("%3s", "OP");
$hdr .= " ".sprintf("%-8s", "  TIME");
$hdr .= " ".sprintf("%-7s", "  FILES");
$hdr .= " ".sprintf("%-10s", "   KBYTES");
$hdr .= " ".sprintf("%4s", "SPD");
print "$hdr\n";

NBU::Class->populate if ($opts{'t'});

my $jobCount = 0;
my %activeClients;
my $MBytes = 0;

my @jl = NBU::Job->list;
for my $job (sort $sortOrder (@jl)) {
  next if (!$opts{'a'} && !$job->active);
  next if (!$opts{'A'} && ($job->start < $since));

  # Skip jobs of the wrong ilk
  my $fits = !($opts{'t'} || $opts{'c'} || $opts{'C'} || $opts{'O'});
  if (!$fits) {
    $fits ||= (defined($job->class) && defined($job->class->type) && ($job->class->type =~ $opts{'t'})) if (!$fits && $opts{'t'});
    $fits ||= (defined($job->class) && ($job->class->name =~ $opts{'c'})) if (!$fits && $opts{'c'});
    $fits ||= (defined($job->client) && ($job->client->name =~ $opts{'C'})) if (!$fits && $opts{'C'});
    $fits ||= (defined($job->client) && defined($job->client->os) && ($job->client->os =~ $opts{'O'})) if (!$fits && $opts{'O'});
  }
  next if (!$fits);

  {
    $jobCount += 1;

    my $who = sprintf("%15s", $job->client->name);
    $activeClients{$who} += 1;

    my $classID = $job->class->name;
    my $classIDlength = 23;
    if ($opts{'v'}) {
      $classID .= "/".$job->schedule->name;
      $classIDlength = 40;
    }
    $classID = sprintf("%-".$classIDlength."s", $classID);

    my $jid = sprintf("%7u", $job->id);
    my $state = $stateCodes{$job->state};


    my $startTime = ((time - $job->start) < (24 * 60 * 60)) ?
	  substr(localtime($job->start), 11, 8) :
	  " ".substr(localtime($job->start), 4, 6)." ";

    print "$who $classID $jid $startTime $state";

    if (my $stu = $job->storageUnit) {
      printf(" %8s ", $stu->label);
    }
    else {
      printf(" %8s ", "");
    }

    if ($state eq "D") {
      printf(" %3d ", $job->status);
      if ($job->status == 0) {
	if (defined($job->dataWritten)) {
	  $totalWritten += ($job->dataWritten / 1024);
	  $MBytes += $job->dataWritten / 1024;
	}
      }
      print dispInterval($job->elapsedTime);
    }
    elsif ($state eq "A") {
      my $op = $job->operation;
      print " $op ".dispInterval($job->busy);
    }

    if ($state ne "Q") {
      if (defined($job->filesWritten)) {
        printf(" %7d", $job->filesWritten);
      }
      else {
	printf(" 7%s", "");
      }
      if (defined($job->dataWritten)) {
        printf(" %10d", $job->dataWritten);
      }
      else {
	printf(" 10%s", "");
      }
      printf(" %.2f", ($job->dataWritten / $job->elapsedTime / 1024))
	if (($job->elapsedTime > 0) && defined($job->dataWritten));

      if (($state eq "A") && ($job->volume)) {
	print " ".$job->volume->id;
      }
    }
    print "\n";
    if ($opts{'f'}) {
      for my $f ($job->files) {
	next if ($f =~ /NEW_STREAM/);
	print "  $f\n";
      }
    }
    if ($opts{'e'}) {
      my @el = $job->errors;
      for my $e (@el) {
	my $tm = $$e{tod};
	my $msg = $$e{message};

	next if ($msg =~ /backup of client [\S]+ exited with status 1 /);

	my $windowsComment = $1 if ($msg =~ s/(\(WIN32.*\))//);

	printf("%15s - %s\n", "  +".dispInterval($tm-$job->start), $msg);
	if (defined($windowsComment) && ($windowsComment !~ /WIN32 32:/)) {
	  printf("%15s   %s\n", "", $windowsComment);
	}
      }
    }
  }
}
if ($opts{'s'}) {
  my $clientCount = (keys %activeClients) + 1;
  my $GBytes = sprintf("%.2f", $MBytes / 1024);
  print <<EOT;
$jobCount jobs from $clientCount clients wrote ${GBytes}Gb to tape
EOT
}
