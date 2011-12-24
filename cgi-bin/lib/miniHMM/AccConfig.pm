package miniHMM::AccConfig; {

    use Log::Log4perl qw/:easy/;
    use Carp;
    use YAML;
    
    use Hash::Accessor;
    use miniHMM::HmmCommand;
    
    
    sub new {
        my $class = shift;
        my $accessor = Hash::Accessor->new(@_);
        my $self = bless(\$accessor, $class);
        return $self;
    }
    
    sub load_file {
        my $class = shift;
        my $file = shift;
        my $params = YAML::LoadFile($file);
        my $self = $class->new($params);
        return $self;
    }
    
    sub save_file {
        my $self = shift;
        my $file = shift;
        my %params;
        my @keys = keys %$$self;
        @params{@keys} = @$$self{@keys};
        return YAML::DumpFile($file, \%params);
    }
    
    sub AUTOLOAD {
        my $self = shift;
        my $name = our $AUTOLOAD;
        my $class = ref $self;
        $name =~ s/^\Q${class}::\E//;
        my $retval;
        eval {
            $retval =  $$self->$name(@_);
        };
        if ($@) {
            croak qq{Can't locate object method "$name" via package "$class"};
        }
        return $retval;
    }
    
    sub DESTROY { }

}
1;