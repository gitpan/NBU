#!/usr/local/bin/perl

use strict;

use Getopt::Std;

my %opts;
getopts('uc', \%opts);

use NBU;
NBU::Class->populate(1);
NBU::Host->populate(1);

foreach my $client (sort {$a->name cmp $b->name} (NBU::Host->hostList)) {
  my $cn = $client->name;

  print "$cn:";
  my %mountPointList = $client->coverage;
  foreach my $mp (sort (keys %mountPointList)) {
    my $clR = $mountPointList{$mp};
    my $mpStatus = "\t$mp:";
    my $disposition;
    my $covered;
    if ($clR) {
      foreach my $class (@$clR) {
	my $cn = $class->name;
	if ($class->active) {
	  $mpStatus .= " $cn" if ($opts{'c'} || !$opts{'u'});
	  $covered += 1;
	}
	else {
	  $mpStatus .= " ($cn)" if ($opts{'u'} || !$opts{'c'});
	}
      }
    }
    else {
      $mpStatus .= " not covered";
    }
    if ((!$opts{'u'} && !$opts{'c'}) ||
	($opts{'u'} && !$covered) ||
	($opts{'c'} && $covered)) {
      print "\n$mpStatus";
    }
  }

  if ($opts{'c'} || !$opts{'u'}) {
    my $sep = "\n\tadditional active classes are: ";
    foreach my $class ($client->classList) {
      if ($class->active && !$class->providesCoverage) {
	print $sep.$class->name;
	$sep = " ";
      }
    }
  }

  if ($opts{'u'} || !$opts{'c'}) {
    my $sep = "\n\tadditional inactive classes are: ";
    foreach my $class ($client->classList) {
      if (!$class->active && !$class->providesCoverage) {
	print $sep."(".$class->name.")";
	$sep = " ";
      }
    }
  }
  print "\n";
}
