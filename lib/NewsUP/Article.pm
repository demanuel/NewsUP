package NewsUP::Article;
use POSIX;
use 5.026;
use NewsUP::yEnc;
use NewsUP::Utils qw(generate_random_string);
use Socket ':crlf';
use File::Basename 'basename';

sub new {
    my ($class, %args) = @_;
    my $self = {};
    bless $self, $class;

    #default values
    $self->{upload_size} = 0;
    $self->{filename}    = '';

    my $mid = delete $args{message_id};
    for (keys %args) {
        if ($self->can($_)) {
            $self->$_($args{$_});
        }
        else {
            warn "Unkown attribute: $_";
        }
    }
    # We want the message id to be the last thing to be set as it will change the header
    $self->message_id($mid) if $mid;

    return $self;
}

sub from {
    my ($self, $from) = @_;

    if ($from) {
        $self->{from} = $from;
    }
    else {
        $self->{from} = _generate_random_uploader() if (!$self->{from});
    }

    return $self->{from};
}

sub header_check {
    my ($self, $header_check) = @_;
    $self->{header_check} = 1 if $header_check;
    return $self->{header_check} // 0;
}

sub newsgroups {
    my ($self, $newsgroups) = @_;

    $self->{newsgroups} = join(',', @$newsgroups) if $newsgroups;
    return $self->{newsgroups};
}

sub part {
    my ($self, $part) = @_;

    if ($part) {
        $self->{part}    = $part;
        $self->{subject} = undef;
    }

    return $self->{part};
}

sub total_parts {
    my ($self, $total_parts) = @_;

    if ($total_parts) {
        $self->{total_parts} = $total_parts;
        $self->{subject}     = undef;
    }

    return $self->{total_parts};
}

# sub line_size {
#     my ($self, $line_size) = @_;

#     if ($ine_size) {
#         $self->{line_size} = $line_size;
#         $self->{subject} = undef;
#     }

#     return $self->{line_size};
# }


sub comments {
    my ($self, $comments) = @_;

    if ($comments) {
        $self->{comments} = $comments;
        $self->{subject}  = undef;
    }
    return $self->{comments};
}

sub message_id {
    my ($self, $message_id) = @_;

    if ($message_id) {
        $self->{message_id} = $message_id;

        my @head = (
            "From: ${\$self->{from}}",         $CRLF, "Newsgroups: ${\$self->{newsgroups}}", $CRLF,
            "Subject: ${\$self->subject}", $CRLF, "Message-ID: <$message_id>",         $CRLF
        );

        push @head, ($self->headers(), $CRLF) if ($self->headers());
        push @head, $CRLF;
        $self->{head} = \@head;
    }

    return $self->{message_id};
}

sub file_number {
    my ($self, $file_number) = @_;

    if ($file_number) {
        $self->{file_number} = $file_number;
        $self->{subject}     = undef;
    }
    return $self->{file_number};
}

sub total_files {
    my ($self, $total_files) = @_;

    if ($total_files) {
        $self->{total_files} = $total_files;
        $self->{subject}     = undef;
    }
    return $self->{total_files};
}

sub file {
    my ($self, $file) = @_;
    if ($file) {
        $self->{file} = $file;
        $self->filename;
    }

    return $self->{file};
}

sub file_size {
    my ($self, $file_size) = @_;

    if ($file_size) {
        $self->{file_size} = $file_size;
    }

    return $self->{file_size};
}

sub size {
    my ($self, $size) = @_;

    if ($size) {
        $self->{size} = $size;
    }

    return $self->{size};
}

sub begin_position {
    my ($self, $begin_position) = @_;

    if ($begin_position) {
        $self->{begin_position} = $begin_position;
    }

    return $self->{begin_position};
}

sub end_position {
    my ($self, $end_position) = @_;

    if ($end_position) {
        $self->{end_position} = $end_position;
    }

    return $self->{end_position};
}

# sub file_position {
#     my ($self) = @_;
#     return $self->{file_position};
# }

sub obfuscate {
    my ($self, $obfuscate) = @_;
    $self->{obfuscate} = 1 if ($obfuscate);

    return $self->{obfuscate};
}

