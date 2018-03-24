#!/usr/bin/env perl
use 5.026;
use warnings;
use utf8;
use FindBin qw($Bin);
use lib "$Bin/../lib";
use NewsUP::Article;
use Socket qw(SO_SNDBUF SO_RCVBUF TCP_NODELAY SO_KEEPALIVE);
use POSIX qw(ceil);
use IO::Socket::SSL;
use IO::Select;
use Scalar::Util qw(refaddr);
use File::Spec::Functions;
use Time::HiRes qw(gettimeofday tv_interval alarm);
use NewsUP::Utils
  qw (read_options generate_random_ids save_nzb get_random_array_elements find_files update_file_settings );
use List::Util qw(min max);
use Carp;

$\ = "\x0D\x0A";
$, = undef;

BEGIN {
    $| = 1;
}

my $files;

sub main {
    my $options = read_options();
    controller($options);
}

sub controller {
    my ($options) = @_;

    if ($options->{FILES}) {
        $files = find_files($options);
        # All the files are now temporary files
        my $articles = upload_files($options, $files);
        header_check($options, $articles) if ($options->{HEADERCHECK});

    }

    if ($options->{LIST}) {
        open my $ifh, '<', $options->{LIST} or die "Unable to open the file defined in list option: $!";
        while (defined(my $line = <$ifh>)) {
            delete_temporary_files();
            chomp $line;
            say "Processing file $line";
            $options->{FILES} = [$line];
            $files = find_files(update_file_settings($options));
            # All the files are now temporary files
            my $articles = upload_files($options, $files);
            header_check($options, $articles) if ($options->{HEADERCHECK});
        }
        close $ifh;
    }

}

sub header_check {
    my ($options, $articles) = @_;

    my $retries = $options->{HEADERCHECK_RETRIES};
    my @missing = ();
    print "Starting the headercheck\r";
    my $t0 = [gettimeofday];
    do {
        print "Sleeping $options->{HEADERCHECK_SLEEP} seconds\r";
        sleep($options->{HEADERCHECK_SLEEP});
        header_check_multiplexer($options, [grep { $_->header_check == 0 } @$articles]);
        @missing = grep { $_->header_check == 0 } @$articles;
        if (@missing) {
            print scalar(@missing) . " segments missing! Reuploading them!";
            my $t1 = [gettimeofday];
            multiplexer($options, \@missing);
            my $elapsed = tv_interval($t1, [gettimeofday]);
            print "Re upload done in $elapsed seconds!\n";
        }
    } while ($retries-- && @missing);
    my $elapsed = tv_interval($t0, [gettimeofday]);
    print "Headercheck done in $elapsed seconds!\n";

}

sub header_check_multiplexer {
    my ($options, $articles) = @_;
    my $select = IO::Select->new(
        @{
            authenticate(
                $options->{AUTH_USER},
                $options->{AUTH_PASS},
                get_connections(
                    min($options->{CONNECTIONS}, scalar(@$articles)), $options->{SERVER},
                    $options->{SERVER_PORT}, $options->{TLS},
                    $options->{TLS_IGNORE_CERTIFICATE}))});
    my $current_position = 0;
    my %connection_status = map { refaddr $_ => -1 } $select->handles();
    do {
        for my $socket ($select->can_write(0)) {
            my $key = refaddr $socket;
            last if $current_position > $#$articles;
            if ($connection_status{$key} == -1) {
                my $mid = $articles->[$current_position]->message_id();
                while (!$mid && $current_position < scalar @$articles) {
                    $mid = $articles->[++$current_position]->message_id();
                }
                print $socket "stat <$mid>";
                $connection_status{$key} = $current_position++;
            }
        }
        for my $socket ($select->can_read(0)) {
            my $key = refaddr $socket;
            if ($connection_status{$key} > -1) {
                my $read = <$socket>;
                chomp $read;
                # say "'$read'";
                # say "\t-> ".$articles->[$connection_status{$key}]->message_id();
                if ($read =~ /223 /) {
                    $articles->[$connection_status{$key}]->header_check(1);
                }
                else {
                    print $read;
                }

                $connection_status{$key} = -1;
            }
        }

      } until ($current_position > $#$articles && $options->{CONNECTIONS} == grep { $_ == -1 }
          values %connection_status);

    for ($select->handles()) {
        print $_ "quit\r\n";
        $_->shutdown(2);
        $_->close();
    }
}


