package TIGR::HTC;

# $Id: HTC.pm.templ 1131 2005-08-09 18:07:48 -0400 (Tue, 09 Aug 2005) vfelix $

=head1 NAME

HTC.pm - One line summary of purpose of class (or file).

=head1 SYNOPSIS

 my $path = "/tmp";
 my $is_nfs = TIGR::HTC->isNFS($path); # $is_nfs = 0;

=head1 DESCRIPTION

=head2 Overview

This method provides several functions and methods that are
useful to the HTC (High Throughput Computing) related Perl
modules.

=head2 Class and object methods

=over 4

=cut

use strict;
use Config::IniFiles;
use Frontier::Client;
use Log::Log4perl qw(:levels get_logger);

my $logger = get_logger(__PACKAGE__);

use vars qw($config $client $server);
our $VERSION = do { my @r=(q$Revision: 1131 $=~/\d+/g); sprintf "%d."."%03d"x$#r,@r };
our @DEPEND = qw( Config::IniFiles Frontier::Client Log::Log4perl);

if ($^W) {
    $VERSION = $VERSION;
    @DEPEND  = @DEPEND;
}

BEGIN {
    my $central_config = "/home/sgeworker/rlx_production/request//rlx-0-0-1.tigr.org/conf/request.conf";
    $config = defined($ENV{HTC_CONFIG}) ? $ENV{HTC_CONFIG} : $central_config;
    my $cfg;
    my $section = "request";
    if (-f $config && -r $config) {
        $cfg = Config::IniFiles->new( -file => $config );
    } else {
        die "Configuration file problem with $config.";
    }

    $server = $cfg->val($section, "URI");
    $client = Frontier::Client->new( url => $server );
    # Don't initialize if we have already done it...
    # TODO: More recent versions of Log4perl support the init_once method,
    # which does the same chack...
    unless (Log::Log4perl->initialized()) {
        my $logger_conf = $cfg->val($section, "Log4perlConf");
        Log::Log4perl::init($logger_conf);
    }
}


=item $obj->new([%arg]);

B<Description:> This is the object contructor. A hash
with arguments may be passed.

B<Parameters:> %arg.

B<Returns:> $self, a blessed hash reference.

=cut

sub new {
    my ($class, %arg) = @_;
    my $self = bless {}, ref($class) || $class;
    $self->_init(%arg);
    return $self;
}


=item $obj->_init();

B<Description:> _init in this class is an abstract method
and is not implemented. In fact, it will die with an error
message if you somehow call this method in this class.

B<Parameters:> None.

B<Returns:> None.

=cut

sub _init {
    $logger->logcroak("_init not implemented in this class.\n");
}


sub config { $config };


=item $obj->client();

B<Description:> This method returns the XML::RPC client that communicates
with the HTC server.

B<Parameters:> None.

B<Returns:> $client.

=cut

sub client { $client }


=item $obj->server();

B<Description:> This method retrieves the url of the HTC server configured
in the htc.conf configuration file. The method can be called as a class
method or an instance method from classes that inherit from this one.

B<Parameters:> None.

B<Returns:> $server, a url of the form: http://servername.tigr.org:8080/path

=cut

sub server { $server };


=item $obj->debug([$debug]);

B<Description:> The debug method allows the user to set or get
the debug level. If an optional argument is sent, it will be used
to set the debug level. The default level is "error". When passing a string
debug level, case is ignored.

B<Parameters:> Optional integer argument to set debug level. The debug
level can be either numeric or a string as follows:

    Name     Code
    ----     ----
    DEBUG       5
    INFO        4
    WARN        3
    ERROR       2
    FATAL       1

B<Returns:> The current debug level in numeric form.

=cut

sub debug {
    $logger->debug("In debug.");
    my ($self, @args) = @_;
    if (scalar(@args)) {
        my $debug = uc($args[0]);

        my %levels = ( DEBUG => [5, $DEBUG],
                       INFO  => [4, $INFO],
                       WARN  => [3, $WARN],
                       ERROR => [2, $ERROR],
                       FATAL => [1, $FATAL] );
        my %name_to_level = map { $_ => $levels{$_}->[1] } keys %levels;
        my %level_to_name = reverse (
                              map { $_ => $levels{$_}->[0] } keys %levels
                            );

        # Anonymous subroutine.
        my $set_by_name = sub {
            my $level_string = shift;
            $logger->info("Setting new debug level to $level_string.");
            my $level = $name_to_level{$level_string};
            $logger->level($level);
            # Set the debug level for the object.
            $self->{debug} = $levels{$level_string}->[0];
        };

        if (exists $levels{$debug}) {
            # If we have a named debug level.
            $set_by_name->($debug);
        } else {
            # We probably have a numbered debug level.
            if ( $debug !~ m/\D/ && $debug >= 1 && $debug <= 5) {
                $set_by_name->( $level_to_name{$debug} );
            } else {
                $logger->error("\"$debug\" is an invalid debug level.");
                $set_by_name->("ERROR");
            }
        }
    } else { # No arguments provided. Act like a simple accessor (getter).
       return $self->{debug};
    }
}


=item TIGR::HTC->isNFS($path);

B<Description:> Calls the HTC server to determine if the specified path
is globally visible to all machines in the HTC infrastructure via NFS. This
is necessary in order to avoid problems with users specifying directories
are only locally accessible to them. The HTC server's notions of what is
globally visible is considered definitive for the Distributed Computing
Environment.

B<Parameters:> $path, the path to a directory or filename that is to be
checked for global availability.

B<Returns:> Returns 1 if the path is globally accessible, and 0 if it is not.

=cut

sub isNFS {
    $logger->debug("In isNFS.");
    my ($self, @args) = @_;

    my $intro = "It appears isNFS was called";
    # Figure out how we were called. Be as forgiving as possible.
    if (ref($self) && $self->isa(__PACKAGE__)) {
        # Instance method
        $logger->debug("$intro as an instance method.");
    } elsif ( (ref(\$self) eq "SCALAR") && ($self eq __PACKAGE__)) {
        # Class method: TIGR::HTC->isNFS
        $logger->debug("$intro as a class method.");
    } else {
        # User called ::isNFS instead of ->isNFS. Forgive and forget...
        unshift(@args, $self);
        $logger->debug("$intro as a subroutine.");
    }

    my $path = shift @args;

    my $answer;
    $logger->logcroak("No path specified.") unless
        (defined($path) && (ref(\$path) eq "SCALAR"));

    # The HTC server's isNFS method returns an XML-RPC boolean.
    # We need to use the 'value' method to get at the actual value.
    eval {
        $answer = $client->call('HTCServer.isNFS', $path )->value;
    };
    $logger->logcroak("Could not connect to the HTC server. ",
                      "Please contact the TIGR HTC Team.") if $@;
    my $result = ($answer) ? 1 : 0;
    return $result;
}


=item $obj->group([$group]);

B<Description:> Used to set or get the group that the HTC job
is to be associated with. The group is necessary to track usage
patterns of the HTC infrastructure and to provide useful management
information.

B<Parameters:> $group, optional group argument.

B<Returns:> $group, the currently set group.

=cut

sub group {
    $logger->debug("In group.");
    my ($self, @args) = @_;
    if (scalar(@args)) {
        $self->{group} = $args[0];
    } else {
       return $self->{group};
    }
}

=item $obj->URI();

B<Description:> This method is an alias for the server() method. In addition,
the lowercase uri() method also works. See the documentation for server() for
details.

B<Parameters:> None.

B<Returns:> $server, a url of the form: http://servername.tigr.org:8080/path

=cut

sub URI { $server }

sub uri { $server }


=item $obj->username([$username]);

B<Description:> Used to set or get the username used to submit
jobs to the HTC infrastructure. An optional argument will be used
to change the username.

B<Parameters:> $username, optional username argument.

B<Returns:> $username, the currently set username.

=cut

sub username {
    my ($self, @args) = @_;
    if (scalar(@args)) {
        $self->{username} = $args[0];
    } else {
        return $self->{username};
    }
}


=item $obj->sleeper();

B<Description:> This method returns a code reference
to a closure implemented as an anonymous subroutine. 
It is used to get progressively longer sleeptimes to
wait before getting a status report on a job. It is 
meant to be used in cases such as in phmmsearch, 
when the user has set the --wait flag. This method
should be used like so:

    my $sleeper = $obj->sleeper;
    my $sleeptime = $sleeper->(); # 1st value
    $sleeptime = $sleeper->();    # 2nd value

After a set minimum sleeptime is surpassed, each
successive call will yield larger sleeptimes,
until a maximum of two hours is reached.

B<Parameters:> None.

B<Returns:> $closure_ref, a code reference to an
anonymous subroutine.

=cut

sub sleeper {
    my ($self, @args) = @_;
    my $exp = 2;
    my $min = 10; # 7200 = 2 hours;
    my $max = 2*60*60; # 7200 = 2 hours;
    $logger->logcroak("Minimum sleeptime must be less than the maximum!") if ($min >= $max);
    my $closure_ref = sub {
        $exp++;
        my $count = int(2**$exp); 
        my $sleep;
        $sleep = ($count > $max) ? $max : $count; 
        $sleep = ($count < $min) ? $min : $count; 
        return $sleep;
    };
    return $closure_ref;
}

1;            # For the use or require to succeed;

__END__

=back

=head1 ENVIRONMENT

If the user sets the HTC_CONFIG environment variable, it will be interpreted
as the path to an alternate configuration file that will override the default.

=head1 DIAGNOSTICS

=over 4

=item "Minimum sleeptime must be less than the maximum!"

The configured mininum sleeptime in the "sleeper" method is not less
than the configured maximum. Please notify the HTC Team of this error.

=back

=head1 BUGS

Description of known bugs (and any workarounds). Usually also includes an
invitation to send the author bug reports.

=head1 SEE ALSO

  HTC::Request
  HTC::Request::HMM

=head1 AUTHOR(S)

 The Institute for Genomic Research
 9712 Medical Center Drive
 Rockville, MD 20850

=head1 COPYRIGHT

Copyright (c) 2002-2004, The Institute for Genomic Research. All Rights Reserved.
