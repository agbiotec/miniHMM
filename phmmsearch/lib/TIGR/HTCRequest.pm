package TIGR::HTCRequest;

# $Id: HTCRequest.pm 8367 2006-04-11 10:27:35 -0400 (Tue, 11 Apr 2006) vfelix $

=head1 NAME

HTCRequest.pm - An API for submitting jobs to the Distributed Computing
Environment.

=head1 VERSION

This document refers to HTCRequest.pm $Revision: 8367 $.

=head1 SYNOPSIS

 use lib qw(/home/sgeworker/lib);
 use TIGR::HTCRequest;
 my $request = TIGR::HTCRequest->new( group => "mygroup" );

 $request->times(2);
 $request->command("/usr/local/common/executable");
 $request->initialdir("/usr/local/devel/project");
 $request->error("/usr/local/devel/project/stderr.err");

 # Note, most of the methods in this module may also be called
 # with get_ and set_ prefixes. For example, the above code would
 # also have worked if coded like so:

 $request->set_times(2);
 $request->set_command("/usr/local/common/executable");
 $request->set_initialdir("/usr/local/devel/project");
 $request->set_error("/usr/local/devel/project/stderr.err");

 # When retrieving information (accessor behavior), you can call
 # such methods with no arguments to return the information, or
 # the get_ may be prepended. For example:

 my $times = $request->times();
 my $times_another_way = $request->get_times();
 # Please note that calling the get version of a method and
 # providing arguments does not make sense and will likely, not work...

 # WRONG
 my $times_wrong_way = $request->get_times(3);

 # Finally, submit the request...
 my $id = $request->submit();
 print "The ID for this request is $id.\n";

 # ...and wait for the results. This step is not necessary, only
 # if you wish to block, or wait for the request to complete before
 # moving on to other tasks.
 $request->wait_for_request();

 exit;

=head1 DESCRIPTION

An API for submitting jobs to the Distributed Computing Environment.

=head1 CONSTRUCTOR AND INITIALIZATION

=over 4

=item TIGR::HTCRequest->new(%args);

B<Description:> This is the object constructor. Parameters are passed to
the constructor in the form of a hash. Examples:

  my $req = TIGR::HTCRequest->new( group => "Somegroup" );

  or

  my $req = TIGR::HTCRequest->new( group => "Somegroup",
                                   opsys => "Linux",
                                   initialdir => "/path/to/initialdir",
                                   output     => "/path/to/output",
                                   times      => 5,
                                 );

By default, a global configuration describing where to submit the request
and what the location of the Log::Log4perl configuration file is used. Users
may override this behavior by supplying their own configuration file with the
config" parameter:

  my $req = TIGR::HTCRequest->new( group => "mygroup",
                                   config => "/home/user/request.conf",
                                 );

The file must have a [request] header in standard INI nototation, and must
define the URI and Log4PerlConf attributes. The Log4PerlConf attribute should
be set to a path to a valid Log4perl configuration file. See Log::Log4perl for
further details on how to set one up.

Finally, users may add a "debug" flag to the constructor call for increased
reporting:

  my $req = TIGR::HTCRequest->new( group => "mygroup",
                                   debug => 1,
                                 );

B<Parameters:> Only the group parameter is mandatory when calling the
constructor.

B<Returns:> $obj, a HTCRequest object.

=back

=head2 Class and object methods

=over 4

=cut


use strict;
use Data::Dumper;
use Config::IniFiles;
use Carp;
use Log::Log4perl qw(get_logger);
#use lib "/home/condor/development/request/lib";
use TIGR::HTC;
use TIGR::HTCRequest::Command;
use TIGR::HTCRequest::CommandStatus;
use TIGR::HTCRequest::ProxyServer;

use vars qw($AUTOLOAD);
# These will be holders for the various method names so we can identify
# what class to route the calls to.
my (%comm_meths, %status_meths, %proxy_meths);

# These are package variables.
# $config will hold the location of the configuration file that configures
# the server to use, logger configuration, etc... The user may specify it
# with a "config" parameter in the constructor, or it will default to
# /home/condor/etc/request.conf.
my ($config, $debug, $default_config, $logger);
$default_config = TIGR::HTC->config();
my $command_element = 0;

our $VERSION = qw$Revision: 8367 $[1];

# This may or may not be used for dependency tracking in the future.
our @DEPEND = qw(Config::IniFiles IO::Scalar Log::Log4perl
                 TIGR::HTCRequest::Command TIGR::HTCRequest::ProxyServer
                 TIGR::HTCRequest::CommandStatus XML::Writer
                );

# Avoid ugly warnings about single usage.
if ($^W) {
    @DEPEND = @DEPEND;
    $VERSION = $VERSION;
}

