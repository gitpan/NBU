use ExtUtils::MakeMaker;


my %args = (
            'NAME'	      => 'NBU',
            'VERSION'         => '0.90',

            'EXE_FILES'       => [
               'bin/coverage.pl',
               'bin/nbutop.pl',
               'bin/history.pl',
               'bin/robot-snapshot.pl',
               'bin/drive-watch.pl',
               'bin/js.pl',
               'bin/volume-status.pl',
               'bin/volume-list.pl',
               'bin/backup-stats.pl',
               'bin/scratch.pl',
               'bin/refresh.pl',
               'bin/toc.pl',
               'bin/class-list.pl',
	       'bin/vu.pl',
	       'bin/sla.pl',
            ],
            
            dist              => {
              DIST_DEFAULT => 'all tardist',
              COMPRESS     => 'gzip -vf',
              SUFFIX       => '.gz',
            },
            
            clean             => {
              FILES        => '*~',
            },
            
            realclean         => {
              FILES        => '*~ examples/*~ bin/*~ lib/*~ lib/NBU/*~',
            },

            );

WriteMakefile(%args);

package MY;

sub libscan {
  my $self = shift;
  my $path = shift;
  ($path =~ / \bCVS\b | \~$ /x) ? undef : $path;
}

1;
