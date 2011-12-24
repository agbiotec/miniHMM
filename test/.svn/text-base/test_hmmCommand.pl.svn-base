#!/usr/local/bin/perl

## SGE Grid Job Submission:
##     qsub -P 04033 -e /tmp -o /tmp -t 1-10 /home/sguo/www/SorcererApprentice/test/test_hmmCommand.pl
## Grid Troubleshooting:
##     qlogin -l hostname=dell1955quadcore2 -l trouble

use strict;
use warnings;

use lib qw(/home/sguo/www/SorcererApprentice/cgi-bin/lib);
use Sorcerer::Apprentice::HmmCommand;
use YAML;
use DBI;

# create database connection
my $db = DBI->connect( "dbi:Sybase:server=SYBTIGR", "access", "access") or die DBI->errstr;

# get all HMMs in Genome Properties system
my @hmm;
$db->do("use common");
my $sth_hmm = $db->prepare("select distinct query from step_ev_link where method = 'HMM' ") or die $db->errstr;
$sth_hmm->execute();
while(my @qresults = $sth_hmm->fetchrow_array()) {
	push @hmm, $qresults[0];
}
$sth_hmm->finish;

my $DIR = "/home/sguo/www/SorcererApprentice/test";
my $taskid = $ENV{'SGE_TASK_ID'};
my $seed = $hmm[$taskid-1];

#my $seed = 'PF00346';

system("mkdir $DIR/$seed");
system("cp /usr/local/db/HMM_IND/$seed\.SEED $DIR/$seed/");

# get trusted and noise cutoff for an HMM
$db->do("use egad");
my $sth_cutoff = $db->prepare("select trusted_cutoff, noise_cutoff from hmm2 where hmm_acc = ? and is_current = 1") or die $db->errstr;
$sth_cutoff->execute($seed);
my @cutoff = $sth_cutoff->fetchrow_array();
$sth_cutoff->finish;

$db->disconnect;

my $cmd = Sorcerer::Apprentice::HmmCommand->new({
    'bin_dir' => '/home/sguo/www/SorcererApprentice/cgi-bin',
    'dir' => "$DIR/$seed",
    'seed_file' => "$seed\.SEED",
    'prefix' => "$seed",
    'trusted_cutoff' => $cutoff[0],
    'noise_cutoff' => $cutoff[1],
#   'seq_db' => '/usr/local/db/omnium/pub/OMNIOME.pep',
    'seq_db' => '/usr/local/db/panda/AllGroup/AllGroup.niaa',
    'model_type' => 'tiles',
    'model_length' => 100,
    'model_overlap' => 50,
    'gap_filter' => '25',
});
chdir $cmd->{dir};

$cmd->prepare;

my $result = $cmd->run;
# print "Done:", YAML::Dump( $result);

1;
