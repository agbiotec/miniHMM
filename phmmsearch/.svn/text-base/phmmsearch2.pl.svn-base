#!/usr/local/bin/perl -w

eval 'exec /usr/local/bin/perl -w -S $0 ${1+"$@"}'
    if 0; # not running under some shell

# $Id: phmmsearch,v 1.18 2005/10/12 19:38:18 vfelix Exp $

use strict;
use Config::IniFiles;
use Cwd 'abs_path';
use File::Basename;
use Getopt::Long;
use TIGR::FASTAreader;
use FindBin qw($Bin);
use lib "$Bin";
use lib qw(/home/sgeworker/lib);
use TIGR::HTC::HMM;
use Log::Log4perl qw(:levels get_logger);

# CAUTION: Do not modify this VERSION logic as the installation
# process relies upon it by parsing this file. Modify only if you
# have read the ExtUtils::MakeMaker documentation concerning VERSION_FROM.
my $VERSION = "1.21";

my @depend = sort qw(Config::IniFiles File::Basename Getopt::Long Log::Log4perl
                     TIGR::Fastareader TIGR::HTC::HMM htab.pl);

my $global_log_conf = "/usr/local/common/phmm/phmmlogger.conf";

my $DEFAULT_DB = '/usr/local/db/HMM_IND';

my %options;
# The ':s' for each parameter means that the flags are optional strings.
GetOptions ( \%options,
           'add-profiles|a:s',
           'blocksize|b=i',
           'conf|c:s',
           'database:s',
           'depend',
           'debug=s',
           'group|g:s',     # TODO: Remove in next release
           'project|p:s',
           'help|h',
           'htab',
           'logconf=s',
           'minus-profiles|m:s',
           'outdir|o:s',
           'sequence:s',
           'known_seq!',
           'username:s',
           'usage',
           'version|v',
           'wait!',
        );


my $logger_conf;
if ( defined($options{logconf}) ) {
    my $logconf = $options{logconf};
    # Check that the file exists, is a text file, and that it is readable.
    if ( -e $logconf &&
         -T $logconf &&
         -r $logconf) {
        $logger_conf = $logconf;
    } else {
        warn("Problem with the specified logger config file. " .
             "Using global default.");
        $logger_conf = $global_log_conf;
    }
} else {
    $logger_conf = $global_log_conf;
}

# Set up the logger specification through the conf file.
Log::Log4perl->init($logger_conf);
my $logger = get_logger("phmmsearch");

depend() if $options{depend};
usage() if $options{help};
version() if $options{version};

# Process the config file.
if (defined($options{conf})) {
    my $conf = $options{conf};
    $logger->debug(qq|Configuration file "$conf" specified.|);
    my $cfg = Config::IniFiles->new( -file => $conf );
    my $section = "phmmsearch";

    $options{"add-profiles"}   ||= $cfg->val($section, "add-profiles");
    $options{blocksize}        ||= $cfg->val($section, "blocksize");
    $options{database}         ||= $cfg->val($section, "database");
    $options{debug}            ||= $cfg->val($section, "debug");
    $options{"minus-profiles"} ||= $cfg->val($section, "minus-profiles");
    $options{outdir}           ||= $cfg->val($section, "outdir");
    # TODO: Remove in next release
    if ($cfg->val($section, "group")) {
        print STDERR qq|The "group" option has been deprecated. Please use "project"| . "\n";
        $options{project} = $cfg->val($section, "group");
    } elsif ($cfg->val($section, "project")) {
        $options{project} = $cfg->val($section, "project");
    }
        
    $options{sequence}         ||= $cfg->val($section, "sequence");
    $options{htab}             ||= $cfg->val($section, "htab");
    $options{wait}             ||= $cfg->val($section, "wait");
    $options{known_seq}        ||= $cfg->val($section, "known_seq");
    
    my $truth_regex = qr/^(yes|true|on|1)$/i;
    $options{htab} = ($options{htab} =~ m/$truth_regex/) ? 1 : 0;
    $options{wait} = ($options{wait} =~ m/$truth_regex/) ? 1 : 0;
    $options{known_seq} = ($options{known_seq} =~ m/$truth_regex/) ? 1 : 0;
}

