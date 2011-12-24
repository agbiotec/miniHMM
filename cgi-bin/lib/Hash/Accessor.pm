package Hash::Accessor;

use Carp;

sub new {
    my $class = shift;
    my $params = shift || {};
    return bless($params, $class);
}

sub add {
    my $self = shift;
    my $params = shift;
    if (not ref($params) eq 'HASH') {
        croak "Attempt to add something other than hashref key/val";
    }
    my @keys = keys %$params;
    @$self{@keys} = @$params{@keys};
    return $self;    
}

sub delete {
    my $self = shift;
    my $key = shift;
    if ($key) {
        delete $self->{$key};
    }
    return $self;
}

sub to_hash {
    my $self = shift;
    my %hash;
    my @keys = keys %$self;
    @hash{@keys} = @$self{@keys};
    if (wantarray) {
        return %hash;
    }
    else {
        return \%hash;
    }
}

sub exists {
    my $self = shift;
    my $key = shift;
    if (exists $self->{$key}) {
        return 1;
    }
    else {
        return;
    }
}

sub AUTOLOAD {
    my $self = shift;
    my $arg = shift;
    my $name = our $AUTOLOAD;
    my $class = ref $self;
    $name =~ s/^\Q$class\E:://;
    my $val = $self->{$name};
    if (defined $arg) {
        $self->{$name} = $arg;
    }
    elsif (! exists ($self->{$name})) {
        my $class = ref $self;
        croak qq{Can't locate object method "$name" via package "$class"};
    }
    return $val;
}

sub DESTROY {}

1;