BEGIN: {
    require 5.006_00; # Make sure we're not running some old Perl.

    # Here we set up which methods go where. This information is of vital
    # importance, as two hashes are created that 
    my @command_meths = qw(add_anon_param add_param class cmd_type command
                           email end_time getenv group error hosts initialdir
                           input length log_location max_workers memory 
                           name notify_script opsys output pass_through params
                           priority start_time state times username runtime evictable
                           );

    my @status_meths = qw(completed errors message return_values running
                          waiting);
    my @proxy_meths = qw(max_time monitor_host);

    # TODO: Use Hash::Util when it is available) to make hashes that cannot
    # later be modified.
    # Create the hash lookups for the methods so we know how to route later.
    %comm_meths = map { $_ => 1 } @command_meths;
    %status_meths = map { $_ => 1 } @status_meths;
    %proxy_meths = map { $_ => 1 } @proxy_meths;
}


sub new {
    my ($class, %args) = @_;
    my $self = bless [], $class || ref($class);

    my $mapper = sub {
        my @meths = @_;
        my %hash;
        foreach my $meth (@meths) {
            if ( exists($args{$meth}) && defined($args{$meth}) ) {
                $hash{$meth} = $args{$meth};
            }
        }
        return \%hash;
    };

    # Here we separate our arguments to route them to the right class.
    my $command_args = $mapper->( sort keys %comm_meths );
    my $status_args = $mapper->( sort keys %status_meths );

    $config = $args{config} || $default_config;
    $debug = $args{debug} || 0;
    
    $self->_init($command_args, $status_args);
    return $self;
}

sub _init {
    # Initialize the HTCRequest object. We need to parse the configuration
    # file, initialize the logger, create the Command and CommandStatus
    # objects and ProxyServer (event listener), among other things.
    my ($self, $command_args_ref, $status_args_ref, @remaining) = @_;
    die "Initialization failed. Too many arguments, stopped" if @remaining;
    $self->_submitted(0);

    # Parse the default config file. Then, check if the user specified their
    # own, and if so, parse that and import the values from the default
    # config. The default config has information about where to create
    # temporary files and other information that user configuration files do
    # not need (or should) know about.

        # TODO: Since TIGR::HTC already parsed the default config file, use
        # an accessor to get that config object rather than reparsing it
        # here. This will involve adding an additional method in TIGR::HTC.
    my $default_cfg_obj = Config::IniFiles->new( -file => $default_config );
    my ($cfg, $same_configs);
    if ($config eq $default_config) {
        $same_configs = 1;
        $cfg = $default_cfg_obj;
    } else {
        $cfg = Config::IniFiles->new(-file   => $config,
                                     -import => $default_cfg_obj);
    }

    # The [section] heading in the configuration file.
    my $section = "request";
    # Parse the location of the logger configuration and initialize
    # Log4perl if it has not already been initialized.
    # TODO: More recent versions of Log4perl support the init_once method,
    # which does the same chack...
    unless (Log::Log4perl->initialized()) {
        my $logger_conf = $cfg->val($section, "Log4perlConf");
        Log::Log4perl::init($logger_conf);
    }

    # The currently installed version of Log::Log4perl (0.34) exhibits
    # a problem when you check the return value of init. Per the perldoc
    # documentation, you should be able to do an "or die..." on the init
    # call, but it fails every time then. Check later releases, and if it's
    # fixed, install and uncomment the next line.
    # or croak "Could not initialize logging with $logger_conf.";
    $logger = get_logger(__PACKAGE__);

    my $uri = $cfg->val($section, "URI");
    unless (defined($uri)) {
        $logger->logcroak("No URI in the $config configuration file.");
    }


    $logger->info("Creating the first Command object.");
    $self->[0]->[$command_element] =
        TIGR::HTCRequest::Command->new( %$command_args_ref);

    $logger->info("Creating CommandStatus object.");
    $self->[1] = TIGR::HTCRequest::CommandStatus->new();
    $logger->info("Creating ProxyServer.");
    $logger->debug("\tWeb service URI: $uri.");
    $self->[2] = TIGR::HTCRequest::ProxyServer->new( uri => $uri, debug => $debug);

    my $maxtime = $cfg->val($section, "max_time");
    if (defined($maxtime) && ($maxtime !~ m/\D/) ) {
        $logger->debug("Setting maxtime to $maxtime.");
        $self->[2]->max_time($maxtime);
    } else {
        # We have to remember, the max_time could be defined in the default config file
        # and not in the user supplied config file. As long as it's defined somewhere...
        # Lets show what the possibilities are.
        my $config_list = $default_config;
        if ($same_configs != 1) { # The configs are different (default was imported).
            $config_list .= " or $config";
        }
        $logger->logdie("The max_time parameter is not defined in $config_list.");
    }

    $self->[3] = 0;     # For the submitted flag.
    $self->[4] = $cfg;  # For the configuration object.
    $self->[5] = [];    # To hold the environment.
    $self->[6] = 0;     # For simulate.
    $self->[7] = undef; # For the submit_url.
    $self->[8] = ""     # For the XML representation.
}

