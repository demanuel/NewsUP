#!/usr/bin/env perl
use 5.026;
use warnings;
use utf8;
use FindBin qw($Bin);
use lib "$Bin/../lib";
use NewsUP::Article;
use Socket qw(SO_SNDBUF SO_RCVBUF TCP_NODELAY SO_KEEPALIVE :crlf);
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

$\ = $CRLF;
$/ = $LF;

BEGIN {
    $| = 1;
}

my $files;

sub main {
    controller(read_options());
}

sub controller {
    my ($options) = @_;

    if ($options->{CHECK_NZB}) {
        verify_nzb($options);
    }

    if (@{$options->{FILES}}) {
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

sub verify_nzb {
    my ($options) = @_;

    my %aggregate_stats = ();
    my $select          = IO::Select->new(
        @{
            authenticate(
                $options->{HEADERCHECK_AUTH_USER},
                $options->{HEADERCHECK_AUTH_PASS},
                get_connections(
                    $options->{HEADERCHECK_CONNECTIONS}, $options->{HEADERCHECK_SERVER},
                    $options->{HEADERCHECK_SERVER_PORT}, $options->{TLS},
                    $options->{TLS_IGNORE_CERTIFICATE}))});

    my $date = 0;
    for my $nzb (@{$options->{CHECK_NZB}}) {
        if (-f $nzb) {
            my @file_stats         = ();
            my $total_completeness = 0;
            my $files_in_nzb       = 0;
            my %nzb_stats          = %{multiplexer_nzb_verification($select, $nzb)};
            while (my ($key, $value) = each %nzb_stats) {
                push @file_stats, [$key, $value->[0]];
                $date = $value->[1] unless $date;
                $total_completeness += $value->[0];
                $files_in_nzb++;
            }
            $aggregate_stats{$nzb} = [int($total_completeness / ($files_in_nzb || 1)), \@file_stats];
        }
        else {
            warn "$nzb isn't a valid file!";
        }
    }
    while (my ($key, $value) = each %aggregate_stats) {
        say "$key [uploaded at $date is $value->[0]% available]";
        if (@{$options->{CHECK_NZB}} < 2 && $value->[1]) {
            say "\t@{[$_->[0]]} @{[$_->[1]]}%" for (sort { $a->[0] cmp $b->[0] } @{$value->[1]});
        }
    }
    for ($select->handles()) {
        print $_ "quit";
        $_->shutdown(2);
        $_->close();
    }
}

sub multiplexer_nzb_verification {
    my ($select, $nzb) = @_;
    my $parser        = XML::LibXML->new();
    my $doc           = $parser->parse_file($nzb);
    my $current_group = '';
    my %stats         = ();
    my %sockets       = map { refaddr $_ => 0 } $select->handles;

    my $date;
    for my $file (@{$doc->getElementsByTagName("file")}) {
        my $group = $file->getElementsByTagName('group')->[0]->textContent;

        {
            local $\;
            print "Changing to group $group\r";
        }
        my $read = '';
        if ($group ne $current_group) {
            for my $socket ($select->handles) {
                print $socket "group $group";
                <$socket>;
            }
            $current_group = $group;
        }
        my $subject = $file->getAttribute('subject');

        my $filename = $subject;
        my @segments = @{$file->getElementsByTagName('segment')};

        my $correct_segments = @segments;
        my $total_segments   = @segments;

        if ($subject =~ /"(.*)"\s.*\(1\/(\d+)\)/i) {
            $filename         = $1;
            $correct_segments = $2;
        }
        elsif ($subject =~ /\"(.*?)\"/) {
            $filename = $1;
        }
        {
            local $\;
            print "Checking $filename" . (' ' x 20) . "\r";

        }

        if ($correct_segments != $total_segments) {
            $stats{$filename} = [int(($total_segments / $correct_segments) * 100.0), []];
            next;
        }

        my ($counter_ok, $counter_fail) = (0, 0);

        do {
            my ($read_ready, $write_ready, undef) = IO::Select->select($select, $select, undef, 0.125);

            for my $socket (@$write_ready) {
                last unless @segments;
                my $mid = $segments[0]->textContent;
                unless ($date) {
                    print $socket "head <$mid>";
                    $date = 1;
                    $sockets{refaddr $socket} = 1;
                    next;
                }
                next if $sockets{refaddr $socket};
                shift @segments;
                print $socket "stat <$mid>";
                $sockets{refaddr $socket} = 1;
            }

            for my $socket (@$read_ready) {
                last if $counter_fail + $counter_ok == $total_segments;
                next unless $sockets{refaddr $socket};
                $read = <$socket>;
                #chomp $read;
                #say "linha: $read";
                if ($read) {
                    if ($read =~ /^223 / || $read =~ /^221 /) {
                        $counter_ok++;
                        $sockets{refaddr $socket} = 0;
                    }
                    elsif ($read =~ /^\d+ /) {
                        $counter_fail++;
                        $sockets{refaddr $socket} = 0;
                        # $date = 0;
                    }
                    elsif ($read =~ /Date: \w+, (\d+ \w+ \d+)|Date: (\d+ \w+ \d+)/) {
                        $date = '20' . join(' ', reverse split /\s/, $^N);
                    }
                    elsif ($read =~ /^\.$/) {
                        $sockets{refaddr $socket} = 0;
                    }

                }
            }
        } until ($counter_fail + $counter_ok == $total_segments);
        $stats{$filename} = [int($counter_ok / $total_segments * 100), $date];
    }

    return \%stats;
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
    my $header_check_connections = min($options->{HEADERCHECK_CONNECTIONS}, scalar(@$articles));
    my $select                   = IO::Select->new(
        @{
            authenticate(
                $options->{HEADERCHECK_AUTH_USER},
                $options->{HEADERCHECK_AUTH_PASS},
                get_connections(
                    $header_check_connections,           $options->{HEADERCHECK_SERVER},
                    $options->{HEADERCHECK_SERVER_PORT}, $options->{TLS},
                    $options->{TLS_IGNORE_CERTIFICATE}))});
    my $current_position  = 0;
    my %connection_status = map { refaddr $_ => -1 } $select->handles();
    do {
        my ($read_ready, $write_ready, $exception_ready) = IO::Select->select($select, $select, $select, 0.125);
        for my $socket (@$write_ready) {
            my $key = refaddr $socket;
            last if $current_position > $#$articles;
            if ($connection_status{$key} == -1) {
                my $mid = $articles->[$current_position++]->message_id();
                while (!$mid && $current_position < scalar @$articles) {
                    $mid = $articles->[$current_position++]->message_id();
                }
                print $socket "stat <$mid>";
                #syswrite_to_socket($socket, "stat <$mid>");
                $connection_status{$key} = $current_position - 1;
            }
        }
        for my $socket (@$read_ready) {
            my $key = refaddr $socket;
            if ($connection_status{$key} > -1) {
                my $read = <$socket>;
                chomp $read;
                if ($read =~ /223 /) {
                    $articles->[$connection_status{$key}]->header_check(1);
                }
                else {
                    print $read;
                }

                $connection_status{$key} = -1;
            }
        }

    } until ($current_position > $#$articles && $header_check_connections == grep { $_ == -1 }
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
        my $ids = generate_random_ids($total_parts, $options) if $options->{GENERATE_IDS} || $options->{OBFUSCATE};
        for (my $part = 1; $part <= $total_parts; $part++) {
            my $article = NewsUP::Article->new(
                newsgroups => $options->{OBFUSCATE}
                ? get_random_array_elements($options->{GROUPS})
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
      . " KBytes/second";


    my $nzb_file = save_nzb($options, \@articles);

    if ($options->{UPLOAD_NZB} && !$options->{OBFUSCATE}) {
        print "Uploading NZB";
        my $file_size    = -s $nzb_file;
        my $total_parts  = ceil($file_size / (750 * 1024));
        my $ids          = generate_random_ids($total_parts, $options) if $options->{GENERATE_IDS};
        my @nzb_articles = ();
        for (my $part = 1; $part <= $total_parts; $part++) {
            my $article = NewsUP::Article->new(
                newsgroups  => $options->{GROUPS},
                file        => $nzb_file,
                from        => $options->{UPLOADER},
                file_number => 1,
                file_size   => $file_size,
                total_files => 1,
                comments    => $options->{COMMENTS},
                part        => $part,
                total_parts => $total_parts,
                upload_size => $options->{UPLOAD_SIZE},
                message_id  => $options->{GENERATE_IDS} ? $ids->[$part - 1] : undef,
                obfuscate   => 0,
                headers     => $options->{HEADERS});
            push @nzb_articles, $article;
        }
        multiplexer($options, \@nzb_articles);
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

    {
        local $\;
        print "0/$progress_total\r";
    }

    do {
        my ($read_ready, $write_ready, $exception_ready) = IO::Select->select($select, $select, $select, 0.125);
        for my $socket (@$read_ready) {
            my $socketId = refaddr $socket;
            my $status   = $connection_status{$socketId};
            if ($status == 1) {
                my $read = <$socket>;
                if (!$read || $read !~ /340/) {
                    local $\;
                    print STDERR 'Sending article failed';
                    print STDERR ": $read" if $read;
                    print STDERR "\n";
                    die "Stopping download! Please check the error message above!\n" if $read && $read =~ /^4|5/;

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
                }
                else {
                    $connection_status{$socketId} = 2;
                }

            }
            elsif ($status == 3) {
                $upload_queue--;

                {
                    local $\;
                    print ++$progress_current, '/', "$progress_total\r";
                }

                $connection_status{$socketId} = 0;
                my $read = <$socket>;
                if ($read && $read =~ /240/) {
                    if ($read =~ /<(.*)>/) {
                        $articles->[$article_table{$socketId}]->message_id($1);
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
                }
            }
        }
        for my $socket (@$write_ready) {
            my $socketId = refaddr $socket;
            my $status   = $connection_status{$socketId};
            if ($status == 0) {
                next if $to_post-- <= 0;
                $connection_status{$socketId} = 1;
                print $socket "POST";
                # syswrite_to_socket($socket, "POST");
            }
            elsif ($status == 2) {
                $article_table{$socketId} = $posted++;
                print $socket $articles->[$article_table{$socketId}]->head(),
                  $articles->[$article_table{$socketId}]->body();
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


sub authenticate {
    my ($user, $passwd, $connections) = @_;

    for my $socket (@$connections) {

        # Welcoming message
        <$socket>;
        print $socket "authinfo user $user";
        if ((my $read = <$socket>) !~ /381 /) { die "Authentication failed: $read "; }
        print $socket "authinfo pass $passwd";
        if ((my $read = <$socket>) !~ /281 /) { die "Wrong authtication parameters: $read "; }

    }
    return $connections;
}


# Even though sysread can be faster than readline, the rest of the code to check if we read until the end of the line isn't.
# Leaving this function as historical
# sub sysread_from_socket {
#     my ($socket) = @_;
#     my $output = '';

#     while (1) {
#         my $status = sysread($socket, my $buffer, 2048);
#         $output .= $buffer;
#         undef $buffer;
#         if ($output =~ /.$CRLF$/ || $status == 0) {
#             last;
#         }
#         elsif (!defined $status) {
#             die "Error: $!";
#         }
#     }

#     return $output;
# }


# Note: using syswrite or print is the same (im assuming if we don't disable nagle's algorithm):
# Network Programming with Perl. Page: 311.
# Since using print seems to be faster than this function, i', using print
# Leaving as historical
# sub syswrite_to_socket {

#     my ($socket, @args) = @_;
#     local $,;


#     for my $arg ((@args, $CRLF)) {
#         my $len    = length $arg;
#         my $offset = 0;

#         while ($len) {
#             my $written = syswrite($socket, $arg, $len, $offset);

#             return 1 unless ($written);
#             $len -= $written;
#             $offset += $written;
#             undef $written;
#         }
#     }
#     undef @args;
#     #Using print
#     # return 0 if (print $socket @args);
#     # return 1;

# }

sub connection_is_alive {
    my ($socket) = @_;
    my $poll     = 1;
    my $dead     = 0;
    $SIG{'PIPE'} = sub { $dead = 1; $poll = 0 };
    $SIG{'ALRM'} = sub { say "connection is alive!"; $poll = 0 };
    alarm(11);
    my $error = !print $socket 0x00;    #print the null byte
    if ($error) {
        $dead = 1;
        say $! ;
    }
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
            ) or die "Error: Failed to connect to $host:$port: $! [$@]";
        }

        $socket->autoflush(1);
        $socket->sockopt(SO_SNDBUF,   4 * 1024 * 1024);
        $socket->sockopt(SO_RCVBUF,   4 * 1024 * 1024);
        $socket->sockopt(TCP_NODELAY, 1);
        # disable naggle algorithm
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

