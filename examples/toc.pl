#!/usr/local/bin/perl

use Getopt::Std;

use NBU;

my %opts;
getopts('dR', \%opts);

NBU->debug($opts{'d'});

my $m = NBU::Media->new($ARGV[0]);
my $n = 1;
foreach my $fragment ($m->tableOfContents) {
#  print $fragment->offset."/".$fragment->size.": ";
  printf("%3u:", $n);

  my $image = $fragment->image;
  print "Fragment ".$fragment->number." of ".$image->class->name." from ".$image->client->name.": ";
  print "Expires ".substr(localtime($image->expires), 4)."\n";
  if ($opts{'R'}) {
    for my $f ($image->fileList) {
      print "      $f\n";
    }
  }

  $n++;
}
