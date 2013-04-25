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


#!/usr/bin/perl
use warnings;
use strict;
use utf8;
use diagnostics;
use Getopt::Long;
use Data::Dumper;
use POSIX;
use File::Find;
use threads;
use Net::NNTP;
use Term::ReadKey;
use File::Basename;
use String::CRC32;
use 5.016;


#Options and their default values
#If the it's required to compress, which format do you want to upload.
my $FILE_FORMAT='7z';
#Bool indicating if you want to password the file or not. The format must support password.
my $FILE_PASSWORD;
#the redundancy of the par files
my $FILE_REDUNDANCY=20;
#Which group do you want upload to
my @NNTP_NEWSGROUPS;
#server where you have an account (TLS/SSL only)
my $NNTP_SERVER;
#port where you should connect to your host  (TLS/SSL only)
my $NNTP_PORT=119;
#The number of simultaneous uploads you want.
my $NNTP_THREADS=2;
#the files to upload
my @FILES;
#comments
my @COMMENT;
#sender's email
my $EMAIL='Anonymous Coward <anonymous.coward@mailinator.com>';


#SCENE OPTIONS
my @UPLOAD_AVAILABLE_SIZES = (30, 50, 100); #A splitted file must have parts of 30M, 50M or 100M
my $UPLOAD_MAX_PARTS = 101;

#NNTP OPTIONS
my $NNTP_LINESIZE=128;
my $NNTP_MAX_POST_BYTES=500*1024; #500 KBytes




GetOptions('format|fo=s'=>\$FILE_FORMAT,
	  'password|passwd=s'=>\$FILE_PASSWORD,
	  'newsgroup|n=s'=>\@NNTP_NEWSGROUPS,
	  'server|s=s'=>\$NNTP_SERVER,
	  'port|p=i'=>\$NNTP_PORT,
	  'threads|t=i'=>\$NNTP_THREADS,
	  'files|f=s'=>\@FILES,
	  'redundancy|r=i'=>\$FILE_REDUNDANCY,
	   'email|e=s'=>\$EMAIL,
	  'comment|c=s'=>\@COMMENT);

if(!@NNTP_NEWSGROUPS || !defined $NNTP_SERVER || !@FILES){
  
  print_help();
  exit 1;

}

if(!@COMMENT){
  $COMMENT[0]='Enjoy!';
  $COMMENT[1]='Powered by NewsUP';
}

print "Username= ";
chomp(my $USERNAME=ReadLine(0));
print "Password= ";
ReadMode('noecho');
chomp(my $USER_PASSWORD=ReadLine(0));
ReadMode('normal');
say '';


my @files_to_upload = ();
my @files_to_remove = ();
for my $file (@FILES){

  if(-d $file && substr ($file, -1, 1) eq '/'){
    chop($file);
  }

  #join the files and split it (if it matches some conditions) and perform other operations such as adding a password...
  push @files_to_upload, pre_process_files ($file, $FILE_FORMAT, $FILE_REDUNDANCY);
  #creates the parity files
  push @files_to_upload, create_parity_files($file, @files_to_upload);
  #store a list of the temp files
  @files_to_remove=@files_to_upload;

  @files_to_upload = split_file_list_by_thread(\@files_to_upload, $NNTP_THREADS);

  my @threads_list = ();

  #start $NNTP_THREADS threads for uploading the content and the parity files
  for my $i (0..$NNTP_THREADS-1){
#    push @threads_list, threads->create(\&process_files, [splice @files_to_upload, 0,$i*ceil(scalar @files_to_upload / $NNTP_THREADS)]);
    push @threads_list, threads->create(\&process_files, $files_to_upload[$i]);
  }
  

  #wait for the thread completion
  my @xml_file_list = ();
  for my $thread (@threads_list){
    push @xml_file_list, $thread->join();
  }
  

  #creates a NZB file.
  create_nzb(\@xml_file_list, $file);

  #remove the temporary files (the compressed and/or splitted file and their parity archives)
  remove_temporary_files($file, @files_to_remove);

}


