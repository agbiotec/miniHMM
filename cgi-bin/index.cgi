#!/usr/local/bin/perl
use strict;
use warnings;

use File::Spec::Functions qw(catfile catdir rel2abs splitpath);

my $bin_dir;
BEGIN {
    umask 0000;
    delete @ENV{qw/ PATH TEMP CDPATH ENV BASH_ENV/};
    $ENV{PATH} = '/bin:/usr/bin:/usr/local/bin';
    (undef, $bin_dir, undef) = splitpath(rel2abs($0)); 
}

use lib catdir($bin_dir,"lib");
use miniHMM::App;

my $config_file = 'apprentice.conf'; 
my $conf_path = catfile($bin_dir, $config_file);

if (-f $conf_path and -r _) {
    $config_file =  $conf_path;
}

my $app = miniHMM::App->new(
    PARAMS => {
        _bin_dir => $bin_dir,
        _config_file => $config_file,
    },
);
$app->run();