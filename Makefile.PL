use ExtUtils::MakeMaker;


my %args = (
            'NAME'	      => 'NBU',
            'VERSION'         => '0.91',
	    'PREREQ_PM' => { 
	      Getopt::Std           => undef,
	      IPC::Open2            => undef,
	      Date::Parse           => undef,
	      Time::Local           => undef,
	      Curses                => undef,
	      XML::XPath::XMLParser => undef,
	      XML::XPath            => undef,
	    },

            'EXE_FILES'       => [
               'bin/coverage.pl',
               'bin/nbutop.pl',
               'bin/history.pl',
               'bin/robot-snapshot.pl',
               'bin/drive-watch.pl',
               'bin/js.pl',
               'bin/volume-status.pl',
               'bin/volume-list.pl',
               'bin/scratch.pl',
               'bin/refresh.pl',
               'bin/toc.pl',
               'bin/policy-list.pl',
               'bin/policy-space.pl',
	       'bin/vu.pl',
	       'bin/sla.pl',
	       'bin/volume-use.pl',
	       'bin/robot-status.pl',
	       'bin/client-list.pl',
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
