package TIGR::HTCRequest::ProxyServer;

# $Id: ProxyServer.pm 8289 2006-03-30 21:13:57Z vfelix $

# Copyright (c) 2003, The Institute for Genomic Research. All rights reserved.

=head1 NAME

ProxyServer.pm - client side proxy for the htcserver.

=head1 VERSION

This document refers to ProxyServer.pm.
$Revision: 8289 $

=head1 SYNOPSIS
    use TIGR::HTCRequest::ProxyServer;

    my $proxy = TIGR::HTCRequest::ProxyServer->new($uri, $debug);
    $proxy->submit_and_wait($request);

=head1 DESCRIPTION

=head2 Overview

 Stub functions that handle client-server communication.  
Allows for the client to send commands to the server and handles event
callbacks to the client from the server.

=head2 Constructor and initialization.

    $proxy = TIGR::HTCRequest::ProxyServer->new($uri, $debug);

=head2 Class and object methods

Class:
    TIGR::HTCRequest::ProxyServer

Methods:
    submit($request)
    submit_and_wait($request)
    wait_for_request($request)

=over 4

=cut

use strict;

# modules needed for XML-RPC.
use Frontier::Client;
use Frontier::RPC2;
use HTTP::Daemon;
use HTTP::Status;
use Data::Dumper;
use XML::Simple;

# TODO: No need to use a hash to store objects after all platforms support
# the Memoize module (should be available with Perl > 5.8.0).
#use Memoize;
#memoize('new');

# Logging
use Log::Log4perl qw(get_logger);
my $logger = get_logger(__PACKAGE__);

our $VERSION = qw$Revision: 8289 $[1];
our @DEPEND = qw(Frontier::Client Frontier::RPC2 HTTP::Daemon HTTP::Status
             Log::Log4perl Data::Dumper XML::Simple);
our $MAXTIME = 8*24*60*60; # 8 days

if ($^W) {
    # Eliminate annoying warnings.
    $VERSION = $VERSION;
    @DEPEND = @DEPEND;
}

# hash of current requests we are accepting events for
my %requests;

our %VALID_ENDSTATE = (
    FAILED        => 1,
    FINISHED      => 1,
    INTERRUPTED   => 1,
    );
my %servers;


=item TIGR::HTCRequest::ProxyServer->new(%args);

B<Description:> This is the proxy server constructor which will only create a 
new object and then return the same object from cache if called subsequently
with the same arguments. Different arguments will result in a new instance
returned.

B<Parameters:> Optional server url where to send commands.  Parameters are
passed to the constructor in the form of a hash. Example:

  my $proxy = TIGR::HTCRequest::ProxyServer->new( uri   => "http://server",
                                                  debug => 0,
                                                );

B<Parameters:> Optional debug which turns on debugging if set to one.

B<Returns:> A proxy server object.

=cut

sub new {
    $logger->debug("in new ProxyServer.");

    # if the singleton has already been created, return it,
    # otherwise create the singleton first
    $logger->debug("In new (constructor).");

    # Initialize variables needed by ProxyServer
    my ($class, %arg) = @_;
    my $server = $arg{uri};
    unless (defined($server)) {
        $logger->fatal("No server URI defined.");
        $logger->logdie("Configuration error. No server URI defined.");
    }

    my $object;
    if (exists($servers{$server})) {
        $object = $servers{$server};
    } else {
        $logger->debug("Server URI: $server.");
        my $debug =  $arg{debug} || 0;
        my $response = new HTTP::Response 200;
        $response->header('Content-Type' => 'text/xml');
        my $decode = Frontier::RPC2->new();

        $logger->debug("Trying to create a new HTTP daemon.");
        my $daemon = HTTP::Daemon->new();
        $logger->debug("\tCreated HTTP daemon at " . $daemon->url . ".");

        #
        # methods to register that handle command events
        my $methods = { 
            "Request.commandStarted" => \&commandStarted,
            "Request.commandSuspended" => \&commandSuspended,
            "Request.commandFinished" => \&commandFinished,
            "Request.commandFailed" => \&commandFailed,
            "Request.commandSubmitted" => \&commandSubmitted,
            "Request.commandInterrupted" => \&commandInterrupted,
            "Request.commandResumed" => \&commandResumed,
            "Request.getIDs" => \&getIDs,
        };

        # create proxyserver object
        $object = bless {
            server_url => $server,
            client => Frontier::Client->new(url => $server, debug => $debug),
            methods => $methods,
            response => $response,
            decode => $decode,
            daemon => $daemon,
        }, ref($class) || $class;

        # Store the object in the servers hash so that if we see the
        # server name again, we can just return from the hash instead
        # of creating a whole new object again (Caching). Again, Memoize would
        # do this for us...
        $servers{$server} = $object;
    }
    return $object;
}


