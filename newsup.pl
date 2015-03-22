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
use Net::NNTP::Uploader;
use NZB::Generator;
use Getopt::Long;
use Config::Tiny;
use File::Find;
use File::Basename;
use POSIX qw /sys_wait_h ceil floor/;
use Time::HiRes qw/gettimeofday tv_interval/;
use IO::Socket::INET;

#Returns a bunch of options that it will be used on the upload. Options passed through command line have precedence over
#options on the config file
sub _parse_command_line{

  my ($server, $port, $username,$userpasswd,
      @filesToUpload, $threads, @comments,
      $from, $headerCheck, $nzbName, $monitoringPort, $fileCounter);

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
	     'monitoringPort'=>\$monitoringPort,
	     'ccounter|cfc!'=>\$fileCounter);
  
  if (defined $ENV{"HOME"} && -e $ENV{"HOME"}.'/.config/newsup.conf') {

    my $config = Config::Tiny->read( $ENV{"HOME"}.'/.config/newsup.conf' );
    %metadata = %{$config->{metadata}};
    
    if (!defined $server) {
      $server = $config->{server}{server} if exists $config->{server}{server};
    }
    if (!defined $port) {
      $port = $config->{server}{port}  if exists $config->{server}{server};
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
      $headerCheck = $config->{generic}{headerCheck} if exists $config->{generic}{headerCheck};
    }
    if (!defined $monitoringPort) {
      $monitoringPort = $config->{generic}{monitoringPort} if exists $config->{generic}{monitoringPort};
    }
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

  return ($server, $port, $username, $userpasswd, 
	  \@filesToUpload, $threads, \@newsGroups, 
	  \@comments, $from, \%metadata, $headerCheck,
	  $nzbName,$monitoringPort, $fileCounter);
}

sub _distribute_files_by_connection{
  my ($threads, $files) = @_;
  my $blockSize = $Net::NNTP::Uploader::NNTP_MAX_UPLOAD_SIZE;

  my @segments = ();
  my $counter = 1;
  my $totalFiles=scalar @$files;
  for my $file (@$files) {
    my $fileSize = -s $file;
    my $maxParts = ceil($fileSize/$blockSize);
    for (1..$maxParts) {
      push @segments, [$file, "$_/$maxParts", _get_message_id(), "$counter/$totalFiles"];
    }
    $counter +=1;
  }
  my @threadedSegments;
  my $i = 0;
  foreach my $elem (@segments) {
    push @{ $threadedSegments[$i++ % $threads] }, $elem;
  };

  @segments = sort{ $a->[0] cmp $b->[0]} @threadedSegments;
  
  return \@segments;
}


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

