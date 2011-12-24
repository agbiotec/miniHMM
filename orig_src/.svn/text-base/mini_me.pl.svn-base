#!/usr/local/bin/perl
# window width
$W = 24;

# step length
$P = 12;

# gap filter (percent)
$Q = 65;

# file
$F    = $ARGV[ 0 ];
$stem = $F;
$stem =~ s/.+\///;
$gap_filtered_path = $stem;
$gap_filtered_path =~ s/\..+/.GFSEED/;

#$gap_filtered_path = "/usr/local/annotation/GENPROP/MINIMOD_dir/SELENGUT/".$gap_filtered_path;
$command = "/usr/local/bin/belvu -Q $Q -o Mul $F > $gap_filtered_path";
system $command;
open( SEED, "<$gap_filtered_path" );
while ( <SEED> ) {
    if ( /\/\// ) {
        next;
    }

#    print ": $_";
    chomp;
    $line = $_;
    $line =~ s/(\s+)/$1\*/;

#    print "\n$line\n";
    @L = split( /\*/, $line );

#    print "\n$L[1]\n";
    @chars  = split( //, $L[ 1 ] );
    $length = scalar( @chars );

#    print "\n length = $length\n";
    for ( $i = 1 ; $i < ( $length / $P ) - 1 ; $i++ ) {

#	print "\ni = $i\t";
        $seed[ $i ] .= $L[ 0 ];
        $start_pos = ( $i - 1 ) * $P;
        $end_pos   = $start_pos + $W;
        for ( $j = $start_pos ; $j < $end_pos ; $j++ ) {

#	    print "j = $j($chars[$j]) ";
            $seed[ $i ] .= $chars[ $j ];
        }
        $seed[ $i ] .= "\n";
        if ( $i * $P == $length ) {
            $skip_last = "YES";
        }
    }
    unless ( $skip_last eq "YES" ) {
## the last model, to cover the C-terminus:
        unless ( $checked eq "YES" ) {
            $num_models = scalar( @seed );
            $checked    = "YES";
        }
        $i         = $num_models + 1;
        $start_pos = $length - $W;
        $end_pos   = $length;
        $seed[ $i ] .= $L[ 0 ];
        for ( $j = $start_pos ; $j <= $end_pos ; $j++ ) {
            $seed[ $i ] .= $chars[ $j ];
        }
        $seed[ $i ] .= "\n";
    }
}
close SEED;

#print "\n\n";
$stem = $F;
$stem =~ s/.+\///;
$stem =~ s/\..+/.MINISEED/;
$n        = 0;
$log_file = $stem;
$log_file =~ s/\..+/.MINIbuild/;
if ( -e $log_file ) {
    $command = "rm $log_file";
    system $command;
}
foreach $seed ( @seed ) {
    unless ( $seed eq "" ) {
        $n++;
        $out_path = $stem;
        $out_path =~ s/\./_$n./;
        print "$out_path\n";
        open( MINI, ">$out_path" );
        print MINI "$seed\n" ;
        close MINI;
        $hmm_out = $out_path;
        $hmm_out =~ s/SEED//;
        $command =
          "/usr/local/bin/hmmbuild --amino -F $hmm_out $out_path >> $log_file";
        print "$command\n";
        system $command;
        $command =
          "/usr/local/bin/hmmcalibrate --num 1000 $hmm_out >> $log_file";
        system $command;
    }
}