# Set the debug level (by name or number).
set_debug_level($options{debug}) if ($options{debug});

# If these still have not been set, then use final defaults.
unless (defined($options{"add-profiles"})) {
    $logger->info("\"add-profiles\" not specified. Checking that a ",
                  "database was specified.");
    unless(defined($options{database})) {
        $logger->warn("No database no add-profiles specified. ",
                      "Using default database: $DEFAULT_DB.");
        $options{database} = $DEFAULT_DB;
    }
}

$options{blocksize} ||= 10;
$options{username} = getpwuid($<);

my @errors;
push (@errors, "Output directory not set.")
    unless (defined($options{outdir}));
push (@errors, "Sequence file must be specified.")
    unless (defined($options{sequence}));
push (@errors, "project to associate the job with must be specified.")
    unless (defined($options{project}));

# Get the absolute path for the file
$options{sequence} = abs_path($options{sequence});
if (-f $options{sequence} && -r $options{sequence}) {
    # Use TIGR::FASTAreader to validate the sequence file.
	if ( !$options{known_seq}) {
    	my $fasta = TIGR::FASTAreader->new(\@errors, $options{sequence});
	}
} else {
    push (@errors, "The sequence file, $options{sequence}, doesn't seem to exist or is unreadable.");
}

if (scalar(@errors)) {
    my $error = join("\n", @errors);
    $logger->logdie($error);
}

my $hmm_request = TIGR::HTC::HMM->new(
                                     blocksize => $options{blocksize},
                                     debug     => $options{debug},
                                     htab      => $options{htab},
                                     outdir    => $options{outdir},
                                     project   => $options{project},
                                     sequence  => $options{sequence},
                                     username  => $options{username},
                                     wait      => $options{wait},
                                  );

$logger->info("Request object created.");

$logger->debug("Building database.");
my $files_ref = build_db();
$hmm_request->database($files_ref);

$logger->info("Submitting request.");
my $id;
eval {
    $id = $hmm_request->submit;
};
$logger->logdie("Job submission failed: $@.") if $@;
$logger->info("Job ID: $id.");

exit;

##############################################################################

sub build_db {
    $logger->debug("In build_db.");
    # Build an array of database files.
    my (@files, @additional_db_files);

    if ( defined($options{database}) && ($options{database} ne "")) {
        if (-d $options{database}) {
            $logger->debug("Preparing to glob files in $options{database}.");
            @files = glob("$options{database}/*.HMM");
        } else {
            $logger->logdie("$options{database} is not a directory.");
        }
    } else {
        $logger->debug("Database left undefined.");
    }

    # First we remove profiles...
    if ( defined($options{"minus-profiles"}) &&
        ($options{"minus_profiles"} ne "")) {
        @files = remove_files($options{"minus-profiles"}, \@files);
    }

    # Then we add... This way, we do not accidentally remove profiles
    # that we first added.
    my $add_profiles = $options{"add-profiles"};
    if ( defined($add_profiles) && ($add_profiles ne "")) {
        $logger->debug("--add-profiles used: $add_profiles.\n", 2);
        if (-f $add_profiles) {
            $logger->debug("--add-profiles parameter resolves to a file.");
            @additional_db_files = &filelist_from_file($add_profiles);
        } else {
            $logger->debug("--add-profiles parameter resolves to a ",
                           "regular expression.");
            @additional_db_files = glob("$add_profiles");
        }
        push (@files, @additional_db_files);
    }

    my $number = scalar(@files);
    $logger->info("Number of database files: $number.");
    return wantarray ? @files : \@files;
}

