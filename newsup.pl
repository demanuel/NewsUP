#!/usr/bin/env perl
use 5.018;
use IO::Socket::SSL;
use IO::Select;
use Scalar::Util qw/refaddr/;
use Getopt::Long;
use Config::Tiny;
use File::Find;
use Time::HiRes qw/gettimeofday tv_interval/;
use File::Basename qw/fileparse basename/;
use Socket qw/SO_SNDBUF SO_RCVBUF TCP_NODELAY/;
use POSIX qw/ceil/;
use XML::LibXML;
use Config;

###### C CODE YENC ######
use Inline C => Config => cc => exists $ENV{NEWSUP_CC}?$ENV{NEWSUP_CC}:$Config{cc};
#In case of message "loaded library mismatch" (this happens typically in windows) we need to add the flag -DPERL_IMPLICIT_SYS
use Inline C => Config => ccflags => exists $ENV{NEWSUP_CCFLAGS}?$ENV{NEWSUP_CCFLAGS}:$Config{ccflags};
use Inline C => <<'C_CODE';
#include <stdint.h>;
static uint32_t crc32_tab[] = {
    0x00000000, 0x77073096, 0xee0e612c, 0x990951ba, 0x076dc419, 0x706af48f,
    0xe963a535, 0x9e6495a3, 0x0edb8832, 0x79dcb8a4, 0xe0d5e91e, 0x97d2d988,
    0x09b64c2b, 0x7eb17cbd, 0xe7b82d07, 0x90bf1d91, 0x1db71064, 0x6ab020f2,
    0xf3b97148, 0x84be41de, 0x1adad47d, 0x6ddde4eb, 0xf4d4b551, 0x83d385c7,
    0x136c9856, 0x646ba8c0, 0xfd62f97a, 0x8a65c9ec, 0x14015c4f, 0x63066cd9,
    0xfa0f3d63, 0x8d080df5, 0x3b6e20c8, 0x4c69105e, 0xd56041e4, 0xa2677172,
    0x3c03e4d1, 0x4b04d447, 0xd20d85fd, 0xa50ab56b, 0x35b5a8fa, 0x42b2986c,
    0xdbbbc9d6, 0xacbcf940, 0x32d86ce3, 0x45df5c75, 0xdcd60dcf, 0xabd13d59,
    0x26d930ac, 0x51de003a, 0xc8d75180, 0xbfd06116, 0x21b4f4b5, 0x56b3c423,
    0xcfba9599, 0xb8bda50f, 0x2802b89e, 0x5f058808, 0xc60cd9b2, 0xb10be924,
    0x2f6f7c87, 0x58684c11, 0xc1611dab, 0xb6662d3d, 0x76dc4190, 0x01db7106,
    0x98d220bc, 0xefd5102a, 0x71b18589, 0x06b6b51f, 0x9fbfe4a5, 0xe8b8d433,
    0x7807c9a2, 0x0f00f934, 0x9609a88e, 0xe10e9818, 0x7f6a0dbb, 0x086d3d2d,
    0x91646c97, 0xe6635c01, 0x6b6b51f4, 0x1c6c6162, 0x856530d8, 0xf262004e,
    0x6c0695ed, 0x1b01a57b, 0x8208f4c1, 0xf50fc457, 0x65b0d9c6, 0x12b7e950,
    0x8bbeb8ea, 0xfcb9887c, 0x62dd1ddf, 0x15da2d49, 0x8cd37cf3, 0xfbd44c65,
    0x4db26158, 0x3ab551ce, 0xa3bc0074, 0xd4bb30e2, 0x4adfa541, 0x3dd895d7,
    0xa4d1c46d, 0xd3d6f4fb, 0x4369e96a, 0x346ed9fc, 0xad678846, 0xda60b8d0,
    0x44042d73, 0x33031de5, 0xaa0a4c5f, 0xdd0d7cc9, 0x5005713c, 0x270241aa,
    0xbe0b1010, 0xc90c2086, 0x5768b525, 0x206f85b3, 0xb966d409, 0xce61e49f,
    0x5edef90e, 0x29d9c998, 0xb0d09822, 0xc7d7a8b4, 0x59b33d17, 0x2eb40d81,
    0xb7bd5c3b, 0xc0ba6cad, 0xedb88320, 0x9abfb3b6, 0x03b6e20c, 0x74b1d29a,
    0xead54739, 0x9dd277af, 0x04db2615, 0x73dc1683, 0xe3630b12, 0x94643b84,
    0x0d6d6a3e, 0x7a6a5aa8, 0xe40ecf0b, 0x9309ff9d, 0x0a00ae27, 0x7d079eb1,
    0xf00f9344, 0x8708a3d2, 0x1e01f268, 0x6906c2fe, 0xf762575d, 0x806567cb,
    0x196c3671, 0x6e6b06e7, 0xfed41b76, 0x89d32be0, 0x10da7a5a, 0x67dd4acc,
    0xf9b9df6f, 0x8ebeeff9, 0x17b7be43, 0x60b08ed5, 0xd6d6a3e8, 0xa1d1937e,
    0x38d8c2c4, 0x4fdff252, 0xd1bb67f1, 0xa6bc5767, 0x3fb506dd, 0x48b2364b,
    0xd80d2bda, 0xaf0a1b4c, 0x36034af6, 0x41047a60, 0xdf60efc3, 0xa867df55,
    0x316e8eef, 0x4669be79, 0xcb61b38c, 0xbc66831a, 0x256fd2a0, 0x5268e236,
    0xcc0c7795, 0xbb0b4703, 0x220216b9, 0x5505262f, 0xc5ba3bbe, 0xb2bd0b28,
    0x2bb45a92, 0x5cb36a04, 0xc2d7ffa7, 0xb5d0cf31, 0x2cd99e8b, 0x5bdeae1d,
    0x9b64c2b0, 0xec63f226, 0x756aa39c, 0x026d930a, 0x9c0906a9, 0xeb0e363f,
    0x72076785, 0x05005713, 0x95bf4a82, 0xe2b87a14, 0x7bb12bae, 0x0cb61b38,
    0x92d28e9b, 0xe5d5be0d, 0x7cdcefb7, 0x0bdbdf21, 0x86d3d2d4, 0xf1d4e242,
    0x68ddb3f8, 0x1fda836e, 0x81be16cd, 0xf6b9265b, 0x6fb077e1, 0x18b74777,
    0x88085ae6, 0xff0f6a70, 0x66063bca, 0x11010b5c, 0x8f659eff, 0xf862ae69,
    0x616bffd3, 0x166ccf45, 0xa00ae278, 0xd70dd2ee, 0x4e048354, 0x3903b3c2,
    0xa7672661, 0xd06016f7, 0x4969474d, 0x3e6e77db, 0xaed16a4a, 0xd9d65adc,
    0x40df0b66, 0x37d83bf0, 0xa9bcae53, 0xdebb9ec5, 0x47b2cf7f, 0x30b5ffe9,
    0xbdbdf21c, 0xcabac28a, 0x53b39330, 0x24b4a3a6, 0xbad03605, 0xcdd70693,
    0x54de5729, 0x23d967bf, 0xb3667a2e, 0xc4614ab8, 0x5d681b02, 0x2a6f2b94,
    0xb40bbe37, 0xc30c8ea1, 0x5a05df1b, 0x2d02ef8d
  };

