#!/usr/bin/perl

###############################################################################
#     NewsUP - create backups of your files to the usenet.
#     Copyright (C) David Santiago
#  
#     This program is free software: you can redistribute it and/or modify
#     it under the terms of the GNU General Public License as published by
#     the Free Software Foundation, either version 3 of the License, or
#     (at your option) any later version.
#
#     This program is distributed in the hope that it will be useful,
#     but WITHOUT ANY WARRANTY; without even the implied warranty of
#     MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#     GNU General Public License for more details.
#
#     You should have received a copy of the GNU General Public License
#     along with this program.  If not, see <http://www.gnu.org/licenses/>.
##############################################################################


use warnings;
use strict;
use utf8;
use 5.018;
use FindBin qw($Bin);
use lib "$Bin/lib";
use Getopt::Long;
use Config::Tiny;
use File::Find;
use File::Basename;
use Data::Dumper;
use Carp;
use threads;
use threads::shared;
use Net::NNTP::Uploader;
use Time::HiRes qw/gettimeofday/;
use POSIX qw/ceil/;
use Compress::Zlib;



#YENC variables used for yenc'ing
my $YENC_NNTP_LINESIZE=128;
my @YENC_CHAR_MAP = map{
	my $char = ($_+42)%256;
	($char == 0 || $char == 10 || $char == 13 || $char == 61) ? '='.chr($char+64) : chr($char);

	} (0..0xffff);
my %FIRST_TRANSLATION_TABLE=("\x09", "=I", "\x20", "=`", "\x2e","=n");
my %LAST_TRANSLATION_TABLE=("\x09", "=I", "\x32","=r");