# Accessors (private) used to return the Command, CommandStatus, ProxyServer,
# and Config objects, .
sub _com_obj { return $_[0]->[0]->[$command_element]; }
sub _com_status { return $_[0]->[1]; }
sub _config { return $_[0]->[4]; }
sub _proxy { $_[0]->[2]; } 

# Some more private methods.
sub _get_env_list {
    $logger->debug("In get_env_list");
    my $self = shift;
    # If the environment hasn't yet been determined, determine it and
    # store it in element 6 (number 5).
    if (scalar(@{ $self->[5] }) == 0) {
	my @temp_env;

	foreach my $key (keys %ENV) {
	    my $value = $ENV{$key};
	    if((index($key, ";") == -1) && (index($value, ";") == -1)) {
		push (@temp_env, "$key=$value");
	    }
	}
	$self->[5] = \@temp_env;
    }

    # Return either the list or the reference depending on the context.
    return wantarray ? @{ $self->[5] } : $self->[5];
}

sub _submitted {
    my ($self, $submitted) = @_;
    if (defined($submitted)) {
        $self->[3] = ($submitted) ? 1 : 0;
    } else {
        return $self->[3];
    }
}

sub set_submit_url {
    my ($self, @args) = @_;
    $self->submit_url(@args);
}

sub get_submit_url {
    my ($self, @args) = @_;
    return $self->submit_url(@args);
}

sub submit_url {
    $logger->debug("In submit_url.");
    my ($self, $submit_url, @args) = @_;

    if (defined $submit_url) {
        $logger->warn("The submit_url method takes only one argument ",
                      "when making an assignment.") if @args;
        $self->[7] = $submit_url;
    } else {
        return $self->[7];
    }
}

# This is invoked before submit and submit_and_wait
sub _validate {
    my $self = shift;
    $logger->debug("In _validate.");

    my $username = $self->username();
    $logger->debug("Checking username.");
    my $uid = getpwnam($username);

    my $rv = 1;
    # Make sure the user is real and that it is not root (root has $id of 0).
    if (defined($uid) && ($uid > 0)) {
        $logger->debug("Username is good.");
    } else {
        $logger->fatal("Bad username: $username.");
        $rv = 0;
    }

    $logger->debug("Returning $rv.");
    return $rv;
}


# This method knows how to dispatch method invocations to the proper module
# or class by checking the name against the hashes set up early in this
# module. The hashes are used to look up which methods go where.
sub AUTOLOAD {
    my ($self, @args) = @_;
    my $method = (split(/::/, $AUTOLOAD))[-1];
    my $set = 0;
    if (($method =~ m/^set_/) || (@args && $method !~ m/^get_/)) {
        $set = 1;
    }
    $method =~ s/^(s|g)et_//;

    if ( $comm_meths{$method} ) {
        $logger->debug("Received a Command method: $method.");
	if ($set) {
	    if (! $self->_submitted ) {
                $self->_com_obj->$method(@args);
	    } else {
		$logger->logcroak("Cannot change a Command object after submission.");
	    }
	} else {
	    $self->_com_obj->$method;
	}
	
    } elsif ( $status_meths{$method} ) {
        $logger->debug("Received a CommandStatus method.");
        $self->_com_status->$method(@args);
    } elsif ( $proxy_meths{$method} ) {
        $logger->debug("Received a ProxyServer method.");
        $self->_proxy->$method(@args);
    } else {
        $logger->logcroak("No such method: $AUTOLOAD.");
    }
}

# We need the DESTROY method because we are using AUTOLOAD. Otherwise,
# the autoload mechanism will fail because it cannot find a DESTROY
# method. Don't modify or remove unless you know what you are doing.
sub DESTROY { }

sub set_id {
    my ($self, @args) = @_;
    $self->id(@args);
}

sub get_id {
    my ($self, @args) = @_;
    return $self->id(@args);
}


=item $obj->id([id]);

B<Description:> This method functions primarily as a getter, but is used by
the set the request ID after it has been submitted.

B<Parameters:> None.
B<Returns:> The request ID. If the command has not been submitted, the
method returns undef.

=cut

# The ProxyServer module may use this method as a setter to set the request
# ID, in which case it should pass the integer ID as the sole argument.
# Only the ProxyServer should be able to set this object attribute.
sub id {
    $logger->debug("In id");
    my ($self, $id, @args) = @_;
    my $rv = undef;

    $logger->warn("The id method takes only one argument ",
                  "when making an assignment.") if @args;

    if (defined $id) {
        $logger->debug("An ID of $id was provided.");
	$self->_com_obj->id($id);
    } else {
        $rv = $self->_com_obj->id();
    }
    return $rv;
}

=item $obj->add_anon_param(@strings);

