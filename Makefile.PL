use ExtUtils::MakeMaker;


my %args = (
            'NAME'	      => 'NBU',
            'VERSION'         => '0.74',

            'EXE_FILES'       => [
               'bin/nbutop.pl',
               'bin/history.pl',
               'bin/robot-snapshot.pl',
               'bin/drive-watch.pl',
            ],
            
            dist              => {
              DIST_DEFAULT => 'all tardist',
              COMPRESS     => 'compress',
              SUFFIX       => '.Z',
#              COMPRESS     => 'gzip -vf',
#              SUFFIX       => '.gz',
            },
            
            clean             => {
              FILES        => '*~',
            },
            
            realclean         => {
              FILES        => '*~',
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
