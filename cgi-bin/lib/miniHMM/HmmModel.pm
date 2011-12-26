package miniHMM::HmmModel;
{

    use warnings;
    use strict;
    use Carp;

    use base qw(Class::Accessor);

    use File::Spec::Functions qw(splitpath);
    use Data::Dumper;

    # use lib qw(/usr/local/devel/ANNOTATION/rrichter/miniHMM/cgi-bin/lib);
    use miniHMM::Alignment;
    use miniHMM::Blast qw/blast_for_relative/;

    use version; our $VERSION = qv( qw$Revision 0.0.1$ [1] );

    # - constants
    my @PUBLIC_FIELDS = qw/
    name
    alignment alignment_file
    hmm_file db hits_file htab_file
    hits residues evalue_cutoff
    /;
    my @PRIVATE_FIELDS = qw/

    /;

    # order of suffixes must be reverse of expected order if order may matter
    my @REMOVABLE_SUFFIXES =
    map { qr/\.${_}$/ }
    qw/htab hits HMM msf selex SEED fas fa clw clustalw cl/;

    my $runcmd       = "/home/sgeworker/bin/runLinux";
    my $hmmbuild     = "/usr/bin/hmmbuild";
    #my $hmmcalibrate = "/usr/bin/hmmcalibrate";
    my $hmmsearch    = "/usr/bin/hmmsearch";

    my $htab = "/usr/local/devel/ANNOTATION/rrichter/miniHMM/phmmsearch/htab_gaps.pl";
#    my @htab_file_fields = qw/
#    accession date hmm_length method db_name hit_accession
#    hmm_start hmm_end hit_start hit_end gap_start gap_end _blank_
#    domain_score total_score domain_num total_domains hmm_desc hit_desc
#    trusted_cutoff noise_cutoff total_escore domain_escore
#    /;

    my @htab_file_fields = qw/
    hit_accession empty_accession_target target_length accession empty_accession_hmm query_len full_evalue 
    total_score full_bias number_of number_total domain_cevalue domain_ievalue domain_score domain_bias 
    hmm_from hmm_to hit_start hit_end env_from env_to acc target_description
    /;

    # create accessors
    __PACKAGE__->follow_best_practice;    # use get_/set_ for accessors
    __PACKAGE__->mk_accessors(@PUBLIC_FIELDS);

    # - utility functions
    sub _base_name {

        # returns name with path and extensions removed
        my ( undef, undef, $file ) = splitpath( shift() );
        for my $suffix (@REMOVABLE_SUFFIXES) {
            $file =~ s/$suffix//;
        }
        return $file;
    }

    # - methods
    sub new {
        my $class    = shift;
        my $field_hr = shift;
        my $self     = bless( {}, $class );
        @$self{@PUBLIC_FIELDS} = @$field_hr{@PUBLIC_FIELDS};
        if ( $self->{alignment} and not $self->{alignment_file} ) {
            $self->{alignment_file} = $self->{alignment}->file_name;
        }
        elsif ( $self->{alignment_file} and not $self->{alignment} ) {
            $self->read_alignment();
        }
        if (
            !$self->{name}
            and (
                my ($path) =
                grep { $_ }
                @$self{qw/alignment_file hmm_file hits_file htab_file/}
            )
        )
        {
            my $name = _base_name($path);
            $self->{name} = $name;
        }

        return $self;
    }

    sub read_alignment {
        my $self           = shift;
        my $alignment_file = $self->get_alignment_file;
        my $alignment = miniHMM::Alignment->new($alignment_file);
        $self->set_alignment($alignment);
        return $alignment;
    }

    sub prepare_hmm_model {
        my $self = shift;
        if ( !$self->get_alignment ) {
            $self->read_alignment() or die "Can't parse alignment file";
        }
        my $alignment_file = $self->get_alignment_file;
        my $prefix         = $self->get_name;
        my $hmm_file       = "$prefix.HMM";
        my $log_file       = "$prefix.log";
        my $hmm_build_cmd;
        #"$hmmbuild -g --amino -F $hmm_file $alignment_file >>$log_file";
        #SEED alignments come in stockholm, so accomodate this
	if ($alignment_file =~ m/SEED/) {
		$hmm_build_cmd = "$hmmbuild --amino $hmm_file $alignment_file >>$log_file";
	}
	else { $hmm_build_cmd = "$hmmbuild --amino --informat afa $hmm_file $alignment_file >>$log_file";}
        warn "HMM build $hmm_build_cmd\n";
        system $hmm_build_cmd;
        #my $hmm_calibrate_cmd =
        #"/usr/local/bin/hmmcalibrate --num 1000 $hmm_file >> $log_file";
        #warn "HMM calibrate $hmm_calibrate_cmd\n";
        #system $hmm_calibrate_cmd;
        $self->set_hmm_file($hmm_file);
        return $self;
    }

    sub run_hmm {
        my $self = shift;
        my $db   = shift;
        if ( !$self->get_hmm_file ) {
            $self->prepare_hmm_model();
        }
        if ($db) {
            $self->set_db($db);
        }
        else {
            $db = $self->get_db;
        }
        if ( !-r $db ) {
            die "Can't read database $db for HMM run\n";
        }
        my $hmm_file      = $self->get_hmm_file;
        my $hits_file     = "$hmm_file.hits";
        my $evalue_cutoff = $self->get_evalue_cutoff || 10;
        #my $hmm_cmd = "$hmmsearch -E $evalue_cutoff $hmm_file $db > $hits_file 2> $hmm_file.err";
        #my $hmm_cmd = "$hmmsearch -E $evalue_cutoff --notextw --domtblout $hits_file $hmm_file $db > $hmm_file.out 2> $hmm_file.err";
        my $hmm_cmd_string = "$hmmsearch -E $evalue_cutoff --notextw --domtblout $hits_file $hmm_file $db > $hmm_file.out 2> $hmm_file.err";
        system("echo $hmm_cmd_string > sge_command.sh");
        system("chmod u+x sge_command.sh");
        my $hmm_cmd = "/opt/sge/bin/lx24-amd64/qsub -b yes -shell yes -v PATH=/opt/sge/bin/lx24-amd64:/opt/galaxy/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin -v DISPLAY=:42 sge_command.sh"; 
        warn "HMM command: $hmm_cmd\n";
        my $res = system($hmm_cmd);
        $res >>= 8;
        if ($res) {
            die "HMM for $hmm_file failed.\n Command: $hmm_cmd\nError: $res\n";
        }
        $self->set_hits_file($hits_file);
        return $self;
    }

    sub create_htab_file {
        my $self = shift;
        if ( !$self->get_hits_file ) {
            die
"Can't read hits file. Run hmm with \$model->run_hmm('</path/database>') to generate hits file.";
        }
        my $hits_file = $self->get_hits_file;
        my $htab_file = $self->get_name . ".HMM.htab";
        my $htab_cmd  = "$htab -s <$hits_file >$htab_file";

        #    warn "HTAB command: $htab_cmd\n";
        my $res;
        {
            local $ENV{HMM_SCRIPTS} = '/usr/local/devel/ANNOTATION/hmm/bin';
            local $ENV{PERL5LIB}    = '/usr/local/devel/ANNOTATION/hmm/bin';
            $res = system($htab_cmd);
        }
        $res >>= 8;
        if ($res) {
            die
"Failed to create htab from $hits_file.\n Command: $htab_cmd\nError: $res\n";
        }
        $self->set_htab_file($htab_file);
        return $self;
    }

    sub get_hits {
        my $self    = shift;
        my $cutoff  = shift;
        my $hit_set = $self->{hits};
        if ( !$hit_set ) {
            #if ( !$self->get_htab_file ) {
            #    $self->create_htab_file;
            #}
            #my $htab = $self->get_htab_file;
            my $hits_file = $self->get_hits_file;
            #open my $fh, "<", $htab;
            open my $fh, "<", $hits_file;
            my @hits;
            while ( my $line = <$fh> ) {
		if ($line =~ /^#/) {next;}    
                chomp $line;
		$line =~ s/\s+/\t/g;
                my $fields;
                @$fields{@htab_file_fields} = split /\t/, $line;
                my $hit = _Hit->new($fields);
		if ( $hit->number_of > 1 ) {next;}
                push @hits, $hit;
            }
            $self->set_hits( \@hits );
            $hit_set = \@hits;
        }
        my @hits;
        if ( defined $cutoff ) {
            @hits = grep { $_->total_score >= $cutoff } @$hit_set;
        }
        else {
            @hits = @$hit_set;
        }

        if (wantarray) {
            return @hits;
        }
        else {
            return \@hits;
        }
    }

    sub get_profile_at_cutoff {
        my $self   = shift;
        my $cutoff = shift;
        my @profile_hits;
        my @ignore_hits;
	if ( not defined $cutoff) {
		return _Profile->new();
	}
        if ( @_ == 2 and ref( $_[0] ) eq 'ARRAY' ) {
            @profile_hits = @{ $_[0] };
            @ignore_hits  = @{ $_[1] };
        }
        elsif ( @_ == 1 and ref( $_[0] ) eq 'ARRAY' ) {
            @profile_hits = @{ $_[0] };
            @ignore_hits  = ();
        }
        elsif ( @_ == 1 and ref( $_[0] ) eq 'HASH' ) {
            @profile_hits = @{ $_[0]->{profile} };
            @ignore_hits = @{ $_[0]->{ignore} } || ();
        }
        else {
            @profile_hits = @_;
        }
        if ( not @profile_hits ) {
            croak "Can't profile without a profile set.\n";
        }
        my %profile_set   = map { $_->hit_accession => 1 } @profile_hits;
        my $profile_count = scalar(@profile_hits);
        my %ignore_set    = map { $_->hit_accession => 1 } @ignore_hits;
        my @matches;
        my @misses;
        my @ignored;
        my $total_hits = 0;
        my $upper_cutoff_score;
        my $lower_cutoff_score;

        foreach my $hit ( $self->get_hits() ) {
            if ( $hit->total_score >= $cutoff ) {

                if ( $ignore_set{ $hit->hit_accession } ) {

                    # skip hits in ignore set
                    push @ignored, $hit;
                    next;
                }

                $total_hits++;
                $upper_cutoff_score = $hit->total_score;
                if ( $profile_set{ $hit->hit_accession } ) {
                    push @matches, $hit;
                }
                else {
                    push @misses, $hit;
                }
            }
            else {
                $lower_cutoff_score = $hit->total_score;
                last;
            }
        }

        my $ignore_count = scalar(@ignored);
        my $specificity;
        if ($total_hits) {
            $specificity = 100 * @matches / $total_hits;
        }
        else {
            $specificity = 0;
        }

        my $sensitivity;
        if ($profile_count) {
            $sensitivity = 100 * ( @matches + $ignore_count ) / $profile_count;
            if ( $sensitivity > 100 ) {
                $sensitivity = 100;
            }
            my $match_count = scalar(@matches);

#warn "sensitivity: \t$sensitivity\nmatches: \t$match_count\nignore_count: \t$ignore_count\nprofile_count:\t $profile_count\n";
        }
        else {
            $sensitivity = 0;
        }

        my $profile = _Profile->new(
            {
                matches            => \@matches,
                misses             => \@misses,
                ignored            => \@ignored,
                cutoff             => $upper_cutoff_score,
                upper_cutoff_score => $upper_cutoff_score,
                lower_cutoff_score => $lower_cutoff_score,
                specificity        => $specificity,
                sensitivity        => $sensitivity,
            }
        );

        return $profile;
    }

    sub get_cutoff_for_specificity {
        my $self          = shift;
        my $db            = shift;
        my $specificity   = shift;
        my $parent_length = shift;

        my @above_trusted_hits = @{ $_[0] };
        my @below_noise_hits   = @{ $_[1] };
        my @ignored_hits       = @{ $_[2] };
        my %stored_blast       = %{ $_[3] };
        my %non_hits 		   = %{ $_[4] };

        my %below_noise_set = map { $_->hit_accession => $_ } @below_noise_hits;
        my %trust_set  = map { $_->hit_accession => $_ } @above_trusted_hits;
        my %ignore_set = map { $_->hit_accession => $_ } @ignored_hits;

        my @blast_filtered;

        my $match_count = 0;
        my $total_count = 0;
        my $backup_score;
        my $last_score;
        my $this_score;
	my $below_specificity = 0;
	
        foreach my $hit ( $self->get_hits ) {
            next if ( $ignore_set{ $hit->hit_accession } );

            $total_count++;
            $this_score = $hit->total_score;

            # 1. If the hit corresponds to an above-trusted hit to the full-length model, then increase match count
            # 2. If the hit corresponds to a below-noise hit to the full-length model, we test if the hit is short or truncated
            #		against the full model. If it's so, and its BLAST best match corresponds to an above-trusted hit to the full model
            #     then, ignore this hit
            # 3. If the hit doesn't corresond to any hit to the full-length model, we test if it's short.
            #     Then we check it's BLAST match and ignore it accordingly.
            if ( $trust_set{ $hit->hit_accession } ) {
                $match_count++;
            }
            elsif ( $below_noise_set{ $hit->hit_accession } ) {
                my $hit_to_parent = $below_noise_set{ $hit->hit_accession };
                my $hit_end       = $hit_to_parent->hit_end;
                my $hit_start     = $hit_to_parent->hit_start;
                my $percent = ( $hit_end - $hit_start ) / $parent_length * 100;

                if (   $percent <= 85 )
                   # || $hit_to_parent->gap_start >= 10
                   # || $hit_to_parent->gap_end >= 10 )
                {
                    print "short or truncated below-noise hit\n",
                    $hit->hit_accession;
                    my $blast_match;
                    if ( exists $stored_blast{ $hit->hit_accession } ) {
                        $blast_match = $stored_blast{ $hit->hit_accession };
                    }
                    else {
                        $blast_match = blast_for_relative($hit->hit_accession, $db);

                        ## set the input argument for blast search result
                        ${ $_[3] }{ $hit->hit_accession } = $blast_match;
                    }

                    if ( $trust_set{$blast_match} ) {
                        print "blast match ($blast_match) above trusted";
                        push @blast_filtered, $hit;
                        $total_count--;
                    }
                    else {
                        print "blast match ($blast_match) below trusted\n";
                    }
                }
            }
            else {    # non-hit to parent
                my $hit_length = 0;
                if( exists $non_hits{ $hit->hit_accession} ) {
                    $hit_length = $non_hits{ $hit->hit_accession};
                } else {
                    open( IN, "<$db" ) or die $!;
                    LOOPLABEL: while (<IN>) {
                        if (/\Q$hit->hit_accession/) {
                            while (<IN>) {
                                last LOOPLABEL if (/>/);
                                $hit_length += length($_);
                            }
                        }
                    }
                    close IN;

                    ${ $_[4] }{ $hit->hit_accession } = $hit_length;
                }

                my $percent = $hit_length / $parent_length * 100;

                if ( $percent <= 85 ) {
                    print "\nshort non-hit to parent model ",
                    $hit->hit_accession,"\n";
                    my $blast_match;
                    if ( exists $stored_blast{ $hit->hit_accession } ) {
                        $blast_match = $stored_blast{ $hit->hit_accession };
                    }
                    else {
                        $blast_match = blast_for_relative($hit->hit_accession, $db );

                        ## set the input argument for blast search result
                        ${ $_[3] }{ $hit->hit_accession } = $blast_match;
                    }

                    if ( $blast_match and $trust_set{$blast_match} ) {
                        print ", it's blast match ", $blast_match,
                        " is above trusted";
                        push @blast_filtered, $hit;
                        $total_count--;
                    }
                }
            }

            if (   $total_count != 0
                && $match_count * 100 / $total_count < $specificity )
            {

                # print "Less than specificity threshold\n";
                last;
		$below_specificity = 1;
            }

 #elsif ($match_count == $used_profile_count) { # if we've hit every possible profile, don't bother continuing
#     $last_score = $hit->total_score;
#     last;
# }
            if ( !$last_score or $this_score < $last_score ) {

            # only update the last score if we leave a score equivalence group
            # this is so, if the hit that drives us below specificity is in
            # said group, the last fully valid score is what counts.
                $backup_score = $last_score;
                $last_score   = $this_score;
            }

    # 	print "This: $this_score\tLast: $last_score\tBackup: $backup_score\n";
        }

        if ( !$last_score ) {
	
	   return [ undef , @blast_filtered];
	
	}

        elsif ($below_specificity && $this_score == $last_score ) {

            $below_specificity = 0;
            #	print "\nReturn backup_score: $backup_score\n\n";
            return [ $backup_score, @blast_filtered ];
        }
        else {

            #	print "\nReturn last_score: $last_score\n\n";
            return [ $last_score, @blast_filtered ];
        }


    }

    sub get_cutoff_for_sensitivity {
        my $self        = shift;
        my $sensitivity = shift;
        my @profile_hits;
        my @ignore_hits;
        if ( @_ == 2 and ref( $_[0] ) eq 'ARRAY' ) {
            @profile_hits = @{ $_[0] };
            @ignore_hits  = @{ $_[1] };
        }
        elsif ( @_ == 1 and ref( $_[0] ) eq 'ARRAY' ) {
            @profile_hits = @{ $_[0] };
            @ignore_hits  = ();
        }
        elsif ( @_ == 1 and ref( $_[0] ) eq 'HASH' ) {
            @profile_hits = @{ $_[0]->{profile} };
            @ignore_hits = @{ $_[0]->{ignore} } || ();
        }
        else {
            @profile_hits = @_;
        }
        if ( not @profile_hits ) {
            croak "Can't profile without a profile set.\n";
        }
        my %profile_set = map { $_->hit_accession => 1 } @profile_hits;
        my %ignore_set  = map { $_->hit_accession => 1 } @ignore_hits;
        my $used_profile_count =
        scalar( grep { not $ignore_set{$_} } @profile_hits );
        my $match_count;
        my $total_count;
        my $last_score;
        foreach my $hit ( $self->get_hits ) {

            if ( $ignore_set{ $hit->hit_accession } ) {
                next;
            }
            if ( $profile_set{ $hit->hit_accession } ) {
                $match_count++;
            }
            if ( $match_count * 100 / $used_profile_count > $sensitivity ) {
                if ( !defined($last_score) ) {
                    $last_score = $hit->total_score;
                }
                last;
            }
            elsif ( $match_count == $used_profile_count )
            {    # if we've hit every possible profile, don't bother continuing
                $last_score = $hit->total_score;
                last;
            }
            my $this_score = $hit->total_score;
            if ( !$last_score or $this_score < $last_score ) {

            # only update the last score if we leave a score equivalence group
            # this is so, if the hit that drives us below specificity is in
            # said group, the last fully valid score is what counts.
                $last_score = $this_score;
            }
        }
        return $last_score;
    }
}

sub get_blast_match {
    croak "Shouldn't run get_blast_match anymore";
    my $self = shift;

    #	my $db_handle = shift;
    my $db  = shift;
    my $hit = shift;
    my $best_match;

#	my $statement = $db_handle->prepare("select accession from all_vs_all where locus = ? and locus != accession
#											and match_order < 10 order by match_order") or die $db_handle->errstr;
#	$statement->execute($hit);
#	my @results=$statement->fetchrow_array();
#	my $best_match = $results[0];

    #	$statement->finish;

    open( IN, "<$db" ) or die $!;
    open( OUT, ">blast_query.fasta" ) or die $!;
  LOOPLABEL: while (<IN>) {
        if (/\Q$hit/) {
            print OUT;
            while (<IN>) {
                last LOOPLABEL if (/>/);
                print OUT;
            }
        }
    }
    close IN;
    close OUT;

    $best_match =
`blastp $db blast_query.fasta mformat=2 W=10 gapE=2000 v=5 b=5 warnings notes | head -2 | tail -1 | cut -f2`;
    chomp $best_match;

    return $best_match;
}

package _Hit;
{
    use strict;
    use warnings;
    use base qw(Class::Accessor);
#    my @FIELDS = qw/
#    hit_accession hit_start hit_end gap_start gap_end hmm_start hmm_end domain_score
#    total_score domain_num total_domains hit_desc total_escore domain_escore
#    /;
    my @FIELDS = qw/
    hit_accession empty_accession_target target_length accession empty_accession_hmm query_len full_evalue 
    total_score full_bias number_of number_total domain_cevalue domain_ievalue domain_score domain_bias 
    hmm_from hmm_to hit_start hit_end env_from env_to acc target_description
    /;
    __PACKAGE__->mk_ro_accessors(@FIELDS);

    sub new {
        my $class     = shift;
        my $fields_hr = shift;
        my $self      = bless( {}, $class );
        @$self{@FIELDS} = @$fields_hr{@FIELDS};
        return $self;
    }
}

package _Profile;
{
    use strict;
    use warnings;
    use base qw(Class::Accessor);
    my @FIELDS =
    qw/matches misses ignored cutoff upper_cutoff_score lower_cutoff_score specificity sensitivity/;
    __PACKAGE__->mk_ro_accessors(@FIELDS);

    sub new {
        my $class     = shift;
        my $fields_hr = shift;
        my $self      = bless( {}, $class );
        @$self{@FIELDS} = @$fields_hr{@FIELDS};
        return $self;
    }
}

1;    # Magic true value required at end of module
