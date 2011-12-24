#!/usr/bin/env perl
use warnings;
use strict;
use FindBin;
use File::Spec::Functions qw/catfile catdir splitpath/;
use lib catdir($FindBin::Bin,'/..', '/cgi-bin/lib');


package App; {

    use Log::Log4perl qw/:easy/;
    
    sub new {
        my $class = shift;
        return bless({}, $class);   
    }

}


package main;

use Carp;
use YAML;

use version; our $VERSION = qv( qw$Revision 0.0.1$[1] );

use Getopt::Long qw(:config no_ignore_case no_auto_abbrev); # Option parser. Exports GetOptions()
use Pod::Usage; # for --help parameter. Exports pod2usage(), which exit()s

use miniHMM::AccConfig;

use Log::Log4perl qw/:easy/;
Log::Log4perl->easy_init();

umask 0000;
use File::Path qw/mkpath rmtree/;
use File::Copy qw/copy/;
use Cwd qw/abs_path/;

my $CONFIG_FILE= catfile($FindBin::Bin,'..','cgi-bin','apprentice.conf');
my $app_config = miniHMM::AccConfig->load_file($CONFIG_FILE) or FATAL "Can't parse $CONFIG_FILE\n";

sub parse_options {
    local @ARGV = @_ if @_;    
    ## Option Parsing
    # add parameters as needed
    my ($help, $version, $man);
    my %opts = (help => \$help, version => \$version, man => \$man);
    
    my @REQUIRED_PARAMS = qw/
        hmm_alignment_file database
        fragment_length fragment_overlap
        trusted_cutoff noise_cutoff
    /;
    GetOptions(\%opts,
        'help|?', 'version', 'man', # help
        'working_directory=s', 'results_directory=s', # directories
        'parameters_file|f=s', # parameters file
        'hmm_alignment_file|H=s', 'database|D=s',
        'fragment_length|l=s', 'fragment_overlap|o=s', 
        'hmmsearch_cutoff|c=s',
        'parallel_search|p',
        'trusted_cutoff|t=s',
        'noise_cutoff|n=s',
        'log_file=s',
        'dry_run',
        
    ) or pod2usage(2);
    
    # Check for and exit with help
    if ($help) {
        pod2usage(1);
    }
    if ($version) {
         print "$0 version $VERSION\n"; exit 0;
    }
    if ($man) {
        pod2usage( -exitstatus => 1, -verbose => 1)
    }
    
    delete $opts{$_} foreach (qw/help man version/);
    
    my $config;
    # Read config file, if passed;
    if ($opts{parameters_file}) {
        DEBUG "Using explicit parameters file $opts{parameters_file}";
        $config = miniHMM::AccConfig->load_file($opts{parameters_file});
        # override with passed parameters
        foreach (keys %opts) {
            if ($_ ne 'parameters_file') {
                $config->$_($opts{$_});
            }
        }
    }
    else {
        $config = miniHMM::AccConfig->new(\%opts);
    }
    
    # Process/Check other parameters
    # set defaults
    if ( not $config->exists('working_directory') ) {
        $config->working_directory('.');
        INFO "Using . as default working directory";
    }
    if ( not $config->exists('results_directory') ) {
        $config->results_directory($config->working_directory);
        INFO "Using ".$config->working_directory." as default results directory";
    }
    if (not $config->exists('hmmsearch_cutoff') ) {
        $config->hmmsearch_cutoff(10.0);
    }
    if (not $config->exists('parallel_search') ) {
        $config->parallel_search(0);
    }
    if (not $config->exists('dry_run') ) {
        $config->dry_run(0);
    }

    # check for existing parameters file
    my $dir_config = miniHMM::AccConfig->new();
    my $working_params_file = catfile ($config->working_directory, $app_config->default_parameters_file_name);
    if ( -r $working_params_file ) {
        $dir_config = miniHMM::AccConfig->load_file($working_params_file);
        DEBUG "Reading parameters in $working_params_file";
        $dir_config->delete('dry_run'); # dry-run parameter should be set only from command line
    }
    # use directory settings if it was the only thing set
    if ($dir_config and not grep {$config->exists($_)} @REQUIRED_PARAMS) {
        my $dry_run = $config->dry_run;
        $config = $dir_config;
        if ($dry_run) {
            $config->dry_run(1);
        }
    }
    
    # Check for existence of required parameters and possible conflicts
    foreach my $required (@REQUIRED_PARAMS) {
        if ( ! $config->exists($required) ) {
            pod2usage( -exitstatus=>2, -message=>"Missing required parameter $required");
        }
        if ($dir_config->exists($required) and $dir_config->$required ne $config->$required) {
            die "Conflicting parameters between directory and passed configuration for $required\n";
        }
    }
    
    # check that seed is readable
    if (! -r $config->hmm_alignment_file) {
        die "Seed alignment file ".$config->hmm_alignment_file." cannot be read. Can't continue."; 
    }
    
    # Add back remaining CMD arguments
    $config->_argv([@ARGV]);
    
    return $config;
}

