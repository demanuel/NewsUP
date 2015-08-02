##############################################################################
#
# Author: David Santiago <demanuel@ymail.com>
# License: GPL V3
#
##############################################################################

package Net::NNTP::Uploader;
use strict;
use File::Basename;
use IO::Socket::INET;
use IO::Socket::SSL;# qw(debug3);
use Time::HiRes qw/ time /;
use String::CRC32;
use 5.018;
use Data::Dumper;
use Benchmark;
#The allowed posting segment size isn't standard
our $NNTP_MAX_UPLOAD_SIZE=2*512*1024; 
my $YENC_NNTP_LINESIZE=128;
$|=1;

my @YENC_CHAR_MAP = map{
	my $char = ($_+42)%256;
	($char == 0 || $char == 10 || $char == 13 || $char == 61) ? '='.chr($char+64) : chr($char);

	} (0..0xffff);

my %YENC_CHAR_MAP2=();
for my $i (0..0xffff) {
  my $char = ($i+42)%256;
  if ($char == 0 || $char == 10 || $char == 13 || $char == 61) {
    $YENC_CHAR_MAP2{chr($i)}='='.chr($char+64);
  }else {
      $YENC_CHAR_MAP2{chr($i)}=chr($char);
  }
}

my %TRANSLATION_TABLE=("\x09", "=I", "\x20", "=`", "\x2e","=n");
#my $TRANSLATION_REGEXP = join('|', (map{quotemeta chr($_);} (0..0xffff)));


sub new{

  my ($class, $connectionNumber, $server, $port, $username, $userpass,$monitoringPort) = @_;
  
  my $self = {authenticated=>0,
	      server=>$server,
	      port=>$port,
	      connection=>$connectionNumber,
	      username=>$username,
	      userpass=>$userpass,
	      parentChannel => IO::Socket::INET->new(Proto => 'udp',PeerAddr=>"localhost:$monitoringPort")};

  if ($port!= 119 && $port != 80 && $port != 23 ) {
    $self->{ssl}=1;
  }else {
    $self->{ssl}=0;
  }
  
  bless $self, $class;
  return $self;
}

#Creates the socket to be used on the communication with the server
sub _create_socket{

  my ($self) = @_;
  my $socket;
  
  if ($self->{ssl}) {
    $socket = IO::Socket::SSL->new(
				   PeerHost=>$self->{server},
				   PeerPort=>$self->{port},
				   SSL_verify_mode=>SSL_VERIFY_NONE,
				   SSL_version=>'TLSv1',
				   #SSL_version=>'TLSv1_2',
				   #SSL_cipher_list=>'DHE-RSA-AES128-SHA',
				   SSL_ca_path=>'/etc/ssl/certs',
				  ) or die "Failed to connect or ssl handshake: $!, $SSL_ERROR";
  }else {
    $socket = IO::Socket::INET->new (
				     PeerAddr => $self->{server},
				     PeerPort => $self->{port},
				     Proto => 'tcp',
				    ) or die "ERROR in Socket Creation : $!\n";
  }
  $socket->autoflush(1);
  sysread($socket, my $output, 8192);

  if (substr($output,0,3)==200) {
    $self->{postok}=1;
  }else {
    $self->{postok}=0;
  }
  
  $self->{socket}=$socket;
}

#performs the server authentication
sub _authenticate{

  my ($self, $socket, $username, $password) = @_;
  #my $socket = $self->{socket};
  #my $username = $self->{username};
  print $socket "authinfo user ",$username,"\r\n";
  sysread($socket, my $output, 8192);
  my $status = substr($output,0,3);
  if ($status != 381) {
    $self->{authenticated}=0;
    shutdown $socket, 2;
    return -1;
  }
  #my $password=$self->{userpass};
  print $socket "authinfo pass ",$password,"\r\n";
  sysread($socket, $output, 8192);
  $status = substr($output,0,3);
  if ($status != 281 && $status != 250) {
    $self->{authenticated}=0;
    shutdown $socket, 2;
    return -1;
  }
  $self->{authenticated}=1;
  return 1;
  
}