B<Description:> This method is similar to the add_param method, however,
no additional logic is done to the parameters provided. The user simply
adds the parameters by passing a list of strings, and they will be added
as parameters to the command line in the same order with no validation.

B<Parameters:> @strings, a list of strings representing command line options.

B<Returns:> None.


=item $obj->add_param( $arg1[, $arg2[, $arg3]] | named params );

B<Description:> This method allows users to add parameters to a command
object. It should be noted that the order in which parameters are added will
be preserved when the command is assembled for execution. Users should use
this method when the executable they wish to run takes various command line
options.

B<Parameters:> If the number of arguments is 1, then it will be considered to
be a "value". If 2 arguments are passed, then they are interpreted as "key",
"value". This is used in situations such as when a command line takes a
parameter of the form:

    key=value

If 3 parameters are passed, then they are read as "key", "value", "type".
The type can be either "ARRAY", "DIR", "PARAM", "FILE", "FASTAFILE", or
"TEMPFILE" (the default is "PARAM" when less than 3 arguments are passed).
The type is used in the following way to aid in the parallelization of
processes: If ARRAY is used, the job will be iterated over the elements of the
array, with the value of the parameter being changed to the next element of the
array each time. The array must be an array of simple strings passed in as an
array reference to VALUE. Newlines will be stripped. Note: Nested data
structures will not be respected.
If DIR is specified, the file contents of the directory will be iterated over.
If a directory contains 25 files, then there will be at least 25 jobs, with
the name of each file being a parameter value for each invocation.
If FILE is specified, then the VALUE specified in the method call will be
interpreted as the path to a file containing entries to iterate over. The file
may contain hundreds of entries (1 per line) to generate a corresponding number
of jobs.
TEMPFILE works similarly to FILE, except that the HTC system will delete, or
clean up the file when the request has finished being processed. Use with
caustion.
If FASTAFILE is specified, the job will iterate over each entry in the FASTA
file. 50 entries will yield 50 jobs, and so forth.
Finally, PARAM, the default type, provides simple parameter support and no
iteration will occur.

If the user prefers greater flexibility, he may wish to pass named parameters
in a hash reference instead, in any order, or combination, as long as the
"value" key is specified:

  $obj->add_param( { key   => "--someparam",
                     value => "somevalue",
                     type  => "DIR",
                   }
                 );

The 3 supported keys are case insensitive, so "KEY", "Value" and "tYpE" are
also valid. Unrecognized keys will generate warnings.

If more then 3 arguments are passed to the method an error occurs.

B<Returns:> None.

=cut

sub add_param {
    $logger->debug("In add_param.");
    my ($self, @args) = @_;

    # This is just a function to set the temporary directory on the
    # command object. It's necessary when the user calls add_param with
    # a type of "ARRAY". The temp dir is the location where each element
    # of the array is written to a file.
    my $tempdir_setter = sub {
        $logger->debug("Getting the configuration object.");
        my $cfg = $self->_config();
        $logger->debug("Setting the temporary directory ",
                       "on the command object.");
        my $tempdir = $cfg->val("system", "tempdir");
        $self->_com_obj->tempdir($tempdir);
    };

    if ( (@args == 1) && (ref($args[0]) eq "HASH") ) {
        foreach my $key ( keys %{ $args[0] } ) {
            if ( (uc($key) eq "TYPE") && (uc($args[0]->{type}) eq "ARRAY") ) {
                $tempdir_setter->();
            }
        }
    } elsif ( (@args == 3) && ($args[2] eq "ARRAY") ) {
        $tempdir_setter->();
    }
    my $return = $self->_com_obj->add_param(@args);
    return $return;
}


=item $obj->id();

B<Description:> Returns the request's ID after it has been submitted. 

B<Parameters:> None.

B<Returns:> The request object's ID. If the request has not been submitted, the
method returns undef.


=item $obj->class([$class]);

B<Description:> This method is used to set and retrieve the request's
class attribute. A request's class describes the its general purpose or
what it will be used for. For example, a command can be marked as a request
for "assembly" or "workflow". Ad hoc requests will generally not use a class
setting. If in doubt, leave the class attribute unset.

B<Parameters:> With no parameters, this method functions as a getter. With one
parameter, the method sets the request's class. No validation is
performed on the class passed in.

B<Returns:> The currently set class (when called with no arguments).


=item $obj->command([$command]);

B<Description:> This method is used to set or retrieve the executable that
will be called for the request.

B<Parameters:> With no parameters, this method functions as a getter. With one
parameter, the method sets the executable. Currently, this module does not
attempt to verify whether the exeutable is actually present or whether
permissions on the executable allow it to be called by the DCE.

B<Returns:> The currently set executable (when called with no arguments).


=item $obj->email([$command]);

B<Description:> This method is used to set or retrieve the email of the user
submitting the request. The email is important for notifications and for
tracking purposes in case something goes wrong.

