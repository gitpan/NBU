#!/usr/local/bin/perl -w

use Getopt::Std;

use NBU;

my %opts;
getopts('ubdR', \%opts);

NBU->debug($opts{'d'});

my $m = NBU::Media->new($ARGV[0]);
my $n = 0;
foreach my $mpxList ($m->tableOfContents) {
  $n++;

  next if (!defined($mpxList));

  my $mpx = 0;
  foreach my $fragment (@$mpxList) {
    if (@$mpxList > 1) {
      printf("%3u.%02u:", $n, ++$mpx);
    }
    else {
      printf("%3u:", $n);
    }

    my $image = $fragment->image;
    print "Fragment ".$fragment->number." of ".$image->class->name.
	  ($opts{'b'} ? " (".$image->id.")" : "").
	  " written on ".$fragment->driveWrittenOn." from ".$image->client->name.": ";
    print $fragment->offset."/".$fragment->size.": ";
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
}
