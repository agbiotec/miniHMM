package miniHMM::HmmCommand;
{
    use warnings;
    use strict;

    use DBI;
    use File::Spec::Functions qw(catfile splitpath);
    use Carp;
    use YAML;
    use Data::Dumper;
    use version;
    our $VERSION = qv( qw$Revision 0.0.1$ [1] );
    use Parallel::Loops;

    # use lib qw(/usr/local/devel/ANNOTATION/rrichter/miniHMM/cgi-bin/lib);
    use miniHMM::Alignment;
    use miniHMM::HmmModel;

    # - global constants
    my @SPECIFICITY_CUTOFFS = ( 100, 98, ); # 90, 80 dropped for speed

    #	my @SPECIFICITY_CUTOFFS = (100);
    my @INPUT_FIELDS = qw/
    dir trusted_cutoff noise_cutoff gap_filter prefix evalue_cutoff
    seq_db exclude_text model_type model_length model_overlap parallel
    /;

    my $phmmsearch = '/usr/local/devel/ANNOTATION/phmmsearch/blib/script/phmmsearch';

    # - utility functions
    sub create_gap_map {

        # takes parameters
        #  (scalar)length of items
        #  (array ref) gaps (1-based), every gap listed
        # returns
        #  (array ref) where value = location on ungapped array. index 0=0
        my $length = shift;
        my $gaps   = shift;
        my @gaps   = ( 0, );    # to deal w/ sequence w/o gaps
        if ( defined $gaps and @$gaps ) {
            @gaps = sort { $a <=> $b } @$gaps;
        }

        # warn "gaps: ",join(" ",@gaps);
        my @gap_map  = 0 .. $length;
        my $next_gap = shift @gaps;
        for ( my $x = 1, my $offset = 0 ; $x < $length + 1 ; $x++ ) {
            $gap_map[$x] = $x + $offset;
            while ( defined $next_gap and $gap_map[$x] == $next_gap ) {
                $next_gap = shift @gaps;
                $offset++;
                $gap_map[$x] = $x + $offset;
            }
        }
        return \@gap_map;
    }

    sub list_to_range {
        my @list = @_;
        if ( @list == 1 and ref( $list[0] ) eq 'ARRAY' ) {
            @list = @{ $list[0] };
        }
        return unless (@list);
        my @ranges;
        my $r_start;
        my $r_end;
        foreach my $loc (@list) {
            if ( not defined $r_start ) {
                $r_start = $loc;
                $r_end   = $loc;
            }
            if ( $loc > $r_end + 1 ) {    #gap
                push @ranges, [ $r_start, $r_end ];
                $r_start = $loc;
            }
            $r_end = $loc;
        }
        push @ranges, [ $r_start, $r_end ];

        if (wantarray) {
            return @ranges;
        }
        else {
            return \@ranges;
        }
    }

    # - internal methods
    sub prepare_models {
        my $self = shift;
        my @models = ( $self->{seed}, @{ $self->{minis} } );
        foreach my $model (@models) {
            $model->prepare_hmm_model;
        }
    }

    sub run_hmmsearches {
        my $self   = shift;
        my $seq_db = $self->{seq_db};
        my @models = ( $self->{seed}, @{ $self->{minis} } );
        my $parallel = $self->{parallel};
        my $evalue_cutoff = $self->{evalue_cutoff} || 10;
        
        if (! $parallel) {
            foreach my $model (@models) {
                $model->run_hmm($seq_db);
            }
            return 1;
        }
        else {
            ## - run parallel HMM search
            my $dir = $self->{dir};
    
            my $phmm_cmd = "$phmmsearch --project 04033 -s $seq_db --validate-fasta=no --database $dir -o $dir -w -b 1 --evalue $evalue_cutoff";
            warn "Phmmsearch command $phmm_cmd\n";
            my $res = system($phmm_cmd);
            $res >>= 8;
            if ($res) {
                warn "Failed parallel HMM search. Returned error code $res";
            }
    
            foreach my $model (@models) {
                my $hmm_name  = $model->get_hmm_file;
                my $hits_file = "$hmm_name.hits";
                print "$hits_file\n";
                if ( -f $hits_file ) {
                    $model->set_hits_file($hits_file);
                }
                else {
                    warn "Could not find hits file $hits_file.\n";
                }
            }
#            return !$res;
            return 1;
        }
    }

    sub get_ignoreable_hits {
       # warn "Getting Ignoreable hits";
        my $self = shift;
        my $exclude_text = $self->{exclude_text};
        my $seed = $self->{seed};

        # get ignorable hits == hits which are shorter than the parent HMM length and still score greater than noise to the parent HMM.
        my $trusted_cutoff = $self->{trusted_cutoff};
        my $noise_cutoff = $self->{noise_cutoff};
        my @hits_above_cutoff = $seed->get_hits($trusted_cutoff);
        my @hits_above_noise = $seed->get_hits($noise_cutoff);
        my @ignoreable_hits;
        if ($exclude_text) {
            #warn "Manually excluding $exclude_text\n";
            my @ignoreable_accessions = split(/\s+/, $exclude_text);
            foreach my $ignoreable_accession (@ignoreable_accessions) {
                #warn "  exclude $ignoreable_accession\n";
                push @ignoreable_hits, _Hit->new({hit_accession => $ignoreable_accession});

            }

        }
        foreach my $above_noise_hit (@hits_above_noise) {
          #  warn "Above noise Hits: \n", Dumper(\@hits_above_noise), "\n";
            my $acc = $above_noise_hit->hit_accession;
            my $hit_end = $above_noise_hit->hit_end;
            my $hit_start = $above_noise_hit->hit_start;
            #my $hmm_end = $trusted_hit->hmm_end;
            my $filtered_model_length = $self->{gap_filtered}->length;
            my $delta = $filtered_model_length - ($hit_end - $hit_start);
            my $percent = ($hit_end - $hit_start) / $filtered_model_length * 100;
            my $mini_length = $self->{model_length};
            if (($delta > ($mini_length * 1.5)) || ($percent <= 85)) {
                push @ignoreable_hits, $above_noise_hit;
            }
        }
       # warn "Ignored Hits: \n",Dumper(\@ignoreable_hits),"\n";
        return @ignoreable_hits;
    }

    sub generate_profiles {
        my $self   = shift;
        my @minis  = @{ $self->{minis} };
        my $seq_db = $self->{seq_db};
        my $filtered_parent_length = $self->{gap_filtered}->length;

        # get all hits for seed
        my $seed           = $self->{seed};

        my @hits_for_seed  = $seed->get_hits();
	#print "\n\n $hits_for_seed[0]->{total_score} \n\n";
	#print "\n\n $self->{trusted_cutoff} \n\n";

        my $trusted_cutoff = $self->{trusted_cutoff};
        my @above_trusted_hits = grep { $_->total_score >= $trusted_cutoff } @hits_for_seed;
        my $noise_cutoff = $self->{noise_cutoff};
        my @below_noise_hits = grep { $_->total_score < $noise_cutoff } @hits_for_seed;

        my %trust_set = map {$_->hit_accession => $_} @above_trusted_hits;

        # set ignorable hits
        my @manual_length_filtered = $self->get_ignoreable_hits();
        my %ignoreable_hits;
        $ignoreable_hits{"Manual or Length Filtered"}=\@manual_length_filtered;

        # for each sub-alignment, get profiles at 100, 95,90,80% specificity
        my %profiles;

        # hash to store non-hits and blast match results
        my %non_hits;
        my %blast_results;

        my $specificity = 100;
        my @threads;  
        #$threads[0] = ();
        #$threads[1] = [$seq_db, $specificity, $filtered_parent_length, \@above_trusted_hits, \@below_noise_hits, \@manual_length_filtered, \%blast_results, \%non_hits];
        my $pl = Parallel::Loops->new(4*scalar(@minis));
        $pl->share(\@threads);

        #foreach my $specificity (@SPECIFICITY_CUTOFFS) {
            $pl->foreach(\@minis,sub{

                my $mini_name = $_->get_name;
                print "\n Creating fork for: ", $mini_name, "\t", $specificity, "\n";

                #my $mini = $_;
                my $thread = get_cutoff_for_specificity($_, $seq_db, $specificity, $filtered_parent_length,
                    \@above_trusted_hits, \@below_noise_hits, \@manual_length_filtered, \%blast_results, \%non_hits );
                #my $thread = $mini->get_cutoff_for_specificity(@{$threads[1]});
                #my $thread = $mini_name;

                print "\n in fork loop ";
                
                #push(@{$threads[0]}, [$thread, $_, $specificity]);
                push(@threads, [$thread, $_, $specificity]);

            });
        #}

        print "\n\n\n ***** outside fork loop";
        print "\n\nsleeping right before qstat\n\n";
        sleep(30);
        
        my $qstat = `qstat`;
        while (length($qstat) > 0) {
              print "\n\ninside qstat\n\n";
              $qstat = `qstat`;
              print "\n ************************ \n BLAST jobs still running on grid :: \n\n".$qstat."\n ************************* \n";
              sleep(30);
        }

        #we BLAST all specificities in parallel (instead of skipping the subsequent ones based on comparison with sensitivity - see ln.222 in mother code) 
        my %skip_profile; 

        foreach my $thread (@threads) {

                my $mini = $thread->[1];
                my $mini_name = $mini->get_name;

                if ($skip_profile{$mini_name}) {
                   next;
                }
                
                print "\n\n@@@@ iterating inside threads @@@@ \n\n";

                my $mini_cutoff_filtered = $thread->[0];
                my $mini_cutoff = shift @$mini_cutoff_filtered;
                my $specificity = $thread->[2];

                my $all_ignored =
                [ @manual_length_filtered, @$mini_cutoff_filtered ];
                my $key_for_ignored =
                "Blast_filtered\t" . $mini_name . "\t" . $specificity;
                $ignoreable_hits{$key_for_ignored} = $mini_cutoff_filtered;

                $profiles{$mini_name}{$specificity} =
                $mini->get_profile_at_cutoff( $mini_cutoff,
                    \@above_trusted_hits, $all_ignored );
                if ( $profiles{$mini_name}{$specificity}->sensitivity >= 100 ) {
                    $skip_profile{$mini_name} = 1;
                }

                else {$profiles{$mini_name}{$specificity} = _Profile->new();}
        }

        $self->{profiles}     = \%profiles;
        $self->{ignored_hits} = \%ignoreable_hits;
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
                        print "---- $hit->hit_accession \t $db \n ----";
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
                        print "---- $hit->hit_accession \t $db \n ----";
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











    sub calculate_overall_sensitivity_at_specificity100 {
        my $self              = shift;
        my @minis             = @{ $self->{minis} };
        my $seed              = $self->{seed};
        my $trusted_cutoff    = $self->{trusted_cutoff};
        my @hits_above_cutoff = $seed->get_hits($trusted_cutoff);
        my %hit_set           =
        map { $_->hit_accession => 1 }
        @hits_above_cutoff;    ### don't need this?
        my %ignored = %{ $self->{ignored_hits} };
        my @ignoreable_hits;

        foreach my $type ( keys %ignored ) {
            push @ignoreable_hits, @{ $ignored{$type} };
        }
        my %ignore_set = map { $_->hit_accession => 1 } @ignoreable_hits;

        my $mini_sensitivity_threshhold =
        35;    # make this an input on the form with a default of 35
        my $overall_sensitivity;
        my $mini_hit_count;
        my $this_hit_count;
        my $minis_above_thresh;
        open my $out, ">", "analysis.txt";
        foreach my $mini (@minis) {
            my $mini_name        = $mini->get_name;
            my $profile100       = $self->{profiles}{$mini_name}{100};
	    if (!$profile100) {next;}
            my $mini_sensitivity = $profile100->sensitivity;
            if ( $mini_sensitivity >= $mini_sensitivity_threshhold ) {
                $minis_above_thresh++;
            }
        }
        print $out
"There are $minis_above_thresh minis above the sensitivity threshhold of $mini_sensitivity_threshhold\%\n\n";

        my $total_count  = 0;
        my $ignore_count = 0;
        foreach my $hit (@hits_above_cutoff) {
            my $hit_accession = $hit->hit_accession;
            my $hit_score     = $hit->total_score;
            $total_count++;
            if ( $ignore_set{$hit_accession} ) {
                $ignore_count++;
                next;
            }
            $this_hit_count = 0;
            my $flag = 0;
            foreach my $mini (@minis) {
                my $mini_name        = $mini->get_name;
                my $profile100       = $self->{profiles}{$mini_name}{100};
                my $mini_sensitivity = $profile100->sensitivity;
                if ( $mini_sensitivity >= $mini_sensitivity_threshhold ) {
                    my @matches = @{ $profile100->matches };
                    my %mini_set = map { $_->hit_accession => 1 } @matches;
                    if ( $mini_set{$hit_accession} ) {
                        if ( $flag == 0 ) {
                            $mini_hit_count++;
                            $flag = 1;
                        }
                        $this_hit_count++;
                    }
                }
            }
            print $out $hit_accession, "\t", $hit_score, "\t", $this_hit_count,
            "\n";
        }
	if ($total_count) {
        $overall_sensitivity =
        ( $mini_hit_count + $ignore_count ) / $total_count * 100;
	}
	else {$overall_sensitivity = 0;}
        print $out "\n\n overall sensitivity = ", $overall_sensitivity;
        close $out;
    }

    sub create_tiled_minis {
        my $self          = shift;
        my $filtered      = $self->{gap_filtered};
        my $gap_map       = $self->{gap_map};
        my $model_length  = $self->{model_length};
        my $model_overlap = $self->{model_overlap} || int( $model_length / 2 );
        my $model_offset  = $model_length - $model_overlap;
        die "Model overlap $model_overlap >= model length $model_length\n"
        if ( $model_offset <= 0 );
        my @minis;
        my $n = 0;

        for ( my $s = 0 ; $s < $filtered->length ; $s += $model_offset ) {
            $n++;
            my $start = $s;
            my $end   = $start + $model_length - 1;
            if ( $end >= $filtered->length ) {
                $end   = $filtered->length - 1;
                $start = $end - $model_length;
            }
            my $name = sprintf( "%s.mini.%02d", ( $self->{prefix}, $n ) );
            my $mini_file_name = "$name.afa";
            my $mini = $filtered->get_sub_alignment( $start, $end );
            $mini->save($mini_file_name);
            my $model = miniHMM::HmmModel->new(
                {
                    name      => $name,
                    alignment => $mini,
                    db        => $self->{seq_db},
                    evalue_cutoff => ($self->{evalue_cutoff} || 10),
                }
            );
            $self->{residues}{$name} = [ @$gap_map[ $start + 1 .. $end + 1 ] ];
            push @minis, $model;
            last
            if ( $end == $filtered->length - 1 )
            ;    #stop if we're at the end of the sequence
        }
        if (wantarray) {
            return @minis;
        }
        else {
            return \@minis;
        }
    }

    sub create_paired_minis {
        my $self         = shift;
        my $gap_map      = $self->{gap_map};
        my $filtered     = $self->{gap_filtered};
        my $model_length = $self->{model_length};
        my @minis;

        # n-terminal
        my $left_begin = 0;
        my $left_end   = $model_length - 1;
        my $left_model = $filtered->get_sub_alignment( $left_begin, $left_end );
        my $lname      = $self->{prefix} . ".01.nterm";
        my $left_file_name = "$lname.afa";
        $left_model->save($left_file_name);
        push @minis,
        miniHMM::HmmModel->new(
            {
                name      => $lname,
                alignment => $left_model,
                db        => $self->{seq_db},
                evalue_cutoff => ($self->{evalue_cutoff} || 10),
            }
        );
        $self->{residues}{$lname} = [ @$gap_map[ $left_begin .. $left_end ] ];

        # c-terminal
        my $right_begin = $filtered->length - $model_length - 1;
        my $right_end   = $filtered->length - 1;
        my $right_model =
        $filtered->get_sub_alignment( $right_begin, $right_end );
        my $rname           = $self->{prefix} . ".02.cterm";
        my $right_file_name = "$rname.afa";
        $right_model->save($right_file_name);
        push @minis,
        miniHMM::HmmModel->new(
            {
                name      => $rname,
                alignment => $right_model,
                db        => $self->{seq_db},
                evalue_cutoff => ($self->{evalue_cutoff} || 10),
            }
        );
        $self->{residues}{$rname} = [ @$gap_map[ $right_begin .. $right_end ] ];

        if (wantarray) {
            return @minis;
        }
        else {
            return \@minis;
        }
    }

    sub write_run_settings {
        my $self = shift;
        my $file = shift;
        if ($file) {
            open my $out, ">>", $file;
            if ( !$out ) {
                warn "Can't save settings to $file. $!\n";
                return;
            }
            print $out "Run started ", scalar(localtime), ".\n";
            print $out "Parameters:\n";
            foreach my $key ( sort @INPUT_FIELDS ) {
                my $value = $self->{$key};
                if ( not defined $value ) {
                    $value = '';
                }
                print $out "  $key => $value\n";
            }
            print $out "Mini-Models:\n";
            foreach my $mini ( @{ $self->{minis} } ) {
                my @ranges =
                list_to_range( $self->{residues}{ $mini->get_name } );
                @ranges =
                map { $_->[1] ? $_->[0] . "-" . $_->[1] : $_->[0] } @ranges;
                print $out "  ", $mini->get_name, ": residues ",
                join( ", ", @ranges ), "\n";
            }
            close $out;
        }
    }

    sub write_ignored_hits {
        my $self         = shift;
        my $ignored_hits = $self->{ignored_hits};

        if ($ignored_hits) {
            open my $out, ">", "ignored_hits.txt";
            if ( not $out ) {
                warn "Can't write ignored_hits. $!\n";
                return;
            }

            foreach my $type ( sort { $b cmp $a } keys %$ignored_hits ) {
                foreach my $hit ( @{ $ignored_hits->{$type} } ) {
                    print $out $hit->hit_accession, "\t", $type, "\n";
                }
            }

            close $out;
        }
    }

    sub write_sticky_hits {    ################JDS
        my $self = shift;
        open my $out, ">", "sticky_hits.txt";
        if ( not $out ) {
            warn "Can't write sticky_hits. $!\n";
            return;
        }
        foreach my $mini ( @{ $self->{minis} } ) {
            my $mini_name  = $mini->get_name;
            my $profile100 = $self->{profiles}{$mini_name}{100};
            my $LOWprofile;
	    if (!$profile100) {next;}
            foreach my $LOW (@SPECIFICITY_CUTOFFS) {
                if ( $self->{profiles}{$mini_name}{$LOW} ) {
                    $LOWprofile = $self->{profiles}{$mini_name}{$LOW};
                }
                else {
                    last;
                }
            }
            my $lcs         = $profile100->lower_cutoff_score;
            my @misses      = @{ $LOWprofile->misses };
            my @sticky_hits = grep { $_->total_score == $lcs } @misses;

#print $out "looking at mini $mini_name", ".  Number of misses is ", scalar(@misses), "\n" ;
            foreach my $h (@sticky_hits) {
                print $out $h->hit_accession, "\t", $mini_name, "\n";
            }
        }
        close $out;
    }

    sub write_mini_profiles {
        my $self = shift;
        foreach my $mini ( @{ $self->{minis} } ) {
            my $mini_name = $mini->get_name;
            open my $out, ">", "$mini_name.profile.txt";
            if ( not $out ) {
                warn "Can't save profile output file. $!\n";
                return;
            }
            my @table = $self->get_mini_profile_table($mini);
            foreach my $row (@table) {
                print $out join( "\t", @$row ), "\n";
            }
            close $out;
        }
    }

    sub get_mini_profile_table {
        my $self = shift;
        my $mini = shift;
        return unless ($mini);
        my $mini_name      = $mini->get_name;
        my $seed           = $self->{seed};
        my $trusted_cutoff = $self->{trusted_cutoff};
        my @seed_hit_names =
        map { $_->hit_accession } @{ $seed->get_hits($trusted_cutoff) };
        my @fields = (
            'Upper Score Cutoff',
            'Lower Score Cutoff',
            '% Specificity',
            '% Sensitivity',
            'Match Count',
            'Miss Count',
            'Skip Count',
            @seed_hit_names
        );
        my @profile_results;
        #my @profiles =
        #sort { $b->cutoff <=> $a->cutoff }
        #values %{ $self->{profiles}{$mini_name} };
	my @profiles = ();
	{ no warnings qw/uninitialized/;
	@profiles = sort { $b->cutoff <=> $a->cutoff }
	       values %{ $self->{profiles}{$mini_name} };
	}
        my $last_score_cutoff;

        foreach my $profile (@profiles) {
            if ( !defined ($profile->cutoff) or ($last_score_cutoff and $profile->cutoff == $last_score_cutoff) )
            {
                next;    # skip identical or empty profiles
            }
	    
            my $lower_cutoff = $profile->lower_cutoff_score;
            if ( not defined $lower_cutoff ) {
                $lower_cutoff = 'None';
            }
            my %profile_result = (
                'Upper Score Cutoff' => $profile->upper_cutoff_score,
                'Lower Score Cutoff' => $lower_cutoff,
                '% Specificity' => sprintf( '%02.1f', $profile->specificity ),
                '% Sensitivity' => sprintf( '%02.1f', $profile->sensitivity ),
                'Match Count' => scalar( @{ $profile->matches } ),
                'Miss Count'  => scalar( @{ $profile->misses } ),
                'Skip Count'  => scalar( @{ $profile->ignored } ),
            );

            my %match_set =
            map { $_->hit_accession => $_ } @{ $profile->matches };
            foreach my $hit_name (@seed_hit_names) {
                if ( my $hit = $match_set{$hit_name} ) {
                    $profile_result{$hit_name} = $hit->total_score;
                }
                else {
                    $profile_result{$hit_name} = '(no hit to parent)';
                }
            }
            push @profile_results, \%profile_result;
            $last_score_cutoff = $profile->cutoff;
        }

        # - merge result tables
	print YAML::Dump(\@profile_results);
        my @result_table;
        foreach my $field (@fields) {
            push @result_table,
            [ $field, ( map { $_->{$field} } @profile_results ) ];
        }
        if (wantarray) {
            return @result_table;
        }
        else {
            return \@result_table;
        }
    }

    # - methods
    sub new {
        my $class    = shift;
        my $param_hr = shift;
        my $self     = bless( {}, $class );

        # TODO validate fields
        @$self{@INPUT_FIELDS} = @$param_hr{@INPUT_FIELDS};

        my $seed_file_name =
        catfile( $param_hr->{dir}, $param_hr->{seed_file} );
        $self->{seed_alignment} =
        miniHMM::Alignment->new($seed_file_name);
        if ( $self->{seed_alignment} ) {
            $self->{seed} = miniHMM::HmmModel->new(
                {
                    alignment      => $self->{seed_alignment},
                    name           => $self->{prefix},
                    alignment_file => $seed_file_name,
                    db             => $self->{seq_db},
                    evalue_cutoff => ($self->{evalue_cutoff} || 10),
                }
            );
            return $self;
        }
        else {
            return;
        }
    }

    sub prepare {
        my $self = shift;
        my $seed = $self->{seed}{alignment};

        # gap filter and set up gap map
        my ( $filtered, $gaps ) = $seed->get_gap_trimmed( $self->{gap_filter} );
        if ($filtered) {
            $filtered->save( $self->{prefix} . ".gap_filter.afa" );
        }
        else {
            warn "Could not filter seed file\n";
            return;
        }
        $self->{gap_filtered} = $filtered;
        $self->{gap_map} = create_gap_map( $filtered->length, $gaps );
        YAML::DumpFile( "gap_map.log", $self->{gap_map} );

        # get sub-alignments
        $self->{minis} = [];
        if ( $self->{model_type} eq 'tiles' ) {
            $self->{minis} = $self->create_tiled_minis;
        }
        elsif ( $self->{model_type} eq 'pairs' ) {
            $self->{minis} = $self->create_paired_minis;
        }
        else {
            warn "Invalid mini-model type $self->{model_type}\n";
        }

        $self->write_run_settings('run_parameters.txt');
        return 1;
    }

    sub run {
        warn "Starting run\n";
        my $self = shift;

#        # prep seed and minis for hmm (hmmbuild step)
        $self->prepare_models();

        # do hmm evaluation on all models (seed and mini-models);
        warn "Running hmmsearches\n";
        $self->run_hmmsearches();
#        my $qstat = `qstat`;
#        while (length($qstat) > 0) {
#              $qstat = `qstat`;
#              print "\n ************************ \n Hmmsearch jobs still running on grid :: \n\n".$qstat."\n ************************* \n";
#              sleep(30);
#        }
#
        if ( ! @{$self->{seed}->get_hits($self->{trusted_cutoff})} ) {
		die "Seed HMM has no hits to specified database!\n";
	}

        # generate profiles
        $self->generate_profiles();
exit;
#
#        if ( ! @{$self->{seed}->get_hits($self->{trusted_cutoff})} ) {
#		die "Seed HMM has no hits to specified database!\n";
#	}
#
#        $self->write_mini_profiles();
#
#        $self->write_ignored_hits();
#        $self->write_sticky_hits();    ##########JDS
#
#        $self->calculate_overall_sensitivity_at_specificity100();
#
#        # return values
#        warn "Completed run\n";
#        my %summary;
#        $summary{specificity_cutoffs}    = [@SPECIFICITY_CUTOFFS];
#        $summary{seed_hits_above_cutoff} =
#        [ map { $_->hit_accession }
#            $self->{seed}->get_hits( $self->{trusted_cutoff} ) ];
#        $summary{profiles_by_mini} = [];
#        foreach my $mini ( @{ $self->{minis} } ) {
#            my %mini_summary;
#            my $mini_name = $mini->get_name;
#            $mini_summary{mini_name} = $mini_name;
#            $mini_summary{profiles}  = $self->{profiles}{$mini_name};
#            my @ranges = list_to_range( $self->{residues}{$mini_name} );
#            $mini_summary{mini_range} = join( ', ',
#                map { ( defined $_->[1] ) ? $_->[0] . "-" . $_->[1] : $_->[0] }
#                @ranges );
#            push @{ $summary{profiles_by_mini} }, \%mini_summary;
#        }
#        return \%summary;
    }
}

1;    # Magic true value required at end of module
