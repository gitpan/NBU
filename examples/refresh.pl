#!/usr/local/bin/perl -w

use strict;
use lib '/usr/local/lib/perl5';

use Getopt::Std;
use Date::Parse;


use NBU;

my %opts;
getopts('vftdw:c:s:', \%opts);

my $window = defined($opts{'w'}) ? $opts{'w'} : 10;
my $controlSize = defined($opts{'c'}) ? $opts{'c'} : 5 * 1024;
my $skipCount = defined($opts{'s'}) ? $opts{'s'} : 0;

#
# Activate internal debugging if -d was specified
NBU->debug($opts{'d'});

#
# The class representing the SAP backup we're interested in and a target date/time are
# all we need:
if (@ARGV != 2) {
  print STDERR "Usage: refresh.pl <SAP-INSTANCE> <time-of-split>\n";
  exit -1;
}

my $splitTime = str2time($ARGV[1]);
if (!defined($splitTime)) {
  print STDERR "refresh.pl: Could not parse split time: \"".$ARGV[1]."\"\n";
  exit -1;
}
print "Using split target of ".localtime($splitTime)."\n" if (!$opts{'t'});

#
# Create an NBU Class object corresponding to the class we're interested in
my $targetInstance = $ARGV[0];
my $targetClass = NBU::Class->byName("NBU".$targetInstance);
if (!defined($targetClass)) {
  print STDERR "refresh.pl: No such SAP-INSTANCE as \"".$ARGV[0]."\"\n";
  exit -1;
}
elsif ($targetClass->type !~ /SAP/) {
  print STDERR "refresh.pl: supplied class is not of type SAP\n";
  exit -1;
}

#
# Sort the images from this class in reverse chronological order (most
# recent first).
my @imageList = (sort { $b->ctime <=> $a->ctime } $targetClass->images);
print "Found ".@imageList." images for class ".$targetClass->name."\n" if ($opts{'v'});

#
# At this point there are two alternatives:
# Find the youngest backup that started before the split, or the youngest backup that
# finished before the split.  This script currently defaults to latter, somewhat safer technique
my $controlFileSet;
my $hit;
my @targets;
for my $i (@imageList) {

  if ($i->ctime > $splitTime) {
    print "Skipping ".$i->size."k image from ".localtime($i->ctime)." as it is not old enough\n" if ($opts{'v'});
    next;
  }

  if ($i->size < $controlSize) {
    print "".(defined($hit) ? "Ignoring" : "Skipping").
	  " image smaller than ${controlSize}k, guessing it only contains control files\n" if ($opts{'v'});
    $controlFileSet = $i if (!defined($hit));
    next;
  }

  if (!defined($hit)) {
    if (!defined($controlFileSet)) {
      print "Skipping ".$i->size."k image from ".localtime($i->ctime)." as it is still not old enough\n" if ($opts{'v'});
      next;
    }

    if ($skipCount == 0) {
      print "BINGO: Found image dated ".localtime($i->ctime)."\n" if (!$opts{'t'});

      $hit = $i;
      push @targets, $controlFileSet;
      push @targets, $hit;
    }
    else {
      $skipCount -= 1;
      print "Skipping allowed image dated ".localtime($i->ctime).", $skipCount left to go\n" if (!$opts{'t'});
    }
  }
  else {
    if (($hit->ctime - $i->ctime) < ($window * 60)) {
      print "Adding image dated ".localtime($i->ctime)." as it is within $window minutes\n" if ($opts{'v'});
      push @targets, $i;
    }
    else {
      last;
    }
  }
}

if (@targets == 0) {
  print STDERR "No images met the criteria:\n";
  print STDERR "  NetBackup class is ".$ARGV[0]."\n";
  print STDERR "  Control file image < ${controlSize}k\n";
  print STDERR "  Control file image older than ".localtime($splitTime)."\n";
  exit -1;
}

#
# With the main backup in hand, we now go hunting for the archive log images needed to make the
# restore whole.  The question becomes: Knowing when the backup started, do we know when it ended?
# As answer we use the ctime of the control file backup.
# Thus, we want all archive logs written since the backup started up to and at least one image past
# the time the control files were backed up:
my $windowEnd = $targets[0]->ctime;
my $windowStart = $targets[$#targets]->ctime;
my $targetHost = $hit->client;

@imageList = (sort { $a->ctime <=> $b->ctime} $targetHost->images);
my $priorSafety;
my $postSafety;

#
# In the interest of expediency we are only going to consider images less than 36 hours old
my $tooOld = $windowStart - (144 * 60 * 60);

my $logCount = 0;
my $logSpace = 0;

for my $i (@imageList) {
  next if ($i->class->type ne $targetClass->type);
  next if ($i->class->name !~ /archive/i);

  next if ($i->ctime < $tooOld);

  my $thisLogCount = 0;
  #
  # There are two types of archive log images produced by SAP's brarchive; one contains bonafide
  # archive log files, the other contains some control file data.  We are only interested in the
  # former.
  my $containsLogs = 0;
  for my $f ($i->fileList) {
    if ($f =~ /$targetInstance.*\.dbf$/) {
      $containsLogs += 1;
      $thisLogCount += 1;
    }
  }
  next if (!$containsLogs);

  if ($i->ctime < $windowStart) {
    $priorSafety = $i;
    next;
  }

  if ($i->ctime < $splitTime) {
    push @targets, $i;
    $logCount += $thisLogCount;
    $logSpace += $i->size;
  }
  else {
    last if (defined($postSafety));
    $postSafety = $i;
  }
}

if (!defined($postSafety) || !defined($priorSafety)) {
  print STDERR "refresh.pl: No extra safety archive log backup prior to ".localtime($windowStart)." found\n"
    if (!defined($priorSafety));
  print STDERR "refresh.pl: No extra safety archive log backup after ".localtime($splitTime)." found\n"
    if (!defined($postSafety));
  exit -1 unless ($opts{'f'});
}
push @targets, $priorSafety if (defined($priorSafety));
push @targets, $postSafety if (defined($postSafety));

my %needed;
print "Backup images needed for this split are:\n" if (!$opts{'t'});
for my $i (sort { $a->ctime <=> $b->ctime} @targets) {
  print "  ".localtime($i->ctime)." ".$i->class->name."\n" if (!$opts{'t'});
  for my $f ($i->fragments) {
    if (!$opts{'t'}) {
      print "    Used volume ".$f->volume->id."\n";
    }
    $needed{$f->volume->id} += 1;
  }
  next if ($i->class->name !~ /archive/i);
  if (!$opts{'t'}) {
    print "    Archive log files:\n";
    for my $f (sort $i->fileList) {
      print "        ".$f."\n";
    }
  }
}

print "Volumes needed for this split are:\n" if (!$opts{'t'});
for my $id (sort (keys %needed)) {
  my $m = NBU::Media->byID($id);
  print "  $id";
  print " (".$m->group.")" if (!$opts{'t'} && defined($m->group));
  print "\n";
}

$logSpace = sprintf("%.2f", $logSpace / 1024 / 1024);
if (!$opts{'t'}) {
  print "The $logCount archive log files will need ${logSpace}Gb\n";
}