#perform the server logout
sub logout{
  my ($self) = @_;
  my $socket = $self->{socket};
  print $socket "quit\r\n";
  shutdown $socket, 2;  
}

sub transmit_files{
  my ($self, $filesListRef, $from, $initComment, $endComment, $newsgroupsRef, $isHeaderCheck) = @_;

  my $newsgroups = join(',',@$newsgroupsRef);
  
  if ($self->{authenticated}==0) {
    while ($self->{authenticated} == 0){
      $self->_create_socket;
      $self->_authenticate($self->{socket}, $self->{username}, $self->{userpass});
      last if($self->{authenticated} == 1);
      sleep 30;
    }
  }
  my $socket = $self->{socket};

  my $ifh;
  my $lastFile = '';
  my $fileSize = 0;
  for my $filePair (@$filesListRef) {

    #To avoid opening the same file multiple times
    if ($filePair->[0] ne $lastFile) {
      close $ifh if defined $ifh;
      open $ifh, '<:bytes', $filePair->[0] or die "Couldn't open file: $!";
      binmode $ifh;
      $lastFile=$filePair->[0];
      $fileSize = -s $lastFile;
    }
    my @temp = split('/',$filePair->[1]);
    my $currentFilePart = $temp[0];
    my $totalFilePart = $temp[1];
    
    #my $fileSize= -s $filePair->[0];
    my $fileName=(fileparse($filePair->[0]))[0];
    
    my ($readedData, $readSize) = _get_file_bytes_by_part($ifh, $currentFilePart-1);# $filePair->[0]);

    print $socket "POST\r\n";
    sysread($socket, my $output, 8192);

    if (substr($output,0,3)==340) {
      $output = '';
      
      eval{
	
	
	my $pcrc32=sprintf("%x", crc32($readedData));
	
	print $socket "From: ",$from,"\r\n",
	  #	  print $out "From: ",$from,"\r\n",
	  "Newsgroups: ",$newsgroups,"\r\n",
	  "Subject: \"",$fileName,"\" yenc (",$currentFilePart,"/",$totalFilePart,")\r\n",
	  "Message-ID: <",$filePair->[2],">\r\n",
	  "\r\n=ybegin part=",$currentFilePart," line=",$YENC_NNTP_LINESIZE," size=",$fileSize, " name=",$fileName,
	  "\r\n=ypart begin=",1+$NNTP_MAX_UPLOAD_SIZE*($currentFilePart-1), " end=",tell($ifh),
	  "\r\n", _yenc_encode2($readedData),
	  "\r\n=yend size=",$readSize," pcrc32=",$pcrc32, "\r\n.\r\n";
	
	sysread($socket, $output, 8192);
      };
      if ($@){
	say "Error: $@";
	return undef;
      }
      #441 Posting Failed. Message-ID is not unique E1
      if ($isHeaderCheck) {
	say 'Header Checking: '.$output if ($output!~ /240/ && $output!~ /441/)
      }else {
	say $output if ($output!~ /240/);      
      }      
    }
    
    $|=1;
    $self->{parentChannel}->send($readSize);
    
  }
  close $ifh
}

