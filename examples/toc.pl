#!/usr/local/bin/perl -w

use Getopt::Std;

use NBU;

my %opts;
getopts('ubdR', \%opts);

NBU->debug($opts{'d'});

my $m = NBU::Media->new($ARGV[0]);
my $n = 0;
foreach my $fragment ($m->tableOfContents) {

  $n++;

  next if (!defined($fragment));
#  print $fragment->offset."/".$fragment->size.": ";
  printf("%3u:", $n);

  my $image = $fragment->image;
  print "Fragment ".$fragment->number." of ".$image->class->name.
	($opts{'b'} ? " (".$image->id.")" : "").
	" written on ".$fragment->driveWrittenOn." from ".$image->client->name.": ";
  print "Created ".substr(localtime($image->ctime), 4)."; ";
  print "Expires ".substr(localtime($image->expires), 4)."\n";
  if ($opts{'R'}) {
    my @list = $image->fileList;
    @list = (sort @list) unless ($opts{'U'});
    for my $f (@list) {
      print "      $f\n";
    }
  }
}