sub upload_files {
    my ($options, $files) = @_;

    my @articles     = ();
    my $i            = 1;
    my $total_files  = @$files;
    my $total_upload = 0;

    for my $file (@$files) {
        my $file_size   = -s $file;
        my $total_parts = ceil($file_size / $options->{UPLOAD_SIZE});
        $total_upload += $file_size;
        my $ids = generate_random_ids($total_parts) if $options->{GENERATE_IDS} || $options->{OBFUSCATE};
        for (my $part = 1; $part <= $total_parts; $part++) {
            my $article = NewsUP::Article->new(
                newsgroups => $options->{OBFUSCATE} ?
                  get_random_array_elements($options->{GROUPS})
                : $options->{GROUPS},
                file        => $file,
                from        => $options->{OBFUSCATE} ? '' : $options->{UPLOADER},
                comments    => $options->{COMMENTS},
                file_number => $i,
                file_size   => $file_size,
                total_files => $total_files,
                part        => $part,
                total_parts => $total_parts,
                upload_size => $options->{UPLOAD_SIZE},
                message_id  => ($options->{GENERATE_IDS} || $options->{OBFUSCATE}) ? $ids->[$part - 1] : undef,
                obfuscate   => $options->{OBFUSCATE},
                headers     => $options->{HEADERS});

            push @articles, $article;
        }
        $i++;
    }
    my $t0 = [gettimeofday];
    multiplexer($options, \@articles);
    my $elapsed = tv_interval($t0, [gettimeofday]);
    print "Uploaded "
      . int($total_upload / 1024 / 1024)
      . " MBytes in "
      . int($elapsed)
      . " seconds. Avg. Speed: "
      . int($total_upload / 1024 / $elapsed)
      . " KBytes/second"
      . ' ' x $options->{PROGRESSBAR_SIZE};


    my $nzb_file = save_nzb($options, \@articles);

    if ($options->{UPLOAD_NZB}) {
        print "Uploading NZB";
        my $file_size   = -s $nzb_file;
        my $total_parts = ceil($file_size / (750 * 1024));
        my $ids         = generate_random_ids($total_parts) if $options->{GENERATE_IDS} || $options->{OBFUSCATE};
        my @articles    = ();
        for (my $part = 1; $part <= $total_parts; $part++) {
            my $article = NewsUP::Article->new(
                newsgroups => $options->{OBFUSCATE} ?
                  get_random_array_elements($options->{GROUPS})
                : $options->{GROUPS},
                file        => $nzb_file,
                from        => $options->{OBFUSCATE} ? '' : $options->{UPLOADER},
                file_number => 1,
                file_size   => $file_size,
                total_files => 1,
                comments    => $options->{COMMENTS},
                part        => $part,
                total_parts => $total_parts,
                upload_size => $options->{UPLOAD_SIZE},
                message_id  => ($options->{GENERATE_IDS} || $options->{OBFUSCATE}) ? $ids->[$part - 1] : undef,
                obfuscate   => $options->{OBFUSCATE},
                headers     => $options->{HEADERS});
            push @articles, $article;
        }
        multiplexer($options, \@articles);
        print "NZB uploaded!" . ' ' x $options->{PROGRESSBAR_SIZE};
    }

    return \@articles;
}

sub multiplexer {
    my ($options, $articles) = @_;
    my $progress_current = 0;
    my $progress_total   = scalar(@{$articles});
    my $progress_print   = 0;
    my $select           = IO::Select->new(
        @{
            authenticate(
                $options->{AUTH_USER},
                $options->{AUTH_PASS},
                get_connections(
                    min($options->{CONNECTIONS}, scalar(@$articles)), $options->{SERVER},
                    $options->{SERVER_PORT}, $options->{TLS},
                    $options->{TLS_IGNORE_CERTIFICATE}))});

    my %connection_status  = map { refaddr $_ => 0 } $select->handles();
    my $number_of_articles = scalar @$articles;
    my $to_post            = $number_of_articles;
    my %article_table      = ();
    my $posted             = 0;
    my $upload_queue       = 0;
    print_progress(0, 0, $progress_total);
    do {
        for my $socket ($select->can_read(0)) {
            my $socketId = refaddr $socket;
            my $status   = $connection_status{$socketId};
            if ($status == 1) {
                my $read = <$socket>;
                if (!$read || $read !~ /^340/) {
                    local $\;
                    print STDERR 'Sending article failed';
                    print STDERR ": $read" if $read;
                    print STDERR "\n";
                    die "Stopping download! Please check the error message above!\n" if $read =~ /^4|5/;

                    if (!connection_is_alive($socket)) {
                        print STDERR "Starting a new connection!\n";
                        $select->remove($socket);
                        delete $connection_status{$socketId};
                        delete $article_table{$socketId};
                        my $new_socket;
                        do {
                            eval {
                                $new_socket = authenticate(
                                    $options->{AUTH_USER},
                                    $options->{AUTH_PASS},
                                    get_connections(
                                        1,                       $options->{SERVER},
                                        $options->{SERVER_PORT}, $options->{TLS},
                                        $options->{TLS_IGNORE_CERTIFICATE}))->[0];
                            };
                            if ($@) {
                                say "Exception starting connection $@";
                            }
                        } until ($new_socket);
                        say "Connection created!";

                        $select->add($new_socket);
                        $connection_status{refaddr $new_socket} = 0;
                    }
                    print_progress($progress_current, $upload_queue, $progress_total);

                }
                else {
                    $connection_status{$socketId} = 2;
                }

            }
            elsif ($status == 3) {
                print_progress(++$progress_current, $upload_queue--, $progress_total);
                $connection_status{$socketId} = 0;
                my $read = <$socket>;
                if ($read && $read =~ /^240/) {
                    if ($read =~ /<(.*)>/) {
                        $articles->[$article_table{$socketId}]->message_id($1);

                        # #my $article = $articles->[$article_table{$socketId}];
                        # if (!defined $article->message_id()) {
                        #     $article->message_id($1);
                        # }
                        #
                    }
                }
                else {
                    unless ($read) {
                        local $\;
                        print STDERR "Sending article failed\n";
                        if (!connection_is_alive($socket)) {
                            print STDERR "Starting a new connection!\n";
                            $select->remove($socket);
                            delete $article_table{$socketId};
                            delete $connection_status{$socketId};
                            my $new_socket;
                            do {
                                eval {
                                    $new_socket = authenticate(
                                        $options->{AUTH_USER},
                                        $options->{AUTH_PATH},
                                        get_connections(
                                            1,                       $options->{SERVER},
                                            $options->{SERVER_PORT}, $options->{TLS},
                                            $options->{TLS_IGNORE_CERTIFICATE}))->[0];
                                };
                                say "Exception: $@" if $@;

                            } until ($new_socket);
                            $select->add($new_socket);
                            $connection_status{refaddr $new_socket} = 0;
                        }
                    }
                    else {
                        chomp $read;
                        print STDERR "Article posting failed: $read";
                        die "Stopping download! Please check the error message above!\n" if $read =~ /^4|5/;
                    }
                    print_progress($progress_current, $upload_queue, $progress_total);
                }
            }
        }
        my @a = $select->can_write();
        for my $socket ($select->can_write(0)) {
            my $socketId = refaddr $socket;
            my $status   = $connection_status{$socketId};
            if ($status == 0) {
                next if $to_post-- <= 0;
                $connection_status{$socketId} = 1;
                print $socket "POST";
            }
            elsif ($status == 2) {
                $article_table{$socketId} = $posted++;
                print $socket @{$articles->[$article_table{$socketId}]->head},
                  @{$articles->[$article_table{$socketId}]->body};

                $connection_status{$socketId} = 3;
                $upload_queue++;
            }

        }
    } until ($posted == $number_of_articles && $upload_queue == 0);
    {
        local $\;
        print ' ' x 18 . "\r";
    }

    for ($select->handles()) {
        print $_ "quit";
        $_->shutdown(2);
        $_->close();
    }
}