//Thank you Tomas Novysedlak for yenc encoding piece :-)
AV* _yenc_encode_c(unsigned char* data, size_t data_size)
{
	const unsigned char maxwidth = 128;

	unsigned char *pointer, *encbuffer;
	size_t encoded_size = data_size;
	int column = 0;
	unsigned char c;
	int i;
	unsigned int crc32 = 0xFFFFFFFF;


	if (NULL == (encbuffer = malloc(data_size << 1)))
	{
		return NULL;
	}
	else
	{
		pointer = encbuffer;
	}

	for(i = 0; i < data_size; ++i)
	{
		c = data[i];
		crc32 = crc32_tab[(crc32 ^ c) & 0xFF] ^ (crc32 >> 8);
		c = (c + 42) & 0xFF;

		switch (c)
		{
			case 0 :
			case '\n' :
			case '\r' :
			case '=' :
			  c += 64;
			  *(pointer++) = '=';
			  column++;
			  encoded_size++;
			  break;

			case '\t' :
			case ' ' :
			  if(!column || column - 1 == maxwidth)
			  {
				  column++;
				  encoded_size++;
				  *(pointer++) = '=';
				  c += 64;
			  }
			  break;

			case '.' :
			  if(!column)
			  {
				  column++;
				  encoded_size++;
				  *(pointer++) = '=';
				  c += 64;
			  }
			  break;
		}

		*(pointer++) = c;
		column++;

		if(column >= maxwidth)
		{
			column = 0;
			*(pointer++) = '\r';
			*(pointer++) = '\n';
			encoded_size += 2;
		}
	}

	*pointer = 0;
	encoded_size++;
	crc32 = crc32 ^ 0xFFFFFFFF;
  encbuffer = (char*) realloc(encbuffer, encoded_size);
  SV* yenc_string = newSVpv(encbuffer, 0);
	SV* ret = sv_2mortal(newAV());
	av_push(ret, yenc_string);
  //av_push(ret, newSVuv(crc32));
  free(encbuffer);

  char *hex_number = (char*)malloc(sizeof(char)*9);//8 chars + the termination char (null)
  int hex_size = sprintf(hex_number, "%x", crc32);
  //printf("say size: %d\n", hex_size);
  //hex_number = (char*) realloc(hex_number,hex_size);
  SV* hex_string = newSVpv(hex_number, 0);
  av_push(ret, hex_string);
  free(hex_number);



        return ret;
}

