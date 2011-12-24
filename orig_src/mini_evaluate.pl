#!/usr/local/bin/perl
# filename (an hmm accession)
$F   = $ARGV[ 0 ];
$acc = $F;
$acc =~ s/.+\///;  ## strips off path info if it was supplied
$acc =~ s/\..+//;  ## strips off file type information
## looks for an .htab file in this directory
if ( -e "$acc.htab" ) {

#    print "\n$acc.htab exists!\n";
    $htab_path = $acc . ".htab";
}
elsif ( -e "$acc.omni" ) {  ## if there is an hmm results vs. omni file
    $command2 = "cat $acc.omni | htab.pl -s > $acc.htab";
    print "\n$command2\n";
    system $command2;
}
elsif ( -e "$acc.hmm" )
{  ## if there is a version of the hmm in this directory
    $command1 =
      "hmmsearch $hmm_path /usr/local/db/omnium/internal/OMNIOME.pep > $acc.omni";
    print "\n$command1\n";
    $hmm_path = "$acc.hmm";
    system $command1;
    $command2 = "cat $acc.omni | htab.pl -s > $acc.htab";
    print "\n$command2\n";
    system $command2;
}
else {
    $hmm_path = "/usr/local/db/HMM_IND/$acc.HMM";
    $command1 =
      "hmmsearch $hmm_path /usr/local/db/omnium/internal/OMNIOME.pep > $acc.omni";
    print "\n$command1\n";
    system $command1;
    $command2 = "cat $acc.omni | htab.pl -s > $acc.htab";
    print "\n$command2\n";
    system $command2;
}
##
open( HTAB, "<$acc.htab" );
$Tot_trusted = 0;
while ( <HTAB> ) {
    @F         = split( /\t/ );
    $TC        = $F[ 17 ];
    $NC        = $F[ 18 ];
    $accession = $F[ 5 ];
    $score     = $F[ 11 ];
    if ( $score >= $TC ) {
        $class = "TRUSTED";
        if ( $FULL{ $accession } eq "" ) {
            $Tot_trusted++;
        }
    }
    elsif ( $score >= $NC ) {
        $class = "GREY";

#	print "$accession\t$score\n";
    }
    else {
        $class = "NOISE";
    }
    $FULL{ $accession } = $class;
}
close HTAB;
$search_string1 =
  $acc . "_";  ## only get the files with an extension, not the originals
$search_string2 = ".htab";  ## only get the htab files
$search_string3 = ".MINI";  ## only get the MINI (hmm) files
$command        =
  "ls -l | grep $search_string1 | grep $search_string2 > mini_htabs.temp";
system $command;
$command =
  "ls -l | grep $search_string1 | grep $search_string3 > mini_MINIs.temp";
system $command;
$command = "chmod 777 mini_htabs.temp";
$command = "chmod 777 mini_MINIs.temp";
system $command;
open( MINIs, "<mini_MINIs.temp" );
open( HTABs, "<mini_htabs.temp" );

