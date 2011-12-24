#!/usr/bin/env perl
use warnings;
use strict;



package main;
use Carp;

use version; our $VERSION = qv( qw$Revision 0.0.1$[1] );

use Getopt::Long qw(:config no_ignore_case no_auto_abbrev); # Option parser. Exports GetOptions()
use Pod::Usage; # for --help parameter. Exports pod2usage(), which exit()s
use Log::Log4perl qw/:easy/;
Log::Log4perl->easy_init();

use DBI;

use Schedule::DRMAAc qw/:all/;

use YAML;
use Carp qw/confess/;
#BEGIN {
#    $SIG{__DIE__} = sub { confess @_};
#}

use File::Spec::Functions qw/catfile catdir splitpath/;
use File::Temp qw/tempdir/;
use File::Path qw/mkpath/;
BEGIN {umask 0000;};

use FindBin;

use lib $FindBin::Bin."/../cgi-bin/lib";
use miniHMM::AccConfig;
my $CONFIG_FILE= catfile($FindBin::Bin,'..','cgi-bin','apprentice.conf');
my $app_config =  miniHMM::AccConfig->load_file($CONFIG_FILE); 


sub find_db {
    my $db_name = shift;
    my ($db_path) = map { $_->{path} } grep {$_->{short_name} eq $db_name} @{$app_config->seq_dbs()};
    return $db_path;
}

sub find_hmm_seed {
    my $hmm_acc = shift;
    my $seed_file = catfile($app_config->hmm_source_dir, "$hmm_acc.SEED");
    # if the file is an HMM id (i.e exists as $app_config->hmm_source_dir/$n.SEED)
    if (-f $seed_file) {
        return $seed_file,
    }
    
    return;
}

sub get_last_version {
    my $dir = shift;
    my $last_version = 0;
    if (-d $dir) {
        my $spec = catfile($dir, "v*");
        my @versions = glob($spec);
        $last_version = grep {/^v\d+$/} @versions; # count of versions
    } 
    return $last_version;  
}

sub get_next_directory {
    my $params = shift;
    my @fields = qw/base hmm_acc fragment_length fragment_overlap database/;
    my ($base, $hmm_acc, $f_length, $f_cutoff, $database) = @$params{@fields};
    (undef, undef, $database) = splitpath($database);
    my $working_dir = catdir($base,$hmm_acc, "${f_length}X${f_cutoff}",$database);
    my $last_version = get_last_version($working_dir);
    $last_version++;
    $working_dir = catdir($working_dir, sprintf("v%03s",$last_version) );
    return $working_dir;
}

sub get_hmm_cutoffs {
    my $hmm_acc = shift;
    my $dbh = DBI->connect_cached('dbi:Sybase:server=SYBTIGR;database=egad','access','access');
    my $sth = $dbh->prepare(qq{
        SELECT trusted_cutoff, noise_cutoff
        FROM hmm2
        WHERE hmm_acc = ?
    });
    $sth->execute($hmm_acc);
    my $cutoffs = $sth->fetchrow_hashref();
    $sth->finish;
    return $cutoffs;
}