sub _get_files_to_upload{
  
  my $filesToUploadRef = shift;

#  my $zip = 0;
  
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
      $commentsRef, $from, $meta, $headerCheck,
      $nzbName, $monitoringPort, $fileCounter)=_parse_command_line();
  
  my $tempFilesRef = _get_files_to_upload($filesToUploadRef);
  my $totalSize=0;

  
  $totalSize +=-s $_ for (@$tempFilesRef);
  
  $tempFilesRef = _distribute_files_by_connection ($connections, $tempFilesRef);

  my $lastChild = _monitoring_server_start($monitoringPort, $connections,
					   ceil($totalSize/$Net::NNTP::Uploader::NNTP_MAX_UPLOAD_SIZE));
  my $timer = time();
  
  my @threadsList = ();
  for (my $i = 0; $i<$connections; $i++) {
    say 'Starting connection '.($i+1).' for uploading';

    push @threadsList, _transmit_files($i,
				       $server, $port, $username, $userpasswd, 
				       $tempFilesRef->[$i], $connections, $newsGroupsRef, 
				       $commentsRef, $from, $headerCheck, $monitoringPort, $fileCounter);
  }


  for (@threadsList) {
    my $child = $_;
    waitpid($child,0);
    say "Parent: Child $child was reaped - ", scalar localtime, ".";
  }
  #all the kids died. There's no point in keeping the last child - the monitoring server
  kill 'KILL', $lastChild;

  printf("Transfer speed: [%0.2f KBytes/sec]\r\n", $totalSize/(time()-$timer)/1024);

  
  my @nzbSegmentsList = ();
  for my $connectionFiles (@$tempFilesRef) {
    for my $file (@$connectionFiles) {
      my $fileName=(fileparse($file->[0]))[0];
      my @temp = split('/',$file->[1]);
      my $currentFilePart = $temp[0];
      my $totalFilePart = $temp[1];
      my $messageID=$file->[2];
      my $readSize=$Net::NNTP::Uploader::NNTP_MAX_UPLOAD_SIZE;
      if ($currentFilePart == $totalFilePart) {
	$readSize= (-s $file->[0]) % $Net::NNTP::Uploader::NNTP_MAX_UPLOAD_SIZE;
	$readSize=$Net::NNTP::Uploader::NNTP_MAX_UPLOAD_SIZE if($readSize==0);
      }
      push @nzbSegmentsList, NZB::Segment->new($fileName, $readSize, $currentFilePart,$totalFilePart,$messageID);
      
    }
  }
  
  my $nzbGen = NZB::Generator->new($nzbName, $meta, \@nzbSegmentsList, $from, $newsGroupsRef);
  say 'NZB file '.$nzbGen->write_nzb . " created!\r\n";
  
}


sub _transmit_files{

  my $pid;

  unless (defined($pid = fork())) {
    say "cannot fork: $!";
    return -1;
  }
  elsif ($pid) {
    return $pid; # I'm the parent
  }

  my ($connectionNumber, $server, $port, $username, $userpasswd, 
      $filesRef, $connections, $newsGroupsRef, 
      $commentsRef, $from, $headerCheck, $monitoringPort, $fileCounter) = @_;

  
  my $uploader = Net::NNTP::Uploader->new($connectionNumber, $server, $port, $username, $userpasswd, $monitoringPort);
  $uploader->transmit_files($filesRef, $from, $commentsRef->[0], $commentsRef->[1], $newsGroupsRef, 0, $fileCounter);

  if ($headerCheck){
    $uploader->header_check($filesRef, $newsGroupsRef, $from, $commentsRef, $fileCounter);
  }
  $uploader->logout;
  exit 0;
}


# Launches a process only to collect upload statistics and display on stdout
sub _monitoring_server_start {
  my ($monitoringPort, $connections, $maxParts)=@_;

  my $pid;
  unless (defined($pid = fork())) {
    say "cannot fork: $!";
    return -1;
  }
  elsif ($pid) {
    return $pid; # I'm the parent
  }

  my $socket = IO::Socket::INET->new(
				     Proto    => 'udp',
				     LocalPort => $monitoringPort,
				     Blocking => '1',
				     LocalAddr => 'localhost'
				    );
  die "Couldn't create Monitoring server: $!\r\nThe program will continue without monitoring!" unless $socket;
  my $count=0;
  my $t0 = [gettimeofday];
  my $size=0;
  while (1) {
    $socket->recv(my $msg, 1024);
	
    $count=$count+1;
    $size+=$msg;
    if ($count % $connections==0) {#To avoid peaks;
      my $elapsed = tv_interval($t0);
      $t0 = [gettimeofday];
      my $speed = floor($size/1024/$elapsed);
      my $percentage=floor($count/$maxParts*100);

      printf( "%3d%% [%-8d KBytes/sec]\r", $percentage, $speed);# "$percentage\% [$speed KBytes/sec]\r";
      $size=0;
    }
  }

  exit 0;#Just to be sure that the process doesn't go further than this.
}


#use Benchmark qw(:all);
#my $t0 = Benchmark->new;
main();
#my $t1 = Benchmark->new;
#my $td = timediff($t1, $t0);
#print "Uploading took:",timestr($td),"\n";