=item $proxy->submit($request);

B<Description:> Submit $request to the DCE server.

B<Parameters:> $request, a HTCRequest object or a sub-class that 
supports the same interface.

B<Returns:> $id, id of request submitted

=cut

sub submit {
    $logger->debug("In submit.");
    my ($self, $request) = @_;
    my $id = -1;
    my $result;

    $id = $self->_createCmdID();
    $logger->debug("Setting ID to $id.");
    $request->set_id($id);
    $request->_com_obj->submit_url($self->{daemon}->url() . "RPC2");

    $logger->debug("XML: " . $request->to_xml());
    # check if we should send the environ and then submit
    if($request->get_getenv() ) {
        my @envp = $request->_get_env_list();
        $result = $self->_submit($request->to_xml(), \@envp);
    } else {
        $result = $self->_submit($request->to_xml());
    }

    # check returned id 
    if ($id < 0) {
        $logger->fatal("Job request rejected by $self->{server_url}.",
                       "Request was ", $request->to_xml());
        $request->set_message("Job request rejected by server at ",
                              "$self->{server_url}.");
    }

    return $id;
}

=item $proxy->monitor_host($request);

B<Description:> Retrieve the monitor host for this request

B<Parameters:> $request, a HTCRequest object or a sub-class that 
supports the same interface.

B<Returns:> $host, name of the host monitoring the job

=cut

sub monitor_host {
    $logger->debug("In get_monitor_host.");
    my ($self, $request) = @_;
    my $id = -1;

    $id = $request->id();
    my $host = $self->_monitorHost($id);
    return $host;
}

=item $proxy->get_tasks($request);

B<Description:> Retrieve the tasks for this request

B<Parameters:> $request, a HTCRequest object or a sub-class that 
supports the same interface.

B<Returns:> $task_group, a hash representing the tasks for this
request. The hash is organized by the task index and the value
is another hash with the actual values. The following is an example
of the returned hash.
$VAR1 = {
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
    my ($self, $request) = @_;
    my $id = -1;
    my $host;

    $id = $request->id();
    my $task_group = $self->_getTasks($id);
    $logger->debug(Dumper($task_group));
    return $task_group;
}

=item $proxy->submit_and_wait($request);

B<Description:> Submit $request to the DCE server and wait for it 
to finish.

B<Parameters:> $request, a HTCRequest object or a sub-class that 
supports the same interface.

B<Returns:> $id, id of request submitted

=cut

sub submit_and_wait {
    $logger->debug("In submit_and_wait.");
    my ($self, $request) = @_;

    # submit
    my $id = $self->submit($request);
    $logger->info("Request Submitted. ID is $id");
    # and wait
    $self->wait_for_request($request);

    return $id;
}

=item $proxy->wait_for_request($request);

B<Description:> Wait for $request to finish and return the id of the
request that finished.

B<Parameters:> $request, request to wait for.

B<Returns:> $id, id of request

=cut

