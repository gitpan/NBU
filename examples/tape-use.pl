#!/usr/local/bin/perl

use strict;

use Getopt::Std;
use Time::Local;
use NBU;

my %opts;
getopts('hda:p:', \%opts);

NBU->debug($opts{'d'});

my $period = 1;
my ($mm, $dd, $yyyy);
if (!$opts{'a'}) {
  my ($s, $m, $h, $mday, $mon, $year, $wday, $yday, $isdst) = localtime();
  $year += 1900;
  $mm = $mon + 1;
  $dd = $mday;
  $yyyy = $year;

}
else {
  $opts{'a'} =~ /^([\d]{4})([\d]{2})([\d]{2})$/;
  $mm = $2;
  $dd = $3;
  $yyyy = $1;

  if ($opts{'p'}) {
    $period = $opts{'p'};
  }
}
my $midnightStart = timelocal(0, 0, 0, $dd, $mm-1, $yyyy);
my $midnightEnd = $midnightStart + (24 * 60 * 60 * $period);

NBU::Media->populate(1);

my %usedCount;
foreach my $volume (NBU::Media->listVolumes) {
  my $dt = $volume->lastWritten;
  if (($dt >= $midnightStart) && ($dt < $midnightEnd)) {
    if ($volume->full) {
#      print "Filled ".$volume->id." at ".localtime($dt)."\n";
      my ($s, $m, $h, $mday, $mon, $year, $wday, $yday, $isdst) = localtime($dt);
      $year += 1900;
      $mm = $mon + 1;
      $dd = $mday;
      $yyyy = $year;
      my $key = $volume->pool->name;
      $key .= ":".sprintf("%04u%02u%02d", $year, $mm, $dd);
      $key .= ":".$volume->mmdbHost->name if ($opts{'h'});;
      $usedCount{$key} += 1;
      
    }
  }
}

foreach my $k (sort (keys %usedCount)) {
  
  my ($pool, $dt, $hostName) = split(':', $k);
  my $c = $usedCount{$k};
  print $hostName." " if (defined($hostName));
  print "filled $c $pool volumes on ".$dt."\n";
}