#It will perform the header check!
sub header_check{
  my ($self, $filesRef, $newsgroups, $from, $comments, $sleepTime, $server, $port, $user, $password)=@_;

  eval{
    my $socket = $self->_get_headercheck_socket($server,$port, $user,$password);
    my $newsgroup = $newsgroups->[0]; #The first newsgroup is enough to check if the segment was uploaded correctly
    print $socket "group ",$newsgroup,"\r\n";
    my $output;
    sysread($socket, $output, 8192);

    sleep $sleepTime;
    for my $fileRef (@$filesRef) {
      my $count = 0;
      do {
	my $messageID = $fileRef->[2];
	print $socket "stat <",$messageID,">\r\n";
	sysread($socket, $output, 8192);
	chop $output;

	if (substr($output,0,3) == 223) {
	  next;
	}elsif ($count==5) {
	  say "Aborting! Header $messageID not found on the server! Please check for issues on the server.";
	  last; #There's no point in keep going to the other subjects, since there are already issues with the upload.
	}else {
	  #print "\rHeader check: Missing segment $messageID [$output]\r\n";
	  $self->transmit_files([$fileRef], $from, $comments->[0], $comments->[1], $newsgroups, 1);
	  $count=$count+1;
	  sleep $sleepTime;
	  
	}
      }while(1);
    }
    $self->_shutdown_headercheck_socket($socket, $server,$port);
  };
  if ($@) {
    say "Error: $@";
  }
}

sub _shutdown_headercheck_socket{
  my ($self, $socket, $server,$port) = @_;
  return if $self->{server} eq $server && $self->{port} == $port;

  print $socket "quit\r\n";
  shutdown $socket, 2; 
  
}

sub _get_headercheck_socket{
  my ($self, $server,$port, $username, $password) = @_;

  return $self->{socket} if $self->{server} eq $server;

  my $socket;
  if ($port!= 119 && $port != 80 && $port != 23 ) {
    $socket = IO::Socket::SSL->new(
				   PeerHost=>$server,
				   PeerPort=>$port,
				   SSL_verify_mode=>SSL_VERIFY_NONE,
				   SSL_version=>'TLSv1',
				   SSL_ca_path=>'/etc/ssl/certs',
				  ) or die "Failed to connect or ssl handshake: $!, $SSL_ERROR";

  }else {
        $socket = IO::Socket::INET->new (
				     PeerAddr => $server,
				     PeerPort => $port,
				     Proto => 'tcp',
				    ) or die "ERROR in Socket Creation : $!\n";
  }

  $socket->autoflush(1);
  sysread($socket, my $output, 8192);#Discard the data the server sends when we connect
  die "Unable to authenticate on the headercheck server!" if ($self->_authenticate($socket, $username, $password) == -1);
  
  return $socket;
}

sub _get_file_bytes_by_part{
  my ($fileNameHandle, $part) = @_;

  my $correctPosition = $NNTP_MAX_UPLOAD_SIZE*$part;

  seek ($fileNameHandle, $correctPosition, 0);

  my $bytes;
  my $readSize = read($fileNameHandle, $bytes, $NNTP_MAX_UPLOAD_SIZE);
  return ($bytes, $readSize);
}




sub _yenc_encode2{
  my ($string) = @_;
  my $content = "";

  $string =~ s/(.{1})/$YENC_CHAR_MAP2{$1}/g;
  my @lines= unpack("(A$YENC_NNTP_LINESIZE)*", $string);
  for my $line (@lines) {
    if (length($line)==$YENC_NNTP_LINESIZE) {
      if (exists $TRANSLATION_TABLE{substr($line,-1)}) {
	$line .= $TRANSLATION_TABLE{chop ($line)};
      }
    }
  }
  return join("\r\n", @lines);#$content;
}


sub _yenc_encode{
  my ($string) = @_;
  my $column = 0;
  my $content = '';
  
 for my $hexChar (unpack('W*',$string)) {

    my $char= $YENC_CHAR_MAP[$hexChar];
    
    #null || LF || CR || =
    
    if($char =~ /=/){
      $column++;
    }
    elsif($column==0 && $char =~ /(\x09|\x20|\x2e)/){
      
      $column++;
      $char = $TRANSLATION_TABLE{$1};
    }
    elsif($column == $YENC_NNTP_LINESIZE && $char =~ /(\x09|\x32)/){
      $column++;
      $char=$TRANSLATION_TABLE{$1};
      
    }

    if (++$column>= $YENC_NNTP_LINESIZE ) {
      $column = 0;
      $char .= "\r\n";
    }
    $content .= $char;
  }

  return $content;
}

1;