sub print_progress {
    my ($got, $wait, $total) = @_;
    local $\;
    print "U:$got Q:$wait T:$total\r";
}

sub authenticate {
    my ($user, $passwd, $connections) = @_;

    for my $socket (@$connections) {
        read_socket($socket, 'Problem Reading from the server: ', sub { });    # Welcoming message
        print $socket "authinfo user $user";
        read_socket(
            $socket,
            'Authentication failed!',
            sub { my ($read) = @_; die "Error while login: $!" if $read !~ /^381/; }
        );                                                                     # Welcoming message
        print $socket "authinfo pass $passwd";
        read_socket(
            $socket,
            'Authentication failed!',
            sub { my ($read) = @_; die "Wrong authentication parameters!" if $read !~ /^281/; });
    }
    return $connections;
}

sub read_socket {
    my ($socket, $message, $function) = @_;
    if (defined(my $read = <$socket>)) {
        if ($function) {
            $function->($read);
        }
        return $read;
    }
}

sub connection_is_alive {
    my ($socket) = @_;
    my $poll     = 1;
    my $dead     = 0;
    $SIG{'PIPE'} = sub { $dead = 1; $poll = 0 };
    $SIG{'ALRM'} = sub { say "connection is alive!"; $poll = 0 };
    alarm(11);
    print $socket 0x00;    #print the null byte
    do {
        sleep(3);
    } while ($poll);
    alarm(0);
    delete $SIG{'PIPE'};
    delete $SIG{'ALRM'};
    return !$dead;

}

sub get_connections {
    my ($how_many, $host, $port, $with_ssl, $ignore_cert) = @_;
    my @sockets = ();
    while ($how_many--) {
        my $socket;
        if ($with_ssl) {
            $socket = IO::Socket::SSL->new(
                PeerHost        => $host,
                PeerPort        => $port,
                SSL_verify_mode => $ignore_cert ? SSL_VERIFY_NONE : SSL_VERIFY_PEER,
                Proto           => 'tcp',
                Blocking        => 1
            ) or die "Error: Failed to connect or ssl handshake: $!, $SSL_ERROR";
        }
        else {
            $socket = IO::Socket::INET->new(
                PeerHost => $host,
                PeerPort => $port,
                Proto    => 'tcp',
                Blocking => 1
            ) or die "Error: Failed to connect: $!";
        }

        $socket->autoflush(1);
        $socket->sockopt(SO_SNDBUF,    4 * 1024 * 1024);
        $socket->sockopt(SO_RCVBUF,    4 * 1024 * 1024);
        $socket->sockopt(TCP_NODELAY,  1);
        $socket->sockopt(SO_KEEPALIVE, 1);

        push @sockets, $socket;
    }

    return \@sockets;
}

sub delete_temporary_files {
    # delete all the temporary files
    unlink @$files if $files;
    $files = [];
}

END {
    delete_temporary_files();
}


main(@ARGV) unless caller();