sub wait_for_request {
    $logger->debug("In wait_for_request.");
    my ($self, $request) = @_;
    my $id = $request->get_id();
    $logger->debug("Request ID: $id.");

    # first let the server know we are alive and listening
    my $result = 0;
    eval {
        $result = $self->{client}->call('HTCServer.addListener', $self->{daemon}->url() . "RPC2",
                                         $self->{client}->string($id), 1);
        $logger->debug("Result value after call to addListener: $result.");
    };

    if ($@) {
        $logger->logcroak("Unable to register listener: $@");
    } elsif ($result <= 0) {
        # Check the state to make sure the command hasn't already finished. Some commands
        # finish or error so quickly, that the user's subsequent call to addListener will fail
        # as the id has already been dequeued on the server side.
        my $state = $self->{client}->call('HTCServer.status', $id)->{state};
        if ( exists($VALID_ENDSTATE{$state}) && ($VALID_ENDSTATE{$state} == 1) ) {
            $logger->warn("Command has already finished or failed! Cannot wait...");
        } else {
            $logger->logcroak("Command state not finished, but unable to add listener!");
        }
    } else {
        # now wait 
        $logger->debug("Begin waiting for the request.");
        $self->_wait($request);
    }

    return $id;
}


=item $proxy->_submit(@args);

B<Description:> Private submit for internal module use.

B<Parameters:>

B<Returns:>

=cut

sub _submit {
    $logger->debug("In _submit.");
    my ($self, @args) = @_;
    my $result = 0;

    eval {
	$result = $self->{client}->call('HTCServer.submit', @args);
    };
    
    if ($@) {
        $logger->logcroak("Submission failed for $self->{server_url}. ",
                       "Message: $@");
    }

    return $result;
}

=item $proxy->_monitorHost(@args);

B<Description:> Private get monitor host for internal module use.

B<Parameters:>

B<Returns:>

=cut

sub _monitorHost {
    $logger->debug("In _monitorHost.");
    my ($self, $id, @args) = @_;
    my $result = 0;
    # The server side code requires a string version of the id.
    my $stringified_id = $self->{client}->string($id);

    eval {
        $result = $self->{client}->call('HTCServer.monitorHost', $stringified_id);
    };
    
    if ($@) {
        $logger->logcroak("Could not get monitor host failed for $self->{server_url}. ",
                       "Message: $@");
    }

    return $result;
}


=item $proxy->_getTasks(@args);

B<Description:> Private get tasks for internal module use.

B<Parameters:>

B<Returns:>

=cut

sub _getTasks {
    $logger->debug("In _getTasks.");
    my ($self, $id, @args) = @_;
    my $result = 0;
    # The server side code requires a string version of the id.
    my $stringified_id = $self->{client}->string($id);

    eval {
        $result = $self->{client}->call('HTCServer.getTasks', $stringified_id);
    };
    
    if ($@) {
        $logger->logcroak("Could not get tasks failed for $self->{server_url}. ",
                       "Message: $@");
    }

    # Convert from the XML string to a hash or tasks where
    # the the task index forms the key and the value is a has
    # with the following task info keys, 'index', 'returnValue',
    # 'message', 'state'
    my $ref = XMLin($result, ForceArray => 1);
    my %tasks = ();
    my @tks = @{$ref->{task}};
    foreach my $task_ref (@tks) {
        $tasks{$task_ref->{index}} = $task_ref;
    }
    
    #$logger->debug(Dumper(\%tasks));
    return \%tasks;
}

=item $proxy->_createCmdID();

B<Description:> Private 

B<Parameters:>

B<Returns:>

=cut

sub _createCmdID {
    $logger->debug("In _createCmdID.");
    my ($self, @args) = @_;
    my $id = 0;

    eval {
	$id = $self->{client}->call('HTCServer.createCmdID');
    };

    $logger->debug(" created new id = $id");
    

    if ($@) {
        $logger->logcroak("Create command id failed for $self->{server_url}. ",
                       "Message: $@");
    }

    return $id;
}