sub generate_parameter_file {
    my $hmm_info = shift;
    my $parameters = shift;
    my %run_parameters;
    # from parameters, we get database, fragment_length, fragment_overlap, 
    # hmmsearch_cutoff, parallel_search, and param_files_dir
    my $param_files_dir = $parameters->{param_files_dir};
    my @general_fields = qw/
        database fragment_length fragment_overlap
        hmmsearch_cutoff parallel_search/;
    if (my @missing_fields = grep {! defined $parameters->{$_} } @general_fields) {
        croak "Didn't get parameters ",join(', ', @missing_fields);   
    }
    @run_parameters{@general_fields} = @$parameters{@general_fields};
    # from hmm_info, we get hmm_acc and seed_file
    my $hmm_acc = $hmm_info->{hmm_acc};
    $run_parameters{hmm_alignment_file} = $hmm_info->{seed_file} or croak "Didn't get seed file passed";
    
    # need additional info:
    
    # log file
    $run_parameters{log_file} = 'out.log';
    
    # working_directory
    my $working_dir = get_next_directory({
        base    =>$app_config->working_directory_root,
        hmm_acc => $hmm_acc,
        %run_parameters,
    });
    $run_parameters{working_directory} = $working_dir;
    # results_directory
    my $results_dir = get_next_directory({
        base    =>$app_config->results_directory_root,
        hmm_acc => $hmm_acc,
        %run_parameters,
    });
    $run_parameters{results_directory} = $results_dir;
    
    # fetch cutoffs
    my $cutoffs = get_hmm_cutoffs($hmm_acc);
    @run_parameters{qw/trusted_cutoff noise_cutoff/} = @$cutoffs{qw/trusted_cutoff noise_cutoff/};

    my $param_file = catfile( $param_files_dir, "$hmm_acc.parameters");
    my $config = miniHMM::AccConfig->new(\%run_parameters);
    $config->save_file($param_file);
    return $param_file;
}

sub launch_grid_jobs {
    my $param_files_dir = shift;
    my @param_files = @_;
    
    # save files to a temporary file
    my $param_files_list_file = catfile($param_files_dir, "param_files.list");
    open my $file_list, ">", $param_files_list_file or die "Couldn't create $param_files_list_file. $!\n";
    foreach my $file_name (@param_files) {
        print $file_list "$file_name\n";
    }
    close $file_list or die "Can't close $param_files_list_file.$!\n";
    my $blocksize = $app_config->block_size || 1;
    
    # calc number of lines in the parameters file
    my $num_blocks = scalar(@param_files) /$blocksize;
    if ($num_blocks != int($num_blocks) ) {
        $num_blocks = int($num_blocks) + 1 ;
    }
    
    my $cmd_name = 'create_minihmm.pl';
    my $args = '-f {}';
    my $command = catfile($FindBin::Bin, $cmd_name);
    # my $wrap = '/home/rrichter/grid/echo_env.pl';
    my $wrap = catfile($FindBin::Bin,'grid_wrapper.pl');
    
    my $base_dir = $app_config->working_directory_root;
    my $project_id = $app_config->project_id;
    
    
    
    #start DRMAA connection
    my ($error, $diagnosis);
    ($error, $diagnosis) = drmaa_init(undef);
    die drmaa_strerror($error)."\n".$diagnosis if $error;
    
    # create job template
    my $jt;
    ($error, $jt, $diagnosis) = drmaa_allocate_job_template();
    die drmaa_strerror($error)."\n".$diagnosis if $error;
    
    # set project
    ($error, $diagnosis) = drmaa_set_attribute($jt, $DRMAA_NATIVE_SPECIFICATION, "-P $project_id");
    die drmaa_strerror($error)."\n".$diagnosis if $error;
    
    # set command
    ($error, $diagnosis) = drmaa_set_attribute($jt, $DRMAA_REMOTE_COMMAND, $wrap);
    die drmaa_strerror($error)."\n".$diagnosis if $error;
    
    # set job name
    ($error, $diagnosis) = drmaa_set_attribute($jt, $DRMAA_JOB_NAME, $cmd_name);
    die drmaa_strerror($error)."\n".$diagnosis if $error;
    
    # set working directory
    ($error, $diagnosis) = drmaa_set_attribute($jt, $DRMAA_WD, $base_dir);
    die drmaa_strerror($error)."\n".$diagnosis if $error;
    
    # set stdout
    my $time = time();
    ($error, $diagnosis) = drmaa_set_attribute($jt,$DRMAA_OUTPUT_PATH, ":$cmd_name.$time.$DRMAA_PLACEHOLDER_INCR.out");
    die drmaa_strerror($error)."\n".$diagnosis if $error;
    
    # set stderr to stdout
    ($error, $diagnosis) = drmaa_set_attribute($jt, $DRMAA_JOIN_FILES, 'y');
    die drmaa_strerror($error)."\n".$diagnosis if $error;
    
    # set parameters (the only option to be passed to individual items is the placeholder item)
    my @args = ('-s',$blocksize, '-f', $param_files_list_file, '-c', "$command $args");
    ($error, $diagnosis) = drmaa_set_vector_attribute($jt, $DRMAA_V_ARGV, \@args);
    die drmaa_strerror($error)."\n".$diagnosis if $error;
    
    
    # run the jobs
    my $jobid_it;
    ($error, $jobid_it, $diagnosis) = drmaa_run_bulk_jobs($jt,1,$num_blocks,1);
    die drmaa_strerror($error)."\n".$diagnosis if $error;
    
    # show job ids
    my @job_ids;
    $error = $DRMAA_ERRNO_SUCCESS;
    while ($error == $DRMAA_ERRNO_SUCCESS) {
        my $job_id;
        ($error, $job_id) = drmaa_get_next_job_id($jobid_it);
        if ($error == $DRMAA_ERRNO_SUCCESS) {
            push @job_ids, $job_id;
        }
    }
    my ($id) = $job_ids[0] =~ /^([^\.]+)/;
    print "Starting job group $id.[1 .. $num_blocks]\n";
    print "Waiting for completion\n";
    # wait till jobs finish
    ($error, $diagnosis) = drmaa_synchronize(\@job_ids, $DRMAA_TIMEOUT_WAIT_FOREVER, 0);
    
    # exit
    ($error, $diagnosis) = drmaa_exit();
}

