package TIGR::HTCUtils;

use strict;
use Net::Domain qw(hostname hostfqdn hostdomain);
use Date::Manip qw(UnixDate);

my $tr_logfile = "/usr/local/scratch/$ENV{USER}/test_track.log";
open(LOG, '>>', $tr_logfile) or die "Couldn't open file $tr_logfile"; 

# Maximum number of perl processes that exist before launching 
# a round of tests for htcservice
my $PERL_PROCESS="/usr/local/bin/perl";
my $USER=(getpwuid($<))[0];
my $HOST=hostfqdn();
my $TIME=undef;

sub get_perl_process_count {
	# Get the number active perl processes by $USER 
	print LOG "Counting active perl processes for : $USER \n";
	my $count=`ps -aef | grep "${USER}" | grep -c "$PERL_PROCESS"`;
	print LOG "Active perl processes are : $count \n";

	return $count;
}

sub log_test_start {
    my ($self, $testname) = @_; 
    $TIME=localtime(); 
    print LOG "$TIME : $HOST: Test $testname STARTED\n";
}


sub log_test_finish {
    my ($self, $testname) = @_; 
    $TIME=localtime(); 
    print LOG "$TIME : $HOST: Test $testname FINISHED\n";
}

sub log_test_fail {
    my ($self, $testname) = @_; 
    $TIME=localtime(); 
    print LOG "$TIME : $HOST: Test $testname FAILED\n";
}

sub log_test_skip {
    my ($self, $testname) = @_; 
    $TIME=localtime(); 
    print LOG "$TIME : $HOST: Test $testname SKIPPED\n";
}


1;