#Returns a bunch of options that it will be used on the upload. Options passed through command line have precedence over
#options on the config file
sub _parse_command_line{

  my ($server, $port, $username,$userpasswd,
      @filesToUpload, $threads, @comments,
      $from, $headerCheck, $headerCheckSleep, $headerCheckServer, $headerCheckPort,
      $headerCheckUserName, $headerCheckPassword, $nzbName, $monitoringPort,
      $tempDir);
  my $uploadSize=750*1024;

  #default value
  $monitoringPort=8675;
  
  my @newsGroups = ();
  my %metadata=();

  GetOptions('server=s'=>\$server,
	     'port=i'=>\$port,
	     'username=s'=>\$username,
	     'password=s'=>\$userpasswd,
	     'file=s'=>\@filesToUpload,
	     'comment=s'=>\@comments,
	     'uploader=s'=>\$from,
	     'newsgroup|group=s'=>\@newsGroups,
	     'connections=i'=>\$threads,
	     'metadata=s'=>\%metadata,
	     'nzb=s'=>\$nzbName,
	     'headerCheck'=>\$headerCheck,
	     'headerCheckSleep=i'=>\$headerCheckSleep,
	     'headerCheckServer=s'=>\$headerCheckServer,
	     'headerCheckPort=i'=>\$headerCheckPort,
	     'headerCheckUserName=s'=>\$headerCheckUserName,
	     'headerCheckPassword=s'=>\$headerCheckPassword,
	     'monitoringPort=i'=>\$monitoringPort,
	     'uploadsize=i'=>\$uploadSize
	    );
  
  if (defined $ENV{"HOME"} && -e $ENV{"HOME"}.'/.config/newsup.conf') {

    my $config = Config::Tiny->read( $ENV{"HOME"}.'/.config/newsup.conf' );
    %metadata = %{$config->{metadata}};
    
    if (!defined $server) {
      $server = $config->{server}{server} if exists $config->{server}{server};
    }
    if (!defined $port) {
      $port = $config->{server}{port}  if exists $config->{server}{port};
    }
    if (!defined $username) {
      $username = $config->{auth}{user}  if exists $config->{auth}{user};
    }
    if (!defined $userpasswd) {
      $userpasswd = $config->{auth}{password} if exists $config->{auth}{password};
    }
    if (!defined $from) {
      $from = $config->{upload}{uploader} if exists $config->{upload}{uploader};
    }
    if (!defined $threads) {
      $threads = $config->{server}{connections} if exists $config->{server}{connections};
    }
    if ($threads < 1) {
      say "Please specify a correct number of connections!";    
    }

    if (!defined $headerCheck) {
      $headerCheck = $config->{headerCheck}{enabled} if exists $config->{headerCheck}{enabled};
    }
    if ($headerCheck){
      if (!defined $headerCheckSleep) {
	if (exists $config->{headerCheck}{sleep}){
	  $headerCheckSleep = $config->{headerCheck}{sleep};
	}else {
	  $headerCheckSleep=20;
	}
      }
      if (!defined $headerCheckServer || $headerCheckServer eq '') {
	if (exists $config->{headerCheck}{server} && $config->{headerCheck}{server} ne ''){
	  $headerCheckServer = $config->{headerCheck}{server};
	}else {
	  $headerCheckServer=$server;
	}
      }
      if (!defined $headerCheckPort || $headerCheckPort eq '') {
	if (exists $config->{headerCheck}{port} &&  $config->{headerCheck}{port} ne ''){
	  $headerCheckPort = $config->{headerCheck}{port};
	}else {
	  $headerCheckPort=$port;
	}
      }
      if (!defined $headerCheckUserName || $headerCheckUserName eq '') {
	if (exists $config->{headerCheck}{username} && $config->{headerCheck}{username} ne ''){
	  $headerCheckUserName = $config->{headerCheck}{username};
	}else {
	  $headerCheckUserName=$username;
	}
      }
      if (!defined $headerCheckPassword || $headerCheckPassword eq '') {
	if (exists $config->{headerCheck}{password} && $config->{headerCheck}{password} ne ''){
	  $headerCheckPassword = $config->{headerCheck}{password};
	}else {
	  $headerCheckPassword=$userpasswd;
	}
      }
    }

    if (!defined $monitoringPort) {
      $monitoringPort = $config->{generic}{monitoringPort} if exists $config->{generic}{monitoringPort};
    }

    $tempDir = $config->{generic}{tempDir} if exists $config->{generic}{tempDir};
    croak "Please define a valid temporary dir in the configuration file" if !defined $tempDir || !-d $tempDir;

    
    if ( @newsGroups == 0) {
      if (exists $config->{upload}{newsgroup}){
	@newsGroups = split(',', $config->{upload}{newsgroup});
	$_ =~ s/^\s+|\s+$//g for @newsGroups;
      }
    }
    undef $config;
  }
  
  if (!defined $server || !defined $port || !defined $username || !defined $from || @newsGroups==0 || !defined $threads) {
    say "Please check the parameters ('server', 'port', 'username'/'password', 'connections','uploader' and 'newsgoup')";
    exit 0;
  }

  # if (defined $uploadSize) {
  #   $Net::NNTP::Uploader::NNTP_MAX_UPLOAD_SIZE=$uploadSize;
  # }
  
  return ($server, $port, $username, $userpasswd, 
	  \@filesToUpload, $threads, \@newsGroups, 
	  \@comments, $from, \%metadata, $headerCheck, $headerCheckSleep,
	  $headerCheckServer, $headerCheckPort, $headerCheckUserName,
	  $headerCheckPassword, $nzbName,$monitoringPort, $uploadSize, $tempDir);
}

sub _get_files_to_upload{
  
  my $filesToUploadRef = shift;

  my $tempFilesRef=[];
    
  for (@$filesToUploadRef) {
    my $dir = $_;
    find(sub{
	   
	   if (-f) {
	     my $newName = $File::Find::name;
	     push @$tempFilesRef, $newName;
	     
	   }
	 }, ($dir));
  }

  return $tempFilesRef;
}

