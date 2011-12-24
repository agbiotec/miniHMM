#!/usr/local/bin/perl
#### Plan: given an path to a mini_hmm directory, a db to search against
# filename (an hmm accession)
$mini_path = $ARGV[ 0 ];
$db_path   = $ARGV[ 1 ];

#get the mini-info file to figure out which mini-hmms to run.
$acc = $mini_path;
$acc =~ s/_mini_dir\///;  ## strips off file type information
$acc =~ s/.+\///;         ## strips off path info if it was supplied
$info_path = "$mini_path/$acc.MINIINFO";
open( INFO, "<$info_path" );
while ( <INFO> ) {
    if ( /HMMFILE/ ) {
        chomp;
        $hmm_path = $_;
        $hmm_path =~ s/.+: //;
        push @hmms, $mini_path . "/" . $hmm_path;
    }
}
close INFO;
## create a runfile
open( RUN, ">runfile" );
foreach $hmm_file ( @hmms ) {
    print RUN
      "hmmsearch --frames \"1 2 3 -1 -2 -3\" -E 100 $hmm_file $db_path | /usr/local/devel/ANNOTATION/hmm/bin/htab.pl -s \n"
      ;
}
close RUN;
$command = "chmod 777 runfile";
system $command;
$command = "$ENV{'PWD'}/runfile\n";
system $command;
