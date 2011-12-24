package miniHMM::Alignment; {
    use warnings;
    use strict;
    use Carp;
    use File::Temp;
    
    use version; our $VERSION = qv( qw$Revision 0.0.1$[1] );
    
    use Bio::AlignIO;
    
    my $belvu = '/usr/local/bin/belvu';
    
    my @acceptable_formats = qw(msf selex clustalw fasta);
    
    sub new {
        my $class = shift;
        my $alignment = shift;
        my $self = bless({},$class);
        if ($alignment) {
            if (UNIVERSAL::isa($alignment,'Bio::Align::AlignI')) {
                $self->{aln} = $alignment;
            }
            else {
                $self->load($alignment);
            }
        }
        if (not $self->{aln}) { # load failed
            return;
        }
        else {
            return $self;
        }
    }
    
    sub load {
        my $self = shift;
        my $file = shift;
        # warn "Starting load of $file\n",`/bin/ls -l $file`,"\n";
        $self->{file} = $file;
        if ( -r $file) {
            foreach my $format (@acceptable_formats) {
                my $in = Bio::AlignIO->new(-file=>$file, -format=>$format);
                $self->{aln} = $in->next_aln();
                if ($self->{aln}) {
                    last; # read the file
                }
            }
            if (! $self->{aln}) {
                die "Could not parse alignment file\n";
            }
        }
        else {
            die "$file is unreadable\n";
        }
        $self->{orig_aln} = $self->{aln};
        return $self;
    }
    
    sub get_gap_trimmed {
        my $self = shift;
        my $class = ref $self;
        my $threshold = shift || 65;
        my $source_name = $self->{file};
        my $source_tfh;
        if (not $source_name) { # save to temp file
            $source_tfh = File::Temp->new(UNLINK=>0);
            $source_name = $source_tfh->filename;
            $self->save($source_name);
        }
        my $log_tfh = File::Temp->new(SUFFIX =>".log", UNLINK=>0);
        my $log_name = $log_tfh->filename;
        my $target_tfh = File::Temp->new(SUFFIX=>".msf", UNLINK=>0);
        my $target_name = $target_tfh->filename;
        my $cmd = "$belvu -o msf -Q $threshold $source_name 2>$log_name >$target_name";
        # warn "belvu: $cmd";
        my $res = system($cmd);
        $res = $res >> 8;
        if ($res) {
            warn "Gap trimming failed. Error code $res\n";
            return
        }
        else {
            my $aln_in = Bio::AlignIO->new(-fh=>$target_tfh, -format=>'msf');
            my $aln = $aln_in->next_aln();
            my $trimmed = $class->new($aln);
            my @cols = ();
            while (my $line = <$log_tfh>) {
                my ($start, $end) = $line =~ /Removing Columns (\d+)-(\d+)./;
                if ($start and $end) {
                    push @cols, ($start)..($end);
                }
            }
            @cols = sort {$a <=> $b} @cols;
            return ($trimmed, \@cols);
        }
    }

    sub file_name {
        my $self = shift;
        if ($self->{file}) {
            return $self->{file};
        }
        else {
            return;
        }
    }

    sub length {
        my $self = shift;
        return $self->{aln}->length;
    }
    
    sub get_sub_alignment {
        my $self = shift;
        my $class = ref $self;
        my $start = shift;
        my $end = shift;
        if ($end < $start) {
            ($end, $start) = ($start, $end);
        }
        if (!$start or $start <= 0) {
            $start = 0;
        }
        if (!$end or $end >= $self->{aln}->length) {
            $end = $self->{aln}->length -1;
        }
        
        my $aln = $self->{aln};
        my $sub_aln = $class->new($aln->slice($start+1, $end+1));
        return $sub_aln;
    }
    
    sub to_string {
        my $self = shift;
        my $format = shift || 'selex';
        my $output;
        open my $ofh, ">", \$output;
        my $out = Bio::AlignIO->new(-fh=>$ofh, -format=>$format);
        $out->write_aln($self->{aln});
        $out = undef;
        close $ofh;
        return $output;
    }
    
    sub save {
        my $self = shift;
        my $file_name = shift;
        my $format = shift || 'selex';
        my $out = Bio::AlignIO->new(-file=>">$file_name", -format=>$format);
        $out->write_aln($self->{aln});
        $out = undef;
        $self->{file} = $file_name;
        return $self;
    }
}

1; # Magic true value required at end of module