# This method splits a list into smaller lists containing the most identical size.
#Example: Imagine that you want to upload some files with the following sizes (in MiB):
# 1,20,5,3,18,32,2,21
# For 2 threads uploading the files, lets say: (1,20,5,3,18,32,2,21)/2 threads == ((1,20,5,3),(18,32,2,21)),
# so thread 1 will upload the files with (1,20,5,3) sizes and thread 2 the files with sizes 
# (18,32,2,21). When the Thread 1 finishes uploading all the files (29 MiB total), the Thread 2 
# is still uploading the second file (32 MiB). The thread 2 will still have to upload 23 MiB, while 
# the thread 1 is already # finished. This will prevent to reach the full upload speed. Ideally each 
# thread should upload 51 MiB in parallel. A more correct file distribution would be a file distribution 
# where the upload would be around the 51 MiB for each thread. Something like:
#  T1->(1,2,3,5,18,20) T2->(21,32)
# This method tries to solve this problem.
sub split_file_list_by_thread{
  my @file_list = @{shift @_};
  my $threads = shift;
  
  #calculates the total upload size
  my $total_size_to_upload = 0;
  $total_size_to_upload+=-s $_ for (@file_list);
  
  # calculates the optimal upload size for each thread
  my $ideal_size = $total_size_to_upload/$threads;

  #sorts the files according to their size (smaller to bigger)
  my @sorted_file_list = sort {-s $a <=> -s $b} @file_list;

  my @aoa = ();

  my $thread_size=0;
  my $index=0;

  #loop through all files
  for my $i (0..$#sorted_file_list){
    
    my $file =$sorted_file_list[$i];

    # if the sum of the current file size with the previous ones is BIGGER than the "optimal" value
    # checks if the difference to the optimal with the file added is bigger than the difference to optimal
    # size without the file added.
    # If the difference is smaller without the file, it will add the file in the next slot (except if its
    # already the last slot) and resets the size counter.
    # If the difference is bigger without the file, it will add the file in the current slot and updates where
    # the next files will be inserted (except if its the last slot)
    # if the sum of the current file size with the previous ones is SMALLER than the "optimal" value, it adds
    # to the current thread (except if there is more threads than files which in this case it will update the 
    # slot number - except if you're already in the last slot)
    if($thread_size + -s $file > $ideal_size){
      
      my $diff1 = ($thread_size + -s $file)-$ideal_size;
      my $diff2 = $ideal_size-$thread_size;
      
      if($diff1>=$diff2 && $index < $threads-1){
	$index+=1;
	$thread_size =0 ;
      }
      push @{ $aoa[$index]}, $file;

      if($diff2>$diff1 && $index < $threads-1){
	$index+=1;
	$thread_size =0 ;
      }

      $thread_size +=-s $file ;
      
    }else{

      push @{ $aoa[$index]}, $file;
      $thread_size +=-s $file ;

      if($#sorted_file_list-$i <= $threads-1 && $index < $threads-1){
      	$index+=1;
	$thread_size =0 ;
      }
    }
  }

  return @aoa;
}

#Delete the files created in the pre_process step
sub remove_temporary_files{
  my $file=shift;
  my @files_to_remove_candidates = @_;
  
  for my $candidate (@files_to_remove_candidates){
    if($file ne $candidate){
      unlink $candidate or warn "Unable to delete $file: $!";
    }
  }
}


#Writes to filesystem the nzb file
sub create_nzb{
  my @xml_file_list = @{shift @_};
  my $file = shift . ".nzb";

  open my $FH, '>', $file or die "Couldn't open file: $!";

  print $FH "<nzb xmlns=\"http://www.newzbin.com/DTD/2003/nzb\">\r\n";
  print $FH "<head>\r\n<meta type=\"password\">$FILE_PASSWORD</meta>\r\n</head>\r\n" if defined $FILE_PASSWORD;

  for my $xml_node (@xml_file_list){
    print $FH $xml_node."\r\n";
  }
  print $FH "</nzb>";

  close $FH;

  say "NZB file created!";
}


sub process_files{

  my @files_to_upload = @{shift @_};
  my @xml_files=();

  my $nntp = Net::NNTP->new($NNTP_SERVER);
  $nntp->authinfo($USERNAME, $USER_PASSWORD);

  if($nntp->postok()){
    for my $file (@files_to_upload){
      say "Uploading $file: 0%";
      push @xml_files, _encode_and_upload($file, $nntp);
    }
  }

  $nntp->quit();
  return @xml_files;
}


