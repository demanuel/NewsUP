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
use POSIX;
use NZB::File;
use Carp;
use String::CRC32;
use Data::Dumper;
use Digest::MD5 qw(md5_hex);
use 5.018;

#512Kb - the segment size. I tried with 4 Megs and got a 441. The allowed posting segment size isn't standard
my $NNTP_MAX_UPLOAD_SIZE=512*1024; 
my $YENC_NNTP_LINESIZE=128;
$|=1;

sub new{

  my $class = shift;  
  my $server = shift;
  my $port = shift;

  my $username = shift;
  my $userpass = shift;
  
  my $self = {server=>$server,
	      port=>$port,
	      username=>$username,
	      userpass=>$userpass};
  
  # $self->{server}=$server;
  # $self->{port}=$port;


  if ($port==995 || $port == 563) {
    $self->{ssl}=1;
  }else {
    $self->{ssl}=0;
  }
  
  bless $self, $class;
  return $self;
}

#Creates the socket to be used on the communication with the server
sub _create_socket{

  my $self = shift;
  my $socket;
  
  if ($self->{ssl}) {
    $socket = IO::Socket::SSL->new(
				   PeerHost=>$self->{server},
				   PeerPort=>$self->{port},
				   SSL_verify_mode=>SSL_VERIFY_NONE,
				   SSL_version=>'TLSv1',
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
  
  my @array = split ' ', $output;
  
  
  if ($array[0]==200) {
    $self->{postok}=1;
  }else {
    $self->{postok}=0;
  }
  
  $self->{socket}=$socket;
}

#performs the server authentication
sub _authenticate{

  my $self = shift;
  my $socket = $self->{socket};
  print $socket sprintf("authinfo user %s\r\n",$self->{username});
  sysread($socket, my $output, 8192);


  my @status = split(' ', $output);
  if ($status[0] != 381) {
    return -1;
  }

  print $socket sprintf("authinfo pass %s\r\n",$self->{userpass});
  sysread($socket, $output, 8192);


  @status = split(' ', $output);
  if ($status[0] != 281 && $status[0] != 250) {
    return -1;
  }
  return 1;
  
}

#perform the server logout
sub _logout{
  my $self = shift;
  my $socket = $self->{socket};
  print $socket "quit\r\n";
  shutdown $socket, 2;
  
}

#loops across the files and uploads them
sub upload_files{

  my $self = shift;
  my $filesListRef = shift;
  my $from = shift;
  my $initComment=shift;
  my $endComment=shift;
  my $newsgroupsRef = shift;


  $self->_create_socket;
  croak "Authentication Failed!" if $self->_authenticate == -1;
  say "Thread Authenticated!";

  my @nzbFiles = ();


  for my $file (@$filesListRef) {
    open my $ifh, '<:bytes', $file or die "Couldn't open file: $!";
    binmode $ifh;
    my $fileCRC32=crc32( *$ifh);
    close $ifh;
    open $ifh, '<:bytes', $file or die "Couldn't open file: $!";
    binmode $ifh;

    my $fileSize= -s $file;
    my $fileName=(fileparse($file))[0];

    my $filePart=1;
    my $fileMaxParts = ceil($fileSize/$NNTP_MAX_UPLOAD_SIZE);

    my $NZBFile = NZB::File->new($from, $newsgroupsRef);
    $NZBFile->set_subject(sprintf("\"%s\" yenc (/%d) [%s]", $fileName,$fileMaxParts,$fileSize));

    my $fileSpeedInitTimer = time();    
    while(read($ifh, my $bytes, $NNTP_MAX_UPLOAD_SIZE)>0){
      my $subject = sprintf("\"%s\" yenc (%d/%d) [%s]", $fileName,$filePart,$fileMaxParts,$fileSize,$fileCRC32);
      my $readSize=bytes::length($bytes);
      my $startingBytes = 1+$NNTP_MAX_UPLOAD_SIZE*($filePart-1);

      $subject = "[$initComment] $subject" if defined $initComment;
      $subject = "$subject [$endComment]" if defined $endComment;

      my $content = $self->_get_post_body($filePart, $fileMaxParts, $fileName, $startingBytes, $readSize, $bytes);

      my $partSpeedTimer = time();
      my $messageID;
      my $counter=0;

      do {
	$messageID = $self->_post($newsgroupsRef, $subject, $content, $from);
	$counter+=1;

	#3 tries
	if ($counter > 3) {
	  carp "Uploading file $fileName failed!";
	  $self->_logout;
	  last;
	}
	
      } while (!defined $messageID);

      printf("[%0.2f KBytes/sec]\r", $readSize/(time()-$partSpeedTimer)/1024);

      $NZBFile->add_segment($readSize, $messageID);
      $filePart+=1;

    }

    printf("%s was uploaded with a velocity of %0.2f KBytes/sec\r\n", $fileName, ($fileSize/(time()-$fileSpeedInitTimer))/1024);

    close $ifh;
    push @nzbFiles, $NZBFile;  
  }

  $self->_logout;
  return @nzbFiles;

}

sub _get_post_body{

  my $self = shift;
  my $filePart = shift;
  my $fileMaxParts = shift;
  my $fileName = shift;
  my $startingBytes=shift;
  my $readSize = shift;
  my $bytes = shift;
  my $fileCRC32 = shift;

  

  my $content = sprintf("=ybegin part=%d total=%d line=%d size=%d name=%s\r\n",$filePart, $fileMaxParts, $YENC_NNTP_LINESIZE,$readSize,$fileName);

  $content .= sprintf("=ypart begin=%d end=%d\r\n",$startingBytes, $startingBytes+$readSize);
  $content .= $self->_yenc_encode($bytes);
  $content .= sprintf("\r\n=yend size=%d pcrc32=%x",$readSize, crc32($bytes));

  if ($filePart==$fileMaxParts){
    $content .= sprintf(" crc32=", $fileCRC32);
  }

  return $content;
}

sub _post{

  my $self = shift;
  my @newsgroups = @{shift()};
  my $subject = shift;
  my $content = shift;
  my $from = shift;

  my $socket = $self->{socket};

  print $socket "POST\r\n";
  my $output;
  read($socket, $output, 8192);

  my @response = split(' ', $output);
  my $outputCode = $response[0];
  my $messageID;
  
  if ($outputCode==340) {
    $output = '';
    $messageID = _get_message_id();
    
    eval{
      print $socket sprintf("From: %s\r\n",$from).
       	sprintf("Newsgroups: %s\r\n",join(', ',@newsgroups)).
       	sprintf("Subject: %s\r\n", $subject).
       	sprintf("Message-ID: <%s>\r\n", $messageID).
       	"\r\n$content\r\n.\r\n";
      
      sysread($socket, $output, 8192);

    };
    if ($@){
      carp "Error: $@";
      return undef;
    }

    #441 Posting Failed. Message-ID is not unique E1
    #$self->_post(\@newsgroups, $subject, $content, $from) if $output=~ /duplicate/i || $output=~ /not unique/i;
    $messageID = undef if ($output!~ /240/ );
    say $output if ($output =~ /441/);
    
    return $messageID;
  }

  return undef;
}

sub _get_message_id{

  my $time = _encode_base36(rand(time()),8);
  my $randomness = _encode_base36(rand(time()),8);
  
  return sprintf("newsup.%s.%s@%s",$time,$randomness,
		 sprintf("%s.%s",substr(md5_hex(rand()),-5,5), substr(md5_hex(time()),-3,3)));

}


sub _encode_base36 {
  my ($val) = @_;
  my $symbols = join '', '0'..'9', 'A'..'Z';
  my $b36 = '';
  while ($val) {
    $b36 = substr($symbols, $val % 36, 1) . $b36;
    $val = int $val / 36;
  }
  return $b36 || '0';
}


sub _yenc_encode{
  my $self = shift;
  my $string = shift;
  my $column = 0;
  my $content = '';


  for(my $i=0; $i<bytes::length($string); $i++){
    my $byte=bytes::substr($string,$i,1);
    my $char= (hex (unpack('H*', $byte))+42)%256;

    if ($char == 0 ||		# null
	$char == 10 ||		# LF
	$char == 13 ||		# CR
	$char == 61 ||		# =
	(($char == 9 || $char == 32) && ($column == $YENC_NNTP_LINESIZE || $column==0)) || # TAB || SPC
	($char==46 && $column==0) # . 
       ) {
    
      $content .= '=';
    
      $column+=1;
    
      $char=($char + 64)%256;
    
    }
  
    $content .= chr $char;


    $column+=1;
  
    if ($column> $YENC_NNTP_LINESIZE ) {
      $column=0;
      $content .= "\r\n";
    }

  }
  return $content;
}



1;