while ( <MINIs> ) {
    @F = split( /\s+/ );
    unless ( $F[ 7 ] =~ /SEED/ ) {
        push @mini_files, $F[ 7 ];
        $mini = $F[ 7 ];
        $mini =~ s/.+_(.+)\..+/$1/;
        $minis[ $mini ] = $mini;
        $minifiles{ $mini } = $F[ 7 ];
    }
}
close MINIs;
while ( <HTABs> ) {
    @F = split( /\s+/ );
    push @htab_files, $F[ 7 ];

#    print "$F[7]\n";
}
close HTABs;
foreach $file ( @mini_files ) {
    $done = "NO";
    $a    = $file;
    $a =~ s/\..+//;
    foreach $htab ( @htab_files ) {
        $b = $htab;
        $b =~ s/\..+//;

#	print "\nTEST: $file eq $htab\n";
        if ( $a eq $b ) {
            $done = "YES";
        }
    }
    if ( $done eq "NO" ) {
        $htab_path = $file;
        $htab_path =~ s/MINI/htab/;
        $command3 =
          "hmmsearch -E 100 $file /usr/local/db/omnium/internal/OMNIOME.pep | htab.pl -s > $htab_path";
        print "\n$command3\n";
        system $command3;
    }
}
foreach $htab ( @mini_files ) {
    $htab =~ s/MINI/htab/;
    $mini = $htab;
    $mini =~ s/.+_(.+)\..+/$1/;
    $minis[ $mini ] = $mini;

#   print "--------------$minis[$mini]-------------\n";
#    print "\n$htab\n";
    open( HTAB, "<$htab" );
    foreach $key ( keys %scores ) {
        delete $scores{ $key };
    }
    $Num_so_far  = 0;
    $Num_trusted = 0;
    $Num_noise   = 0;
    while ( <HTAB> ) {

#	print "$_";
        @F         = split( /\t/ );
        $accession = $F[ 5 ];
        $score     =
          $F[ 12 ]
          ;  ## this is the total score, we should be looking at the local
        $domain_score = $F[ 11 ];
        unless ( $score == $domain_score ) {
            next;  ## chuck anything that hits more than once to the molecule
        }
        $scores{ $score } = $accession;

#	print "$accession\t$score\n";
        if ( $MINI{ $mini }{ $accession } eq "" ) {
            $Num_so_far++;

#	    print "$Num_so_far\n";
#	    print "$FULL{$accession}\n";
            if ( $FULL{ $accession } eq "TRUSTED" ) {
                $Num_trusted++;

#		print "TRUSTED\n";
            }
            elsif ( $FULL{ $accession } eq "NOISE" ) {
                $Num_noise++;

#		print "NOISE\n";
            }
            elsif ( $FULL{ $accession } eq "GREY" ) {

#		print "GREY\n";
            }
            else {
                $Num_noise++;
                $FULL{ $accession } = "*ABSENT*";

#		print "MISSING!!!\n";
            }
            $sensitivity = $Num_trusted / $Tot_trusted;

#	    print "sensitivity = $sensitivity\t";
            unless ( ( $Num_trusted + $Num_noise ) == 0 ) {
                $specificity = $Num_trusted / ( $Num_trusted + $Num_noise );
            }

#	    print "specificity = $specificity\n";
            $sensitivity{ $score } = $sensitivity;
            $specificity{ $score } = $specificity;
        }
        $MINI{ $mini }{ $accession } = $score;
    }

#    print "\n\nMini_model #".$mini.":\n\n";
#    print "score\tsensitivity\tspecificity\n\n";
    foreach $score ( sort descending keys %scores ) {
        unless ( $score eq "" ) {

#	    print "$score\t$scores{$score}\t$FULL{$scores{$score}}\t$sensitivity{$score}\t$specificity{$score}\n";
            if ( $sensitivity{ $score } > $highest_sens_seen_so_far ) {
                $highest_sens_seen_so_far     = $sensitivity{ $score };
                $score_at_highest_sens_so_far = $score;
            }
            if ( $specificity{ $score } >= $highest_spec_seen_so_far ) {
                $highest_spec_seen_so_far    = $specificity{ $score };
                $sens_at_highest_spec_so_far = $sensitivity{ $score };
                $lowest_score_at_highest_spec_so_far = $score;
            }
            $sum_SS = $specificity{ $score } + $sensitivity{ $score };
            if ( $sum_SS > $highest_sum_SS_seen_so_far ) {
                $highest_sum_SS_seen_so_far = $sum_SS;
                $high_score_at_high_sum     = $score;
            }
            if ( $sum_SS = $highest_sum_SS_seen_so_far ) {
                $low_score_at_high_sum   = $score;
                $score_range_at_high_sum =
                  $high_score_at_high_sum - $low_score_at_high_sum;
            }
            if ( $specificity{ $score } >= 0.9 ) {
                $TC90      = $score;
                $TC90_sens = $sensitivity{ $score };
            }
            if ( $specificity{ $score } >= 0.85 ) {
                $TC85      = $score;
                $TC85_sens = $sensitivity{ $score };
            }
        }
    }
    $max_sensitivity{ $mini }          = $highest_sens_seen_so_far;
    $max_specificity{ $mini }          = $highest_spec_seen_so_far;
    $sens_at_max_spec{ $mini }         = $sens_at_highest_spec_so_far;
    $lowest_score_at_max_spec{ $mini } =
      $lowest_score_at_highest_spec_so_far;
    $max_sum_SS{ $mini } = $highest_sum_SS_seen_so_far;
    $TC90{ $mini }       = $TC90;
    $TC90_sens{ $mini }  = $TC90_sens;
    $TC85{ $mini }       = $TC85;
    $TC85_sens{ $mini }  = $TC85_sens;

#    print "\n\n";
    close HTAB;
    $highest_sens_seen_so_far     = 0;
    $score_at_highest_sens_so_far = 0;
    $highest_spec_seen_so_far     = 0;
    $sens_at_highest_spec_so_far  = 0;
    $highest_sum_SS_seen_so_far   = 0;
    $high_score_at_high_sum       = 0;
    $low_score_at_high_sum        = 0;
    $score_range_at_high_sum      = 0;
}
open( INFO, ">$acc.MINIINFO" );

