#!/usr/local/bin/perl

use strict;

use Getopt::Std;
use Time::Local;

my %opts;
getopts('d', \%opts);


use NBU;
NBU->debug($opts{'d'});

NBU::StorageUnit->populate;

foreach my $stu (NBU::StorageUnit->list) {
  print $stu->label." is of type ".$stu->type."\n";
  print " ".$stu->driveCount." ".$stu->density." drives are controlled through ".$stu->robot->type." robot ".$stu->robot->id."\n";
}
