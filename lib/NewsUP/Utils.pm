package NewsUP::Utils;
use 5.026;
use warnings;
use strict;
use POSIX;
use Time::HiRes qw/gettimeofday tv_interval/;
use XML::LibXML;
use Getopt::Long;
use File::Spec;
use File::Spec::Functions;
use Config::Tiny;
use Carp;
use File::Basename;
use File::Find;
use File::Path qw/rmtree/;
use File::Copy::Recursive qw(rcopy rmove);
$File::Copy::Recursive::CPRFComp = 1;

require Exporter;
our @ISA    = qw(Exporter);
our @EXPORT = qw(
  read_options
  generate_random_string
  generate_random_ids
  save_nzb
  get_random_array_elements
  find_files
  compress_files
  update_file_settings
);


our $CONFIGURATION_FILE = catfile($ENV{HOME}, '.config', 'newsup.conf');

sub read_options {
    my %options = (DEBUG => 0);
    GetOptions(
        'help'                         => sub { help(); },
        'debug!'                       => \$options{DEBUG},
        'file=s@'                      => \$options{FILES},
        'list=s'                       => \$options{LIST},
        'nfo=s'                        => \$options{NFO},
        'configuration=s'              => \$CONFIGURATION_FILE,
        'uploadsize=i'                 => \$options{UPLOAD_SIZE},
        'obfuscate!'                   => \$options{OBFUSCATE},
        'newsgroup|group=s@'           => \$options{GROUPS},
        'username=s'                   => \$options{AUTH_USER},
        'password=s'                   => \$options{AUTH_PASS},
        'connections=i'                => \$options{CONNECTIONS},
        'server=s'                     => \$options{SERVER},
        'port=i'                       => \$options{SERVER_PORT},
        'TLS!'                         => \$options{TLS},
        'generateIDs!'                 => \$options{GENERATE_IDS},
        'ignoreCert!'                  => \$options{TLS_IGNORE_CERTIFICATE},
        'headerCheck!'                 => \$options{HEADERCHECK},
        'headerCheckServer=s'          => \$options{HEADERCHECK_SERVER},
        'headerCheckPort=i'            => \$options{HEADERCHECK_SERVER_PORT},
        'headerCheckRetries|retries=i' => \$options{HEADERCHECK_RETRIES},
        'headerCheckSleep=i'           => \$options{HEADERCHECK_SLEEP},
        'headerCheckUsername=s'        => \$options{HEADERCHECK_AUTH_USER},
        'headerCheckPassword=s'        => \$options{HEADERCHECK_AUTH_PASS},
        'headerCheckConnections=i'     => \$options{HEADERCHECK_CONNECTIONS},
        'comment=s@'                   => \$options{COMMENTS},
        'uploader=s'                   => \$options{UPLOADER},
        'metadata=s%'                  => \$options{METADATA},
        'nzb=s'                        => \$options{NZB_FILE},
        'unzb!'                        => \$options{UPLOAD_NZB},
        'nzbSavePath=s'                => \$options{NZB_SAVE_PATH},
        'splitnpar!'                   => \$options{SPLITNPAR},
        'par2!'                        => \$options{PAR2},
        'headers=s%'                   => \$options{HEADERS},
        'name=s'                       => \$options{NAME},
        'tempFolder=s'                 => \$options{TEMP_FOLDER});

    my $config = {};
    $config = Config::Tiny->read($CONFIGURATION_FILE) if $CONFIGURATION_FILE && -e $CONFIGURATION_FILE;

    $options{UPLOAD_SIZE} //= $config->{upload}{size} // 750 * 1024;
    $options{OBFUSCATE}   //= $config->{upload}{obfuscate} // 0;
    $options{GROUPS}      //= [split(',', $config->{upload}{newsgroups} // '')];
    $options{AUTH_USER}   //= $config->{auth}{user} // '';
    $options{AUTH_PASS}   //= $config->{auth}{password} // '';
    $options{CONNECTIONS} //= $config->{server}{connections} // 2;
    $options{SERVER}      //= $config->{server}{server} // '';
    $options{SERVER_PORT} //= $config->{server}{port} // 443;
    $options{TLS} //= $config->{server}{tls} // ($options{SERVER_PORT} == 443 || $options{SERVER_PORT} == 563 ? 1 : 0);
    $options{GENERATE_IDS}            //= $config->{server}{generate_ids} // 1;
    $options{TLS_IGNORE_CERTIFICATE}  //= $config->{server}{tls_ignore_certificate} // 0;
    $options{HEADERCHECK}             //= $config->{headerCheck}{enabled};
    $options{HEADERCHECK_SERVER}      //= $config->{headerCheck}{server} // $options{SERVER};
    $options{HEADERCHECK_SERVER_PORT} //= $config->{headerCheck}{port} // $options{SERVER_PORT};
    $options{HEADERCHECK_CONNECTIONS} //= $config->{headerCheck}{connections} // 1;
    $options{HEADERCHECK_AUTH_USER}   //= $config->{headerCheck}{user} // $options{AUTH_USER};
    $options{HEADERCHECK_AUTH_PASS}   //= $config->{headerCheck}{password} // $options{AUTH_PASS};
    $options{HEADERCHECK_RETRIES}     //= $config->{headerCheck}{retries} // 1;
    $options{HEADERCHECK_SLEEP}       //= $config->{headerCheck}{sleep} // 30;
    $options{UPLOADER}                //= $config->{upload}{uploader} // 'NewsUP <NewsUP@somewhere.cbr>';
    $options{METADATA}                //= $config->{metadata};
    $options{SPLITNPAR}               //= $config->{options}{splitnpar} // 0;
    $options{PAR2}                    //= $config->{options}{par2} // 0;
    $options{PAR2_PATH}               //= $config->{options}{par2_path};
    $options{PAR2_RENAME_SETTINGS}    //= $config->{options}{par2_rename_settings} // 'c -s768000 -r0';
    $options{PAR2_SETTINGS}           //= $config->{options}{par2_settings} // 'c -s768000 -r15';
    $options{HEADERS}                 //= $config->{'extra-headers'};
    $options{UPLOAD_NZB}              //= $config->{options}{upload_nzb} // 0;
    $options{NZB_SAVE_PATH}           //= $config->{options}{nzb_save_path} // '.';
    $options{SPLIT_CMD}               //= $config->{options}{split_cmd};
    $options{SPLIT_PATTERN}           //= $config->{options}{split_pattern} // '*7z *[0-9][0-9][0-9]';
    $options{TEMP_FOLDER}             //= $config->{options}{temp_folder};
    $options{PROGRESSBAR_SIZE}        //= $config->{options}{progressbar_size} // 16;
    $options{UPLOAD_NZB}              //= 0;

    croak '--nfo option is incompatible with obfuscation' if $options{NFO} && $options{OBFUSCATE};
    croak "NFO file $options{NFO} doesn't exist" if $options{NFO} && !-f $options{NFO};

    %options = %{update_file_settings(\%options)};

    if ($options{DEBUG}) {
        say "Using the options: ";
        for my $k (sort keys %options) {
            my $v = $options{$k};
            if (defined $v) {
                if (ref $v eq 'ARRAY') {
                    say "\t$k:";
                    say "\t\t$_" for @$v;
                }
                elsif (ref $v eq 'HASH') {
                    say "\t$k:";
                    while (my ($key, $value) = each(%$v)) {
                        say "\t\t$key: $value";
                    }
                }
                else {
                    chomp $v;
                    say "\t$k: $v";
                }
            }
        }
    }


    return \%options;
}

