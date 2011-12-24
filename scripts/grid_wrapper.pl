#!/usr/local/bin/perl
use strict;
use warnings;

use Getopt::Long qw(:config no_ignore_case no_auto_abbrev);

my $command;
my $parameters_file;
my $batch_size;

print join(" ", map {"'$_'"} ($0,@ARGV)),"\n";

my $batch_id = $ENV{SGE_TASK_ID} or die "ERROR: Environment var \$SGE_BATCH_ID not defined. Must be run via the grid.\n";

GetOptions(
    'command|c=s' => \$command,
    'parameters_file|f=s' => \$parameters_file,
    'batch_size|s=i' => \$batch_size,
) or die "Can't read options";

if (! -f $parameters_file) {
    die "ERROR: --parameters_file ($parameters_file) does not exist\n";
}


if (! defined $batch_size or $batch_size < 1) {
    $batch_size = 1;   
}
if (! defined $command) {
    die "ERROR: --command is required\n";
}

my ($exec) = $command =~ m{^((?:[\w/\.]+|\\ ))};
if (! -x $exec) {
    die "ERROR: --command ($command) must be executable\n";
}

open my $fh, $parameters_file or die "ERROR: Can't read $parameters_file. $!\n";
my $first_line = ($batch_id -1) * $batch_size;
for (my $x=0 ; $x < $first_line;  $x++) {
    my $line = <$fh>;
}
my $count = 0;
while ($count < $batch_size and my $line = <$fh>) {
    chomp $line;
    my $full_command = $command;
    $full_command =~ s/\{\}/$line/;
    system($full_command);
    $count ++;
}


__END__

=head1 NAME

grid_wrapper.pl -- a simple script to translate grid index entries to argument lists

=head1 SYNOPSIS

In params.txt:
    Hello
    World

Then call (from a bulk_job), using {} as the placeholder for the parameter:
    grid_wrapper.pl -b <batch_id> -f params.txt -c 'echo -e {} again'
    
This results in the two commands on the grid:
    echo -e Hello again
    echo -e World again