sub main{

  my ($server, $port, $username, $userpasswd, 
      $filesToUploadRef, $connections, $newsGroupsRef, 
      $commentsRef, $from, $meta, $headerCheck, $headerCheckSleep,
      $headerCheckServer, $headerCheckPort,
      $headerCheckUsername, $headerCheckPassword, $nzbName,
      $monitoringPort, $uploadSize, $tempDir)=_parse_command_line();

  my @tempFiles  :shared = @{_get_files_to_upload($filesToUploadRef)};
  my $totalFiles = scalar @tempFiles;
  my $totalSize=0;
  $totalSize +=-s $_ for (@tempFiles);
  $totalSize /=1024;
  my $uploadMetaData={firstComment=>$commentsRef->[0],
		      secondComment=>$commentsRef->[1],
		      from=>$from,
		      newsgroups=>join(',',@$newsGroupsRef),
		      uploadSize=>$uploadSize,
		     };


  my @tempYencFiles :shared = ();

  my @producerList=();
  for (0..4) {
    push @producerList , threads->create(\&start_producer, \@tempFiles, $totalFiles, $uploadMetaData, \@tempYencFiles);
  }

  my @consumerList= ();
  for (0..1) {
    push @consumerList, threads->create(\&start_consumer, $server, $port, $username, $userpasswd, \@tempYencFiles, \@producerList);
  }

  my @segments = ();
  my $time = time();
  push @segments, @{$_->join()} for @producerList;
  $_->join() for @consumerList;
  say "Speed: [".$totalSize/(time()-$time)." KBytes/Sec]";

  my %nzbData = ();
  for (@segments) {
    push @{$nzbData{$_->[2]}}, [$_->[1], $_->[0]];
  }


  
  my $xml="<nzb xmlns=\"http://www.newzbin.com/DTD/2003/nzb\">\n";
  for my $file (keys %nzbData) {
    $xml .= "<file poster=\"Newsup\" date=\"".time()."\" subject=\"&quot;$file&quot; yenc (1/".scalar($nzbData{$file}).")\" >\n";
    $xml .= "<groups>\n";
    $xml .= "<group>$_</group>\n" for @$newsGroupsRef;
    $xml .= "</groups>\n";
    $xml .= "<segments>\n";
    for my $f ($nzbData{$file}) {
      for (@$f) {
	$xml.= "<segment bytes=\"$uploadSize\" number=\"".$_->[0]."\">".$_->[1]."</segment>\n"
      }

    }
    $xml .= "</segments>\n";
    $xml .= "</file>\n";
  }
  $xml .= "</nzb>";

  open my $ofh, '>', "newsup.nzb";
  print $ofh $xml;
  close $ofh;

  
}

sub start_consumer{
  my ($server, $port, $username, $userpass, $yencData, $producerList) = @_;
  my $uploader = Net::NNTP::Uploader->new(1, $server, $port, $username, $userpass);


  while (1) {
    my $areAlive = scalar(@$producerList);

    {
      lock($yencData);
      $uploader->post_article(shift(@$yencData)) if defined $yencData->[0];
    }
    threads->yield();
    $areAlive += $_->is_running()?1:-1 for(@$producerList);
    last if($areAlive == 0);
  }
  $uploader->logout;
  
}

sub start_producer{
  my ($tempFilesRef, $totalFiles, $metaData, $yencData) = @_;

  my $fileCounter=1;
  my $file;
  my @messageIDs=();
  while (@$tempFilesRef) {
    #  } my $file (@$tempFilesRef) {

    {
      lock($tempFilesRef);
      $file = shift @$tempFilesRef;
    }
    last if !defined $file;
    
    open my $ifh, '<',$file;
    binmode $ifh;
    my $segmentCounter=1;
    my $totalSegments = ceil((-s $file)/$metaData->{uploadSize});
    my $fileName=(fileparse($file))[0];

    my $startPosition = 0;
    while ((my $readSize = read($ifh,my $data, $metaData->{uploadSize}))!=0) {

      my $subject = "[$fileCounter/$totalFiles] - \"$fileName\" ($segmentCounter/$totalSegments)";
      if (defined $metaData->{firstComment}) {
	$subject = $metaData->{firstComment}." $subject";
	if (defined $metaData->{secondComment}) {
	  $subject .= " [".$metaData->{secondComment}."]";
	}
      }
      my $endPosition=tell($ifh);

      my $messageID=_get_message_id();
      my @article :shared = (
			     "From: ",$metaData->{from},
			     "\r\nNewsgroups: ",$metaData->{newsgroups},
			     "\r\nSubject: ",$subject,
			     "\r\nMessage-ID: <",$messageID,
			     ">\r\n\r\n=ybegin part=",$segmentCounter,
			     " total=",$totalSegments," line=",$YENC_NNTP_LINESIZE,
			     " size=", $readSize, " name=",$fileName,
			     #" size=", $readSize," name=",$fileName,
			     "\r\n=ypart begin=",$startPosition, " end=",$endPosition,
			     "\r\n",_yenc_encode($data),
			     "\r\n=yend size=",$readSize," pcrc32=", sprintf("%x",crc32 $data), "\r\n.\r\n"
			    );
      {
	lock($yencData);
	push @$yencData, \@article;
	
      }#release lock
      push @messageIDs, [$messageID, $segmentCounter, $fileName];
      ++$segmentCounter;
      $startPosition=$endPosition;
      
    }
    close $ifh;

    ++$fileCounter;
    
  }

  return \@messageIDs;
  
}
sub _yenc_encode{
  my ($string) = @_;
  my $column = 0;
  my $content = '';

  for my $hexChar (unpack('W*',$string)) {

    my $char= $YENC_CHAR_MAP[$hexChar];
    
    if($char =~ /=/){
      $column++;
    }
    elsif($column==0 && $FIRST_TRANSLATION_TABLE{$char}){
      
      $column++;
      $char = $FIRST_TRANSLATION_TABLE{$char};
    }
    elsif($column == $YENC_NNTP_LINESIZE && $LAST_TRANSLATION_TABLE{$char}){
      $column++;
      $char=$LAST_TRANSLATION_TABLE{$char};
    }
      
    if (++$column>= $YENC_NNTP_LINESIZE ) {
      $column = 0;
      $char .= "\r\n";
    }
    $content .= $char;
  }

  return $content;
}



