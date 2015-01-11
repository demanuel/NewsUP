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
use File::Glob ':bsd_glob';
use threads;
use File::Find;
use File::Basename;
use POSIX;
use Data::Dumper;

main();

#TODO:
#HEADERCHECK
#FILELIST -> discarded


sub main{

  my ($server, $port, $username, $userpasswd, 
      $filesToUploadRef, $connections, $newsGroupsRef, 
      $commentsRef, $from, $meta, $name, $par2,
      $par2red, $cpass,$temp, $randomize, $headerCheck)=parse_command_line();

  my @comments = @$commentsRef;
  my ($filesRef,$tempFilesRef) = compress_and_split($filesToUploadRef, $temp, $name, $cpass);

  if ($par2) {
    ($filesRef,$tempFilesRef) = create_parity_files($filesRef, $tempFilesRef, $par2red);
  }
  if ($randomize){
    randomize_file_names($tempFilesRef) ;
  }
  
  $filesRef = _distribute_files_by_connection ($connections, $filesRef); 


  my @threadsList = ();
  for (my $i = 0; $i<$connections; $i++) {
    say 'Connection '.($i+1).' uploading';
    push @threadsList, threads->create('transmit_files',
				       $server, $port, $username, $userpasswd, 
				       $filesRef->[$i], $connections, $newsGroupsRef, 
				       $commentsRef, $from, $headerCheck, $temp);
    
   }

  my @nzbSegmentsList = ();
  for (my $i = 0; $i<$connections; $i++){
    push @nzbSegmentsList, $threadsList[$i]->join();
  }

  #TODO: header check
 # check_headers(\@nzbSegmentList, $newsGroupsRef, $server, $port, $username, $userpasswd) if $headerCheck;

  
  for my $tempFileName (@$tempFilesRef) {
    unlink $tempFileName;
  }
  my $nzbGen = NZB::Generator->new($meta, \@nzbSegmentsList, $from, $newsGroupsRef);
  say 'File '.$nzbGen->write_nzb . " created!\r\n";
  
}

sub transmit_files{
  my ($server, $port, $username, $userpasswd, 
      $filesRef, $connections, $newsGroupsRef, 
      $commentsRef, $from, $headerCheck, $temp) = @_;
  my $uploader = Net::NNTP::Uploader->new($server, $port, $username, $userpasswd);
  my $segments = $uploader->transmit_files($filesRef, $from, $commentsRef->[0], $commentsRef->[1], $newsGroupsRef);
  if ($headerCheck){
    $segments = $uploader->header_check($segments, $newsGroupsRef, $from, $commentsRef, $temp);
  }

  return @$segments;
}

#It will toggle randomly the name of some compressed/splitted files
#Example: the file a.7z.001 will be renamed a.7z.003 while the a.7z.003 will be renamed to a.7z.001.
sub randomize_file_names{
  my $tempFilesRef = shift;
  
  my @onlyCompressedFiles = grep /7z\.\d{3}$/, @{$tempFilesRef};
  for (1..int(rand(@onlyCompressedFiles))) {
    my $fileOne = $onlyCompressedFiles[rand(@onlyCompressedFiles)];
    my $fileTwo = $onlyCompressedFiles[rand(@onlyCompressedFiles)];
    if ($fileOne ne $fileTwo) {
      my $tmpFileName=$fileOne.".tmp";
      rename $fileOne, $tmpFileName;
      rename $fileTwo, $fileOne;
      rename $tmpFileName, $fileTwo;
    }
  }
  
}



sub create_parity_files{
  say "Creating parity archives!";
  my @realFilesToUpload=@{shift @_};
  my @tempFiles=@{shift @_};
  my $red = shift;

  my $command = "par2 c -q -r$red ".join(' ',@realFilesToUpload);
  system($command);
  my %folders=();

  #To avoid adding the same files
  for (@realFilesToUpload) {
    my ($f,$d,$s) = fileparse($_);
    $folders{$d}=1;
  }

  for (keys %folders) {
    my @expandedParFiles = bsd_glob("$_*.7z*par2");
    push @realFilesToUpload, @expandedParFiles;
    push @tempFiles, @expandedParFiles;
  }

  return (\@realFilesToUpload,\@tempFiles);
}