B<Parameters:> With no parameters, this method functions as a getter and
returns the currently configured email address. If the request has not yet
been submitted, the user may set or reset the email address by providing an
argument. The address is not currently validated for RFC compliance.

B<Returns:> The email address currently set, or undef if unset (when called
with no arguments).


=item $obj->end_time()

B<Description:> Retrieve the finish time of the request.

B<Parameters:> None.

B<Returns:> The ending time of the request (the time the DCE finished
processing the request), or undef if the end_time has not yet been
established.


=item $obj->error([errorfile])

B<Description:> This method allows the user to set, or if the request has
not yet been submitted, to reset the error file. The error file will be the
place where all STDERR from the invocation of the executable
will be written to. This file should be in a globally accessible location on the
filesystem. The attribute may not be changed with this method once the
request has been submitted.

B<Parameters:> To set the error file, call this method with one parameter,
which should be the path to the file where STDERR is to be written.

B<Returns:> When called with no arguments, this method returns the currently
set error file, or undef if not yet set.


=item $obj->getenv([1]);

B<Description:> The getenv method is used to set whether the user's
environment should be replicated to the DCE or not. To replicate your
environment, call this method with an argument that evaluates to true.
Calling it with a 0 argument, or an expression that evaluates to false,
will turn off environment replication. The default is NOT to replicate
the user environment across the DCE.

B<Parameters:> This method behaves as a getter when called with no arguments.
If called with 1, or more arguments, the first will be used to set the
attribute to either 1 or 0.

B<Returns:> The current setting for getenv (if called with no arguments).


=item $obj->group([group]);

B<Description:> The group attribute is used to affiliate usage of the
Distributed Computing Environment (DCE) with a particular administrative
group at TIGR. This will allow for more effective control and allocation
of resources, especially when high priority projects must be fulfilled.
Therefore, the "group" is mandatory when the request object is built.
However, the user may still change the group attribute as long as the
job has not yet been submitted (after submission most attributes are
locked). Currently, the group setting is not validated, but
may be sometime in the future. Please consult the ANTware team at
antware@tigr.org if you have a question about what you should use for "group".

B<Parameters:> The first parameter will be used to set (or reset)
the group attribute for the request, as long as the request has not
been submitted.

B<Returns:> The currently set group (if called with no parameters).


=item $obj->input([path]);

B<Description:>

B<Parameters:>

B<Returns:>


=item $obj->initialdir([path]);

B<Description:> This method sets the directory where the DCE will be
chdir'd to before invoking the executable. This is an optional parameter,
and if the user leaves it unspecified, the default will be that the DCE
will be chdir'd to the root directory "/" before beginning the request.
Use of initialdir is encouraged to promote use of relative paths.

B<Parameters:> A scalar holding the path to the directory the DCE should
chdir to before invoking the executable.

B<Returns:> When called with no arguments, returns the currently set
initialdir, or undef if not yet set.


=item $obj->length([length]);

B<Description:> This method is used to characterize how long the request
is expected to take to complete. For long running requests, an attempt to
match appropriate resources is made. If unsure, leave this setting unset.

B<Parameters:> "short", "medium", "long". No attempt is made to validate
the length passed in when used as a setter.

B<Returns:> The currently set length attribute (when called with no
arguments).

=item $obj->name([name]);

B<Description:> The name attribute for request objects is optional and is
provided as a convenience to users of the DCE to name their requests.

B<Parameters:> A scalar name for the request. Note that the name will
be encoded for packaging into XML, so the user is advised to refrain from
using XML sensitivie characters such as > and <.

B<Returns:> When called with no arguments, returns the current name, or
undef if not yet set. The name cannot be changed once a request is submitted.


=item $obj->next_command();

B<Description:> The HTC service allows for requests to encapsulate multiple
commands. This method will finish the current command and create a new one.
Commands are processed in the order in which they are created. In addition,
the only attribute that the new command inherits from the command that
preceded it, is the group. However, Users are free to change the group by
calling the group method...

B<Parameters:> None.

B<Returns:> None.


=item $obj->notify_script([path]);

B<Description:> This method allows the user to register a script or
executable that will run when the request has been completed. It is typically
used to perfrom simply post-processsing or notifications, but may perform
whatever tasks the user wishes. No validation is currently done for the
existence, accessibility and/or usability of the file specified.

B<Parameters:> The path to the script to be invoked after the request has
completed (a scalar). This script should be in a globally accessible location
on the file system or the invocation will fail on the DCE.

B<Returns:> If invoked with no arguments, this method will return the
currently registered path to the script, or undef if not set.


=item $obj->opsys([OS]);

B<Description:> The default operating system that the request will be processed
on is Linux. Users can choose to submit requests to other operating systems in
the DCE by using this method. Available operating systems are "Linux", "Solaris"
and "OSF1". An attempt to set the opsys attribute to anything else results
in an error.

B<Parameters:> "Linux", "Solaris" or "OSF1" when called as a setter (with one
argument).