C_CODE
##### END C CODE ######


$|=1;
my $CRLF="\x0D\x0A";
$/=$CRLF;
$\=$CRLF;

# Default values
my %OPTIONS=(server=>undef,
            port=>undef,
            username=>undef,
            password=>undef,
            TLS=>1,
            ignoreCert=>1,
            uploader=>undef,
            connections=>undef,
            files=>[],
            comments=>[],
            newsgroups=>[],
            extraHeaders=>[],
            metadata=>{},
            nzb=>'./newsup.nzb',
            headerCheck=>undef,
            headerCheckServer=>undef,
            headerCheckPort=>undef,
            headerCheckSleep=>undef,
            headerCheckUsername=>undef,
            headerCheckRetries=>undef,
            headerCheckConnections=>undef,
            uploadSize=>750*1024,
            lineSize => 128,
            configuration=>$^O eq 'MSWin32'? $ENV{"USERPROFILE"}.'/.config/newsup.conf': $ENV{"HOME"}.'/.config/newsup.conf');


sub _parse_user_options{
  GetOptions('help'=>=>sub{help();},
            'configuration=s'=>\$OPTIONS{configuration},
            'server=s'=>\$OPTIONS{server},
            'port=i'=>\$OPTIONS{port},
            'connections=i'=>\$OPTIONS{connections},
            'username=s'=>\$OPTIONS{username},
            'password=s'=>\$OPTIONS{password},
            'file=s'=>$OPTIONS{files},
            'comment=s'=>$OPTIONS{comments},
            'uploader=s'=>\$OPTIONS{uploader},
            'newsgroup|group=s'=>$OPTIONS{newsgroups},
            'metadata=s'=>$OPTIONS{metadata},
            'nzb=s'=>\$OPTIONS{nzb},
            'headerCheck=i'=>\$OPTIONS{headerCheck},
            'headerCheckSleep=i'=>\$OPTIONS{headerCheckSleep},
            'headerCheckServer=s'=>\$OPTIONS{headerCheckServer},
            'headerCheckPort=i'=>\$OPTIONS{headerCheckPort},
            'headerCheckUsername=s'=>\$OPTIONS{headerCheckUsername},
            'headerCheckPassword=s'=>\$OPTIONS{headerCheckPassword},
            'headerCheckRetries|retries=i'=>\$OPTIONS{headerCheckRetries},
            'headerCheckConnections=i'=>\$OPTIONS{headerCheckConnections},
            'uploadsize=i'=>\$OPTIONS{uploadSize},
            'linesize=i'=>\$OPTIONS{lineSize},
            'TLS!'=>\$OPTIONS{TLS},
            'ignoreCert!'=>\$OPTIONS{ignoreCert}
            );

  if(-e $OPTIONS{configuration}){
    my $config = Config::Tiny->read( $OPTIONS{configuration} );
    $OPTIONS{metadata}=$config->{metadata} if(!%{$OPTIONS{metadata}} && exists $config->{metadata});
    # Usefull for creating the subject
    if(!defined $OPTIONS{comments}->[0]){
	$OPTIONS{comments}->[0] = '';
	$OPTIONS{comments}->[1] = '';
    }else{
	$OPTIONS{comments}->[0] .=' ';
	if (defined $OPTIONS{comments}->[1]){
	    $OPTIONS{comments}->[1] =' '.$OPTIONS{comments}->[1] ;
	}else{
	    $OPTIONS{comments}->[1] ='';
	}
    }
    
    $OPTIONS{server}=$config->{server}{server} if !defined $OPTIONS{server} && exists $config->{server}{server};
    $OPTIONS{port}=$config->{server}{port} // 443 if !defined $OPTIONS{port};
    $OPTIONS{connections}=$config->{server}{connections} // 2  if !defined $OPTIONS{connections};
    $OPTIONS{username}=$config->{auth}{user} if !defined $OPTIONS{username} && exists $config->{auth}{user};
    $OPTIONS{password}=$config->{auth}{password} if !defined $OPTIONS{password} && exists $config->{auth}{password};

    $OPTIONS{uploader}=$config->{upload}{uploader} if !defined $OPTIONS{uploader} && exists $config->{upload}{uploader};

    # remove duplicates and trim
    if(@{$OPTIONS{newsgroups}}){
        $OPTIONS{newsgroups}= [keys %{{map{$_ =~ s/^\s+|\s+$//;  $_=>1} @{$OPTIONS{newsgroups}}}}];
    }elsif(exists $config->{upload}{newsgroups}){
      $OPTIONS{newsgroups}= [keys %{{map{$_ =~ s/^\s+|\s+$//;  $_=>1} split(',',$config->{upload}{newsgroups})}}];
    }

    $OPTIONS{headerCheck} = $config->{headerCheck}{enabled} // 0 if !defined $OPTIONS{headerCheck};
    $OPTIONS{headerCheckSleep} = $config->{headerCheck}{sleep} // 30 if !defined $OPTIONS{headerCheckSleep};

    $OPTIONS{headerCheckServer} = $config->{headerCheck}{server} if (!defined $OPTIONS{headerCheckServer} && exists $config->{headerCheck}{server});
    $OPTIONS{headerCheckPort} = $config->{headerCheck}{port} if (!defined $OPTIONS{headerCheckPort} && exists $config->{headerCheck}{port});
    $OPTIONS{headerCheckUsername} = $config->{headerCheck}{user} if (!defined $OPTIONS{headerCheckUsername} && exists $config->{headerCheck}{user});
    $OPTIONS{headerCheckPassword} = $config->{headerCheck}{password} if (!defined $OPTIONS{headerCheckPassword} && exists $config->{headerCheck}{password});

    $OPTIONS{headerCheckRetries} = $config->{headerCheck}{retries} // 1 if(!defined $OPTIONS{headerCheckRetries});

    $OPTIONS{headerCheckConnections} = $config->{headerCheck}{connections} if (!defined $OPTIONS{headerCheckRetries} && exists $config->{headerCheck}{connections});
    # uploadsize, linesize and TLS, only possible to set them through command line

    for my $key (keys %{$config->{extraHeaders}}){
      if ($key !~ /^X-/){
        push @{$OPTIONS{extraHeaders}}, "X-$key: $config->{extraHeaders}{$key}";
      }else{
        push @{$OPTIONS{extraHeaders}}, "$key: $config->{extraHeaders}{$key}";
      }
    }
    push @{$OPTIONS{extraHeaders}}, $CRLF; #The extra headers are the last thing from the header. So they need two (2) CRLFs separating them

    if (@{$OPTIONS{newsgroups}} == 0 || !$OPTIONS{server} || !$OPTIONS{port} || !$OPTIONS{username} || !$OPTIONS{password}){
      say "Please configure all the required inputs server,port,username,password, newsgroups";
      say "Server: $OPTIONS{server}";
      say "Port: $OPTIONS{port}";
      say "username: $OPTIONS{username}";
      say 'password: '.('x'x length $OPTIONS{server});
      say 'Newsgroups: '.join(',', @{$OPTIONS{newsgroups}});
      exit 0;
    }


  }
}




sub _create_socket{
  my ($host, $port, $withSSL, $ignoreCert) = @_;

  my $socket = undef;
  if(($port == 443 || $port== 563) && $withSSL){
    $socket = IO::Socket::SSL->new(PeerHost=>$host,
                                    PeerPort=>$port,
                                    SSL_verify_mode=>$ignoreCert?SSL_VERIFY_NONE:SSL_VERIFY_PEER,
                                    Proto => 'tcp',
                                    Blocking=>1) or die "Error: Failed to connect or ssl handshake: $!, $SSL_ERROR";
  }else{
    $socket = IO::Socket::INET->new(PeerHost=>$host,
                                    PeerPort=>$port,
                                    Proto => 'tcp',
                                    Blocking=>1) or die "Error: Failed to connect: $!";
  }

  $socket->autoflush(1);
  $socket->sockopt(SO_SNDBUF, 4*1024*1024);
  $socket->sockopt(SO_RCVBUF, 4*1024*1024);
  $socket->sockopt(TCP_NODELAY, 1);

  return $socket;
}

sub _initialize_sockets{
  my ($numberSockets, @params) = @_;
  my @sockets = ();
  my %socketStatus = ();
  while($numberSockets--){
    my $socket = _create_socket(@params);
    push @sockets, $socket;
    $socketStatus{refaddr($socket)}=0;
  }

  return (\@sockets, \%socketStatus);
}


sub _authenticate_sockets{
  my ($sockets, $socketStatus, $username, $password) = @_;
  my $select = IO::Select->new(@$sockets);

  my $authenticatedSockets = 0;
  while ($authenticatedSockets < @$sockets){
    my ($readReady, $writeRead, $exceptionReady) = IO::Select->select($select, $select, undef);
    for my $socket (@$sockets){
      next if($socketStatus->{refaddr($socket)} > 4);
      my $read = _read_from_socket($socket); #<$socket>;

      if($socketStatus->{refaddr($socket)} == 0){
        # Welcome message
        $socketStatus->{refaddr($socket)}++;

      }elsif($socketStatus->{refaddr($socket)} == 2 && $read =~ /^381/){
        $socketStatus->{refaddr($socket)}++;
      }elsif($socketStatus->{refaddr($socket)} == 4 && $read =~ /^281|^250/){
        $socketStatus->{refaddr($socket)}++;
        $authenticatedSockets++;
      }else{
        die 'Unable to authenticate!';
      }
    }
    # my @writeReady = $select->can_write(0.5);
    for my $socket (@$sockets){
      if($socketStatus->{refaddr($socket)}==1){
        _print_to_socket ($socket, "authinfo user $username");
        $socketStatus->{refaddr($socket)}++;

      }elsif($socketStatus->{refaddr($socket)}==3){
        _print_to_socket ($socket, "authinfo pass $password");
        $socketStatus->{refaddr($socket)}++;
      }
    }
  }

  return ($sockets, $socketStatus, $select);
}

sub _print_to_socket{

  my ($socket, @args) = @_;
  local $,;
  return 0 if (print $socket @args);
  return 1;

}


sub _read_from_socket{
  my ($socket) = @_;
  my $output=<$socket>;

  return $output;
}

sub _upload_files{
  my ($socketStatus, $select, $files) = @_;
  $files = _get_file_list($files);

  my $segments = _get_segments($files);

  my $initialTime = [gettimeofday];
  $segments = _upload_segments($segments, $select, $socketStatus);

  my $uploadTime = tv_interval($initialTime);
  my $uploadSize = $OPTIONS{uploadSize}*scalar (@$segments) / 1024 ;
  my $approxSpeed = int($uploadSize/$uploadTime);
  say 'Uploaded '.int($uploadSize/1024).' MB in '.int($uploadTime/60).'m '.int($uploadTime%60)." s. Avg. Speed: [$approxSpeed KBytes/sec]";

  return $segments;

}

sub _upload_segments{
  my ($segments, $select, $status) = @_;

  my $segment;
  my $waitingForServerAck = @$segments;
  my @lastFileHandlerOpened = ('', undef,0);

  my @newIDs = ();
  my %segmentsIDs = ();

  my @progressBar = _fill_progress_bar(scalar @$segments);
  my $progressBarLineCounter = 0;

  while (@$segments){
    for my $socket ($select->can_write(0.05)){
      if($status->{refaddr $socket} == 5){
        _print_to_socket($socket, 'POST');
        $status->{refaddr $socket}=4;
      }elsif($status->{refaddr $socket} == 3){
        #post segment
        $segment = shift @$segments;
        if(defined $segment){
          @lastFileHandlerOpened = @{_post_segment($socket, $segment, \@lastFileHandlerOpened)};
          $status->{refaddr $socket} = 2;
          $segmentsIDs{refaddr $socket} = $segment;

          {
            local $\;
            print $progressBar[$progressBarLineCounter++];
          }

        }else{
          $status->{refaddr $socket}=4;
          last;
        }
      }
    }
    for my $socket ($select->can_read(0.05)){
      my $read = _read_from_socket($socket);
      next if $read eq '';
      if($status->{refaddr $socket} == 4){
        die "Unable to POST: $read" if $read !~ /^340 /;
        $status->{refaddr $socket}= 3;
      }elsif($status->{refaddr $socket} == 2){
        # A post was done and we need to confirm the post was done OK
        if($read =~ /^400 /){
          # The session expired. Put the segment back
          push @$segments, $segment;

          delete $status->{refaddr $socket};
          $select->remove($socket);

          my ($socketListRef, $socketStatus) = _initialize_sockets(1, $OPTIONS{server}, $OPTIONS{port}, $OPTIONS{TLS}, $OPTIONS{ignoreCert});
          ($socketListRef, undef, undef) = _authenticate_sockets($socketListRef, $socketStatus, $OPTIONS{username}, $OPTIONS{password});
          $status->{refaddr $socketListRef->[0]} = 5;
          $select->add($socketListRef->[0]);

        }elsif($read =~ /^240 .*<(.*)>/){
          $segmentsIDs{refaddr $socket}->{id}=$1;
          push @newIDs, $segmentsIDs{refaddr $socket};
          $status->{refaddr $socket} = 5;

        }else{
          chomp $read;
          say "Warning: Read after posting article: $read";
          push @newIDs, $segmentsIDs{refaddr $socket};
          $segmentsIDs{refaddr $socket}->{id}=undef;
          $status->{refaddr $socket} = 5;
        }
        $waitingForServerAck--;
      }
    }
  }


  # We need to wait until it finishes reading all the uploads
  while($waitingForServerAck){
    for my $socket ($select->can_read(0.05)){
      # say "counter: $counter";
      next if $status->{refaddr $socket} != 2;
      my $read = _read_from_socket($socket);
      if($read =~ /^240 .*<(.*)>/){
        $segmentsIDs{refaddr $socket}->{id}=$1;
      }else{
        $segmentsIDs{refaddr $socket}->{id}=undef;
      }
      push @newIDs,  $segmentsIDs{refaddr $socket};
      $status->{refaddr $socket} = 5;
      $waitingForServerAck--;
    }
  }

  close $lastFileHandlerOpened[1];
  return \@newIDs;
}

sub _post_segment{
  my ($socket, $segment, $lastFileHandlerOpened) = @_;

  my $baseName = fileparse($segment->{fileName});
  my $startPosition=1+$OPTIONS{uploadSize}*($segment->{segmentNumber}-1);
  (my $binString, my $readSize, my $endPosition, $lastFileHandlerOpened) = _get_file_data($segment->{fileName}, $startPosition-1, $lastFileHandlerOpened);
  my ($yenc_data, $crc32_data) = @{_yenc_encode_c($binString, $readSize)};

  my $subject = $OPTIONS{comments}->[0].'['.$segment->{fileNumber}.'/'.$segment->{totalFiles}.'] - "'.$baseName.'" ('.$segment->{segmentNumber}.'/'.$segment->{totalSegments}.')'.$OPTIONS{comments}->[1];

  _print_to_socket($socket,
      "From: ",$OPTIONS{uploader}, $CRLF,
      "Newsgroups: ",join(',',@{$OPTIONS{newsgroups}}),$CRLF,
      "Subject: ",$subject,$CRLF,
      # "Message-ID: <", $segment->{id},">",$CRLF,
      join($CRLF,@{$OPTIONS{extraHeaders}}), #Note: the extraHeaders contain a mandatory CRLF
      "=ybegin part=", $segment->{segmentNumber}, " total=",$segment->{totalSegments}," line=", $OPTIONS{lineSize}, " size=", $lastFileHandlerOpened->[2], " name=",$baseName, $CRLF,
      "=ypart begin=",$startPosition," end=", $endPosition, $CRLF,
      $yenc_data, $CRLF,
      "=yend size=",$readSize, " pcrc32=",$crc32_data,$CRLF,'.');

      return $lastFileHandlerOpened;
}

sub _get_file_data{
  my ($fileName, $position, $lastFileHandlerOpened) = @_;
  if($fileName ne $lastFileHandlerOpened->[0]){
    close $lastFileHandlerOpened->[1] if(defined $lastFileHandlerOpened->[1]);
    open my $fh, '<:raw :bytes', $fileName;
    $lastFileHandlerOpened->[0] = $fileName;
    $lastFileHandlerOpened->[1] = $fh;
    $lastFileHandlerOpened->[2] = -s $fileName;
  }
  #open my $fh, '<:raw :bytes', $fileName;
  #binmode $fh;
  seek $lastFileHandlerOpened->[1], $position,0;
  my $readSize = read($lastFileHandlerOpened->[1], my $byteString, $OPTIONS{uploadSize});
  my $endPosition = tell $lastFileHandlerOpened->[1];

  return ($byteString, $readSize, $endPosition, $lastFileHandlerOpened);

}

sub _get_segments{
  my ($files) =@_;
  my $totalFiles=scalar(@$files);
  my $digitNumber = split(//,$totalFiles);
  $digitNumber = 2 if $digitNumber < 2;

  my $digitString='%0'.$digitNumber.'d';

  my @segments = ();
  my $messageIDs={};
  for (my $fileNumber=0; $fileNumber < $totalFiles; $fileNumber++) {
    my $fileSize=-s $files->[$fileNumber];
    my $segmentNumber=0;

    my $totalSegments=ceil($fileSize/$OPTIONS{uploadSize});

    while ($segmentNumber++ < $totalSegments) {
      push @segments, {fileName=> $files->[$fileNumber],
		    fileSize=> $fileSize,
		    segmentNumber=>$segmentNumber,
		    totalSegments=>$totalSegments,
		    fileNumber=>sprintf($digitString,$fileNumber+1),
		    totalFiles=>sprintf($digitString,scalar(@$files)),
		    id=>undef,
		   };
    }
  }

  return \@segments;
}

sub _get_file_list{

  my ($userFilesToUpload) = @_;

  my @tempFiles=();
  for my $file (@$userFilesToUpload) {
    if(-d $file){
      find(sub{
      if (-f $_) {
        my $newName = $File::Find::name;
        push @tempFiles, $newName;

        }
      }, ($file));
    }elsif(-f $file){
      push @tempFiles, $file;
    }
  }

  @tempFiles = sort keys %{{map {$_ => 1} @tempFiles}};
  return \@tempFiles;
}


sub main{
  _parse_user_options;
  my $segments = _start_upload();
  $segments = _start_header_check($segments);
  _save_nzb($segments);

}

sub _save_nzb{
  my ($segments) = @_;

  my $dom = XML::LibXML::Document->new('1.0', 'UTF-8');
  my $nzb = $dom->createElement('nzb');
  my $head = $dom->createElement('head');
  $nzb->addChild($head);

  for(keys %{$OPTIONS{metadata}}){
    my $meta = $dom->createElement('meta');
    $meta->setAttribute('type'=>$_);
    $meta->appendText($OPTIONS{metadata}{$_});
    $head->addChild($meta);
  }

  my $totalFiles = 0; # variable used to build the subject
  my %fileMapping = ();
  for my $segment (@$segments){
    my $name = fileparse($segment->{fileName});
    $fileMapping{$name} = [] if(!exists $fileMapping{$name});

    push @{$fileMapping{$name}}, $segment;
    $totalFiles++;
  }

  # The segments should be already ordered, but we need to make sure
  my $currentFile = 0;
  for my $filename (sort keys %fileMapping){
    my $fileElement = $dom->createElement('file');
    $fileElement->setAttribute('poster'=>$OPTIONS{uploader});
    $fileElement->setAttribute('date'=>time());
    $fileElement->setAttribute('subject'=>$OPTIONS{comments}->[0].'['.++$currentFile."/$totalFiles] - \"$filename\"".$OPTIONS{comments}->[1].' yEnc (1/'.scalar(@{$fileMapping{$filename}}).')');

    my $groups = $dom->createElement('groups');
    $fileElement->addChild($groups);
    for my $groupname (@{$OPTIONS{newsgroups}}){
      my $group = $dom->createElement('group');
      $groups->addChild($group);
      $group->appendText($groupname);
    }

    my $segmentsElement = $dom->createElement('segments');
    $fileElement->addChild($segmentsElement);
    for my $segment (sort {$a->{segmentNumber} <=> $b->{segmentNumber}}  @{$fileMapping{$filename}}){
      my $segElement = $dom->createElement('segment');
      $segElement->setAttribute('number'=>$segment->{segmentNumber});

      my $byteSize = $OPTIONS{uploadSize};
      $byteSize = $segment->{fileSize} % $OPTIONS{uploadSize} if $segment->{segmentNumber}==$segment->{totalSegments};
      $byteSize = $OPTIONS{uploadSize} if $byteSize == 0;

      $segElement->setAttribute('bytes'=>$byteSize);
      $segElement->appendText($segment->{id});
      $segmentsElement->addChild($segElement);
    }
    $nzb->addChild($fileElement);
  }


  $dom->setDocumentElement($nzb);
  $OPTIONS{nzb}.='.nzb' if($OPTIONS{nzb} !~ /\.nzb$/);

  open my $ofh, '>:raw', $OPTIONS{nzb};
  print $ofh $dom->serialize;
  close $ofh;
  say "$OPTIONS{nzb} created!";
}

sub _start_upload{
  my ($sockets, $socketStatus) = _initialize_sockets($OPTIONS{connections}, $OPTIONS{server}, $OPTIONS{port}, $OPTIONS{TLS}, $OPTIONS{ignoreCert});
  ($sockets, $socketStatus, my $select) = _authenticate_sockets($sockets, $socketStatus, $OPTIONS{username}, $OPTIONS{password});
  my $segments = _upload_files($socketStatus, $select, $OPTIONS{files});
  _close_sockets($sockets);
  return $segments;
}

sub _start_header_check{
  my ($segments) = @_;
  if($OPTIONS{headerCheck}){
    $OPTIONS{headerCheckServer} = $OPTIONS{server} if (!defined $OPTIONS{headerCheckServer});
    $OPTIONS{headerCheckPort} = $OPTIONS{port} if (!defined $OPTIONS{headerCheckPort});
    $OPTIONS{headerCheckUsername} = $OPTIONS{username} if (!defined $OPTIONS{headerCheckUsername});
    $OPTIONS{headerCheckPassword} = $OPTIONS{password} if (!defined $OPTIONS{headerCheckPassword});
    $OPTIONS{headerCheckConnections} = $OPTIONS{connections} if (!defined $OPTIONS{headerCheckConnections});

    # Temporary variable to avoid searching for segments with two loops.
    my %segmentMap = map { $_->{fileNumber}.'|'.$_->{segmentNumber} => $_} @$segments;

    my $initialTime=[gettimeofday];
    while(@$segments && $OPTIONS{headerCheckRetries}--){
      {local $\; print "Header Checking\r"; }

      sleep($OPTIONS{headerCheckSleep});
      my ($sockets, $socketStatus) = _initialize_sockets($OPTIONS{headerCheckConnections}, $OPTIONS{headerCheckServer}, $OPTIONS{headerCheckPort}, $OPTIONS{TLS}, $OPTIONS{ignoreCert});
      ($sockets, undef, my $select) = _authenticate_sockets($sockets, $socketStatus, $OPTIONS{headerCheckUsername}, $OPTIONS{headerCheckPassword});

      say 'Warping up header check engines to ['.$OPTIONS{headerCheckServer}.':'.$OPTIONS{headerCheckPort}.'] with '.$OPTIONS{headerCheckConnections}.' connections!';
      my %socketStatus = map{ refaddr($_) => 0} @$sockets;
      $segments = _header_check($select, \%socketStatus, $segments);
      _close_sockets($sockets);
      say 'Missing '.scalar @$segments." segments";
      if(@$segments){
        say 'Re-Uploading missing segments';
        ($sockets, $socketStatus) = _initialize_sockets($OPTIONS{connections}, $OPTIONS{server}, $OPTIONS{port}, $OPTIONS{TLS}, $OPTIONS{ignoreCert});
        ($sockets, $socketStatus, $select) = _authenticate_sockets($sockets, $socketStatus, $OPTIONS{username}, $OPTIONS{password});
        $segments = _upload_segments($segments, $select, $socketStatus);

        $segmentMap{$_->{fileNumber}.'|'.$_->{segmentNumber}}->{id} = $_->{id} for(@$segments);

        _close_sockets($sockets);
      }
    }
    my $headerCheckTime = tv_interval($initialTime);
    say "HeaderCheck done in ".int($headerCheckTime/60)."m ".($headerCheckTime%60)."s";

    # my @return = values(%segmentMap);
    return [values(%segmentMap)];

  }

}

sub _header_check{

  my ($select, $socketStatus, $checkSegments) = @_;

  my %missingSegments = map{$_->{id}, $_} @$checkSegments;

  my $counter = 0;
  my @progressBar = ("[-]\r", "[\\]\r", "[|]\r", "[/]\r" );
  my $i = 0;
  while(@$checkSegments){
    for my $socket  ($select->can_write(0.05)){
      if($socketStatus->{refaddr $socket}==0){
        my $segment = shift @$checkSegments;
        if(defined $segment){
          if(defined $segment->{id}){
            _print_to_socket ($socket, 'stat <'.$segment->{id}.'>');
            $socketStatus->{refaddr $socket}=1;
            $counter++;
            local $\;
            print $progressBar[$i++%4];
          }
        }
      }
    }
    for my $socket  ($select->can_read(0.05)){
      if($socketStatus->{refaddr $socket}==1){
        my $read = _read_from_socket($socket);
        chomp $read;
        if($read =~ /^223 \d+ <(.*)>/){
          delete $missingSegments{$1};
        }
        $socketStatus->{refaddr $socket}=0;
        $counter--;
      }
    }
  }
  while($counter){
    for my $socket ($select->can_read(0.05)){
      if($socketStatus->{refaddr $socket}==1){
        my $read = _read_from_socket($socket);
        chomp $read;
        if($read =~ /^223 \d+ <(.*)>/){
          delete $missingSegments{$1};
        }
        $socketStatus->{refaddr $socket}=0;
        $counter--;
      }
    }
  }
  return [values %missingSegments];
}



sub _close_sockets{
  my ($sockets) = @_;

  for (@$sockets){
    _print_to_socket($_, "quit");
    close $_;
  }
}


sub _fill_progress_bar{
  my ($size) = @_;

  # $size = $size < 20? $size : 20;
  my @chars = qw (- \ | / );
  my @progressBar = ();
  my $progressString = '';
  my $progressStringIndicator = '=';

  my $jump = $size/20;
  if($jump < 1 ){
    $jump = 1;
    $progressStringIndicator = '=' x int(20/$size);
  }
  my $percentage = $size/20 < 1 ? 1 : $size/20 ;
  for(0.. $size-1){

    push @progressBar, sprintf("[%s] %02d%% [%-20s]\r", $chars[$_ % @chars ], $_/$size*100, $progressString);
    $progressString .= $progressStringIndicator if ($_ % $percentage == 0);
  }
  return @progressBar;
}


 main;