#Compress the input
sub compress_and_split{
  say "Compressing and splitting files!";
  
  my @files = @{shift(@_)};
  my $temp = shift @_;
  my $name = shift @_;
  my $cpass = shift @_;
  
  my @realFilesToUpload = ();
  my @tempFiles = ();
  my $totalSize = 0;

  my $linuxCommand = '7z a -mx0 -v%dm "'.$temp.'/'.$name.'.7z" > /dev/null';
  my $winCommand='"c:\Program Files\7-Zip\7z.exe" a -mx0 -v%dm "'.$temp.'/'.$name.'.7z"';
  my $command='';
  
  $command = $^O eq 'MSWin32' ? $winCommand:$linuxCommand;

  if (defined $cpass) {
    $command.=" -p$cpass"
  }
  
  my $isDir=0;
  for my $file(@files){
    if (-d $file) {
      $isDir=1;
      my $dirSize=0;
      find(sub{ -f and ( $dirSize += -s ) }, $file );
      $totalSize+=$dirSize;
      
    }else {
      $totalSize+=-s $file ;
    }
  }

  if ($totalSize > 10*1024*1024 || $isDir==1) {#10Megs
    $command.=' "'.$_.'"' for (@files);
  }else {
    return (\@files,[]);
  }

  #7zip has a limitation of only supporting a file splitted into a max of 1000 parts
  my @availableSizesForSplitting = (10,50,120,350); #Max 350 Gigs.
  my $splittingSize = 1;
  for my $megs (@availableSizesForSplitting) {
    $splittingSize=$megs;
    last if (ceil($totalSize/($splittingSize*1024*1024)) <= 999 );#Kilobytes -> Megabytes
    $splittingSize = 1
  }

  croak "Please split this upload into several small ones. Max upload 350 Gigs!" if ($splittingSize==1);
  
  system(sprintf($command, $splittingSize));
  my @expandedCompressFiles = bsd_glob("$temp/$name.7z*");
  push @realFilesToUpload, @expandedCompressFiles;
  push @tempFiles, @expandedCompressFiles;

  return (\@realFilesToUpload,\@tempFiles);
  
}

#Returns a bunch of options that it will be used on the upload. Options passed through command line have precedence over
#options on the config file
sub parse_command_line{

  my ($server, $port, $username,$userpasswd,
      @filesToUpload, $threads, @comments,
      $from, $name, $par2,$par2red, $cpass,
      $temp,$randomize, $headerCheck);

  
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
	     'name=s'=>\$name,
	     'metadata=s'=>\%metadata,
	     'par2'=>\$par2,
	     'par2red=i'=>\$par2red,
	     'cpass=s'=>\$cpass,
	     'tmp=s'=>\$temp,
	     'randomize'=>\$randomize,
	     'headerCheck'=>\$headerCheck);

  if (-e $ENV{"HOME"}.'/.config/newsup.conf') {

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
    if (!defined $name) {
      $name = 'newsup';
    }
    if (!defined $par2) {
      $par2 = $config->{parity}{enabled} if exists $config->{parity}{enabled};
    }
    if (!defined $par2red) {
      $par2red = $config->{parity}{redundancy} if exists $config->{parity}{redundancy};
    }
    if (!defined $threads) {
      $threads = $config->{server}{connections} if exists $config->{server}{connections};
    }
    if ($threads < 1) {
      croak "Please specify a correct number of connections!";    
    }
    if (!defined $temp) {
      $temp = $config->{generic}{tmp} if exists $config->{generic}{tmp};
    }
    if (!defined $randomize) {
      $randomize = $config->{generic}{randomize} if exists $config->{generic}{randomize};
    }

    if (!defined $headerCheck) {
      $headerCheck = $config->{generic}{headerCheck} if exists $config->{generic}{headerCheck};
    }


    chop $temp if (substr ($temp, -1) eq '/');
  }

  if (!defined $temp || !(-e $temp && -d $temp)) {
    $temp = '.';
  }
  
  if (!defined $server || !defined $port || !defined $username || !defined $from || @newsGroups==0) {
    croak "Please check the parameters ('server', 'port', 'username'/'password', 'from' and 'newsgoup')";
  }

  return ($server, $port, $username, $userpasswd, 
	  \@filesToUpload, $threads, \@newsGroups, 
	  \@comments, $from, \%metadata, $name,
	  $par2, $par2red, $cpass, $temp, $randomize, $headerCheck);
}


sub _distribute_files_by_connection{
  my ($threads, $files) = @_;
  my $blockSize = $Net::NNTP::Uploader::NNTP_MAX_UPLOAD_SIZE;

  my @segments = ();
  for my $file (@$files) {
    my $fileSize = -s $file;
    my $maxParts = ceil($fileSize/$blockSize);
    for (1..$maxParts) {
      push @segments, [$file, "$_/$maxParts"];
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