# sub _distribute_files_by_connection{
#   my ($threads, $files, $tempFolder, $from, $newsgroups, $initComment,$endComment) = @_;
#   my $blockSize = $Net::NNTP::Uploader::NNTP_MAX_UPLOAD_SIZE;

#   my $fileCounter=1;
  
#   for my $file (@$files) {
#     open my $ifh, '<', $file;
#     while (read($ifh, my $read, $blockSize)) {
#       my $messageID = _get_message_id();
#       open my $ofh, '>', "$tempFolder/$messageID";
#       binmode $ofh;
#       print $ofh "From: $from\r\n",
# 	"Newsgroups: $newsgroups\r\n",
# 	"Subject:",sprintf("");
#       close $ofh;
#     }
#   }
  
#   my @segments = ();
#   my $counter = 1;
#   my $totalFiles=scalar @$files;
#   for my $file (@$files) {
#     my $fileSize = -s $file;
#     my $maxParts = ceil($fileSize/$blockSize);
#     for (1..$maxParts) {
#       push @segments, [$file, "$_/$maxParts", _get_message_id(), "$counter/$totalFiles"];
#     }
#     $counter +=1;
#   }
#   my @threadedSegments;
#   my $i = 0;
#   foreach my $elem (@segments) {
#     push @{ $threadedSegments[$i++ % $threads] }, $elem;
#   };

#   @segments = sort{ $a->[0] cmp $b->[0]} @threadedSegments;
  
#   return \@segments;
# }


