#!/usr/local/bin/perl
#### Plan: given an path to a mini_hmm directory, a db to search against
# filename (an hmm accession)
$htab_path = $ARGV[ 0 ];
$info_path = $ARGV[ 1 ];
$cutoff    = $ARGV[ 2 ];
open( INFO, "<$info_path" );
while ( <INFO> ) {

#    print $_;
    if ( /HMMFILE/ ) {
        chomp;
        $hmm = $_;
        $hmm =~ s/.+: //;
        $hmm =~ s/\..+//;
    }
    if ( $cutoff eq "" ) {
        if ( /TC100/ ) {
            chomp;
            $TC = $_;
            $TC =~ s/.+: //;
            $TC{ $hmm } = $TC;
        }
    }
    elsif ( $cutoff eq "90" ) {
        if ( /TC90/ ) {
            chomp;
            $TC = $_;
            $TC =~ s/.+: //;
            $TC{ $hmm } = $TC;
        }
    }
}
close INFO;
open( HTAB, "<$htab_path" );
while ( <HTAB> ) {
    @F     = split( /\t/ );
    $hmm   = $F[ 0 ];
    $score = $F[ 11 ];
    if ( $score >= $TC{ $hmm } ) {
        print;
    }
}
close HTAB;
