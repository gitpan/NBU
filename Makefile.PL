use ExtUtils::MakeMaker;


my %args = (
            'NAME'	      => 'NBU',
            'VERSION'         => '0.72',
            
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