#print "model\tSENS(m)\tscore\tSPEC(m)\tscore\tsens(s)\tSUM(m)\tscore\trange\n\n";
foreach $mini ( @minis ) {
    $F1 = $max_sensitivity{ $mini };
    $F1 =~ s/(.....).+/$1/;
    $F2 = $max_specificity{ $mini };
    $F2 =~ s/(.....).+/$1/;
    $F3 = $max_sum_SS{ $mini };
    $F3 =~ s/(.....).+/$1/;
    $F4 = $sens_at_max_spec{ $mini };
    $F4 =~ s/(.....).+/$1/;
    $F5 = $TC90_sens{ $mini };
    $F5 =~ s/(.....).+/$1/;
    $F6 = $TC85_sens{ $mini };
    $F6 =~ s/(.....).+/$1/;

#    print "$mini\t$F1\t$score_at_max_sens{$mini}\t$F2\t";
#    print "$lowest_score_at_max_spec{$mini}\t$F4\t$F3\t$low_score_at_max_sum{$mini}\t$score_range_at_max_sum{$mini}\n";
    if ( $max_sensitivity{ $mini } >= 0.1 ) {
        if ( $F2 == 1 ) {
            $TC{ $mini } = $lowest_score_at_max_spec{ $mini };
            print INFO "HMMFILE: $minifiles{$mini}\n" ;
            print INFO "TC100: $TC{$mini}\n" ;
            print INFO "Sensitivity: $F4\n" ;
            print INFO "TC90: $TC90{$mini}\n" ;
            print INFO "Sensitivity: $F5\n" ;
            print INFO "TC85: $TC85{$mini}\n" ;
            print INFO "Sensitivity: $F6\n" ;
            print INFO "\n" ;
        }
    }
}
foreach $accession ( keys %FULL ) {
    if ( $FULL{ $accession } eq "TRUSTED" ) {
        foreach $mini ( @minis ) {
            unless ( $TC{ $mini } eq "" ) {
                if ( $MINI{ $mini }{ $accession } >= $TC{ $mini } ) {
                    $num_minis_hit{ $accession } =
                      $num_minis_hit{ $accession } + 1;
                    $minis_contributing{ $mini } = "YES";
                }
                if ( $MINI{ $mini }{ $accession } >= $TC90{ $mini } ) {
                    $num_90{ $accession } = $num_90{ $accession } + 1;
                }
                if ( $MINI{ $mini }{ $accession } >= $TC85{ $mini } ) {
                    $num_85{ $accession } = $num_85{ $accession } + 1;
                }
            }
        }

#	print "$accession\t$num_minis_hit{$accession}\n";
        if ( $num_minis_hit{ $accession } > 0 ) {
            $found_hits++;
        }
        if ( $num_90{ $accession } > 0 ) {
            $found_hits90++;
        }
        if ( $num_85{ $accession } > 0 ) {
            $found_hits85++;
        }
        $all_hits++;
    }
}
unless ( $all_hits == 0 ) {
    $overall_sensitivity = &trunc( $found_hits / $all_hits );
    $overall_90          = &trunc( $found_hits90 / $all_hits );
    $overall_85          = &trunc( $found_hits85 / $all_hits );
    foreach $mini ( keys %minis_contributing ) {
        $num_minis_contributing++;
    }
    print
      "\nOverall sensitivity = $overall_sensitivity\tNumber of mini models contributing: $num_minis_contributing\n\n";
    print INFO
      "\n\nOverall sensitivity at 100% specificity: $overall_sensitivity" ;
    print INFO "\nOverall sensitivity at 90% specificity: $overall_90" ;
    print INFO "\nOverall sensitivity at 85% specificity: $overall_85" ;
    print INFO "\n" ;
}
close INFO;

sub descending {
    $b <=> $a;
}

sub trunc {
    my ( $in ) = @_;
    $in =~ s/(.....).+/$1/;
    return $in;
}
