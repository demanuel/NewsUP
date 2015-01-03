#!/usr/bin/perl

###############################################################################
#     NewsUP - create backups of your files to the usenet.
#     Copyright (C) 2012  David Santiago
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

main();


sub main{

  my ($server, $port, $username, $userpasswd, 
      $filesToUploadRef, $connections, $newsGroupsRef, 
      $commentsRef, $from, $meta)=parse_command_line();

  my @comments = @$commentsRef;
  my ($filesRef,$tempFilesRef) = compress_folders($filesToUploadRef);
  
  $filesRef = distribute_files_by_thread($connections, $filesRef); 

  my @threadsList = ();
  for (my $i = 0; $i<$connections; $i++) {
     push @threadsList, threads->create('start_upload',
				        $server, $port, $username, $userpasswd, 
     				    $filesRef->[$i], $connections, $newsGroupsRef, 
     				    $commentsRef, $from);    
    
   }

  my @nzbFilesList = ();
  for (my $i = 0; $i<$connections; $i++){
    push @nzbFilesList, $threadsList[$i]->join();
  }

  for my $tempFileName (@$tempFilesRef) {
    unlink $tempFileName;
  }

  my $nzbGen = NZB::Generator->new();
  say $nzbGen->create_nzb(\@nzbFilesList, $meta), " created!";

}

#Creates the required objects to upload and starts the upload
sub start_upload{

  my ($server, $port, $username, 
      $userpasswd, $filesToUploadRef, 
      $connections, $newsGroupsRef, $commentsRef, $from) = @_;

  my @comments = @$commentsRef;
  
  my $up = Net::NNTP::Uploader->new($server,$port,$username,$userpasswd);

  my ($initComment, $endComment);
  if ($#comments+1==2) {
    $initComment = $comments[0];
    $endComment = $comments[1];
  }elsif ($#comments+1==1) {
    $initComment = $comments[0];
  }
  my @filesList = $up->upload_files($filesToUploadRef,$from,$initComment,$endComment ,$newsGroupsRef);
  return @filesList;

}

#Checks if every element in the listRef is a directory.
#If it is a directory it compresses it in files of 10Megs
#Returns a list of the actual files to be uploaded and a list of the files created (so they can be removed later)
sub compress_folders{
  
  my $linuxCommand = '7z a -mx0 -v10m "%s.7z" "%s"';
  my $winCommand='"c:\Program Files\7-Zip\7z.exe" a -mx0 -v10m "%s.7z" "%s"';
  my $command='';
  
  $command = $^O eq 'MSWin32' ? $winCommand:$linuxCommand;
  
  my @files = @{shift()};
  my @realFilesToUpload = ();
  my @tempFiles = ();

  for my $file (@files){

    if (-d $file) {
      $file =~ s/\/\z//;
      system(sprintf($command, $file, $file));
      my @expandedCompressFiles = bsd_glob("$file.7z*");
      push @realFilesToUpload, @expandedCompressFiles;
      push @tempFiles, @expandedCompressFiles;
	
    }else {
      push @realFilesToUpload, $file;
    }
    
  }

  return (\@realFilesToUpload,\@tempFiles);

}

#Returns a bunch of options that it will be used on the upload. Options passed through command line have precedence over
#options on the config file
sub parse_command_line{

  my ($server, $port, $username, $userpasswd, @filesToUpload, $threads, @comments, $from);
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
	     'connections'=>\$threads,
	     'metadata=s'=>\%metadata,);

  if (-e $ENV{"HOME"}.'/.config/newsup.conf') {

    my $config = Config::Tiny->read( $ENV{"HOME"}.'/.config/newsup.conf' );
    %metadata = %{$config->{metadata}};
    
    if (!defined $server) {
      $server = $config->{server}{server};
    }
    if (!defined $port) {
      $port = $config->{server}{port};
    }
    if (!defined $username) {
      $username = $config->{auth}{user};
    }
    if (!defined $userpasswd) {
      $userpasswd = $config->{auth}{password};
    }
    if (!defined $from) {
      $from = $config->{upload}{uploader};
    }
    
    $threads = $config->{server}{connections};
    
    if ($threads < 1) {
      croak "Please specify a correct number of connections!";    
    }
   
  }

  if (!defined $server || !defined $port || !defined $username || !defined $from || @newsGroups==0) {
    croak "Please check the parameters ('server', 'port', 'username'/'password', 'from' and 'newsgoup')";
  }

  return ($server, $port, $username, $userpasswd, 
	  \@filesToUpload, $threads, \@newsGroups, 
	  \@comments, $from, \%metadata);
}

# takes number+arrayref, returns ref to array of arrays
sub distribute_files_by_thread {
    my ($threads, $array) = @_;

    my @parts;
    my $i = 0;
    foreach my $elem (@$array) {
        push @{ $parts[$i++ % $threads] }, $elem;
    };
    return \@parts;
};