B<Returns:> When called with no arguments, returns the operating system the
request will run on, which defaults to "Linux".

=item $obj->max_workers([integer]);

B<Description:> Set the maximum number of jobs to run in parallel.  This is a
maximum so less maybe used.  Defaults to 0 meaning no maximum.

B<Parameters:> number of parallel jobs to run at one time.  Fan out.

B<Returns:> When called with no arguments, returns the max workers 


=item $obj->hosts([hostname]);

B<Description:> Used to set a set of possible machines to run the command
on.  If this value is not set then any host that might all other requirements
will be used.  

B<Parameters:> hostname(s), example "firecoral,shrew"

B<Returns:> When called with no arguments, returns the hosts if set.


=item $obj->memory([megabytes]);

B<Description:> Used to set the minimum amount of physical memory needed.

B<Parameters:> memory in megabytes, example 10MB, 512MB

B<Returns:> When called with no arguments, returns the memory if set.


=item $obj->pass_through([pass_value]);

B<Description:> Used to pass strings to the underlying grid technology
(Condor, SunGrid, etc...) as part of the request's requirements. Such pass
trourghs are forwarded unchanged. This is an advanced and should only be used
by those familiar with the the underlying grid architecture.

B<Parameters:> $string

B<Returns:> None.


=item $obj->log_location([path]);

B<Description:> Set or get the location (path) of the request's log file.
The logfile will contain details about the execution of the job on the grid
and my be useful when debugging, checking a request's status, etc...

B<Parameters:> $path

B<Returns:> None, when called as a setter. Returns the $path when called
as a getter.

=cut

sub next_command {
    my $self = shift;

    $logger->debug("Creating Command object in element $command_element.");

    # The only piece of information replicated from command to command is the
    # group. So we first get the group and then use it to build the new
    # Command object.
    my $group = $self->group();

    # Increment element pointer.
    $command_element++;

    $self->[0]->[$command_element] =
        TIGR::HTCRequest::Command->new( group => $group );
}

=item $obj->output([path]);

B<Description:> Sets the path for the output file, which would hold all of
the output directed to STDOUT by the request on the DCE. This method functions
as a setter and getter.

B<Parameters:> A path to a file. The file must be globally accessible on
the filesystem in order to work, otherwise, the location will not be accessible
to compute nodes on the DCE. This attribute may not be changed once a request
is submitted.

B<Returns:> When called with no arguments, the method returns the currently
set path for the output file, or undef if not yet set.


=item $obj->params();

B<Description:> Retrieve the list of currently registered parameters for the
request.

B<Parameters:> None.

B<Returns:> The method returns a list of hash references.


=item $obj->priority([priority]);

B<Description:> Use this method to set the optional priority attribute on the
request. The priority setting is used to help allocate the appropriate
resources to the request. Higher priority requests may displace lower priority
requests.

B<Parameters:> Scalar priority value.

B<Returns:> The current priority, or undef if unset.

=cut

=item $obj->set_env_list(@vars);

B<Description:> This method is used to establish the environment that a
a request to the DCE should run under. Users may pass this method a list
of strings that are in "key=value" format. The keys will be converted into
environment variables set to "value" before execution of the command is
begun. Normally, a request will not copy the user's environment in this way.
The only time the environment is established on the DCE will be if the user
invokes the getenv or sets it with this method. This set_env_list method
allows the user to override the environment with his or her own notion of
what the environment should be.

B<Parameters:> A list of strings in "key=value" format. If any string does
not contain the equals (=) sign, it is skipped and a warning is generated. 

B<Returns:> None.

=cut

sub set_env_list {
    my ($self, @args) = @_;
    my @valid; 
    foreach my $arg (@args) {
        if ($arg !~ /\S+=\S+/) {
            $logger->logcroak("$arg is not a valid environment parameter. Skipping it.");
            next;
        }
        push(@valid, $arg);
    }

    $self->[5] = \@valid;

    # If the user has set their own environment with set_envlist, then we
    # assume that they want getenv to be true. We do it for them here to save
    # them an extra step.
    $self->getenv(1);
}


=item $obj->simulate([value]);

B<Description:> This method is used to toggle the simulate flag for the
request. If this method is passed a true value, the request will not
be submitted to the Distributed Computing Environment, but will appear to
have been submitted. This is most useful in development and testing
environments to conserve resources. When a request marked simulate is
submitted, the request ID returned will be -1. Note that this attribute
cannot be modified once a request is submitted.

B<Parameters:> A true value (such as 1) to mark the request as a simulation.
A false value, or express (such as 0) to mark the request for execution.

B<Returns:> When called with no arguments, this method returns the current
values of the simulate toggle. 1 for simulation, 0 for execution. 

=cut

sub simulate {
    $logger->debug("In simulate.");
    my ($self, $simulate, @args) = @_;
    if (defined($simulate)) {
        $self->[6] = ($simulate) ? 1 : 0;
    } else {
        return $self->[6];
    }
}