sub prepare_working_directory {
    my $config = shift;

    my $work_path = abs_path($config->working_directory) || $config->working_directory;
    # if it does not exist, create the working directory;
    if (! -e $work_path) {
        mkpath($work_path);
    }
    # if the HMM seed is not already in the target, copy it, then change config
    my $hmm_seed = $config->hmm_alignment_file;
    my ($seed_drive, $seed_dir, $seed_file) = splitpath($hmm_seed);
    my $seed_path = abs_path("$seed_drive$seed_dir");
    my $work_seed = catfile($work_path,$seed_file); 
    if ($seed_path ne $work_path) {
        copy($hmm_seed, $work_seed);
        $config->hmm_seed($seed_file)
    }
    # update config to map to parameters file in target, writing it if needed.
    my $parameters_file = catfile($work_path, $app_config->default_parameters_file_name);
    $config->parameters_file($parameters_file);
    if ( ! -e $parameters_file) {
        $config->save_file($parameters_file);
    }
    
    return 1;
}

sub run_minihmm_eval {
    my $opts = shift;
    if ($opts->exists('log_file')) {
        open STDOUT, ">", $opts->log_file or FATAL("Can't log to ".$opts->log_file);
        open STDERR, ">&STDOUT";
    }
    my $working_dir = $opts->working_directory;
    my $hmm_seed_aln = $opts->hmm_alignment_file;
    my $prefix = $hmm_seed_aln;
    $prefix =~ s/\.[^.]+$//;
    
    
    TRACE "Instantiating command object for $prefix";
    my $cmd = miniHMM::HmmCommand->new({
        dir => $opts->working_directory,
        seed_file => $opts->hmm_alignment_file,
        prefix => $prefix,
        trusted_cutoff =>  $opts->trusted_cutoff,
        noise_cutoff => $opts->noise_cutoff,
        evalue_cutoff => $opts->hmmsearch_cutoff,
        gap_filter => 25,
        seq_db => $opts->database,
        exclude_text => '',
        model_type => 'tiles',
        model_length => $opts->fragment_length,
        model_overlap => $opts->fragment_overlap,
        parallel => $opts->parallel_search,
    });
    
    TRACE "Preparing $prefix";
    $cmd->prepare();
    TRACE "Running $prefix";
    my $summary;
    $summary = $cmd->run() if not $opts->dry_run;
    TRACE "Done with $prefix";
    return $summary;
}

sub write_summary_file {
    my $summary = shift;
    YAML::DumpFile('summary.yaml', $summary);
    my $outfile = 'summary.txt';
    my $ok = open my $fh, '>', $outfile;
    if (! $ok) {
        ERROR "Could not open summary file for writing. $!\n";
        return;
    }
    print $fh join("\t", qw/Mini_Name Upper_Cutoff Lower_Cutoff Sensitivity Range/), "\n";
    foreach my $profile_mini (@{$summary->{profiles_by_mini}}) {
        my $mini_name = $profile_mini->{mini_name};
        my $mini_range = $profile_mini->{mini_range};
        my $profile = $profile_mini->{profiles}->{100};
        my $upper_cutoff_score = $profile->upper_cutoff_score || '';
        $upper_cutoff_score = sprintf('%4.2f',$upper_cutoff_score) if $upper_cutoff_score ne '';
        my $lower_cutoff_score = $profile->lower_cutoff_score || '';
        $lower_cutoff_score = sprintf('%4.2f',$lower_cutoff_score) if $lower_cutoff_score ne '';
        my $sensitivity = sprintf('%02.1f',$profile->sensitivity);
        print $fh join("\t", $mini_name, $upper_cutoff_score, $lower_cutoff_score, $sensitivity, $mini_range), "\n";
    }
}

sub copy_to_results_directory {
    my $opts = shift;
    my $results_dir = $opts->results_directory;
    if ( not -d $results_dir ) {
        mkpath($results_dir);
    }
    my @results_files = (glob('*.mini.*.HMM'),glob('*.profile.txt'),'analysis.txt','run_parameters.txt', 'summary.txt');
    my $abs_results_dir = abs_path($results_dir);
    my $abs_working_dir = abs_path($opts->working_directory);
    if ( $abs_results_dir ne $abs_working_dir) {
        foreach my $file (@results_files) {
            my $result_file = catfile($results_dir, $file);
            copy($file, $result_file) or WARN "Couldn't copy $file to $result_file\n";
        }
    }
    return 1;
}

