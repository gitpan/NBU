#!/usr/local/bin/perl -w

use NBU;
#NBU->debug(1);

NBU::Image->populate;

my @l = NBU::Image->list;
print "There are $#l images\n";

my %retentionTotal;
my $total = 0;
for my $image (@l) {
  next if (!defined($image->size));

  my $size = $image->size / 1024;
  $retentionTotal{$image->retention->level} += $size;
  $total += $size;
}

for my $l (sort (keys %retentionTotal)) {
  my $rlt = sprintf("%10.2f", $retentionTotal{$l}/1024);
  my $r = NBU::Retention->byLevel($l);
  print $rlt."Gb at ".$r->description."\n";
}

$total = sprintf("%.2f", $total/1024);
print "Total size is ${total}Gb\n";