sub _get_message_id{

  (my $s, my $usec) = gettimeofday();
  my $time = _encode_base36("$s$usec");
  my $randomness = _encode_base36(rand("$s$usec"));

  return "$s$usec.$randomness\@$time.newsup";
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


# sub main{

#   my ($server, $port, $username, $userpasswd, 
#       $filesToUploadRef, $connections, $newsGroupsRef, 
#       $commentsRef, $from, $meta, $headerCheck, $headerCheckSleep,
#       $headerCheckServer, $headerCheckPort,
#       $headerCheckUsername, $headerCheckPassword, $nzbName,
#       $monitoringPort, $tempDir)=_parse_command_line();
  
#   my $tempFilesRef = _get_files_to_upload($filesToUploadRef);
#   my $totalSize=0;

#   $totalSize +=-s $_ for (@$tempFilesRef);
#   $tempFilesRef = _distribute_files_by_connection ($connections, $tempFilesRef, $tempDir);
#   say Dumper($tempFilesRef);
#   exit 0;

#   my $lastChild = _monitoring_server_start($monitoringPort, $connections,
# 					   ceil($totalSize/$Net::NNTP::Uploader::NNTP_MAX_UPLOAD_SIZE));
#   my $timer = time();
  
#   my @threadsList = ();
#   for (my $i = 0; $i<$connections; $i++) {
#     say 'Starting connection '.($i+1).' for uploading';

#     push @threadsList, _transmit_files($i,
# 				       $server, $port, $username, $userpasswd, 
# 				       $tempFilesRef->[$i], $connections, $newsGroupsRef, $commentsRef, 
# 				       $from, $headerCheck, $headerCheckSleep, $headerCheckServer, $headerCheckPort,
# 				       $headerCheckUsername, $headerCheckPassword, $monitoringPort);
#   }


#   for (@threadsList) {
#     my $child = $_;
#     waitpid($child,0);
#     say "Parent: Child $child was reaped - ", scalar localtime, ".";
#   }
#   #all the kids died. There's no point in keeping the last child - the monitoring server
#   kill 'KILL', $lastChild;

#   my $timeDiff = time()-$timer != 0? time()-$timer : 1;
  

#   printf("Transfer speed: [%0.2f KBytes/sec]\r\n", $totalSize/$timeDiff/1024);

  
#   my @nzbSegmentsList = ();
#   for my $connectionFiles (@$tempFilesRef) {
#     for my $file (@$connectionFiles) {
#       my $fileName=(fileparse($file->[0]))[0];
#       my @temp = split('/',$file->[1]);
#       my $currentFilePart = $temp[0];
#       my $totalFilePart = $temp[1];
#       my $messageID=$file->[2];
#       my $readSize=$Net::NNTP::Uploader::NNTP_MAX_UPLOAD_SIZE;
#       if ($currentFilePart == $totalFilePart) {
# 	$readSize= (-s $file->[0]) % $Net::NNTP::Uploader::NNTP_MAX_UPLOAD_SIZE;
# 	$readSize=$Net::NNTP::Uploader::NNTP_MAX_UPLOAD_SIZE if($readSize==0);
#       }
#       push @nzbSegmentsList, NZB::Segment->new($fileName, $readSize, $currentFilePart,$totalFilePart,$messageID);
      
#     }
#   }
  
#   my $nzbGen = NZB::Generator->new($nzbName, $meta, \@nzbSegmentsList, $from, $newsGroupsRef);
#   say 'NZB file '.$nzbGen->write_nzb . " created!\r\n";
  
# }


# sub _transmit_files{

#   my $pid;

#   unless (defined($pid = fork())) {
#     say "cannot fork: $!";
#     return -1;
#   }
#   elsif ($pid) {
#     return $pid; # I'm the parent
#   }

#   my ($connectionNumber, $server, $port, $username, $userpasswd, 
#       $filesRef, $connections, $newsGroupsRef, $commentsRef,
#       $from, $headerCheck,$headerCheckSleep, $headerCheckServer, $headerCheckPort,
#       $headerCheckUsername, $headerCheckPassword ,$monitoringPort) = @_;


#   my $uploader = Net::NNTP::Uploader->new($connectionNumber, $server, $port, $username, $userpasswd, $monitoringPort);
#   $uploader->transmit_files($filesRef, $from, $commentsRef->[0], $commentsRef->[1], $newsGroupsRef, 0);

#   if ($headerCheck){
#     say "Child $$ starting header check!";
#     $uploader->header_check($filesRef, $newsGroupsRef, $from, $commentsRef, $headerCheckSleep,
# 			    $headerCheckServer, $headerCheckPort, $headerCheckUsername, $headerCheckPassword);
#   }
#   $uploader->logout;
#   exit 0;
# }


# # Launches a process only to collect upload statistics and display on stdout
# sub _monitoring_server_start {
#   my ($monitoringPort, $connections, $maxParts)=@_;

#   my $pid;
#   unless (defined($pid = fork())) {
#     say "cannot fork: $!";
#     return -1;
#   }
#   elsif ($pid) {
#     return $pid; # I'm the parent
#   }

#   my $socket = IO::Socket::INET->new(
# 				     Proto    => 'udp',
# 				     LocalPort => $monitoringPort,
# 				     Blocking => '1',
# 				     LocalAddr => 'localhost'
# 				    );
#   die "Couldn't create Monitoring server: $!\r\nThe program will continue without monitoring!" unless $socket;
#   my $count=0;
#   my $t0 = [gettimeofday];
#   my $size=0;
#   while (1) {
#     $socket->recv(my $msg, 1024);
	
#     $count=$count+1;
#     $size+=$msg;
#     if ($count % $connections==0) {#To avoid peaks;
#       my $elapsed = tv_interval($t0);
#       $t0 = [gettimeofday];
#       my $speed = floor($size/1024/$elapsed);
#       my $percentage=floor($count/$maxParts*100);

#       printf( "%3d%% [%-8d KBytes/sec]\r", $percentage, $speed);# "$percentage\% [$speed KBytes/sec]\r";
#       $size=0;
#     }
#   }

#   exit 0;#Just to be sure that the process doesn't go further than this.
# }


#use Benchmark qw(:all);
#my $t0 = Benchmark->new;
main();
#my $t1 = Benchmark->new;
#my $td = timediff($t1, $t0);
#print "Uploading took:",timestr($td),"\n";

