#!/usr/local/bin/perl

use Getopt::Std;

use NBU;

my %opts;
getopts('dR', \%opts);

NBU->debug($opts{'d'});

my $m = NBU::Media->new($ARGV[0]);
my $n = 0;
foreach my $fragment ($m->tableOfContents) {

  $n++;

  next if (!defined($fragment));
#  print $fragment->offset."/".$fragment->size.": ";
  printf("%3u:", $n);

  my $image = $fragment->image;
  print "Fragment ".$fragment->number." of ".$image->class->name." from ".$image->client->name.": ";
  print "Created ".substr(localtime($image->ctime), 4)."; ";
  print "Expires ".substr(localtime($image->expires), 4)."\n";
  if ($opts{'R'}) {
    for my $f (sort ($image->fileList)) {
      print "      $f\n";
    }
  }
}