sub _encode_and_upload{
  my $file = shift;
  my $nntp = shift;


  my $file_part=1;
  my $file_pos=1;
  my $file_size= -s $file;
  my $file_name=(fileparse($file))[0];
  my $file_max_parts = ceil($file_size/$NNTP_MAX_POST_BYTES);


  # NZB XML GENERATION
  # Note: This shouldn't be done this way. However, all my efforts with libxml weren't productive:
  # *- There are some issues with threads. It's not possible (at this moment) to share nested structures.
  # more info on: http://perldoc.perl.org/threads/shared.html#BUGS-AND-LIMITATIONS
  my $xml = "\t<file poster=\"$EMAIL\" date=".time()." subject=\"[$COMMENT[0]] \"$file_name\" yenc ($file_part/$file_max_parts)\">\r\n";
  $xml.="\t\t<groups>\r\n";

  for my $group (@NNTP_NEWSGROUPS){
    $xml.="\t\t\t<group>$group</group>\r\n";
  }
  $xml.="\t\t<groups>\r\n";
  $xml.="\t\t<segments>\r\n";


  open (my $FH, $file);
  binmode $FH;
  my $file_crc32 = crc32 *$FH;
  close $FH;

  open my $ifh, '<', $file or die "Couldn't open file: $!";
  binmode $ifh;

  while(read($ifh, my $bytes, $NNTP_MAX_POST_BYTES)){
    my $read_size=bytes::length($bytes);

    #CREATES THE MESSAGE HEADER
    my $msg_header = 'Newsgroups: '.join(',',@NNTP_NEWSGROUPS)."\r\n";
    $msg_header.="Subject: [$COMMENT[0]] \"$file_name\" yenc ($file_part/$file_max_parts) [$file_size] [$COMMENT[1]]\r\n";
    $msg_header.="From: $EMAIL\r\n\r\n";    

    #creates the msg content
    my $content_header="=ybegin part=$file_part total=$file_max_parts line=$NNTP_LINESIZE size=$file_size name=$file_name\r\n";
    $content_header.="=ypart begin=$file_pos end=".($file_pos-1+$read_size)."\r\n";
    my $content=_yenc_encode($bytes);
    my $pcrc32 = crc32 $bytes;

    my $content_tail="\r\n=yend size=$read_size pcrc32=".sprintf("%x",$pcrc32);
    $content_tail.=' crc32='.sprintf("%x",$file_crc32) if $file_part==$file_max_parts;

    #join the content
    $content=$content_header.$content.$content_tail;
    
    #post the message
    $nntp->post($msg_header.$content) or die "nntp_post: posting failed: ", $nntp->message;

    #NZB xml generation
    my $code = $nntp->code; 
    if ($code eq "240") {
      $nntp->message=~ /<(\S+)>/;
      $xml.="\t\t\t<segment bytes=$read_size number=\"$file_part\">$1</segment>\r\n";
      my $uploaded_percentage=floor($file_part/$file_max_parts *100.0);
      say "Uploading $file: ${uploaded_percentage}%";
    }

    
    $file_pos+=$read_size;
    $file_part+=1;
  }

  #NZB xml generation
  $xml.="\t\t</segments>";
  $xml.="\t</file>";

  close $ifh;
  return $xml;
}

sub _yenc_encode{
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
	(($char == 9 || $char == 32) && ($column == $NNTP_LINESIZE || $column==0)) || # TAB || SPC
	($char==46 && $column==0) # . 
       ) {
    
      $content .= '=';
    
      $column+=1;
    
      $char=($char + 64)%256;
    
    }
  
    $content .= chr $char;


    $column+=1;
  
    if ($column> $NNTP_LINESIZE ) {
      $column=0;
      $content .= "\r\n";
    }

  }
  return $content;
}


sub create_parity_files{
  my $file = shift;
  my @files = @_;
  
  my @COMMAND_LINE=('par2create', "-r$FILE_REDUNDANCY", '-n'.ceil(scalar(@files)*0.2), "${file}.par2", @files);

  system(@COMMAND_LINE)==0 or die "system @COMMAND_LINE failed: $?";

  return glob("'$file.*par2'");

}