sub stop {
    my ($self, $stop_id, $request) = @_;
    my $result = undef;

    if (defined($stop_id)) { 
	if (defined($request)) {
	    my $state = $request->_com_obj->state();
	    $logger->debug("In stop for request $stop_id with state = $state");
	    my $id = $request->get_id();

	    if ($id > 0) { # A good ID.
                if ( exists($VALID_ENDSTATE{$state}) && ($VALID_ENDSTATE{$state} == 1) ) {
                    $logger->error("Trying to stop $id when it has already finished: $state.");
                } else {
                    eval {
                        $result = $self->{client}->call('HTCServer.stop', $self->{client}->string($id));
                    };

                    if ($@) {
                        $logger->error("Could not call stop for $id with state $state");
                    }
                }
	    }
	} else { 
	    $logger->debug("In stop for id $stop_id ");
	    eval {
		$result = $self->{client}->call('HTCServer.stop', $self->{client}->string($stop_id));
	    };

	    if ($@) {
		$logger->error("Could not call stop for $stop_id ");
	    }
	}
    } else {
	$logger->error("Incorrect number of arguments to proxy.stop");
    }

    return $result;
}

=item $proxy->_wait($request);

B<Description:> Private wait for internal module use.

B<Parameters:> $request, the request object.

B<Returns:> None.

=cut

sub _wait {
    $logger->debug("In _wait");
    my ($self, $request) = @_;
    my $id = $request->get_id();
    my $conn;

    $logger->debug("Add request($id) to waiting list");
    $requests{$id} = $request;
    
    my $state = $request->_com_obj->state();

    # Let's keep track of when we were started.
    my $starttime = time;

    # keep accepting network connections until the command state is 
    # set to a valid end state
    while (! defined( $VALID_ENDSTATE{ $state }) && ((time - $starttime) <= $MAXTIME) ) {
	if ($conn = $self->{daemon}->accept()) {
	    my $rq = $conn->get_request();
	    if ($rq) {
		if ($rq->method eq 'POST' && $rq->url->path eq '/RPC2') {
		    $self->{response}->content($self->{decode}->serve ($rq->content, $self->{methods}));
		    $conn->send_response($self->{response});
		} else {
		    $conn->send_error(RC_FORBIDDEN);
		}
	    }
	    $conn->close;
	    $conn = undef;
	} else {
	    $logger->fatal("Network connection failed, couldn't create HTTP::Daemon ",  
			   "or accept call failed on Daemon.");
	    $conn->close;
	    $conn = undef;
	    $logger->logcroak("Failed to establish callback network connection.");
	}
	$state = $request->_com_obj->state();
	$logger->debug("Should we continue to wait? - state is $state.");
    }

    $logger->debug("Removing request($id) from waiting list.");
    delete($requests{$id});
}

#
# Listener methods to handle event callbacks 
#

sub commandStarted {
    $logger->debug("In commandStarted.");
    my ($id, $message, $date, $machine) = @_;

    my $request;
    if (exists($requests{$id})) {
        $request = $requests{$id};
        $request->_com_obj()->state("RUNNING");
        $request->_com_obj()->start_time($date);
        $request->set_message($message);
    } else {
        $logger->error("ID $id does not exist in the requests hash.");
    }
}

sub commandFinished {
    $logger->debug("In commandFinished.");
    my ($id, $message, $date, $return_value) = @_;

    my $request;
    if (exists($requests{$id})) {
        $request = $requests{$id};
        $request->_com_obj()->state("FINISHED");
        $request->_com_obj()->end_time($date);
        $request->set_return_values($return_value);
        $request->set_message($message);
    } else {
        $logger->error("ID $id does not exist in the requests hash.");
    }
}

sub commandFailed {
    $logger->debug("In commandFailed.");
    my ($id, $message, $date, $return_value) = @_;

    my $request;
    if (exists($requests{$id})) {
        $request = $requests{$id};
        $request->_com_obj()->state("FAILED");
        $request->_com_obj()->end_time($date);
        $request->set_message($message);
    } else {
        $logger->error("ID $id does not exist in the requests hash.");
    }
}