sub update_file_settings {

    my ($options) = @_;

    if ($options->{UPLOAD_NZB} && !$options->{NZB_FILE}) {
        if ($options->{NAME}) {
            $options->{NZB_FILE} = $options->{NAME} . '.nzb';
        }
        elsif ($options->{FILES} && @{$options->{FILES}} == 1) {
            $options->{NZB_FILE} = $options->{FILES}[0] . '.nzb';
        }
    }
    if ($options->{SPLITNPAR} && !$options->{NAME}) {
        if ($options->{FILES} && @{$options->{FILES}} == 1) {
            $options->{NAME} = (fileparse($options->{FILES}[0], qr/\.[^.]*/))[0];
            $options->{NZB_FILE} //= $options->{NAME} . '.nzb';
        }
    }

    return $options;
}

sub help {
    say <<"END";
    Copyright (C) 2018 David Santiago

    This program is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with this program.  If not, see <http://www.gnu.org/licenses/>.    
END
    _exit 0;
}

sub save_nzb {
    my ($options, $articles) = @_;
    my $dom  = XML::LibXML::Document->new('1.0', 'UTF-8');
    my $nzb  = $dom->createElement('nzb');
    my $head = $dom->createElement('head');
    # if ($options->{SPLIT_PASSWORD}) {
    #     my $pass_meta = $dom->createElement('meta');
    #     $pass_meta->setAttribute('type' => "password");
    #     $pass_meta->appendText($options->{SPLIT_PASSWORD});
    #     $head->add_child($pass_meta);
    # }
    for (keys %{$options->{METADATA}}) {
        my $meta = $dom->createElement('meta');
        $meta->setAttribute('type' => $_);
        $meta->appendText($options->{METADATA}{$_});
        $head->addChild($meta);
    }
    $nzb->addChild($head);

    my $totalFiles  = 0;    # variable used to build the subject
    my %fileMapping = ();
    for my $article (@$articles) {
        $fileMapping{$article->filename} = [] if (!exists $fileMapping{$article->filename});

        push @{$fileMapping{$article->filename}}, $article;
        $totalFiles++;
    }

    my $currentFile = 0;
    for my $filename (sort keys %fileMapping) {
        my $fileElement = $dom->createElement('file');
        $fileElement->setAttribute(
            'poster' => $options->{OBFUSCATE} ? generate_random_string(12, 1) : $options->{UPLOADER});
        $fileElement->setAttribute('date' => time() - $options->{OBFUSCATE} * int(rand(1_000_000)));
        if ($options->{OBFUSCATE}) {
            $fileElement->setAttribute('subject' => generate_random_string(64));
        }
        else {
            my $subject = '[' . ++$currentFile . "/$totalFiles] - \"$filename\" ";
            if ($options->{COMMENTS}) {
                $subject = $options->{COMMENTS}[0] . " $subject";
                $subject .= "$options->{COMMENTS}[1] " if ($options->{COMMENTS}[1]);
                $subject .= 'yEnc (1/' . scalar(@{$fileMapping{$filename}}) . ')';
            }
            $fileElement->setAttribute('subject' => $subject);
        }

        my $groupsElement = $dom->createElement('groups');

        if ($options->{obfuscate}) {
            my @common_groups = (
                'boneless', 'cores',      'erotica', 'games',  'sounds.lossless', 'anime',
                'mp3',      'multimedia', 'tv',      'teevee', 'music',           'warez',
                'movies'
            );
            my $groupElement = $dom->createElement('group');
            $groupElement->appendText($common_groups[int(rand(@common_groups))]);

        }
        else {
            my @newsgroups = @{$fileMapping{$filename}->[0]{newsgroups}};
            for (@newsgroups) {
                my $groupElement = $dom->createElement('group');
                $groupElement->appendText($_);
                $groupsElement->addChild($groupElement);
            }
        }

        $fileElement->addChild($groupsElement);

        my $segmentsElement = $dom->createElement('segments');
        $fileElement->addChild($segmentsElement);

        for my $article (sort { $a->{part} <=> $b->{part} } @{$fileMapping{$filename}}) {
            my $segElement = $dom->createElement('segment');
            $segElement->setAttribute('number' => $article->{part});
            $segElement->setAttribute(bytes    => $article->size());
            if ($article->message_id()) {
                $segElement->appendText($article->message_id());
            }
            else {
                warn "The NZB isn't going to be valid. There are unknown articles. Please check output for failures";
            }
            $segmentsElement->addChild($segElement);
        }
        $nzb->addChild($fileElement);
    }

    my $nzb_file = catfile($options->{NZB_SAVE_PATH}, $options->{NAME} // $options->{NZB_FILE});
    $nzb_file .= '.nzb' if $nzb_file !~ /\.nzb$/;
    open my $fh, '>:raw', $nzb_file or die "Unable to create the NZB: $!";
    print $fh $nzb->serialize;
    close $fh;
    say "created nzb $nzb_file";
    return $nzb_file;
}

sub get_random_array_elements {

    my $array        = shift;
    my $i            = @$array;
    my $randElements = int(rand($i));
    while (--$i) {
        my $j = int rand($i + 1);
        @$array[$i, $j] = @$array[$j, $i];
    }

    return [@$array[0 .. $randElements]];
}

sub find_files {
    my ($options) = @_;
    my @files = ();

    croak "The `temp_folder` option isn't defined!"            if !$options->{TEMP_FOLDER};
    croak "The `temp_folder` isn't empty! Please clean it."    if glob(catfile($options->{TEMP_FOLDER}, '*'));
    croak "The `temp_folder` doesn't exist! Please create it." if !-e $options->{TEMP_FOLDER};
    croak "The  `par2_path` option isn't defined!"             if $options->{OBFUSCATE} && !$options->{PAR2_PATH};
    croak "The  `split_cmd` option isn't defined!"             if $options->{SPLITNPAR} && !$options->{SPLIT_CMD};

    for my $path (@{$options->{FILES}}) {
        croak "The file $path doesn't exist!" if !-e $path;
    }

    if ($options->{SPLITNPAR} && $options->{OBFUSCATE}) {
        my $obfuscated_files = _obfuscate_files($options->{FILES}, $options);
        my $split_files = _split_files($obfuscated_files, $options);
        return _par_files($split_files, $options);
        # my @compressed_files = compress_files(@obfuscated_files);
        # my @rarnpar_files = par_files(@compressed_files);

    }
    elsif ($options->{SPLITNPAR} && !$options->{OBFUSCATE}) {
        my $temp_files = _copy_files_to_temp($options->{FILES}, $options);
        my $split_files = _split_files($temp_files, $options);
        return _par_files($split_files, $options);

    }
    elsif ($options->{PAR2} && $options->{OBFUSCATE}) {
        my $obfuscated_files = _obfuscate_files($options->{FILES}, $options);
        return _par_files($obfuscated_files, $options);

    }
    elsif ($options->{PAR2} && !$options->{OBFUSCATE}) {
        my $temp_files = _copy_files_to_temp($options->{FILES}, $options);
        return _par_files($temp_files, $options);

    }
    elsif ($options->{OBFUSCATE}) {
        return _obfuscate_files($options->{FILES}, $options);

    }
    else {
        return _copy_files_to_temp($options->{FILES}, $options);
    }
}

sub _copy_files_to_temp {
    my ($files, $options) = @_;
    for (@$files) {
        if (-e catfile($options->{TEMP_FOLDER}, basename($_))) {
            die 'The file ' . catfile($options->{TEMP_FOLDER}, basename($_)) . ' already exists! Use a folder!';
        }
    }

    rcopy($_, $options->{TEMP_FOLDER}) or die "Unable to copy the file to the temp folder: $!" for (@$files);

    return _return_all_files_in_folder($options->{TEMP_FOLDER});
}

sub _par_files {
    my ($files, $options) = @_;

    # Add the NFO in this step
    if ($options->{NFO}) {
        $files = _copy_files_to_temp([$options->{NFO}], $options);
    }

    my $cmd = sprintf(
        '%s %s %s "%s"',
        $options->{PAR2_PATH},
        $options->{PAR2_SETTINGS},
        catfile(
            $options->{TEMP_FOLDER},
            $options->{OBFUSCATE} ? generate_random_string(12, 1)
            : $options->{NAME}    ? $options->{NAME}
            :                       generate_random_string(12, 1)
        ),
        join('" "', @$files));
    qx/$cmd/;
    return _return_all_files_in_folder($options->{TEMP_FOLDER});
}

sub _return_all_files_in_folder {
    my ($folder) = @_;
    my @files = ();
    find(sub { push @files, $File::Find::name if (-f $File::Find::name); }, $folder);
    return \@files;
}


sub _split_files {
    # $files - isn't being used but i want a consistent function signature
    my ($files, $options) = @_;

    my $split_name
      ;    #= $options->{OBFUSCATE}?generate_random_string(12,1):$options->{NAME}//generate_random_string(12,1);

    if ($options->{OBFUSCATE}) {
        $split_name = generate_random_string(12, 1);
    }
    elsif ($options->{NAME}) {
        $split_name = $options->{NAME};
        my $test_split_name = catfile($options->{TEMP_FOLDER}, $split_name);
        for (@{_return_all_files_in_folder($options->{TEMP_FOLDER})}) {
            if ($test_split_name eq $_) {
                $split_name = generate_random_string(12, 1);
                last;
            }
        }
    }
    else {
        $split_name = generate_random_string(12, 1);
    }


    my $cmd = sprintf('%s "%s" "%s"',
        $options->{SPLIT_CMD},
        catfile($options->{TEMP_FOLDER}, $split_name),
        join('" "', glob(catfile($options->{TEMP_FOLDER}, '*'))));
    qx/$cmd/;

    my %f = ();
    for my $pat (split(/\s/, $options->{SPLIT_PATTERN})) {
        for (glob(catfile($options->{TEMP_FOLDER}, $pat))) {
            $f{$_} = 1;
        }
    }

    for (glob(catfile($options->{TEMP_FOLDER}, '*'))) {
        rmtree $_ or die "unable to delete file: $!" unless $f{$_};
    }

    return [keys %f];
}

sub _obfuscate_files {
    my ($files, $options) = @_;

    my @processed_files   = ();
    my @only_files        = ();
    my %random_name_table = ();

    for my $file (@$files) {
        my $new_random_name;

        if (-d $file) {
            my $new_random_name;
            do { $new_random_name = generate_random_string(12, 1); } while ($random_name_table{$new_random_name});
            $random_name_table{$new_random_name} = 1;
            $new_random_name = catfile($options->{TEMP_FOLDER}, $new_random_name);

            rcopy($file, $new_random_name);
            my ($files_to_rename, $rename_par2) = _create_renaming_par_from_folder($new_random_name, $options);
            push @processed_files, $rename_par2;

            my %random_name_table_files = ();
            for my $folder_file (@$files_to_rename) {
                my $new_random_file_name;
                do { $new_random_file_name = generate_random_string(12, 1); }
                  while ($random_name_table_files{$new_random_file_name});
                $random_name_table_files{$new_random_file_name} = 1;

                rmove($folder_file, catfile($new_random_name, $new_random_file_name));
                push @processed_files, catfile($new_random_name, $new_random_file_name);
            }
        }
        else {
            push @only_files, $file;
        }
    }

    if (@only_files) {

        my @files_to_rename = ();
        for my $file (@only_files) {
            my $filename = fileparse($file);
            push @files_to_rename, catfile($options->{TEMP_FOLDER}, $filename);
            rcopy($file, $options->{TEMP_FOLDER});
        }
        push @processed_files, _create_renaming_par_from_files(\@files_to_rename, $options);

        for (@files_to_rename) {
            my $new_random_name;
            do { $new_random_name = generate_random_string(12, 1); } while ($random_name_table{$new_random_name});
            $new_random_name = catfile($options->{TEMP_FOLDER}, $new_random_name);
            rmove($_, $new_random_name);
            push @processed_files, $new_random_name;
        }
    }
    return \@processed_files;
}

sub _create_renaming_par_from_files {
    my ($files, $options) = @_;
    my $cmd = sprintf("%s %s '%s' '%s'",
        $options->{PAR2_PATH},
        $options->{PAR2_RENAME_SETTINGS},
        catfile($options->{TEMP_FOLDER}, 'rename.with.this.par2'),
        join("' '", @$files));
    # say "create renaming par from files: $cmd";
    qx/$cmd/;
    return catfile($options->{TEMP_FOLDER}, 'rename.with.this.par2');
}

sub _create_renaming_par_from_folder {
    my ($folder, $options) = @_;
    my @files = glob(catfile($folder, '*'));
    my $cmd = sprintf("%s %s '%s' '%s'",
        $options->{PAR2_PATH},
        $options->{PAR2_RENAME_SETTINGS},
        catfile($folder, 'rename.with.this.par2'),
        join("' '", @files));
    # say $cmd;
    qx/$cmd/;
    return \@files, catfile($folder, 'rename.with.this.par2');
}

sub generate_random_string {
    my ($length, $alphan) = @_;
    my @allowedCharacters = ('0' .. '9', 'A' .. 'Z', 'a' .. 'z');
    push @allowedCharacters, ('-', '_', '.', '$') if !$alphan;
    my $string = '';
    $string .= $allowedCharacters[rand(@allowedCharacters)] while ($length--);
    return $string;
}

sub generate_random_ids {
    my ($how_many, $options) = @_;
    my %ids               = ();
    my @random_generators = (\&_generate_random_ids_newsup);
    push @random_generators,
      (
        \&_generate_random_id,       \&_generate_random_id_gopoststuff, \&_generate_random_id_newsmangler,
        \&_generate_random_ids_nyuu, \&_generate_random_ids_jbinup,     \&_generate_random_ids_jbindown,
        \&_generate_random_ids_powerpost
      ) if $options->{OBFUSCATE};
    # my @random_generators = (
    #     \&_generate_random_id,           \&_generate_random_id_gopoststuff, \&_generate_random_id_newsmangler,
    #     \&_generate_random_ids_newsup,   \&_generate_random_ids_nyuu,       \&_generate_random_ids_jbinup,
    #     \&_generate_random_ids_jbindown, \&_generate_random_ids_powerpost
    # );
    while ($how_many--) {
        while (1) {
            my $id = $random_generators[int(rand(scalar @random_generators))]->(gettimeofday());
            if (!exists $ids{$id}) {
                $ids{$id} = $id;
                last;
            }
        }
    }
    return [keys %ids];
}

sub _generate_random_id {
    my ($sec, $usec) = @_;
    return generate_random_string(8 + int(rand(24))) . '@' . generate_random_string(1 + int(rand(12)), 1);
}

sub _generate_random_ids_newsup {
    my ($sec, $usec) = @_;
    my $time       = _generate_encode_base36("$sec$usec");
    my $randomness = _generate_encode_base36(rand("$sec$usec"));

    return "$sec$usec.$randomness\@$time.newsup";
}

sub _generate_encode_base36 {
    my ($val) = @_;
    my $symbols = join '', '0' .. '9', 'A' .. 'Z';
    my $b36 = '';
    while ($val) {
        $b36 = substr($symbols, $val % 36, 1) . $b36;
        $val = int $val / 36;
    }
    return $b36 || '0';
}

sub _generate_random_ids_jbindown {
    my ($sec, $usec) = @_;
    return generate_random_string(32) . ".$sec-$usec" . int(rand(9999)) . '@JBinDown.local';
}

sub _generate_random_ids_jbinup {
    my ($sec, $usec) = @_;
    return generate_random_string(32) . '@JBinUp.local';
}

sub _generate_random_ids_nyuu {
    my ($sec, $usec) = @_;
    return generate_random_string(12) . "-$sec$usec\@nyuu";
}

sub _generate_random_ids_powerpost {
    my ($sec, $usec) = @_;
    my $domain = '@camelsystem-powerpost.local';
    $domain = '@powerpost2000AA.local' if (rand(10) > 5);
    return 'part' . (1 + int(rand(98))) . 'of' . (1 + int(rand(98))) . '.' . generate_random_string(22) . $domain;
}

sub _generate_random_id_newsmangler {
    my ($sec, $usec) = @_;
    my @domains = (
        'reader.easyusenet.nl',    'eu.news.astraweb.com',
        'news.usenet.farm',        'unliminews.com',
        'reader.usenetbucket.com', 'news.astraweb.com',
        'reader2.newsxs.nl',       'reader.usenetdiscounter.com',
        'news.giganews.com',       'news.usenetserver.com',
        'news.powerusenet.com',    'news.usenet.net',
        'news.supernews.com',      'news.rhinonewsgroups.com',
        'news.tweaknews.eu',       'news.newshosting.com',
        'news.easynews.com',       'news.frugalusenet.com',
        'news.123usenet.nl',       'news.alibis.com',
        'post.anarqy.com',         'news.usenetexpress.com',
        'news.budgetnews.net',     'east.usenetstorm.com',
        'news.xennews.com',        'news.yottanews.com',
        'secure.fastusenet.org',   'news.newsdemon.com'
    );
    return "$sec.$usec." . int(rand(1024)) . '@' . $domains[int(rand(scalar @domains))];
}

sub _generate_random_id_gopoststuff {
    my ($sec, $usec) = @_;
    return "$sec.$usec\$gps\@gpoststuff";
}



1;
