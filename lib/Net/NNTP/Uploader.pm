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

#750Kb - the segment size. I tried with 4 Megs and got a 441. The allowed posting segment size isn't standard
our $NNTP_MAX_UPLOAD_SIZE=512*1024; 
my $YENC_NNTP_LINESIZE=128;
$|=1;

my @YENC_CHAR_MAP = map{($_+42)%256;} (0..0xffff);


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

  my ($self) = @_;
  my $socket = $self->{socket};
  my $username = $self->{username};
  print $socket "authinfo user $username\r\n";
  sysread($socket, my $output, 8192);
  
  my $status = substr($output,0,3);
  if ($status != 381) {
    $self->{authenticated}=0;
    shutdown $socket, 2;
    return -1;
  }
  my $password=$self->{userpass};
  print $socket "authinfo pass $password\r\n";
  sysread($socket, $output, 8192);

  $status = substr($output,0,3);
  if ($status != 281 && $status != 250) {
    say $output;
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
  my ($self, $filesListRef, $from, $initComment, $endComment, $newsgroupsRef, $isHeaderCheck, $fileCounter) = @_;

  if ($self->{authenticated}==0) {
    while ($self->{authenticated} == 0){
      $self->_create_socket;
      $self->_authenticate;
      last if($self->{authenticated} == 1);
      sleep 30;
    }
  }
  my %commentMap = ();
  for my $filePair (@$filesListRef){
    if (!exists $commentMap{$filePair->[0]}) {
      if (defined $initComment && $fileCounter==1) {
	$commentMap{$filePair->[0]}=$initComment." [".$filePair->[-1]."]";
      }elsif ($fileCounter){
	$commentMap{$filePair->[0]}=$filePair->[-1];
      }elsif (defined $initComment){
	$commentMap{$filePair->[0]}=$initComment;
      }
    }
  }

  for my $filePair (@$filesListRef) {
 #   my $initTime = time();
    open my $ifh, '<:bytes', $filePair->[0] or die "Couldn't open file: $!";
    binmode $ifh;

    my @temp = split('/',$filePair->[1]);
    my $currentFilePart = $temp[0];
    my $totalFilePart = $temp[1];

    #my $fileSize= -s $filePair->[0];
    my $fileName=(fileparse($filePair->[0]))[0];
    my ($readedData, $readSize) = _get_file_bytes_by_part($ifh, $currentFilePart-1);# $filePair->[0]);
    close $ifh;
    my $subject = "\"$fileName\" yenc ($currentFilePart/$totalFilePart)";

    $subject = "[".$commentMap{$filePair->[0]} ."] $subject" if exists $commentMap{$filePair->[0]};

    $subject = "$subject [$endComment]" if defined $endComment;


    my $content = _get_post_body($currentFilePart, $totalFilePart, $fileName,
				 1+$NNTP_MAX_UPLOAD_SIZE*($currentFilePart-1), $readSize, $readedData);

    #Free readed data
    undef $readedData;
    
    $self->_post($newsgroupsRef, $filePair->[2], $subject, $content, $from, $isHeaderCheck);
    #Free readed data
    undef $content;
    #    my $speed = floor($readSize/1024/(time()-$initTime));
    #    print "[$speed KBytes/sec]\r";
    $|=1;
    $self->{parentChannel}->send("$readSize");

  }
}

#It will perform the header check!
sub header_check{
  my ($self, $filesRef, $newsgroups, $from, $comments, $fileCounter)=@_;

  my $socket = $self->{socket};
  my $newsgroup = $newsgroups->[0]; #The first newsgroup is enough to check if the segment was uploaded correctly
  print $socket "group $newsgroup\r\n";
  my $output;
  sysread($socket, $output, 8192);
    
  for my $fileRef (@$filesRef) {
    my $count = 0;
    do {
      my $messageID = $fileRef->[2];
      print $socket "stat <$messageID>\r\n";
      sysread($socket, $output, 8192);
      chop $output;
      
      if (substr($output,0,3) == 223) {
	next;
      }elsif ($count==5) {
	say "Aborting! Header $messageID not found on the server! Please check for issues on the server.";
	next;
      }else {
	#print "\rHeader check: Missing segment $messageID [$output]\r\n";
	$self->transmit_files([$fileRef], $from, $comments->[0], $comments->[1], $newsgroups, 1, $fileCounter);
	$count=$count+1;
	sleep 20;
      }
    }while(1);
  }
}


sub _get_file_bytes_by_part{
  my ($fileNameHandle, $part) = @_;

  my $correctPosition = $NNTP_MAX_UPLOAD_SIZE*$part;

  seek ($fileNameHandle, $correctPosition, 0);

  my $bytes;
  my $readSize = read($fileNameHandle, $bytes, $NNTP_MAX_UPLOAD_SIZE);
  return ($bytes, $readSize);
}


sub _get_post_body{

  my ($filePart, $fileMaxParts, $fileName, $startingBytes, $readSize, $bytes)=@_;
  my $yencBody=_yenc_encode($bytes);
  #some clients will complain if this is missing
  my $pcrc32 = sprintf("%x", crc32($bytes));
  
  my $endPosition= $startingBytes+$readSize;
  my $content = <<"EOF";
=ybegin part=$filePart total=$fileMaxParts line=$YENC_NNTP_LINESIZE size=$readSize name=$fileName\r
=ypart begin=$startingBytes end=$endPosition\r
$yencBody\r
=yend size=$readSize pcrc32=$pcrc32
EOF

  #We only need this on the last part
  if ($filePart == $fileMaxParts) {
    $content = $content." crc32=".crc32($bytes);
  }
  undef $bytes;
  
  return $content;
}

sub _post{

  my ($self, $newsgroupsRef, $messageID, $subject, $content, $from, $isHeaderCheck) =@_;
  
  my @newsgroups = @{$newsgroupsRef};

  my $socket = $self->{socket};

  print $socket "POST\r\n";
  sysread($socket, my $output, 8192);

  if (substr($output,0,3)==340) {
    $output = '';
    
    eval{

      my $newsgroups = join(', ',@newsgroups);
      print $socket <<"END";
From: $from\r
Newsgroups: $newsgroups\r
Subject: $subject\r
Message-ID: <$messageID>\r
\r
$content\r
.\r
END
      undef $content;
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

}

sub _yenc_encode{
  my ($string) = @_;
  my $column = 0;
  my $content = '';


  my @hexString = unpack('W*',$string); #Converts binary string to hex
 
  for my $hexChar (@hexString) {
    my $char= $YENC_CHAR_MAP[$hexChar];

    if ($char == 0 ||		# null
  	$char == 10 ||		# LF
  	$char == 13 ||		# CR
  	$char == 61 ||		# =
  	(($char == 9 || $char == 32) && ($column == $YENC_NNTP_LINESIZE || $column==0)) || # TAB || SPC
  	($char==46 && $column==0) # . 
       ) {
      
      $content =$content. '=';
      $column+=1;
      
      $char=($char + 64);#%256;
    }
    $content = $content.chr $char;
    
    $column+=1;
    
    if ($column> $YENC_NNTP_LINESIZE ) {
      $column=0;
      $content = $content."\r\n";
    }

  }

  return $content;
  


  
  #first version: slow but better to understand the algorithm
  # for(my $i=0; $i<bytes::length($string); $i++){
  #   my $byte=bytes::substr($string,$i,1);
  #   my $char= (hex (unpack('H*', $byte))+42)%256;
  #   ....
  # }

}



1;