=item $obj->start_time([time]);

B<Description:> Retrieve the start time when the request began processing.
Any attempt to set the time will result in an error.

B<Parameters:> None.

B<Returns:> $time, the start time (scalar) that the DCE began processing
the request.


=item $obj->state([state]);

B<Description:> Retrieve the "state" attribute of the request. This method
is "read only" and an attempt to set the state will result in an error.
The states are:

    INIT
    INTERRUPTED
    FAILURE
    FINISHED
    RUNNING
    SUSPENDED
    UNKNOWN
    WAITING

B<Parameters:> None.

B<Returns:> $state, the current state of the request.


=item $obj->stop();

B<Description:> Stop a request that has already been submitted.

B<Parameters:> Request ID (optional)

B<Returns:> None.

=cut

sub stop {
    $logger->debug("In stop.");
    my ($self, $stop_id, @args) = @_;

    if (! defined $stop_id) {
	my $submitted = $self->_submitted;
	if (!$submitted) {
	    $logger->warn("Stop was called on but no request was submitted. Do nothing...");
	    return;
	} else {
	    $logger->debug(" stop call was for self ");
	    $stop_id = $self->get_id();
	    $logger->debug(" call proxy stop ");
	    $self->_proxy->stop($stop_id, $self);
	}
    } else {
	$logger->warn("The stop method takes only one argument.") if @args;
	$logger->debug(" call proxy stop ");
	$self->_proxy->stop($stop_id);
    }
}


=item $obj->submit();

B<Description:> Submit the request to the HTC server for execution
on the Distributed Computing Environment (grid).

B<Parameters:> None.

B<Returns:> The request ID.

=cut

sub submit {
    $logger->debug("In submit.");
    my ($self, @args) = @_;
    my $validate_result = $self->_validate();
    my $id;
    if ($validate_result == 1) {
        $logger->info("Validation process succeeded.");

        my $simulate = $self->simulate;
        if ($simulate) {
            $logger->debug("Simulation is turned on, so do not really submit.");
            $id = -1;
        } else {
            $id = $self->_proxy->submit($self);
        }
        # Set the submitted flag, so we can't submit multiple times.
        $logger->debug("Set the submitted flag to 1.");
        $self->_submitted(1);
    } else {
        $logger->error("Validation failed. Setting id to 0.");
        $id = 0;
    }

    $logger->debug("Returning $id.");
    return $id;
}

=item $obj->submit_and_wait();

B<Description:> Submit the request to the HTC server for execution on the
Distributed Computing Environment (grid) and wait for the request to finish
executing before returning control (block).

B<Parameters:> None.

B<Returns:> $id, the request's id.

=cut

sub submit_and_wait {
    $logger->debug("In submit_and_wait.");
    my ($self, @args) = @_;
    my $validate_result = $self->_validate();
    my $id;
    if ($validate_result == 1) {
        $logger->info("Validation process succeeded.");
        my $simulate = $self->simulate;
        if ($simulate) {
            $logger->debug("Simulation is turned on, so do not really submit.");
            $id = "-1";
        } else {
            $id = $self->_proxy->submit_and_wait($self);
        }
        # Set the submitted flag, so we can't submit multiple times.
        $logger->debug("Set the submitted flag to 1.");
        $self->_submitted(1);
    } else {
        $logger->error("Validation failed. Setting id to 0.");
        $id = 0;
    }

    $logger->debug("Returning $id.");
    return $id;
}


=item $obj->times([times]);

B<Description:> Sometimes it may be desirable to execute a command more than
one time. For instance, a user may choose to run an executable many
times, with each invocation operating on a different input file. This technique
allows for very powerful parallelization of commands. The times method
establishes how many times the executable should be invoked.

B<Parameters:> An integer number may be passed in to set the times attribute on
the request object. If no argument is passed, the method functions as a getter
and returns the currently set "times" attribute, or undef if unset. The setting
cannot be changed after the request has been submitted.

B<Returns:> $times, when called with no arguments.


=item $obj->to_xml();

B<Description:> Requests are packaged into XML before they are submitted. To
inspect the XML produced, users can call this method, which will return the
XML in the form of a string (scalar).

B<Parameters:> None.

B<Returns:> $xml, a string representation of the request object in XML as it
would be transmitted to the DCE.

=cut