sub obfuscate_filename {
    my ($self) = @_;

    if ($self->obfuscate) {
        my $random_string = '';
        my @letters       = (q(a) .. q(z));
        for (1 .. 1 + int(rand(32))) {
            $random_string .= @letters[rand(26)];
        }
        return $random_string;
    }
    return $self->filename;
}

sub read_file_data {
    my ($self) = @_;
    $self->{begin_position} = $self->upload_size * ($self->part - 1);
    open my $fh, '<:raw :bytes', $self->{file} or die "Unable to open file: $!";
    seek $fh, $self->{begin_position}, 0;
    $self->size(read($fh, my $bin_data, $self->upload_size));
    $self->end_position(tell $fh);
    close $fh;
    return $bin_data;
}

sub filename {
    my ($self) = @_;
    unless ($self->{filename}) {
        $self->{filename} = basename($self->file);
    }

    return $self->{filename};
}

sub upload_size {
    my ($self, $upload_size) = @_;

    if ($upload_size) {
        $self->{upload_size} = $upload_size;
    }
    return $self->{upload_size};
}

# sub _ypart_begin {
#     my ($self) = @_;

#     $self->{_ypart_begin} = 1+$self->file_position unless $self->{_ypart_begin};
#     return $self->{_ypart_begin};
# }

sub subject {
    my ($self) = @_;
    unless ($self->{subject}) {
        if ($self->obfuscate) {
            $self->{subject} = $self->obfuscate_filename;
        }
        else {
            $self->{subject}
              = "[${\$self->{file_number}}/${\$self->{total_files}}] - \"${\$self->{filename}}\" (${\$self->{part}}/${\$self->{total_parts}})";
            my $comments = $self->comments();
            $self->{subject} = $comments->[0] . ' ' . $self->{subject} if ($comments->[0]);
            $self->{subject} = $self->{subject} . ' ' . $comments->[1] if ($comments->[1]);
        }
    }

    return $self->{subject};
}

# To be overwritten when the message-id is set
sub head {
    my ($self) = @_;
    if (!$self->{head}) {
        my @head = (
            "From: ${\$self->from}",
            $CRLF, "Newsgroups: ${\$self->{newsgroups}}",
            $CRLF, "Subject: ${\$self->subject}", $CRLF,
        );

        push @head, $self->headers(), $CRLF if ($self->headers());

        push @head, $CRLF;
        $self->{head} = \@head;
    }
    return @{$self->{head}};
}

sub headers {
    my ($self, $headers) = @_;

    if ($headers) {
        while (my ($k, $v) = each %$headers) {
            next if $k =~ /from|newsgroups|message\-id|subject/i;
            $k = "X-$k" if ($k !~ /^X-/);
            $self->{headers} .= "$k: $v$CRLF";
        }
    }

    return $self->{headers} // '';
}

sub body {
    my ($self) = @_;    #params always different, so for us to have low memory usage we should avoid storing them

    # Avoid de-ref stuff. It creates overhead
    my $encoding = NewsUP::yEnc::encode($self->read_file_data, $self->{size});
# TODO: to be truly obfuscated we need need to break YENC spec. I prefer not to do that. If you want that, replase the first line
# from the returned value for:
# =ybegin part=-1 total-2 line=128 size=999999999 name=${\$self->obfuscate_filename}$CRLF
    return
"=ybegin part=${\$self->{part}} total=${\$self->{total_parts}} line=128 size=${\$self->{file_size}} name=${\$self->{filename}}",
      $CRLF,
      "=ypart begin=@{[$self->{begin_position}+1]} end=${\$self->{end_position}}",
      $CRLF,
      "${\$encoding->[0]}",
      $CRLF,
      "=yend size=${\$self->{size}} pcrc32=${\$encoding->[1]}",
      $CRLF,
      ".";
}

sub message {
    my ($self) = @_;
    return $self->head(), $self->body();
}

sub _generate_random_uploader {
    return
        generate_random_string(8) . ' <'
      . generate_random_string(int(rand(18))) . '@'
      . generate_random_string(1 + int(rand(6))) . '.'
      . generate_random_string(1 + int(rand(3))) . '>';
}
1;
