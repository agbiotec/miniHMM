package TIGR::HTCRequest::CommandStatus;

# $Id: CommandStatus.pm 297 2003-08-01 18:12:53Z vfelix $

# Copyright (c) 2003, The Institute for Genomic Research. All rights reserved.

=head1 NAME

CommandStatus.pm - One line summary of purpose of class (or file).

=head1 VERSION

This document refers to CommandStatus.pm.
$Revision: 297 $

=head1 SYNOPSIS

Short examples of code that illustrate the use of the class (if this file is a class).

=head1 DESCRIPTION

=head2 Overview

An overview of the purpose of the file.

=head2 Constructor and initialization.

if applicable, otherwise delete this and parent head2 line.

=head2 Class and object methods

if applicable, otherwise delete this and parent head2 line.

=cut


use strict;
use Log::Log4perl qw(get_logger);
my $logger = get_logger(__PACKAGE__);

use vars qw( $VERSION );

$VERSION = qw$Revision: 297 $[1];

sub new {
    $logger->debug("In constructor, new.");
    my ($class, %args) = @_;
    my $self = bless {}, $class || ref($class);
    $self->_init(\%args);
    return $self;
}

sub _init {
    $logger->debug("In _init");
    my ($self, $arg_ref) = @_;
    my %args = %$arg_ref;

    $logger->debug("Setting errors to 0.");
    $self->errors(0);
}

sub completed {
    $logger->debug("In completed.");
    my ($self, $completed, @args) = @_;
    my $return;

    if (defined $completed) {
        $logger->warn("The completed method takes only one argument ",
                      "when making an assignment.") if @args;
        if ($completed =~ m/\D/) {
            $logger->error("Encountered non-numeric 'completed' attribute.");
            $return = undef;
        }
        $return = $self->{completed} = $completed;
    } elsif (exists($self->{completed}) && defined($self->{completed})) {
        $return = $self->{completed};
    } else {
        $return = undef;
    }
    return $return;
}

sub message {
    $logger->debug("In message.");
    my ($self, $message, @args) = @_;
    my $msg;

    if (defined $message) {
        $logger->warn("The message method takes only one argument.") if @args;
        $msg = $self->{message} = $message;
    } elsif (exists($self->{message}) && defined($self->{message})) {
        $msg = $self->{message};
    } else {
        $msg = undef;
    }
    return $msg
}

sub errors {
    $logger->debug("In errors.");
    my ($self, $errors, @args) = @_;

    if (defined $errors) {
        $logger->warn("The errors method takes only one argument ",
                      "when making an assignment.") if @args;
        if ($errors =~ m/\D/) {
            $logger->error("Encountered non-numeric 'errors' attribute.");
            return undef;
        }
        $self->{errors} = $errors;
    } elsif (exists($self->{errors}) && defined($self->{errors})) {
        return $self->{errors};
    } else {
        return undef;
    }
}

sub running {
    $logger->debug("In running.");
    my ($self, $running, @args) = @_;
    my $return;

    if (defined $running) {
        $logger->warn("The running method takes only one argument ",
                      "when making an assignment.") if @args;
        if ($running =~ m/\D/) {
            $logger->error("Encountered non-numeric 'running' attribute.");
            $return = undef;
        }
        $return = $self->{running} = $running;
    } elsif (exists($self->{running}) && defined($self->{running})) {
        $return = $self->{running};
    } else {
        $return = undef;
    }
    return $return;
}

sub return_values {
    my ($self, @args) = @_;
    my $return;

    if (@args) {
        foreach my $arg (@args) {
            if ($arg !~ m/\D/) {
                push( @{ $self->{return_values} }, $arg)
            } else {
                $logger->error("Non-numeric return value: $arg.");
            }
        }
        $return = undef;
    } else {
        unless( defined($self->{return_values}) &&
                 exists($self->{return_values}) ) {
            $self->{return_values} = [];
        }
        $return = $self->{return_values};
    }
    return wantarray ? @$return : $return;
}

sub waiting {
    $logger->debug("In waiting.");
    my ($self, $waiting, @args) = @_;
    my $return;

    if (defined $waiting) {
        $logger->warn("The waiting method takes only one argument ",
                      "when making an assignment.") if @args;
        if ($waiting =~ m/\D/) {
            $logger->error("Encountered non-numeric 'waiting' attribute.");
            $return = undef;
        }
        $return = $self->{waiting} = $waiting;
    } elsif (exists($self->{waiting}) && defined($self->{waiting})) {
        $return = $self->{waiting};
    } else {
        $return = undef;
    }
    return $return;
}


1;

__END__

=head1 ENVIRONMENT

List of environment variables and other O/S related information
on which this file relies.

=head1 DIAGNOSTICS

=over 4

=item "Error message that may appear."

Explanation of error message.

=item "Another message that may appear."

Explanation of another error message.

=back

=head1 BUGS

Description of known bugs (and any workarounds). Usually also includes an
invitation to send the author bug reports.

=head1 SEE ALSO

List of any files or other Perl modules needed by the file or class and a
brief description why.

=head1 AUTHOR(S)

 The Institute for Genomic Research
 9712 Medical Center Drive
 Rockville, MD 20850

=head1 COPYRIGHT

Copyright (c) 2003, The Institute for Genomic Research. All Rights Reserved.