sub commandSubmitted {
    $logger->debug("In commandSubmitted.");
    my ($id, $message, $date, $user, $log) = @_;

    my $request;
    if (exists($requests{$id})) {
        $request = $requests{$id};
        $request->_com_obj()->state("WAITING");
        $request->_com_obj()->log_location($log);
        $request->set_message($message);
    } else {
        $logger->error("ID $id does not exist in the requests hash."); 
    }
}

sub commandInterrupted {
    $logger->debug("In commandInterrupted.");
    my ($id, $message, $date, $interrupt) = @_;

    my $request;
    if (exists($requests{$id})) {
        $request = $requests{$id};
        $request->_com_obj()->state("INTERRUPTED");
        $request->set_message($message);
    } else {
        $logger->error("ID $id does not exist in the requests hash."); 
    }
}

sub commandSuspended {
    $logger->debug("In commandSuspended.");
    my ($id, $message, $date, $interrupt) = @_;

    my $request;
    if (exists($requests{$id})) {
        $request = $requests{$id};
        $request->_com_obj()->state("SUSPENDED");
        $request->set_message($message);
    } else {
        $logger->error("ID $id does not exist in the requests hash.");
    }
}

sub getIDs {
    $logger->debug("In getIDs.");
    # The spaceship operator will give us a numerical sort.
    my @ids = sort { $a <=> $b } keys %requests;
    if ($logger->is_debug()) {
        if (scalar(@ids) == 1) {
            $logger->debug("There is 1 ID: $ids[0].");
        } else {
            $logger->debug('There are ' . scalar(@ids) . ' IDs: ' . join(", ", @ids) . '.');
        }
    }
    return \@ids;
}

sub commandResumed {
    $logger->debug("In commandResumed.");
    my ($id, $message, $date, $machine) = @_;

    my $request;
    if (exists($requests{$id})) {
        $request = $requests{$id};
        $request->_com_obj()->state("RUNNING");
        $request->set_message($message);
    } else {
        $logger->error("ID $id does not exist in the requests hash.");
    }
}

=item $obj->max_time([$time])

B<Description:> Get or set the maximum time a daemon will wait for completion
of an HTC job. If this time is exceeded, the daemon will simply exit out in
order to prevent an accumulation of daemon that may never receive a finish
event.

B<Parameters:> Optional $time (in seconds). For example, the default time is,
eight days. To set it to 2 days, you would call $obj->max_time(172800);

B<Returns:> The currently set maximum time, in seconds.

=cut

sub max_time {
    my ($self, $time) = @_;
    $logger->debug("In max_time.");
    # CHeck that time is numeric and positive.
    if ( ($time !~ m/\D/) && ($time > 0) ) {
        if (defined($time)) {
            $logger->debug("Received time of $time.");
            $MAXTIME = $time;
        }
    } else {
        $logger->warn("Problem with the time provided: $time.");
    }
    $logger->debug("Returing $MAXTIME.");
    return $MAXTIME;
}


1;

__END__

=back

=head1 ENVIRONMENT

This module does not set or read any environment variables.

=head1 DIAGNOSTICS

=over 4

=item "Failed to establish callback network connection.";

This module attempts to create a HTTP::Daemon to receive events back from the
server when wait_for_request or submit_and_wait methods are used.  This error
message is sent when a network problem occurs with this Daemon.

=item "Could not submit job to server. Please contact the TIGR HTC Team.";

This error occurs when the Proxy Server cannot find the server it is
a proxy for.

=back

=head1 BUGS

Send bugs to bits.antware@tigr.org or antware@tigr.org.

=head1 SEE ALSO

 Frontier::Client
 Frontier::RPC2
 HTTP::Daemon
 HTTP::Status
 Log::Log4perl
 Memoize
 TIGR::HTC
 TIGR::HTCRequest

=head1 AUTHOR(S)

 The Institute for Genomic Research
 9712 Medical Center Drive
 Rockville, MD 20850

=head1 COPYRIGHT

Copyright (c) 2003-2004, The Institute for Genomic Research. All Rights Reserved.