sub launch_non_grid_jobs {
    my $param_files_dir = shift;
    my @param_files = @_;
    my %child_pids;
    foreach my $param_file (@param_files) {
        my $params = miniHMM::AccConfig->load_file($param_file);
        my $working_dir = $params->working_directory;
        my $pid = fork();
        if (! defined $pid) {
            warn "Could not start job for $param_file. $!\n";
        }
        elsif ( !$pid) { # child
            if (! -d $working_dir) {
                mkpath $working_dir;
            }
            open STDERR, '>', catfile($working_dir,'out.log');
            open STDOUT, '>&STDERR';
            exec(catfile($FindBin::Bin,'create_minihmm.pl'), '-f', $param_file) or die "Can't run create_minihmm.pl for $param_file.$!\n";
        }
        else { # parent
           $child_pids{$pid} =1;
        }
    }
    warn "Waiting for ",scalar(keys %child_pids)," jobs to finish.\n";
    1 while (wait() != -1);
}

sub main {
    local @ARGV = @_;
    ## Option Parsing
    my ($database, $fragment_length, $fragment_overlap);
    my $hmmsearch_cutoff = 10;
    GetOptions(
        'help|?'        => sub {pod2usage(1)},
        'version'       => sub {print "$0 version $VERSION\n"; exit 0;},
        'man'           => sub {pod2usage( -exitstatus => 1, -verbose => 1)},
        'database|D=s'  => \$database,
        'fragment_length|l=s' => \$fragment_length,
        'fragment_overlap|o=s' => \$fragment_overlap,
        'hmmsearch_cutoff|c=s' => \$hmmsearch_cutoff,
    ) or pod2usage(2); 
    
    # map database to exact paths (error if not known name, or existing path)
    if (!$database) {
        pod2usage( -exitstatus=>2, -message => "Database (-D) parameter required");
    }
    if (! -f $database) {
        my $db_path = find_db($database);
        if (! $db_path) {
            pod2usage( -exitstatus=>2, -message => "Could not find database '$database'\n");
        }
        else {
            $database = $db_path;
        }
    }
    # check that fragment_length > fragment overlap
    if ($fragment_length <= $fragment_overlap) {
        pod2usage( -exitstatus=>2, -message => "Fragment overlap ($fragment_overlap) must be less than $fragment_length\n");
    }
    
    # store parameters
    my $parameters = {
        database => $database,
        fragment_length => $fragment_length,
        fragment_overlap => $fragment_overlap,
        hmmsearch_cutoff => $hmmsearch_cutoff,        
    };
    
    # generate HMM seed list
    my @hmm_params;
    foreach my $file_or_hmm (@ARGV) {
        my $as_seed = find_hmm_seed($file_or_hmm);
        if ($as_seed) {
            push @hmm_params, {
                hmm_acc=>$file_or_hmm,
                seed_file => $as_seed,
            };
        }
        elsif (-f $file_or_hmm) {
            open my $list, $file_or_hmm or die "Can't open hmm list $file_or_hmm. $!\n";
            while (my $line = <$list>) {
                chomp $line;
                next if (! $line or $line =~ /^#/); # skip blanks and comments
                my ($hmm_acc) = split /\W/, $line;
                my $seed = find_hmm_seed($hmm_acc);
                if ($seed) {
                    push @hmm_params, {
                        hmm_acc=>$hmm_acc,
                        seed_file => $seed,
                    };
                }
                else {
                    die "Can't find seed file for '$hmm_acc' in $file_or_hmm, line $.\n";
                }
            }
        }
        else {
            die "$file_or_hmm is not an HMM accession or a list of accessions.\n";
        }
    }
    
    # decide if the should be run on grid
    my $on_grid = 1;
    $parameters->{parallel_search} = 0;
    if (@hmm_params < $app_config->minimum_hmms_for_grid) {
        $parameters->{parallel_search} = 1;
        $on_grid = 0;   
    }
    
    my $param_files_dir = catdir($app_config->working_directory_root,'parameters');
    if (! -d $param_files_dir) {
        mkpath $param_files_dir or die "Can't create temporary directory in $param_files_dir. $!\n";
    }
    $param_files_dir = tempdir(DIR=>$param_files_dir);
    $parameters->{param_files_dir} = $param_files_dir;
    my @param_files;
    foreach my $hmm_info (@hmm_params) {
        my $param_file = generate_parameter_file($hmm_info, $parameters);
        # warn "$param_file\n";
        push @param_files, $param_file;
    }
    
    if ($on_grid) {
        launch_grid_jobs($param_files_dir, @param_files);
    }
    else {
        launch_non_grid_jobs($param_files_dir, @param_files);
    }
    
    
}

if (!caller) { # only if called as a script
    main(@ARGV);
}

1;
__END__

=head1 NAME

bulk_minihmms.pl - generates minihmms for a list of TIGR/PFAM models


=head1 VERSION

This document describes bulk_minihmms.pl version 0.0.1


=head1 SYNOPSIS

    bulk_minihmms.pl -D <database> -l 50 -o 25 <HMM_ID|filename, ...>

=head1 OPTIONS

=over

=item B<--database> or B<-D>

The path to the protein database to be used for HMM calibration. Standard databases
can be referred to by short name (e.g. omnium, iomnium [internal omnium], nraa, niaa)

=item B<--fragment_length> or B<-l>

The length in residues of each mini-HMM. 

=item B<--fragment_overlap> or B<-o>

The number of residues to overlap successive mini-HMMs. May not be >= fragment_length

=item B<--hmmsearch_cutoff> or B<-c>

Override the hmmsearch e-value cutoff. Defaults to 10

=back

=head1 REQUIRED ARGUMENTS

=for author to fill in:
    A complete list of every argument that must appear on the command line
    when the application is invoked, explaining what each of them does, any
    restriction on where each one may appear (i.e. flags that must appear
    before or after filenames), and how the various arguments and options
    may interact (e.g. mutual exclusions, required combinations, etc.)
    
    If all of the application's arguments are optional, this section 
    may be omitted entirely.
      
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

bulk_minihmms.pl a configuration file at ../cgi-bin/apprentice.conf


=head1 DEPENDENCIES

create_minihmm.pl is used to run the individual miniHMM generation tasks.


=head1 INCOMPATIBILITIES

=for author to fill in:
    A list of any SCRIPTs that this SCRIPT cannot be used in conjunction
    with. This may be due to name conflicts in the interface, or
    competition for system or program resources, or due to internal
    limitations of Perl (for example, many SCRIPTs that use source code
    filters are mutually incompatible).

None reported.


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
C<bug-<RT NAME>@rt.cpan.org>, or through the web interface at
L<http://rt.cpan.org>.

=for author to add or remove:
    The sections EXAMPLES, FREQUENTLY ASKED QUESTIONS, COMMON USAGE MISTAKES,
    SEE ALSO, and ACKNOWLEDGEMENTS can be added or removed as needed

=head1 EXAMPLES

=for author to fill in:
    Add illustrative examples of specific use cases or methods that
    may be I<tricky> or are particularly common and thus should be 
    expanded on from the synopsis or description.

=head1 FREQUENTLY ASKED QUESTIONS

=for author to fill in:
    Add common questions and the standard answers here.

=head1 COMMON USAGE MISTAKES

=for author to fill in:
    If there are common mistakes made when using the code (often discovered 
    through apparently unrelated questions), explain the misconceptions and
    provide examples of correct usage.

=head1 SEE ALSO

=for author to fill in:
    Add references to SCRIPTs, documentation, or other information that
    will make it simpler for users to understand what this code is for
    and how it works.



=head1 AUTHOR

Alexander Richter  C<< <arichter@tigr.org> >>

=head1 ACKNOWLEDGEMENTS

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2006, Alexander Richter C<< <arichter@tigr.org> >>. All rights reserved.

This SCRIPT is free software; you can redistribute it and/or
modify it under the same terms as Perl itself. See L<perlartistic>.


=head1 DISCLAIMER OF WARRANTY

BECAUSE THIS SOFTWARE IS LICENSED FREE OF CHARGE, THERE IS NO WARRANTY
FOR THE SOFTWARE, TO THE EXTENT PERMITTED BY APPLICABLE LAW. EXCEPT WHEN
OTHERWISE STATED IN WRITING THE COPYRIGHT HOLDERS AND/OR OTHER PARTIES
PROVIDE THE SOFTWARE "AS IS" WITHOUT WARRANTY OF ANY KIND, EITHER
EXPRESSED OR IMPLIED, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE. THE
ENTIRE RISK AS TO THE QUALITY AND PERFORMANCE OF THE SOFTWARE IS WITH
YOU. SHOULD THE SOFTWARE PROVE DEFECTIVE, YOU ASSUME THE COST OF ALL
NECESSARY SERVICING, REPAIR, OR CORRECTION.

IN NO EVENT UNLESS REQUIRED BY APPLICABLE LAW OR AGREED TO IN WRITING
WILL ANY COPYRIGHT HOLDER, OR ANY OTHER PARTY WHO MAY MODIFY AND/OR
REDISTRIBUTE THE SOFTWARE AS PERMITTED BY THE ABOVE LICENCE, BE
LIABLE TO YOU FOR DAMAGES, INCLUDING ANY GENERAL, SPECIAL, INCIDENTAL,
OR CONSEQUENTIAL DAMAGES ARISING OUT OF THE USE OR INABILITY TO USE
THE SOFTWARE (INCLUDING BUT NOT LIMITED TO LOSS OF DATA OR DATA BEING
RENDERED INACCURATE OR LOSSES SUSTAINED BY YOU OR THIRD PARTIES OR A
FAILURE OF THE SOFTWARE TO OPERATE WITH ANY OTHER SOFTWARE), EVEN IF
SUCH HOLDER OR OTHER PARTY HAS BEEN ADVISED OF THE POSSIBILITY OF
SUCH DAMAGES.