sub to_xml {
    my ($self, @args) = @_;
    $logger->debug("In to_xml.");

    require IO::Scalar;
    require XML::Writer;
    my $xml = "";
        
    my $handle = IO::Scalar->new(\$xml);


    my $w= XML::Writer->new( OUTPUT      => $handle,
                             DATA_MODE   => 1,
                             DATA_INDENT => 4
                           );

    $w->xmlDecl();
    $w->comment("Generated by " . __PACKAGE__ . ": " . localtime());
    $w->startTag('commandSetRoot');

    # We de-reference the array reference containing all Command
    # objects, call to_xml() on each of them and use the XML string to
    # build the overall request XML document.

    # NOTE: Currently, the server side code does not support multiple
    # commands, so the array will only contain one element until the
    # funcationality is implemented.
    my $count = 1;
    my $total = scalar( @{ $self->[0] } );
    foreach my $com_obj ( @{ $self->[0] } ) {
        $logger->debug("Encoding command object $count/$total.");
        my $command_xml = $com_obj->to_xml;
        $handle->print($command_xml);
        $count++;
    }

    $w->endTag('commandSetRoot');
    $w->end();

    $handle->close;
    $self->[8] = $xml;

    return $self->[8];
}


=item $obj->username([username]);

B<Description:> This method sets or retrieves the username associated with
the request. The username cannot be modified once the reqeust has been
submitted.

B<Parameters:> A scalar holding the username. Additional arguments
will cause a warning and will be ignored.

B<Returns:> When called with no arguments, returns the currently set
username, or undef if not yet set.

=cut


=item $obj->wait_for_request();

B<Description:> Once a request has been submitted, a user may choose to wait
for the request to complete for proceeding. This is called blocking. To block
and wait for a request, submit it (by calling the submit method) and then
immediately call wait_for_request. Control will return once the request has
been finished (either completed or errored). If an attempt is made to call
this method before the request has been submitted, a warning is generated.

B<Parameters:> None.

B<Returns:> None. 

=cut

sub wait_for_request {
    $logger->debug("In wait_for_request.");
    my ($self, @args) = @_;
    my $return = 0;
    my $submitted = $self->_submitted;
    if ($submitted) {
        $self->_proxy->wait_for_request($self);
        $return = 1;
    } else {
        $logger->logcroak("The request must be submitted before wait_for_request ",
                          "may be called.");
    }
    return $return;
}

=item $obj->monitor_host()

B<Description:> In an effort to perform load balancing, the HTC Service generally
employs multiple servers to accept, process and monitor requests. The method is
provided to allow the caller to easily determine which worker is the monitor for
the request object. Most users will not have a need to use this method.

B<Parameters:> None.

B<Returns:> The hostname of the HTC worker montioring the status and progress
of this request.

=cut

sub monitor_host {
    $logger->debug("In monitor_host.");
    my ($self, @args) = @_;
    my $monitor;
    if ($self->_submitted) {
        $monitor = $self->_proxy->monitor_host($self);
    } else {
        $logger->logcroak("The request must be submitted before monitor_host ",
                          "may be called.");
    }
    return $monitor;
}


=item $obj->get_tasks();

B<Description:> Retrieve the tasks for this request

B<Parameters:> None.

B<Returns:> A hash of hashes (HoH) representing the tasks for this
request. The hash is organized by the task index and the value
is another hashref with the actual values. The following is an example
of the return data structure:

    $hashref = {
              '1' => {
                     'index' => '1',
                     'returnValue' => '0',
                     'message' => {},
                     'state' => 'FINISHED'
                   },
              '2' => {
                     'index' => '2',
                     'returnValue' => '-1',
                     'message' => 'Failed task.',
                     'state' => 'FAILED'
                   }
            }
=cut

sub get_tasks {
    $logger->debug("In get_tasks.");
    my ($self, @args) = @_;
    my $tasks;
    if ($self->_submitted) {
        $tasks = $self->_proxy->get_tasks($self);
    } else {
        $logger->logcroak("The request must be submitted before get_tasks ",
                          "may be called.");
    }
    #$logger->debug(Dumper($tasks));
    return $tasks;
}

1;

__END__

=back

=head1 ENVIRONMENT

This module does not read or set any environment variables by default. It will
however, read and store the entire environment if the private _get_env_list
method is invoked.

=head1 DIAGNOSTICS

=over 4

=item "Initialization failed. Too many arguments."

The object could not be initialized when the constructor was called.
Too many arguments were provided to "new".

=item "No such method: <method name>."

A method that does not exist or is not available was called on the object.

=back

=head1 BUGS

Currently, only one command may be submitted per request. It is not yet
possible to submit sets of commands to run in parallel or serially in
what is known as a CommandSet. In the XML message the CommandSets would
be multiple complex elements within the parent CommandSetRoot element.
There are plans to add this functionality in the future.

=head1 SEE ALSO

 Config::IniFiles
 IO::Scalar
 Log::Log4perl
 TIGR::HTCRequest::Command
 TIGR::HTCRequest::CommandStatus
 TIGR::HTCRequest::ProxyServer
 XML::Writer

=head1 AUTHOR(S)

 The Institute for Genomic Research
 9712 Medical Center Drive
 Rockville, MD 20850

=head1 COPYRIGHT

Copyright (c) 2003-2004, The Institute for Genomic Research. All Rights Reserved.
