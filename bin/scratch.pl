#!/usr/local/bin/perl -w

use strict;
use lib '/usr/local/lib/perl5';

use XML::XPath;
use XML::XPath::XMLParser;

use Getopt::Std;

my %opts;
getopts('nd', \%opts);

use NBU;
NBU->debug($opts{'d'});

my $file = "/usr/local/etc/robot-conf.xml";
if (defined($opts{'f'})) {
  $file = $opts{'f'};
  die "No such configuration file: $file\n" if (! -f $file);
}

my $xp;
if (-f $file) {
  $xp = XML::XPath->new(filename => $file);
  die "robot-snapshot.pl: Could not parse XML configuration file $file\n" unless (defined($xp));
}

#
# Rather than XPath-ing on every volume, we build a little hash of the density/pool
# combinations we're allowed to scratch.
my %itchy;
my $nodeset = $xp->find('//itchy/pool');
foreach my $pool ($nodeset->get_nodelist) {
  my $poolName = $pool->getAttribute('id');
  my $nodeset = $pool->find('density');
  foreach my $density ($nodeset->get_nodelist) {
    my $densityCode = $density->getAttribute('code');
    my $key = $densityCode.":".$poolName;
    $itchy{$key} += 1;
  }
}

my $scratch = NBU::Pool->scratch;
die "No scratch pool defined\n" unless (defined($scratch));

NBU::Media->populate(1);
my $tc = 0;
my $sc = 0;
for my $m (NBU::Media->list) {
  next if ($m->cleaningTape);
  $tc += 1;
  next if ($m->allocated);

  next if (defined($m->pool) && !exists($itchy{$m->type.":".$m->pool->name}));

  $sc += 1;
  if ($opts{'n'}) {
    print "Could scratch ".$m->id."\n";
  }
  else {
    $m->pool($scratch);
  }
}
printf("Scratched $sc volumes (%.2f%%)\n", ($sc * 100) / $tc);
