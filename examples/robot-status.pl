#!/usr/local/bin/perl

use strict;

use Getopt::Std;
use Time::Local;

my %opts;
getopts('dtscv', \%opts);

if ($opts{'v'}) {
  $opts{'c'} = $opts{'t'} = $opts{'s'} = 1;
}


use NBU;
NBU->debug($opts{'d'});

NBU::StorageUnit->populate;

foreach my $stu (NBU::StorageUnit->list) {
  NBU::Drive->populate($stu->host);
}

for my $robot (NBU::Robot->farm) {
  next unless (defined($robot));
  print "Robot ".$robot->id;
  print " controlled from ".$robot->host->name if (defined($robot->host));
  print "\n";
  for my $drive (sort {$a->robotDriveIndex <=> $b->robotDriveIndex} $robot->drives) {
    print "  ".($drive->down ? "v" : "^");
    printf(" %-8s", $drive->name);
    if ($opts{'t'}) {
      if ($drive->busy) {
	print " (".$drive->mount->volume->id.")";
      }
      else {
	print " (      )";
      }
    }
    print " SN:".$drive->serialNumber if ($opts{'s'});
    print " Cleaned: ".substr(localtime($drive->lastCleaned), 4) if ($opts{'c'});
    print ": ".$drive->comment if ($opts{'v'});

    print "\n";
  }
}