sub remove_files {
    $logger->debug("In remove_files.");
    my ($minus_profiles, $db_files_ref) = @_;
    my (%db, @files_to_remove);
    # Build a hash with the keys as the db filenames.
    foreach my $db_file (@{ $db_files_ref }) {
        $db{$db_file} = 1;
    }

    if (-f $minus_profiles) {
        $logger->info("--minus-profiles parameter resolves to a file.");
         @files_to_remove = &filelist_from_file($minus_profiles);
    } else {
        $logger->info("--minus-profiles parameter resolves to a regular expression.");
        $logger->debug(qq|--minus-profiles parameter is "$minus_profiles".|);
        @files_to_remove = glob("$minus_profiles");
    }

    $logger->info("Number of files to remove: ", scalar(@files_to_remove));
    foreach my $file_to_remove (@files_to_remove) {
        delete $db{$file_to_remove};
    }

    my @files = sort keys %db;
    $logger->info("Leaving remove_files.");
    return wantarray ? @files : \@files;
}

sub depend {
    print join("\n", @depend);
    exit 0;
}

sub filelist_from_file {
    $logger->debug("In filelist_from_file.");
    my $file = shift;
    my @files;
    open (LIST, "<", $file) or
        $logger->logdie("Could not open $file for readin: $!.\n");
    while (<LIST>) {
        chomp;
        if (-f $_) {
            $logger->debug("File $_ added to the list of database files.");
            push (@files, $_);
        } else {
            $logger->error("File $_ does not exist Skipping.");
        }
    }
    close LIST or
        $logger->logdie("Could not close filehandle: $!");
    return wantarray ? @files : \@files;
}

sub set_debug_level {
    $logger->info("In set_debug_level.");
    my $debug = uc(shift);

    my %levels = ( DEBUG => [5, $DEBUG],
                   INFO  => [4, $INFO],
                   WARN  => [3, $WARN],
                   ERROR => [2, $ERROR],
                   FATAL => [1, $FATAL] );
    my %name_to_level = map { $_ => $levels{$_}->[1] } keys %levels;

    my $setter = sub {
        my $level_string = shift;
        $logger->info("Setting new debug level to $level_string.");
        my $level = $name_to_level{$level_string};
        $logger->level($level);
    };

    if (exists $levels{$debug}) {
        $setter->($debug);
    } else {
        $debug =~ tr/0-9//cd;
        if ($debug >= 1 and $debug <= 5) {
            my %level_to_name =
                reverse ( map { $_ => $levels{$_}->[0] } keys %levels );
            $setter->( $level_to_name{$debug} );
        } else {
            $logger->warn("\"$options{debug}\" is an invalid debug level.");
            return 0;
        }
    }
}

sub usage {
    $logger->debug("In usage.");
    my $usage_string = <<"    _USAGE";
    -a --add-profiles=<profile>    List of regexes or filenames to add to the search

    -b --blocksize                 How many db files to process per job. Default is 10.

    -c --conf                      Configuration file to use (INI format).

    --database                     Database directory.
                                   Default is /usr/local/db/HMM_IND.

    --debug=<n|level>              Set the debug level. Either a number, or the
                                   level's name may be specified:

                                   1 - fatal
                                   2 - error
                                   3 - warn
                                   4 - info
                                   5 - debug

    -g --group=<group>             DEPRECATED. See the --project option.

    -p --project=<project>         What project this job should be associated
                                   with. Required.

    --htab                         Toggle to post-process the hits files
                                   with "htab.pl".

    -l --logconf=<file>            Log::Log4perl configuration file.
                                   Default is /usr/local/common/phmm/phmmlogger.conf.

    -m --minus-profiles=<profile>  List of regexes or filenames to remove
                                   from the search.

    -o --outdir=<dir>              Output directory.

    -s --sequence=<file>           Sequence Fasta File
    
    --known_seq                    Toggle if the Sequence file is known to be good
                                   and validation should be skipped.
                                   Default is to validate.

    -u --username=<username>       Username to submit the request as.

    -v --version                   Display version information.

    -w --wait                      Toggle to wait for results to be returned
                                   Default is not to wait.

    --help | --usage               Display usage/help information.
    _USAGE

    print $usage_string;
    exit 0;
}

sub version {
    $logger->debug("In version.");
    print "Version $VERSION\n";
    exit 0;
}
