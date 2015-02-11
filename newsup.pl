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
use Carp;
use File::Find;
use File::Basename;
use POSIX;
use Data::Dumper;
use Digest::MD5 qw/md5_hex/;
use POSIX ":sys_wait_h";
use Time::HiRes qw/gettimeofday/;

#Returns a bunch of options that it will be used on the upload. Options passed through command line have precedence over
#options on the config file
sub _parse_command_line{

  my ($server, $port, $username,$userpasswd,
      @filesToUpload, $threads, @comments,
      $from, $headerCheck, $nzbName);

  
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
	     'headerCheck'=>\$headerCheck);

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
      croak "Please specify a correct number of connections!";    
    }

    if (!defined $headerCheck) {
      $headerCheck = $config->{generic}{headerCheck} if exists $config->{generic}{headerCheck};
    }
  }
  
  if (!defined $server || !defined $port || !defined $username || !defined $from || @newsGroups==0) {
    croak "Please check the parameters ('server', 'port', 'username'/'password', 'from' and 'newsgoup')";
  }

  return ($server, $port, $username, $userpasswd, 
	  \@filesToUpload, $threads, \@newsGroups, 
	  \@comments, $from, \%metadata, $headerCheck, $nzbName);
}

sub _distribute_files_by_connection{
  my ($threads, $files) = @_;
  my $blockSize = $Net::NNTP::Uploader::NNTP_MAX_UPLOAD_SIZE;

  my @segments = ();
  for my $file (@$files) {
    my $fileSize = -s $file;
    my $maxParts = ceil($fileSize/$blockSize);
    for (1..$maxParts) {
      push @segments, [$file, "$_/$maxParts", _get_message_id()];
    }
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
  
  my $time = _encode_base36("$s$usec",8);
  my $randomness = _encode_base36(rand("$s$usec"),8);
  
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
      $commentsRef, $from, $meta, $headerCheck, $nzbName)=_parse_command_line();

  
  my $tempFilesRef = _get_files_to_upload($filesToUploadRef);
  
  
  $tempFilesRef = _distribute_files_by_connection ($connections, $tempFilesRef); 
  
  
  my @threadsList = ();
  for (my $i = 0; $i<$connections; $i++) {
    say 'Starting connection '.($i+1).' for uploading';
    push @threadsList, _transmit_files($i,
				       $server, $port, $username, $userpasswd, 
				       $tempFilesRef->[$i], $connections, $newsGroupsRef, 
				       $commentsRef, $from, $headerCheck);

  }


  while (1) {
    my $child = waitpid(-1, 0);
    last if $child == -1;       # No more outstanding children
    
    say "Parent: Child $child was reaped - ", scalar localtime, ".";
  }

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
  

  #  my @nzbSegmentsList = ();
  #  for (my $i = 0; $i<$connections; $i++){
  #    push @nzbSegmentsList, $threadsList[$i]->join();
  #  }
  
  # my %filesToRemove = ();
  # for my $tempFileNameSegment (@$tempFilesRef) {
  #   $filesToRemove{$_->[0]}=1 for (@$tempFileNameSegment);
  # }
  # unlink keys %filesToRemove;
  
  my $nzbGen = NZB::Generator->new($nzbName, $meta, \@nzbSegmentsList, $from, $newsGroupsRef);
  say 'File '.$nzbGen->write_nzb . " created!\r\n";
  
}


sub _transmit_files{

  my $pid;
  unless (defined($pid = fork())) {
    carp "cannot fork: $!";
    return -1;
  }
  elsif ($pid) {
    return $pid; # I'm the parent
  }
  
  my ($connectionNumber, $server, $port, $username, $userpasswd, 
      $filesRef, $connections, $newsGroupsRef, 
      $commentsRef, $from, $headerCheck, $temp) = @_;

  my $uploader = Net::NNTP::Uploader->new($connectionNumber, $server, $port, $username, $userpasswd);
  $uploader->transmit_files($filesRef, $from, $commentsRef->[0], $commentsRef->[1], $newsGroupsRef);
  
  if ($headerCheck){
    $uploader->header_check($filesRef, $newsGroupsRef, $from, $commentsRef, $temp);
  }
  $uploader->logout;
  
  exit 0;
#  return @$segments;
}

use Benchmark qw(:all);
my $t0 = Benchmark->new;
main();
my $t1 = Benchmark->new;
my $td = timediff($t1, $t0);
print "the code took:",timestr($td),"\n";
