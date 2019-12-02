package NewsUP::Utils;
use 5.030;
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
use Cwd 'abs_path';
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
  clear_line
);

our $VERSION            = 2019_07_02_22_47;
our $CONFIGURATION_FILE = catfile(($^O eq 'MSWin32' ? $ENV{"USERPROFILE"} : $ENV{HOME}), '.config', 'newsup.conf');

sub read_options {
    my %options = (DEBUG => 0);
    GetOptions(
        'help'                         => sub { help(); },
        'version'                      => sub { version(); },
        'debug!'                       => \$options{DEBUG},
        'checkNZB=s@'                  => \$options{CHECK_NZB},
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
        'tempFolder=s'                 => \$options{TEMP_FOLDER},
        'skipCopy!'                    => \$options{SKIP_COPY},
        'noNzb'                        => \$options{NO_NZB});

    my $config = {};
    $config = Config::Tiny->read($CONFIGURATION_FILE)
      if $CONFIGURATION_FILE && -e $CONFIGURATION_FILE;

    $options{UPLOAD_SIZE} //= $config->{upload}{size}      // 750 * 1024;
    $options{OBFUSCATE}   //= $config->{upload}{obfuscate} // 0;
    $options{GROUPS}    //= [split(/\s*,\s*/, $config->{upload}{newsgroups} // '')];
    $options{AUTH_USER} //= $config->{auth}{user} // '';
    $options{AUTH_PASS}   //= $config->{auth}{password}      // '';
    $options{CONNECTIONS} //= $config->{server}{connections} // 2;
    $options{SERVER}      //= $config->{server}{server}      // '';
    $options{SERVER_PORT} //= $config->{server}{port}        // 443;
    $options{TLS} //= $config->{server}{tls} // ($options{SERVER_PORT} == 443 || $options{SERVER_PORT} == 563 ? 1 : 0);
    $options{GENERATE_IDS}            //= $config->{server}{generate_ids}           // 1;
    $options{TLS_IGNORE_CERTIFICATE}  //= $config->{server}{tls_ignore_certificate} // 0;
    $options{HEADERCHECK}             //= $config->{headerCheck}{enabled};
    $options{HEADERCHECK_SERVER}      //= $config->{headerCheck}{server}            // $options{SERVER};
    $options{HEADERCHECK_SERVER_PORT} //= $config->{headerCheck}{port}              // $options{SERVER_PORT};
    $options{HEADERCHECK_CONNECTIONS} //= $config->{headerCheck}{connections}       // 1;
    $options{HEADERCHECK_AUTH_USER}   //= $config->{headerCheck}{user}              // $options{AUTH_USER};
    $options{HEADERCHECK_AUTH_PASS}   //= $config->{headerCheck}{password}          // $options{AUTH_PASS};
    $options{HEADERCHECK_RETRIES}     //= $config->{headerCheck}{retries}           // 1;
    $options{HEADERCHECK_SLEEP}       //= $config->{headerCheck}{sleep}             // 30;
    $options{UPLOADER}                //= $config->{upload}{uploader}               // 'NewsUP <NewsUP@somewhere.cbr>';
    $options{METADATA}                //= $config->{metadata};
    $options{SPLITNPAR}               //= $config->{options}{splitnpar}             // 0;
    $options{PAR2}                    //= $config->{options}{par2}                  // 0;
    $options{PAR2_PATH}               //= $config->{options}{par2_path};
    $options{PAR2_RENAME_SETTINGS}    //= $config->{options}{par2_rename_settings}  // 'c -s768000 -r0';
    $options{PAR2_SETTINGS}           //= $config->{options}{par2_settings}         // 'c -s768000 -r15';
    $options{HEADERS}                 //= $config->{'extra-headers'};
    $options{UPLOAD_NZB}              //= $config->{options}{upload_nzb}            // 0;
    $options{NZB_SAVE_PATH}           //= $config->{options}{nzb_save_path}         // '.';
    $options{SPLIT_CMD}               //= $config->{options}{split_cmd};
    $options{SPLIT_PATTERN} //= $config->{options}{split_pattern} // '*7z *[0-9][0-9][0-9]';
    $options{TEMP_FOLDER}   //= $config->{options}{temp_folder};
    $options{SKIP_COPY}         //= $config->{options}{skip_copy}     // 0;
    $options{NO_NZB}            //= $config->{options}{no_nzb}        // 1;
    $options{RUN_BEFORE_UPLOAD} //= $config->{options}{before_upload} // 0;

    croak '--nfo option is incompatible with obfuscation'
      if $options{NFO} && $options{OBFUSCATE};
    croak "NFO file $options{NFO} doesn't exist"
      if $options{NFO} && !-f $options{NFO};

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
    for my $f (@{$options->{FILES}}) {
        chop $f if $f =~ m#/$#;
    }

    if ($options->{UPLOAD_NZB} && !$options->{NZB_FILE}) {
        if ($options->{NAME}) {
            $options->{NZB_FILE} = $options->{NAME};
        }
        elsif ($options->{FILES} && @{$options->{FILES}} >= 1) {
            $options->{NZB_FILE} = (File::Spec->splitpath($options->{FILES}[0]))[2];
        }
    }
    if ($options->{SPLITNPAR} && !$options->{NAME}) {
        if ($options->{FILES} && @{$options->{FILES}} >= 1) {
            my $file = $options->{FILES}[0];
            use File::Spec;
            $options->{NAME} = (File::Spec->splitpath($file))[-1];
            $options->{NZB_FILE} //= $options->{NAME};
        }
    }

    $options->{NZB_FILE} //='newsup';
    $options->{NZB_FILE} .='.nzb';
    
    return $options;
}