#Returns a list containing the final files to be uploaded.
#This method returns will return the input file splitted if the file is bigger than 30MiB
sub pre_process_files{

  my ($file, $FILE_FORMAT, $FILE_REDUNDANCY) = @_;

  my $size=_get_upload_size( $file);#size in bytes

  my @pre_processed_files=();


  #The file must be splitted
  if($size > -1){
    $size/=1024;#size in KBytes
    $size/=1024;#size in MBytes

    my $upload_file_size=0;
    for my $upload_size (@UPLOAD_AVAILABLE_SIZES){

      $upload_file_size=$upload_size;
      my $upload_volumes = ceil($size/$upload_size);
      last if $upload_volumes < $UPLOAD_MAX_PARTS || $size == $UPLOAD_AVAILABLE_SIZES[-1];
      
    }
    @pre_processed_files = _compress_and_split_file( $file, $upload_file_size);

  }else{
    @pre_processed_files = _compress_and_split_file($file, -1);
  }

  
  return @pre_processed_files;

}

#Executes a external cmd to join and split the files to upload
sub _compress_and_split_file{
  my $file = shift;
  my $size = shift;
  
  my @COMMAND_LINE  = ('7z', 'a', '-mx=0');
  
  if($size>-1 && $FILE_FORMAT eq '7z'){
    push @COMMAND_LINE, "-v${size}m";
  }

  if(defined $FILE_PASSWORD && $FILE_FORMAT eq '7z'){
    push @COMMAND_LINE, "-p$FILE_PASSWORD";
  }

  if($FILE_FORMAT eq 'zip'){
    push @COMMAND_LINE, "-tzip", "$file.zip", "$file";

  }elsif($FILE_FORMAT eq '7z'){
    push @COMMAND_LINE, "$file.7z", "$file";
  }


  system(@COMMAND_LINE)==0 or die "system @COMMAND_LINE failed: $?";

  return glob("'$file.*'");

}


#returns the size of an upload. If it's a directory, it will sum the size of all files inside
sub _get_upload_size{

  my $file = shift;
  my $size=0;
  if(-f $file){
    $size= -s $file;
  }elsif(-d $file){
    find(sub{$size+= -s $_ if -f $_;}, $file);
    
  }else{
    say "$file: file not found!";
    $size= -1;
  }
  return $size;

}


#self explainatory
sub print_help{
  
  say "This program is licensed as GPLv3.\n";
  say "Usage:";
  say "\tRunning with the minimal options";
  say "\t\tprompt> perl <options> -s upload.server.without.ssl.com -n path.to.group1 -n path.to.group2 -f /path/to/file1 -f /path/to/file2";
  say "";
  say "\tOptions";
  say "\t\t--format | -fo\t\tUploading format. Either 7z or zip - This option takes precedent over option password (password will only be set if format is 7z). (default: 7z)";
  say "\t\t--password | -passwd\tPassword for your files. (default: no password)";
  say "\t\t--newsgroup | -n\tNewsgroup where you want to upload your files. Separate the newsgroups with a comma if you want to";
  say "\t\t\t\t\tcrosspost. OBLIGATORY.\n";
  say "\t\t--server | -s\t\tServer to upload. IT MUST SUPPORT TLS/SSL (Without it, it won't work). OBLIGATORY";
  say "\t\t--port | -p\t\tServer's port where this will connect to upload the file (default: 563)";
  say "\t\t--threads | -t\t\tNumber of simultaneous uploads. Your account must support it. :-) (default: 2)";
  say "\t\t--redundancy | -r\tPercentage of redundancy you want the .par files to have. If you want to disable the creation of par";
  say "\t\t\t\t\tfiles, set it to zero (0). (default:20)\n";  
  say "\t\t--files | -f\t\tFiles to upload. You can pass more than one option (check the example on top). The files will be uploaded";
  say "\t\t\t\t\tseparatelly. If you want to upload them in the same upload, put them inside a folder and upload it. OBLIGATORY\n";
  say "\t\t--redundancy | -rRedundancy of the par files. (default: 20%)";
  say "";
  say "Enjoy uploading!";
  say "";
  
}


