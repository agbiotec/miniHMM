package TIGR::HTC::HMM;

# $Id: HMM.pm,v 1.3 2005/10/12 19:39:23 vfelix Exp $


=head1 NAME

HMM.pm - One line summary of purpose of class (or file).

=head1 VERSION

This document refers to $Revision: 1.3 $ HMM.pm.

=head1 SYNOPSIS

Short examples of code that illustrate the use of the class (if this file is a class).

=head1 DESCRIPTION

=head2 Overview

An overview of the purpose of the file.

=head2 Class and object methods

=over 4

=cut


use strict;
use File::Basename;
use Log::Log4perl qw(get_logger);
use base qw(TIGR::HTC);
use TIGR::HTCRequest;
use POSIX qw(ceil);

use vars qw($VERSION);
$VERSION = do { my @r=(q$Revision: 1.3 $=~/\d+/g); sprintf "%d."."%03d"x$#r,@r };

my $exec_path = '/home/rrichter/tmp/grid/phmmsearch' ||  '/usr/local/common';

my $wrapper = "$exec_path/hmmsearch_wrapper.pl";
my $logger = get_logger(__PACKAGE__);


=item $obj->do_htab();

B<Description:> It appends an additional stage onto the
HTC hmmsearch job to perform the htab post processing on the hits files.

B<Parameters:> None.

B<Returns:> None.

=cut

sub do_htab {
    $logger->debug("In do_htab.");

    my ($self, @args) = @_;
    my $group = $self->{group};
    my $htab_request = TIGR::HTCRequest->new(group => $group);

    $htab_request->command($wrapper);
    $htab_request->add_param("htab");
    $htab_request->initialdir( $self->outdir() );
    # Name this command...
    $htab_request->name("htab");

    $htab_request->output("results.htab");
    $htab_request->error("htab_post_processing.err");

    $htab_request->submit();
    if ($self->wait()) {
        $logger->info("Waiting for htab processing completion.");
        $htab_request->wait_for_request();
    }
}

=item $obj->_init;

B<Description:> This is a private method to initialize the
newly created HMM request object. All required object attributes that
are particular to HMM searches are set here, with certain defaults
as backup in case a client script or user did not specify them.

B<Parameters:> None.

B<Returns:> None.

=cut

sub _init {
    $logger->debug("In _init.");
    my ($self, @args) = @_;

    if ( @args && (ref($args[0]) eq "HASH") ) {
        $self = $args[0];
    } else {
        my %opts = @args;
        map { $self->{$_} = $opts{ $_ } } keys %opts;
    }

    my $group = $self->{group};
    if ( defined($group) && (ref(\$group) eq "SCALAR") ) {
        $self->{request} = TIGR::HTCRequest->new(group => $group);
    } else {
        $logger->logcroak("Group parameter is required.");
    }

    $self->{blocksize} ||= 10; # Default blocksize
    $self->{sequence} or $logger->logcroak("No sequence provided.");

    unless ( exists($self->{htab}) ) {
        $self->{htab} = 0;     # Default: Do not perform htab.
    }

    # Get the outdir and strip out excess slashes.
    if (exists($self->{outdir}) && defined($self->{outdir})) {
        my $outdir = $self->{outdir};
        chomp ($outdir);
        $outdir =~ s|/+$||;
        $self->{outdir} = $outdir;
    }
    $self->{_prepared} = 0;
}


=item $obj->database(@db_list|$dblist_arrayref);

B<Description:> This method sets builds the object profile database
in preparatin for job submission.

B<Parameters:> An array, or array reference of profile names.

B<Returns:> None.

=cut

sub database {
    $logger->debug("In database.");
    my ($self, @args) = @_;
    if (@args) { 
        if (exists($self->{_prepared}) && defined($self->{_prepared}) &&
            ($self->{_prepared} == 1) ) {
            $logger->error("Database already prepared.");
        } else {
            if ((scalar(@args) == 1) && (ref($args[0]) eq "ARRAY")) {
                $logger->debug("A reference to an array was provided.");
                $self->{db} = $args[0];
            } else {
                $logger->debug("A list was provided.");
                $self->{db} = \@args;
            }

            $self->_prepare;
        }
    } else {
        return wantarray ? @{$self->{db}} : $self->{db};
    }
}


=item $obj->_queue_size;

B<Description:> This is a private method to calculate how
many HTC jobs are required to complete the hmmsearch. The
two figures required to determine this number are the number
of files in the database (number of profiles) and the blocksize,
or how many profiles should each job process against the sequence
file. Both the database size and the blocksize are controlled
by the user.

B<Parameters:> None.

B<Returns:> $queue_size.

=cut

sub _queue_size {
    $logger->debug("In _queue_size.");
    my ($self, @args) = @_;
    my $list_length;
    my $db_ref = $self->database();
    if (defined($db_ref) && (ref($db_ref) eq "ARRAY") && scalar(@$db_ref) ) {
        $list_length = scalar(@$db_ref);
    } else {
        $logger->logcroak("Must set the database! There are no files " ,
                          "in the database yet.");
    }

    my $blocksize = int($self->blocksize);
    $logger->logcroak("Illegal blocksize. Must be a positive integer.")
       unless ($blocksize > 0); 
    my $queue_size = ceil($list_length / $blocksize);
    $logger->debug("Queue size: $queue_size.");
    return $queue_size;
}


=item $obj->_validate;

B<Description:> This is a private method to check the existence
and validity of all required parameters. Tests such as file existence,
NFS mounting/availability are done before a job is submitted to
the HTC infrastruture.

B<Parameters:> None.

B<Returns:> In scalar context, the number of errors is returned,
and in list context, a list of the specific error conditions is returned. 

=cut

sub _validate {
    $logger->debug("In _validate.");
    my ($self, @args) = @_;
    my @errors;

    my $outdir = $self->outdir;
    if ((!defined($outdir)) or ($outdir eq "")) {
        push (@errors, "Output directory 'outdir' is not set correctly.");
    }
    if (! -d $outdir) {
        push (@errors, "Output directory does not exist " .
                       "or is not a directory.");
    }
    unless (-R $outdir && -W $outdir) {
        push (@errors, "Output directory is not readable and writable.");
    }

    my $db_ref = $self->database();
    unless ( defined($db_ref) && (ref($db_ref) eq "ARRAY") &&
             scalar(@$db_ref) ) {
        push (@errors, "Number of database files is zero. ",
                       "Check the database parameter.");
    }

    my $group = $self->group;
    unless ($group) {
        push (@errors, "Group to associate the job with must be specified.");
    }

    my $sequence = $self->sequence;
    $logger->debug("Checking if sequence file $sequence passes NFS test.");
    if ($sequence) {
        unless ($self->isNFS($sequence)) {
            push (@errors, "Sequence file not NFS mounted.");
        } 
    } else {
        push (@errors, "Must specify sequence file.");
    } 
 
    return wantarray ? @errors : scalar(@errors); 
}


=item $obj->blocksize([$blocksize]);

B<Description:> A method to get or set the blocksize to use for the 
HTC hmmsearch. The blocksize specifies how many profiles from the 
profile database to analyze on each machine in the HTC infrastructure.

B<Parameters:> An optional positive integer argument can be specified to
set or reset the blocksize.

B<Returns:> $blocksize.

=cut

sub blocksize {
    $logger->debug("In blocksize.");
    my ($self, @args) = @_;
    if (scalar(@args)) {
        my $blocksize = $args[0];
        $blocksize =~ tr/0-9//cd;
        if ($blocksize == 0) {
            $logger->logcroak("Blocksize cannot be set to 0.");
        }
        $self->{blocksize} = int($blocksize);
    } else {
        $self->{blocksize};
    }
}


=item $obj->htab([$htab]);

B<Description:> A method to get or set the htab pos-processing flag
that determines whether htab will be performed on the results of the
hmmsearches (hits files).    

B<Parameters:> Any value that evaluates to 'true' will set the flag
to 1, or "true". A value that evalutes to 'false' will set the flag
to 0, or "false". 

B<Returns:> $htab.

=cut

sub htab {
    $logger->debug("In htab.");
    my ($self, @args) = @_;
    if (scalar(@args)) {
        $self->{htab} = ($args[0]) ? 1 : 0;
    } else {
        $self->{htab};
    }
}


=item $obj->_prepare;

B<Description:> Assemble the job for execution on the
HTC infrastructure.

B<Parameters:> None.

B<Returns:> None.

=cut

sub _prepare {
    $logger->debug("In prepare.");
    my ($self, @args) = @_;

    my $queue = $self->_queue_size;

    my $r = $self->request;

    $r->command($wrapper);
    $r->opsys("Linux");
    $r->name("phmmsearch");

    my $outdir = $self->outdir();
    $r->initialdir($outdir);

    $r->times($queue);

    # Add the parameters to the command
    my $db_ref = $self->database; 

    # Hidden file, with 12 hex char.
    my $filelist = "$outdir/" . '.' . unpack("H*", pack("Nn", time, $$));
    open(TEMP, ">", $filelist) or
        $logger->logcroak("Could not open temporary file for writing. $!");
    foreach my $db_file ( @{ $db_ref }) {
        print TEMP ("$db_file\n");
    }
    close TEMP or
        $logger->logcroak("Could not close temporary file for writing. $!");

    $r->add_param( $filelist );
    $r->add_param("\$(Index)");
    $r->add_param( $self->blocksize );
    $r->add_param( $self->sequence );

    # Add htab post processing command block if user requested htab processing.
    # Since we do not yet have a way in the HTC modules of specifying multiple
    # commands in the XML, we will modify the XML manually in the do_htab method
    # until the API supports doing it "the right way".
    $self->do_htab() if $self->htab;

    my @errs = $self->_validate();
    if (@errs) {
        $logger->logcroak("Errors:\n", join("\n", @errs));
    }

    # Establish where errors will be going.
    my $errdir = "$outdir/.stderr";
    if (! -d $errdir) {
        $logger->debug("Making error file directory ($errdir).");
        my $mk_result = mkdir("$outdir/.stderr");
        unless ($mk_result) {
            my $msg = "Could not make error directory $errdir.";
            $logger->logcroak("$msg: $!");
        }
    } elsif (! -w $errdir) {
        $logger->logcroak("Error directory, $errdir, is not writable.");
    }

    $r->error("$errdir/stderr.\$(Index).log");

    if ($logger->is_debug()) {
        $logger->debug("\n----------------",
                       $r->to_xml(),
                       "\n----------------");
    }

    # Set the prepared flag.
    $self->{_prepared} = 1;
}


=item $obj->sequence([$path_to_sequence_file]);

B<Description:> Get or set the sequence file to use when
performing hmmsearches on the HTC infrastructure. No checking
is done when the sequence file is set with this method, as
all checking is done when the job is submitted with the
private _validate method.

B<Parameters:> None.

B<Returns:> None.

=cut

sub sequence {
    $logger->debug("In sequence.");
    my ($self, @args) = @_;
    if (scalar(@args)) {
        $self->{sequence} = $args[0];
    } else {
        return $self->{sequence};
    }
}


=item $obj->submit;

B<Description:> Submits the job descriptor (in the "job" object
attribute) to the HTC infrastructure. In the case of hmmsearches,
a file containing the list of profiles to analyze is first saved
with this method. The method then calls the parent submit method. 

B<Parameters:> None.

B<Returns:> None.

=cut

sub submit {
    $logger->debug("In submit.");
    my ($self, @args) = @_;

    $logger->info("Submitting request.");
    my $id = $self->request->submit();
    unless ( defined($id) && ($id > 0) ) {
        $logger->logcroak("Problem submitting request to HTC server ",
                          "(Bad ID returned).");
    }

    $logger->info("Received HTC request ID: $id.");
    
    if ($self->wait) {
        $logger->info("Waiting (blocking until finished).");
        $self->request->wait_for_request();
    }


    my $message = $self->request->get_message() || "";
    my $state = $self->request->get_state();

    $logger->info("Request ID: $id.");
    if ($state eq 'FAILED') {
        $logger->error("Request \"$id\" failed. Reason: $message.");
    } else {
        $logger->info("For id $id: State => $state. Message => $message.");
    }

    return $id;
}

sub wait {
    my ($self, $wait) = @_;
    if ($wait) {
        $self->{wait} = 1;
    } else {
        return $self->{wait};
    }
}

sub outdir {
    my ($self, $outdir) = @_;
    if ($outdir) {
        $self->{outdir} = $outdir;
    } else {
        return $self->{outdir};
    }
}

sub request { $_[0]->{request} }

1;            # For the use or require to succeed;

__END__

=back

=head1 ENVIRONMENT

SYBASE must be set properly for htab post-processing to work
correctly.

=head1 DIAGNOSTICS

=over 4

=item "Core dumps occur when htab post-processing is requested."

When htab post-processing is specified, a separate HTC job is
launched to do the work. The executable is TIGR's
htab.pl script, which uses DBI to connect to Sybase. However,
to connect, certain environment variables must be set properly.
These environment variables are passed through
to TIGR's HTC infrastructure to run htab.pl properly, so if 
your SYBASE environment variable points to the wrong location,
you may see core dumps when htab is launched.

=back

=head1 BUGS

No bugs are known at this time. Please submit any that you discover to
antware@tigr.org.

=head1 SEE ALSO

 TIGR::HTCRequest
 Log::Log4perl
 
=head1 AUTHOR(S)

 The Institute for Genomic Research
 9712 Medical Center Drive
 Rockville, MD 20850

=head1 COPYRIGHT

Copyright (c) 2002-2003, The Institute for Genomic Research. All Rights Reserved.