sub version {
    my $year = (localtime())[5] + 1900;
    say <<"END";
    NewsUP $VERSION

    Copyright (C) $year David Santiago

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

sub help {

    say <<'END';
    Usage: newsup [options] --file <file1>

    Options available:
        --help                         => Print this help message
        --version                      => Prints the version
        --debug!                       => Prints debug information
        --checkNZB=s@                  => Checks the status of the NZB files
        --file=s@                      => Files to upload
        --list=s                       => Text file with one file per line to be uploaded
        --nfo=s                        => File to be uploaded but not included in the compressed files
        --configuration=s              => Configuration file
        --uploadsize=i                 => Size of the upload message. By default 750KBytes. Unless you know what you are doing do not change!
        --obfuscate!                   => Enable obfuscation. Tip: If this is set, some options that might conflict with the obfuscation are ignored
        --newsgroup|group=s@           => Groups to where the files are going to be uploaded
        --username=s                   => Username for authentication in the USP
        --password=s                   => Password to be used in the authentication
        --connections=i                => Number of connections to be used. Tip: use the minimal value that saturates your connection
        --server=s                     => Server to upload your files
        --port=i                       => Port in the server to where you are uploading the files
        --TLS!                         => If you want to use secure sockets when connecting to the USP
        --generateIDs!                 => If NewsUP should create IDs or not. Some servers require the client to use IDs. If possible do not use it
        --ignoreCert!                  => Ignore the usenet server certificate
        --headerCheck!                 => Perform headercheck
        --headerCheckServer=s          => Server to perform the header check. By default it is the same server to where the files were uploaded
        --headerCheckPort=i            => Port of the server where the header check is being done. By default it is the same port to where the files were uploaded
        --headerCheckRetries|retries=i => Number of retries to perform the headercheck, after which it will ignore
        --headerCheckSleep=i           => Number of seconds to sleep between the upload and the headercheck and the headercheck retries
        --headerCheckUsername=s        => Username for authentication in the headercheck USP. By default it is the same as the normal username
        --headerCheckPassword=s        => Password for authentication in the headercheck USP. By default it is the same as the normal password
        --headerCheckConnections=i     => Number of connections to use when doing the headercheck
        --comment=s@                   => Comment to be added to the uploaded files. The user can specify two
        --uploader=s                   => From who the post is from. It needs to be compliance with internet syntax
        --metadata=s%                  => Metadata to be added in the nzb
        --nzb=s                        => The name of the NZB to be created. By default is the name option or if not set the name of the uploaded file
        --unzb!                        => If the nzb created should also be uploaded
        --nzbSavePath=s                => To where the nzb should be saved
        --splitnpar!                   => If newsup should split and/or par the files before upload. You need to set some options correctly in the config file to use this feature
        --par2!                        => If newsup should par the files before upload
        --headers=s%                   => Headers to be added to the post
        --name=s                       => Name of the upload
        --tempFolder=s                 => Path to a temporary folder, to where newsup is going to copy the files to be uploaded and which newsup is going to perform the require operations.
        --skipCopy!                    => Avoid copying the files to the tempFolder. Default is 0
	--noNzb                        => Do not create a NZB

END
    exit 0;
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
        if (!exists $fileMapping{$article->filename}) {
            $fileMapping{$article->filename} = [];
            $totalFiles++;
        }

        push @{$fileMapping{$article->filename}}, $article;
    }

    my $currentFile = 0;
    for my $filename (sort keys %fileMapping) {
        my $fileElement = $dom->createElement('file');
        $fileElement->setAttribute('poster' => $options->{UPLOADER});
        $fileElement->setAttribute('date'   => time());

        my $subject = '[' . ++$currentFile . "/$totalFiles] - \"$filename\" ";
        if ($options->{COMMENTS}) {
            $subject = $options->{COMMENTS}[0] . " $subject";
            $subject .= "$options->{COMMENTS}[1] "
              if ($options->{COMMENTS}[1]);
            $subject .= 'yEnc (1/' . scalar(@{$fileMapping{$filename}}) . ')';
        }
        $fileElement->setAttribute('subject' => $subject);

        my $groupsElement = $dom->createElement('groups');

        my @newsgroups = split(',', $fileMapping{$filename}->[0]{newsgroups});
        for (@newsgroups) {
            my $groupElement = $dom->createElement('group');
            $groupElement->appendText($_);
            $groupsElement->addChild($groupElement);
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
    my $handler = select $fh;
    $| = 1;
    select $handler;
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
    if ($options->{PAR2} || $options->{SPLITNPAR}) {
        croak "The `temp_folder` option isn't defined!" if !$options->{TEMP_FOLDER};
        croak "The `temp_folder` isn't empty! Please clean it."
          if glob(catfile($options->{TEMP_FOLDER}, '*'));
        croak "The `temp_folder` doesn't exist! Please create it."
          if !-e $options->{TEMP_FOLDER};
        croak "The  `par2_path` option isn't defined!"
          if $options->{OBFUSCATE} && !$options->{PAR2_PATH};
        croak "The  `split_cmd` option isn't defined!"
          if $options->{SPLITNPAR} && !$options->{SPLIT_CMD};
    }
    for my $path (@{$options->{FILES}}) {
        croak "The file $path doesn't exist!" if !-e $path;
    }

    if ($options->{SPLITNPAR} && $options->{OBFUSCATE}) {
        my $obfuscated_files = _obfuscate_files($options->{FILES}, $options);
        my $split_files      = _split_files($obfuscated_files, $options);
        return _process_files_before_upload(_par_files($split_files, $options), $options);
    }
    elsif ($options->{SPLITNPAR} && !$options->{OBFUSCATE}) {
        my $temp_files  = _copy_files_to_temp($options->{FILES}, $options);
        my $split_files = _split_files($temp_files, $options);
        return _process_files_before_upload($split_files, $options) unless $options->{PAR2};
        return _process_files_before_upload(_par_files($split_files, $options), $options);
    }
    elsif ($options->{PAR2} && $options->{OBFUSCATE}) {
        my $obfuscated_files = _obfuscate_files($options->{FILES}, $options);
        return _process_files_before_upload(_par_files($obfuscated_files, $options), $options);
    }
    elsif ($options->{PAR2} && !$options->{OBFUSCATE}) {
        my $temp_files = _copy_files_to_temp($options->{FILES}, $options);
        return _process_files_before_upload(_par_files($temp_files, $options), $options);
    }
    elsif ($options->{OBFUSCATE}) {
        return _process_files_before_upload(_obfuscate_files($options->{FILES}, $options), $options);
    }
    else {
        return _process_files_before_upload(_copy_files_to_temp($options->{FILES}, $options), $options);
    }
}

sub _process_files_before_upload {
    my ($files, $options) = @_;
    local $\;
    return $files unless $options->{RUN_BEFORE_UPLOAD};

    my $cmd       = $options->{RUN_BEFORE_UPLOAD} . " '" . join("' '", @$files) . "'";
    _clear_line();
    print "Processing files before upload\r";
    my @new_files = map { chomp; $_ } qx/$cmd/;
    return \@new_files;
}

sub _clear_line {
    local $\;
    print "\r"." "x37 ."\r";
}

sub _copy_files_to_temp {
    my ($files, $options) = @_;
    my @files = ();
    for (@$files) {
        unless ($options->{SKIP_COPY}) {
            die 'The file ' . catfile($options->{TEMP_FOLDER}, basename($_)) . ' already exists! Use a folder!'
              if (-e catfile($options->{TEMP_FOLDER}, basename($_)));
            push @files, $_;
        }
        else {
            my $file = $_;
            if (-f $file) {
                push @files, $file;
            }
            else {
                push @files, @{_return_all_files_in_folder($file)};
            }
        }
    }
    unless ($options->{SKIP_COPY}) {
        rcopy($_, $options->{TEMP_FOLDER})
          or die "Unable to copy the file to the temp folder: $!"
          for (@files);

        return _return_all_files_in_folder($options->{TEMP_FOLDER});
    }
    return \@files;
}

sub _par_files {
    my ($files, $options) = @_;
    # Add the NFO in this step
    if ($options->{NFO}) {
        $files = _copy_files_to_temp([$options->{NFO}], $options);
    }

    my $file_folder = (File::Spec->splitpath($files->[0]))[1];
    $file_folder ||= '.';

    my $gen_par_name = catfile(
          $options->{SKIP_COPY} ? $file_folder
        : $options->{TEMP_FOLDER},
        $options->{OBFUSCATE} ? generate_random_string(12, 1)
        : $options->{NAME}    ? $options->{NAME}
        :                       generate_random_string(12, 1));
    my $cmd
      = sprintf('%s %s "%s" "%s"', $options->{PAR2_PATH}, $options->{PAR2_SETTINGS}, $gen_par_name,
        join('" "', @$files));

    if ($options->{DEBUG}) {
        say $cmd;
        system($cmd);

    }
    else {
	local $\;
	_clear_line();
	print "Start par'ing the files\r";
        qx/$cmd/;
    }

    croak $options->{PAR2_PATH} . " failed to execute. Please make sure that the option par2_path is set correctly"
      if $? == -1;

    # special case, because the par2cmd (the de facto standard) doesn't support creating par archives to another folder
    return [glob("$gen_par_name*"), @$files] if ($options->{PAR2} && $options->{SKIP_COPY} && !$options->{SPLITNPAR});
    return _return_all_files_in_folder($options->{TEMP_FOLDER});
}

sub _return_all_files_in_folder {
    my ($folder) = @_;
    $folder = abs_path($folder);
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
        (split(/\s/, $options->{SPLIT_PATTERN}))[0] =~ m/([a-zA-Z0-9]+)/;
        $split_name .= ".$1";
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

    my $cmd = sprintf(
        '%s "%s" "%s"',
        $options->{SPLIT_CMD},
        catfile($options->{TEMP_FOLDER}, $split_name),
        join('" "',
              $options->{SKIP_COPY} && !$options->{OBFUSCATE}
            ? @$files
            : glob(catfile($options->{TEMP_FOLDER}, '*'))));

    if ($options->{DEBUG}) {
        say $cmd;
        system($cmd);

    }
    else {
	local $\;
	_clear_line();
	print "Splitting the files\r";
        qx/$cmd/;
    }

    croak "The split command failed! Please verify the split_cmd option" if $? == -1;

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

    if ($options->{DEBUG}) {
        say $cmd;
        system($cmd);

    }
    else {
	local $\;
	_clear_line();
	print "Creating renaming par for the files\r";
        qx/$cmd/;
    }

    croak "Creating the renaming par2 file failed!" if $? == -1;

    return catfile($options->{TEMP_FOLDER}, 'rename.with.this.par2');
}

sub _create_renaming_par_from_folder {
    my ($folder, $options) = @_;
    my @files = glob(catfile($folder, '*'));
    my $cmd   = sprintf("%s %s '%s' '%s'",
        $options->{PAR2_PATH},
        $options->{PAR2_RENAME_SETTINGS},
        catfile($folder, 'rename.with.this.par2'),
        join("' '", @files));

    if ($options->{DEBUG}) {
        say $cmd;
        system($cmd);

    }
    else {
	local $\;
	_clear_line();
	print "Creating renaming par for the files\r";
        qx/$cmd/;
    }

    croak "Creating the renaming par2 file failed!" if $? == -1;

    return \@files, catfile($folder, 'rename.with.this.par2');
}

# Avoid two consecutive symbols
# A string must not start or end in symbol
sub generate_random_string {
    my ($length, $alphan) = @_;
    state @allowedCharacters = ('0' .. '9', 'A' .. 'Z', 'a' .. 'z');

    my $string = $allowedCharacters[rand(@allowedCharacters)];
    $length -= 2;
    $length = 0 if $length < 0;

    # avoid two consecutive alpha chars
    unless ($alphan) {
        my %alpha_chars = ('-' => 1, '_' => 1, '.' => 1, '$' => 1);
        state @set_allowed = (@allowedCharacters, keys %alpha_chars);

        my ($previous_char, $current_char) = ('', '');

        while ($length--) {
            do {
                $current_char = $set_allowed[rand(@set_allowed)];
            } while (exists $alpha_chars{$current_char}
                && exists $alpha_chars{$previous_char});
            $string .= $current_char;
            $previous_char = $current_char;
        }

        $string .= $allowedCharacters[rand(@allowedCharacters)];

    }
    else {

        $string .= $allowedCharacters[rand(@allowedCharacters)] while ($length--);
    }

    $string .= $allowedCharacters[rand(@allowedCharacters)];
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
    state @symbols = ('0' .. '9', 'A' .. 'Z');
    my $b36 = '';
    while ($val) {
        $b36 .= $symbols[$val % 36];
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
    my $number_of_domains = 28;    # micro-optimization
    return "$sec.$usec." . int(rand(1024)) . '@' . $domains[int(rand($number_of_domains))];
}

sub _generate_random_id_gopoststuff {
    my ($sec, $usec) = @_;
    return "$sec.$usec\$gps\@gpoststuff";
}

1;
