#!/usr/local/bin/perl

eval 'exec /usr/local/bin/perl  -S $0 ${1+"$@"}'
    if 0; # not running under some shell

# $Id: hmmsearch_wrapper,v 1.7 2003/10/30 16:18:31 vfelix Exp $

$|++;
use strict;
use File::Basename;

# This wrapper is called with 3 args: filelist process blocksize sequence
#                                         0       1        2        3
#
# Where filelist(0) is the list of HMM profiles. One profile (HMM) per line,
# process(1) is the number of the job (determined dividing # of profiles by
# blocksize), blocksize(2) is the user specified number of profiles to examine
# on each machine, and sequence(3) is the file containing the sequence
# information required by hmmsearch.

BEGIN: {
    $ENV{HMM_SCRIPTS} ||= "/usr/local/devel/ANNOTATION/hmm/bin";
}

&htab if ($ARGV[0] eq "htab");

my $filelist = $ARGV[0];
my $process = int($ARGV[1]);
my $blocksize = $ARGV[2];
my $sequence = $ARGV[3];

my $hmmsearch_exe = '/usr/local/bin/hmmsearch';
my $debug = 1;

if ($debug) {
    warn <<"    _EOF";
    Filelist = $filelist
    process = $process
    Blocksize = $blocksize
    Sequence = $sequence
    _EOF
}

# Do some validation/protection.
$blocksize =~ tr/0-9//cd;
$process =~ tr/0-9//cd;
$blocksize = int($blocksize);
$process = int($process) - 1; # process id is 1-based, we need 0-based for offset calculation

if ($blocksize <= 0) {
   die "Blocksize must be a positive integer, stopped";
}

if (!-f $sequence) {
   die "\"$sequence\" does not exist or is not a plain file, stopped";
} elsif (!-r $sequence) {
   die "\"$sequence\" is not readable, stopped";
} elsif (-z $sequence) {
   die "\"$sequence\" has zero size, stopped";
} elsif (!-T $sequence) {
   die "\"$sequence\" is not a text file, stopped";
}


open (FILE, "<", $filelist) or die "Cannot open $filelist for read, stopped";
my @file_list = <FILE>;   # Each line (containing a path) becomes an element;
close FILE or die "Cannot close the $filelist filehandle, stopped";

my $offset = int($process * $blocksize);
my $length = $blocksize;
my @files_to_process = splice(@file_list, $offset, $length);
map (chomp, @files_to_process);  # Strip off the newlines.

warn ("Number of files to process: ", scalar(@files_to_process), ".\n")
    if $debug;

my @hitsfiles;
my $error_count = 0;
foreach my $profile (@files_to_process) {
    my $hits = basename($profile) . ".hits";
    if ($debug) {
        warn "COMMAND: $hmmsearch_exe $profile $sequence\n";
    } else {
        my @command = "$hmmsearch_exe $profile $sequence > $hits";
        my $return = system(@command);
        if ($return != 0) {
            warn "Command failed: @command\nReason: $?";
            $error_count++;
        }
    }
}

# The exit code is the number of failures.
exit $error_count;

####################################################

# This subroutine is provided solely for producing the htab
# results file, after all the hits files are complete. In other words,
# this processing requires a separate condor job to run on a single
# machine. With the HTC server, this post-processing is done through
# a separate stage from the stage that produced the hits files.
sub htab {
    $ENV{SYBASE} ||= "/usr/local/packages/sybase";
    my $htab_exe = 'HMM_SCRIPTS=/usr/local/devel/ANNOTATION/hmm/bin /usr/local/devel/ANNOTATION/hmm/bin/htab.pl';
    my @hits_files = glob("*.hits");

    open HTAB, "| xargs cat | $htab_exe"
             or die "Tried to htab. Could not fork: $!";
    local $SIG{PIPE} = sub { die "HTAB pipe broke" };

    print HTAB "@hits_files";
 
    close HTAB or die "Bad htab process: $! $?";
    exit;
}
