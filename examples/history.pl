#!/usr/local/bin/perl -w

use Getopt::Std;

use NBU;

my %opts;
getopts('dfRc:', \%opts);

NBU->debug($opts{'d'});

my $h = NBU::Host->new($ARGV[0]);
my $n = 0;
foreach my $image ($h->images) {
  $n++;

  if ($opts{'c'}) {
    my $classPattern = $opts{'c'};
    next unless ($image->class->name =~ /$classPattern/);
  }

  printf("%4u:", $n);

  print substr(localtime($image->ctime), 4)." of ".$image->class->name."/".$image->schedule->name;
  print " Expires ".substr(localtime($image->expires), 4)."\n";
  if ($opts{'f'}) {
    for my $f ($image->fragments) {
      print "     ".$f->number.": File ".$f->fileNumber." on ".$f->volume->id." drive ".$f->driveWrittenOn."\n";
    }
  }
  if ($opts{'R'}) {
    for my $f ($image->fileList) {
      print "      $f\n";
    }
  }
}
