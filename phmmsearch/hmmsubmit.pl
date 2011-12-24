#!/usr/local/bin/perl
use strict;
use warnings;
use TIGR::HTC::Request;

sub hmm_files_from_dir {
    my $dir = shift;
    my @files = glob("$dir/*.HMM");
    return @files;
}

my $hmm_dir = "/usr/local/scratch/s_apprentice/test_hmm";
my $out_dir = $hmm_dir;
my $db = "/usr/local/db/panda/AllGroup/AllGroup.niaa";
my $group = "mini_hmm";
my $opsys = "Linux";
my $user = 'rrichter';

my @hmms = hmm_files_from_dir($hmm_dir);

my $hmm_cmd = "/home/rrichter/bin/echo.pl";

warn "Preparing job\n";
my $req = TIGR::HTC::Request->new(group=>$group, opsys=>$opsys, user=>$user);
$req->command($hmm_cmd);
$req->initialdir($out_dir);
$req->add_param({key=>'-d', value=>$db,type=>'PARAM'});
$req->add_param({key=>'-h', value=>\@hmms,type=>'ARRAY'});
$req->times(scalar @hmms);
$req->output("$out_dir/stdout.\$(Index).txt");
$req->log_location("$out_dir/output.\$(Index).log");
$req->error("$out_dir/stderr.\$(Index).txt");

# $req->simulate(1);
print $req->to_xml();
warn "Submitting job\n";
my $id;
eval {
    $id = $req->submit;
};
if (my $err = $@) {
    warn "Error Submitting job. $err\n";
}
if (not $id ) {
    die "Unknown problem submitting job. Bad job ID\n"; 
}
my $message = $req->get_message || "";
my $state = $req->get_state;
if ($state eq 'FAILED') {
    die "Job $id failed. Reason: $message\n";
}
else {
    print "Job $id submitted. State = $state. Message = $message\n";
}