sub main {
    local @ARGV = @_ if @_;
    my $opts = parse_options();
    @ARGV = @{$opts->_argv};
    prepare_working_directory($opts);

    my $working_dir = $opts->working_directory;
    chdir $working_dir or FATAL("Cannot change directory to $working_dir. $!");
    
    my $summary = run_minihmm_eval($opts);
    write_summary_file($summary);
    copy_to_results_directory($opts);    
    
    
}

if (!caller) { # only if called as a script
    main(@ARGV);
}

1;
__END__

=head1 NAME

create_minihmm.pl - generates and analyzes miniHMMs from a single seed alignment


=head1 VERSION

This document describes create_minihmm.pl version 0.0.1


=head1 SYNOPSIS

Run, specifying minimal options. This will store all working files, 
and all results in the current directory (use -w to change the working
directory, and -r to change the directory for results output), and will 
run in serial (use --parallel to run hmmsearch-es in parallel).
    
    create_minihmm.pl -D /usr/local/db/omnium/internal/OMNIOME.pep \
        -H /usr/local/db/HMM_IND/TIGR03001.SEED \
        -l 50 -o 25
        
Run, from an existing working directory. 
This will read the config file in that directory for parameters

    create_minihmm.pl -w /usr/local/scratch/miniHMM/working_dir01
    
Run based on a pre-created config file.
This will act identically to having specified parameters on the command line

    create_minihmm.pl -f config.tigr03001.50.25.omnium.yaml

  
=head1 OPTIONS

=over

=item B<--parameters_file> or B<-f>

Specify a pre-created parameters file (YAML format) to use in place of 
command-line arguments. It is strongly recommended that all the 
following arguments are set in the file. Any other options set from the command line
override the parameters file. 

=item B<--working_directory> or B<-w>

The directory to use for temporary files, and for processing. Defaults to the
current directory.

B<WARNING> If a valid parameters file already exists in the working directory,
the script will attempt to continue processing, rather than start 
from scratch. If the parameters file in the working directory does not match
parameters set from the command line (or from a pre-created parameters file 
specified with --parameters_file), the script will not run.

=item B<--results_directory> or B<-r> 

The directory to store the final results. Defaults to the working directory.

Results include all mini HMM files, and the tab-delimited summary file.

=item B<--hmm_alignment_file> or B<-H>

Set the full-length HMM alignment seed file that will be used to create the mini-HMMs.
Note that this must be the alignment, not the generated HMM.

=item B<--database> or B<-D>

The path to the protein database to be used for HMM calibration (e.g. PANDA, OMNIUM, or NR)

=item B<--fragment_length> or B<-l>

The length in residues of each mini-HMM. 

=item B<--fragment_overlap> or B<-o>

The number of residues to overlap successive mini-HMMs. May not be >= fragment_length

=item B<--hmmsearch_cutoff> or B<-c>

Override the hmmsearch e-value cutoff.

=item B<--parallel_search> or B<-p>

Run hmmsearches in parallel, rather than serially.

=back

      
=head1 DESCRIPTION

=for author to fill in:
    Write a full description of the SCRIPT and its features here.
    Use subsections (=head2, =head3) as appropriate.


=head1 DIAGNOSTICS

=for author to fill in:
    List every single error and warning message that the SCRIPT can
    generate (even the ones that will "never happen"), with a full
    explanation of each problem, one or more likely causes, and any
    suggested remedies.

=over

=item C<< Error message here, perhaps with %s placeholders >>

[Description of error here]

=item C<< Another error message here >>

[Description of error here]

[Et cetera, et cetera]

=back


=head1 CONFIGURATION AND ENVIRONMENT

create_minihmm.pl can read, and will create, a YAML-based config file 
of run-time parameters. This file is completely equivalent to the 
available command-line parameters.



=head1 BUGS AND LIMITATIONS

=for author to fill in:
    A list of known problems with the SCRIPT, together with some
    indication Whether they are likely to be fixed in an upcoming
    release. Also a list of restrictions on the features the SCRIPT
    does provide: data types that cannot be handled, performance issues
    and the circumstances in which they may arise, practical
    limitations on the size of data sets, special cases that are not
    (yet) handled, etc.

No bugs have been reported.

Please report any bugs or feature requests to
C<rrichter@jcvi.org>.

=head1 AUTHOR

Alexander Richter  C<< <rrichter@jcvi.org> >>
