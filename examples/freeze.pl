#!/usr/local/bin/perl

use strict;

use NBU;

NBU::Media->populate(1);

while (<STDIN>) {
  chop;
  if (my $m = NBU::Media->byID($_)) {
    $m->freeze;
  }
}
