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
use Carp;
use String::CRC32;
use Data::Dumper;
use Digest::MD5 qw(md5_hex);
use 5.018;
#use Benchmark qw(:all);

#500Kb - the segment size. I tried with 4 Megs and got a 441. The allowed posting segment size isn't standard
our $NNTP_MAX_UPLOAD_SIZE=500*1024; 
my $YENC_NNTP_LINESIZE=128;
$|=1;

sub new{

  my $class = shift;
  my $connectionNumber=shift;
  my $server = shift;
  my $port = shift;

  my $username = shift;
  my $userpass = shift;
  
  my $self = {authenticated=>0,
	      server=>$server,
	      port=>$port,
	      connection=>$connectionNumber,
	      username=>$username,
	      userpass=>$userpass};
  
  # $self->{server}=$server;
  # $self->{port}=$port;


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
    $self->{authenticated}=0;
    shutdown $socket, 2;
    return -1;
  }

  print $socket sprintf("authinfo pass %s\r\n",$self->{userpass});
  sysread($socket, $output, 8192);


  
  @status = split(' ', $output);
  if ($status[0] != 281 && $status[0] != 250) {
    carp $output;
    $self->{authenticated}=0;
    shutdown $socket, 2;
    return -1;
  }
  $self->{authenticated}=1;
  return 1;
  
}

#perform the server logout
sub logout{
  my $self = shift;
  my $socket = $self->{socket};
  print $socket "quit\r\n";
  shutdown $socket, 2;  
}

sub transmit_files{
  my $self = shift;
  my $filesListRef = shift;
  my $from = shift;
  my $initComment=shift;
  my $endComment=shift;
  my $newsgroupsRef = shift;

  if ($self->{authenticated}==0) {
    while ($self->{authenticated} == 0){
      $self->_create_socket;
      $self->_authenticate;
      last if($self->{authenticated} == 1);
      sleep 30;
    }
  }
  
  for my $filePair (@$filesListRef) {
    open my $ifh, '<:bytes', $filePair->[0] or die "Couldn't open file: $!";
    binmode $ifh;
    my $fileCRC32=crc32( *$ifh);

    my $fileSize= -s $filePair->[0];
    my $fileName=(fileparse($filePair->[0]))[0];
    my @temp = split('/',$filePair->[1]);
    my $currentFilePart = $temp[0];
    my $totalFilePart = $temp[1];
#    say $self->{connection}." ".$filePair->[0]." [".$filePair->[1]."]";
    my $readedData = $self->_get_file_bytes_by_part($ifh, $currentFilePart-1);# $filePair->[0]);
    my $subject = sprintf("\"%s\" yenc (%d/%d) [%s]", $fileName,$currentFilePart,$totalFilePart,$fileSize,$fileCRC32);
#    say "Uploading: $subject";
    my $readSize=bytes::length($readedData);

    $subject = "[$initComment] $subject" if defined $initComment;
    $subject = "$subject [$endComment]" if defined $endComment;
    my $content = $self->_get_post_body($currentFilePart, $totalFilePart, $fileName,
					1+$NNTP_MAX_UPLOAD_SIZE*($currentFilePart-1), $readSize, $readedData);

    my $segmentTimer = time();
    my $counter=0;

    $self->_post($newsgroupsRef, $filePair->[2], $subject, $content, $from);
#    say "Upload of segment from file ".$filePair->[0]." failed! Retrying segment".$filePair->[1]."!" if (!defined $messageID);
      

    printf("[%0.2f KBytes/sec]\r", $readSize/(time()-$segmentTimer)/1024);
    close $ifh;

  }

}



#It will perform the header check!
sub header_check{
  my $self = shift;
  my $filesRef = shift;
  my $newsgroups = shift;
  my $from = shift;
  my $comments=shift;

#  $self->_create_socket;
#  $self->_authenticate;
  
  my $socket = $self->{socket};
  my $newsgroup = $newsgroups->[0]; #The first newsgroup is enough
  print $socket "group $newsgroup\r\n";
  my $output;
  sysread($socket, $output, 8192);
    
  for my $fileRef (@$filesRef) {
    do {
      my $messageID = $fileRef->[2];
      print $socket "stat <$messageID>\r\n";
      sysread($socket, $output, 8192);
      chop $output;
      my @status = split(' ', $output);
      if ($status[0] == 223) {
	next;
      }else {
	say "Header check: Missing segment $messageID [$output]";
	$self->transmit_files([$fileRef], $from, $comments->[0], $comments->[1], $newsgroups);
      }
      
    }while(1);
  }
}


sub _get_file_bytes_by_part{
  my $self = shift;
  my $fileNameHandle = shift;
  my $part = shift;

  my $correctPosition = $NNTP_MAX_UPLOAD_SIZE*$part;

  seek ($fileNameHandle, $correctPosition, 0);

  my $bytes;
  read($fileNameHandle, $bytes, $NNTP_MAX_UPLOAD_SIZE);
  
  return $bytes;
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

#  my $t0 = Benchmark->new;
  $content .= $self->_yenc_encode($bytes);
#  my $t1 = Benchmark->new;
#  my $td = timediff($t1, $t0);
#  print "Yenc coding took:",timestr($td),"\n";


  $content .= sprintf("\r\n=yend size=%d pcrc32=%x",$readSize, crc32($bytes));

  if ($filePart==$fileMaxParts){
    $content .= sprintf(" crc32=", $fileCRC32);
  }

  return $content;
}

sub _post{

  my $self = shift;
  my @newsgroups = @{shift()};
  my $messageID = shift;
  my $subject = shift;
  my $content = shift;
  my $from = shift;

  my $socket = $self->{socket};

  print $socket "POST\r\n";
  sysread($socket, my $output, 8192);
  
  my @response = split(' ', $output);
  my $outputCode = $response[0];
  
  if ($outputCode==340) {
    $output = '';
    
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
    carp $output if ($output!~ /240/);
#    carp $output if ();
    
  }

}

sub _yenc_encode{
  my $self = shift;
  my $string = shift;
  my $column = 0;
  my $content = '';



  #first version: slow but better to understand the algorithm
  # for(my $i=0; $i<bytes::length($string); $i++){
  #   my $byte=bytes::substr($string,$i,1);
  #   my $char= (hex (unpack('H*', $byte))+42)%256;
  #   ....
  # }
  
  my @hexString = unpack('W*',$string); #Converts binary string to hex
  foreach my $hexChar (@hexString) {
    my $char= ($hexChar+42)%256;
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


sub mycrc32 {
 my ($input, $init_value, $polynomial) = @_;

 $init_value = 0 unless (defined $init_value);
 $polynomial = 0xedb88320 unless (defined $polynomial);

 my @lookup_table;

 for (my $i=0; $i<256; $i++) {
   my $x = $i;
   for (my $j=0; $j<8; $j++) {
     if ($x & 1) {
       $x = ($x >> 1) ^ $polynomial;
     } else {
       $x = $x >> 1;
     }
   }
   push @lookup_table, $x;
 }

 my $crc = $init_value ^ 0xffffffff;

 foreach my $x (unpack ('C*', $input)) {
   $crc = (($crc >> 8) & 0xffffff) ^ $lookup_table[ ($crc ^ $x) & 0xff ];
 }

 $crc = $crc ^ 0xffffffff;

 return $crc;
}



1;
