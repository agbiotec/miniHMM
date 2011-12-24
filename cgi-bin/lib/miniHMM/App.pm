package miniHMM::App; {
    use warnings;
    use strict;
    use CGI::Carp qw(confess);
    # BEGIN {
    #     $SIG{__DIE__} = sub {confess @_};
    # }

    use DBI;

    use version; our $VERSION = qv( qw$Revision 0.0.1$[1] );

    # use lib qw(/usr/local/devel/ANNOTATION/rrichter/miniHMM/cgi-bin/lib);
    use base 'CGI::Application';

    use CGI::Session;
    use CGI::Application::Plugin::Stream (qw/stream_file/);

    use Errno qw(EAGAIN);
    use File::Spec::Functions qw(catfile catdir splitpath splitdir);
    use File::Temp qw(tempdir);
    use File::Path qw/make_path/;
    use YAML;
    use Data::Dumper;
    use Template;

    use miniHMM::HmmCommand;

    # -- CGI::App overrides
    sub setup {
        my $self = shift;
        $self->mode_param(path_info=>1, param =>'rm',);
        $self->start_mode('redirect_home');
        $self->param('home', 'form');
        $self->error_mode('error');
        $self->run_modes( {
            'redirect_home' => '_redirect',
            'form'          => 'show_form',
            'go'            => 'process_form',
            'results'       => 'results',
            'download'      => 'download',
            'error'         => 'error',
        });

        # setup application directory
        my $script_path = $ENV{SCRIPT_NAME};
        $self->param('script_path',$script_path);

        # load config data
        $self->_load_config_file();

        # set up temporary directory
        my $temp_dir = $self->cfg('temp_dir');
        if (not -d $temp_dir) {
            make_path($temp_dir) or die "Can't create temporary base directory $temp_dir. $!"; # only goes 1 layer deep, so the parent must exist
        }
        $ENV{TMPDIR} = $ENV{TEMP} = $temp_dir;

    }

    # -- helper methods
    sub session {
        my $self = shift;
        my $session = $self->param('_session');
        my $temp_dir = $self->cfg('temp_dir');
        if (not $session ) {
            # get session info, if we're in one
            my @path_info = split('/', $ENV{PATH_INFO});
            my $session_type = $self->cfg('session_type');
            my $session_params = $self->cfg('session_params');
            if (@path_info >= 3) {
                my $session_id = $path_info[2];
                $session = CGI::Session->new($session_type, $session_id, $session_params);
                $self->param('_session',$session);
            }
            else {
                $session = CGI::Session->new($session_type, undef, $session_params);
                $self->param('_session',$session);
            }
        }
        return $session;
    }

    sub release_session {
        my $self = shift;
        $self->param('_session', undef);
        return $self;
    }
    sub in_session {
        my $self = shift;
        if ($self->param('_session')) {
            return 1;
        }
        else {
            return;
        }
    }

    sub _load_config_file {
        my $self = shift;
        my $config_file = $self->param('_config_file');
        my $config;
        eval {
            $config = YAML::LoadFile($config_file);
        };
        if ($@) {
            warn "Could not read Config file $config_file.\n$@";
        };
        $self->param('_config', $config);
        return $config;
    }

    sub cfg {
        my $self = shift;
        my $param = shift;
        if (not $param) {
            return $self->param('_config');
        }
        else {
            return $self->param('_config')->{$param};
        }
    }

    sub _get_tt {
        my $self = shift;
        my $tt = $self->param('_tt');
        if (not $tt) {
            my $include_path = catfile(
                $self->param('_bin_dir'),
                $self->cfg('template_dir')
            );
            $self->param('_tt_include_path',$include_path);
            $tt = Template->new({
                INCLUDE_PATH => $include_path,
            });
            $self->param('_tt',$tt);
        }
        return $tt;
    }

    sub tt_process {
        my $self = shift;
        my $template = shift;
        my $params = shift;

        my $tt = $self->_get_tt;
        my $output;
        $tt->process($template, $params, \$output);
        return $output;
    }

    sub add_error {
        my $self = shift;
        my $error = shift;
        my $errs = $self->param('_errors');
        if ($errs) {
            push @$errs, $error;
        }
        else {
            $errs = [$error, ];
        }
        $self->param('_errors', $errs);
        return scalar @$errs;
    }

    sub _check_pid {
        my ($child_pid) = shift =~ /^(\d+)/;
        my $child_ppid = shift;
        return unless ($child_pid);
        my @ps = split(/\n/, `/bin/ps -fp $child_pid`);
        my $status = undef;
        if (my $ps = $ps[1]) {
            my (undef,$pid,$ppid) = split(/\s+/,$ps);
            if ($child_ppid and ($child_ppid == $ppid or $child_ppid == 1) and $child_pid == $pid) {
                $status = $pid;
            }
            elsif ( $child_pid == $pid) {
                $status = $pid;
            }
        }

        if ($status) {
            return $status;
        }
        else {
            return;
        }
    }

    sub _run_fork {
        my $self = shift;
        my $obj;
        my $method = shift;
        my @args = @_;
        if (ref $method ne 'CODE') { #assume we passed an object with a method
            $obj = $method;
            $method = shift @args;
        }
        my $session = $self->session;
        my $pid = fork();
        if ($pid) { #parent
            sleep(1);
            return;
        }
        elsif (defined $pid) { #child
            my $ppid = getppid();
            # open OLDERR, ">&STDERR";
            close STDERR;
            # open STDERR, ">&OLDERR";
            open STDERR, ">out.log";
            close STDOUT;
            open STDOUT, ">&STDERR";
            close STDIN;
            open STDIN, "<", "/dev/null";
            delete $SIG{__WARN__};
            delete $SIG{__DIE__};
            sleep(1);
            $session->param('status',"RUNNING");
            $session->param('childpid',$$);
            $session->param('childppid',$ppid);
            $session->flush;
            my $results;
            eval {
                if ($obj) {
                    $results = $obj->$method(@args);
                }
                else {
                    $results = $method->(@args);
                }
            };
            if (my $err = $@) {
                $session->param('results','ERROR');
                my $err_ar = $session->param('_errors');
                my @err = ($err,);
                if ($err_ar && @$err_ar) {
                    push @err, @$err_ar;
                }
                $session->param('_errors',\@err);
                $session->flush;
            }
            else {
                my ($zip_file) = $session->param('output_dir') =~ m{([^/]+)$};
                $zip_file .= ".zip";
                $zip_file = $self->cfg('temp_dir')."/$zip_file";
                my $output_dir = $session->param('output_dir');
                # TODO fix taint for insecure globs
                my @zip_cmd = ('/usr/bin/zip', '-j', $zip_file, glob("$output_dir/*.selex"), glob("$output_dir/*.HMM*"), glob("$output_dir/*.txt"));
                my $zip_cmd = join(" ", @zip_cmd);
                `$zip_cmd`;
                $session->param('zip_file',$zip_file);
                $session->param('results',$results);
                $session->param('status',"DONE");
                $session->flush;
            }
            warn "\nDone\n";
            exit(0);
        }
    }

    # -- worker methods

    sub check_parameters {
        my $self = shift;
        my $q = $self->query;
        #- check parameters
        my ($db, $trusted_cutoff, $noise_cutoff, $seed_file, $seed_fh, $exclude_text,
            $segment_method, $model_length, $model_overlap, $evalue_cutoff
        );

        # seed file
        $seed_file = $q->param('seed_hmm_model');
        if ( !$seed_file and $q->cgi_error) {
            die $q->cgi_error,"\n";
        }
        ($seed_file) = $seed_file =~ /([\w\-\.]+)$/; # everything past last delimiter
        $seed_fh = $q->upload('seed_hmm_model');


        # cutoffs
        $trusted_cutoff = $q->param('seed_trusted_cutoff') + 0;
        $noise_cutoff = $q->param('seed_noise_cutoff') + 0;
        if ($noise_cutoff == 0) {
            $noise_cutoff = $trusted_cutoff;
        }

        # manually set db exists and is readable
        if (my $man_db = $q->param('calibration_db_path')||'') {
            ($man_db) = $man_db =~ m{([\w/\-\.]+)$}; # get only good part of path
            if (not ( -f $man_db and -r _) ) {
                die "Calibration db $man_db does not exist or is unreadable\n";
            }
            else {
                $db = $man_db;
            }
        }
        else { # get the database from the dropdown;
            my $sel_db_name = $q->param('calibration_db_select')||'';
            if ($sel_db_name) {
                my %sel_dbs = map {$_->{name} => $_->{path}} @{$self->cfg('seq_dbs')};
                my $sel_db = $sel_dbs{$sel_db_name};
                if ($sel_db and -f $sel_db and -r _) {
                    $db = $sel_db;
                }
                else {
                    die "Selected DB $sel_db_name does not exist, or is unreadable (config error)\n";
                }
            }
        }
        if (not $db) {
            die "No database selected\n";
        }

        # manually input accessions to exclude
        $exclude_text = $q->param('exclude_accessions');

        # length is positive and overlap < length (for tiling)
        if (my $man_length = ($q->param('mini_model_length_text')||0) + 0) {
            $model_length = $man_length;
        }
        else {
            $model_length = ($q->param('mini_model_length_select')||0) + 0;
        }
        if ($model_length <= 0) {
            die "Invalid Model Length $model_length\n";
        }

        # valid segmentation method
        $segment_method = $q->param('segmentation_method');
        my %valid_methods = map {$_->{type} => 1} @{$self->cfg('seg_method')};
        if (not $valid_methods{$segment_method}) {
            die "Invalid segmentation method $segment_method\n";
        }
        # for tiling method, 0 < model overlap <= model length
        $model_overlap = ($q->param('mini_model_overlap')||0) + 0;
        if ($segment_method eq 'tiles') {
            if ($model_overlap == 0) {
                die "Must specify overlap > 0\n";
            }
            elsif ($model_overlap >= $model_length) {
                die "Overlap ($model_overlap) must be <= Model Length ($model_length)\n";
            }
        }

        # evalue cutoff must be >0
        $evalue_cutoff = $q->param('evalue_cutoff');
        if (not $evalue_cutoff) {
            $evalue_cutoff = $self->cfg('evalue_cutoff');
        }
        if ($evalue_cutoff < 0) {
            $evalue_cutoff = 0;
        }

        my %params = (
            seq_db => $db,
            trusted_cutoff => $trusted_cutoff,
            noise_cutoff => $noise_cutoff,
            seed_name => $seed_file,
            seed_fh => $seed_fh,
            exclude_text => $exclude_text,
            model_type => $segment_method,
            model_length => $model_length,
            model_overlap => $model_overlap,
            evalue_cutoff => $evalue_cutoff,
        );
        if (wantarray) {
            return %params;
        }
        else {
            return \%params;
        }
    }

    # -- controllers
    sub _redirect {
        my $self = shift;
        my $mode = shift || $self->param('home');
        my $session_id;
        if ($self->in_session) {
            my $session = $self->session;
            $session_id = $session->id;
        }
        my $url = catdir($self->param('script_path'), $mode, $session_id);
        $self->header_type('redirect');
        $self->header_props('-url' => $url);
        return "Redirected to $url";
    }

    sub error {
        my $self = shift;
        my @err = @_;
        my $errors = $self->param('_errors');
        if ($self->in_session) {
            my $session = $self->session;
            my $sess_errors = $session->param('_errors');
            if ($sess_errors) {
                push @$errors, @$sess_errors;
            }
        }
        if (@err) {
            push @$errors, @err;
        }
        $self->param('_errors', $errors);
        $self->header_props(-type=>'text/plain');
        my $result;
        my %app_params;
        $result .= "Errors:\n".YAML::Dump($self->param('_errors'))."\n" if ($self->param('_errors'));
        $result .= $self->dump()."\n";
        foreach my $param_key ($self->param()) {
            my $param = $self->param($param_key) || "";
            $app_params{$param_key} = "$param";
        }
        $result .= "CGI::App parameters: \n".YAML::Dump(\%app_params)."\n";
        if ($self->in_session) {
             my $session = $self->session;
             $result .= "Session parameters: \n".YAML::Dump($session->dataref)."\n";
        }
        return $result;
    }

    sub show_form {
        my $self = shift;
        my $template = 'query.tt';
        my $t_params;
        my $seq_dbs_ar = $self->cfg('seq_dbs');
        $t_params->{calibration_dbs} = $seq_dbs_ar;
        return $self->tt_process($template, $t_params);
    }

    sub process_form {
        my $self = shift;
        my $q = $self->query;
        my $session = $self->session; # start session
        $session->param('status','STARTING');
        my $temp_dir = $self->cfg('temp_dir');
        my $output_dir = tempdir("s_appren.XXXXX",DIR=>$temp_dir,CLEANUP=>0,);
        chmod 0777, $output_dir;
        $session->param('output_dir',"$output_dir");
        $session->flush;
        chdir "$output_dir";
        my %parameters = $self->check_parameters();
        my @base_fields = qw/trusted_cutoff noise_cutoff seq_db exclude_text model_type model_length model_overlap/;
        my ($seed_fh, $trusted_cutoff, $noise_cutoff, $db, $exclude_text, $method, $length, $overlap) =
            @parameters{'seed_fh', @base_fields};
        foreach my $f (@base_fields) {
            $session->param($f,$parameters{$f});
        }
        $session->flush;
        my $gap_filter_percent = $self->cfg('gap_filter_percent');
        my $evalue_cutoff = $parameters{evalue_cutoff};

        # save seed alignment
        my ($prefix,$ext) = $parameters{'seed_name'} =~ /^([^\.]+).*\.([^\.]+)$/; # anything past last .
        $ext ||= '.selex';
        my $seed_name = "$prefix.$ext";
        $session->param('seed_file',$seed_name);
        open my $out_fh, ">", "$seed_name" or die "Can't open $seed_name to save. $!\n";
        while (my $line = <$seed_fh>) {
            print $out_fh $line or die "Error saving seed alignment in $seed_name. $!\n";
        }
        close $out_fh or die "Can't save seed alignment in $seed_name. $!\n";


        # start hmm searches
        my $app_params = {
            bin_dir => $self->param('_bin_dir'),
            prefix => $prefix,
            dir => $session->param('output_dir'),
            seed_file => $seed_name,
            trusted_cutoff => $trusted_cutoff,
            noise_cutoff => $noise_cutoff,
            seq_db => $db,
            exclude_text => $exclude_text,
            model_type => $method,
            model_length => $length,
            model_overlap => $overlap,
            gap_filter => $gap_filter_percent,
            evalue_cutoff => $evalue_cutoff,
            parallel => 1,
        };
        # warn Dumper($app_params),"\n";
        my $cmd = miniHMM::HmmCommand->new( $app_params);
        $session->param('status','PREPARING');
        $session->flush;
        $cmd->prepare();
        $self->_run_fork($cmd,'run');
        $self->_redirect('results');
    }

    sub results {
        my $self = shift;
        my $session = $self->session;
        my $status = $session->param('status');
        if (! $status) {
            return $self->error("Could not retrieve status information from session");
        }

        # get status of hmm searches
        my $child_pid = $session->param('childpid');
        if ($status eq 'ERROR' ) {
            return $self->error();
        }
        elsif ($status eq 'DONE') { # if done, display results
            my $t = 'results.tt';
            my $results = $session->param('results');
            my @specs = @{$results->{specificity_cutoffs}};
            my @seed_hits = @{$results->{seed_hits_above_cutoff}};
            my @profiles_by_mini;
            # remove the specificity goals and duplicate profiles
            foreach my $profile_mini (@{$results->{profiles_by_mini}}) {
                my %result = (
                    mini_name => $profile_mini->{mini_name},
                    mini_range => $profile_mini->{mini_range},
                    profiles => [],
                );
                my $last_cutoff;
                my $last_specificity;
                my @profiles = sort {$b->cutoff <=> $a->cutoff} values %{$profile_mini->{profiles}};
                foreach my $profile (@profiles) {
                    if ($last_cutoff and $profile->cutoff == $last_cutoff) {
                        next; # skip duplicate profiles;
                    }
                    elsif ($last_specificity and $last_specificity < $profile->specificity) {
                        pop @{$result{profiles}}; # drop higher cutoffs with lower specificity
                    }
                    push @{$result{profiles}}, $profile;
                    $last_cutoff = $profile->cutoff;
                    $last_specificity = $profile->specificity;
                }
                push @profiles_by_mini, \%result;
            }
            my $params = {
                profiles_by_mini => \@profiles_by_mini,
                seed_hits => scalar(@seed_hits),
                output_dir => $session->param('output_dir'),
                session => $session->id,
            };
            # { local $YAML::UseHeader = 0; $params->{debug} = YAML::Dump($params); }
            return $self->tt_process($t,$params);
        }
        elsif (! _check_pid($child_pid) ) { # missing process is an error
            my @err = ('Running process unexpectedly died');
            my $err = $session->param('_errors');
            if ($err and @$err) {
                push @err, @$err;
            }
            $session->param('_errors',\@err);
            return $self->error();
        }
        else { # if not done, wait
            my $t = 'waiting.tt';
            my $time = localtime();
            my $params = {
                ctime => scalar(localtime($session->ctime())),
                time => $time,
                mode => 'results',
                session => $session->id,
                status => $status,
            };
            return $self->tt_process($t, $params);

        }
        return $self->error;
    }

    sub download {
        my $self = shift;
        my $session = $self->session;
        my $zip_file = $session->param('zip_file');
        local $| = 1; # autoflush
        if (-r $zip_file) {
            $self->header_props(-type=>'application/zip');
            if ($self->stream_file($zip_file)) {
                return;
            }
            else {
                return $self->error('Cannot stream file');
            }
        }
        else {
            return $self->error('Cannot read file.');
        }
    }
}

1; # Magic true value required at end of module
