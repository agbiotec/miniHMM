#!/usr/bin/env perl
use strict;
use warnings;

use YAML;

my $c = {
    template_dir => "templates", 
    temp_dir => '/usr/local/scratch/s_apprentice',
    seq_dbs => [
        {name => "NIAA", path => "/usr/local/db/panda/AllGroup/AllGroup.niaa"},
        {name => "NRAA" , path => "/usr/local/db/panda/nraa/nraa"},
        {name => "OMNIUM", path => "/usr/local/db/omnium/pub/OMNIOME.pep"},
        {name => "Internal OMNIUM", path => "/usr/local/db/omnium/internal/OMNIOME.pep"}
    ],
    seg_method => [
        {name => "Tiling models", type=> "tiles"},
        {name => "C-/N- Terminal pairs", type => "pairs"},
    ],
    gap_filter_percent => 65,
    session_type => "driver:db_file;serializer:storable",
    session_params => {FileName => "/usr/local/scratch/s_apprentice/sessions.bdb"},
};
print YAML::Dump($c);
