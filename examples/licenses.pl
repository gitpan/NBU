#!/usr/local/bin/perl

use strict;
use Getopt::Std;

use NBU;

my %opts;
getopts('csd', \%opts);
$opts{'c'} = 1;

NBU::->debug($opts{'d'});

NBU::License->populate;

my @ll = NBU::License->list();

foreach my $l (@ll) {
  print "License key ".$l->key."\n";
    print "  Product ".$l->productDescription($l->product)."\n";
    print "  Server Tier ".$l->serverTier."\n";
    my @fcl = $l->features;
    foreach my $fc (@fcl) {
      print "    Feature ".$l->featureDescription($fc)."\n";
    }
}
