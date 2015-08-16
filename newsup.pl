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
use Getopt::Long;
use Config::Tiny;
use File::Find;
use File::Basename;
use Data::Dumper;
use Carp;
use Time::HiRes qw/gettimeofday/;
use POSIX qw/ceil/;
use Compress::Zlib;
use Data::Dumper;
use IO::Socket::INET;
use IO::Socket::SSL;# qw(debug3);
use File::Path qw(remove_tree);


$|=1;

#YENC variables used for yenc'ing
my $YENC_NNTP_LINESIZE=128;
my $NNTP_MAX_UPLOAD_SIZE=750*1024;
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


  #Check if the files passed on the cmd are folders or not and if they are folders,
  #it will search inside for files
  my $files = _get_files_to_upload($filesToUploadRef);
  my $size=0;
  $size += -s $_ for @$files;
  $size /=1024;
  
  my $headers="From: $from\r\nNewsgroups: ".join('',@$newsGroupsRef)."\r\n";
  my $init=time();
  #  my $searchFolders = _launch_yenc_processes($connections,$files, $tempDir, $headers, $commentsRef);
  my $searchFolders = _launch_yenc_processes(8,$files, $tempDir, $headers, $commentsRef);
  say "Conversion finished!";
  # my $searchFolders = [
  # 		       '/tmp/test.part01.rar_yenc',
  # 		       '/tmp/test.part02.rar_yenc',
  # 		       '/tmp/test.part03.rar_yenc',
  # 		       '/tmp/test.part04.rar_yenc',
  # 		       '/tmp/test.part05.rar_yenc',
  # 		       '/tmp/test.part06.rar_yenc',
  # 		       '/tmp/test.part07.rar_yenc',
  # 		       '/tmp/test.part08.rar_yenc',
  # 		       '/tmp/test.part09.rar_yenc',
  # 		       '/tmp/test.part10.rar_yenc',
  # 		       '/tmp/test.part11.rar_yenc',
  # 		       '/tmp/test.part12.rar_yenc',
  # 		       '/tmp/test.part13.rar_yenc',
  # 		       '/tmp/test.part14.rar_yenc',
  # 		       '/tmp/test.part15.rar_yenc',
  # 		       '/tmp/test.part16.rar_yenc',
  # 		       '/tmp/test.part17.rar_yenc',
  # 		       '/tmp/test.part18.rar_yenc',
  # 		       '/tmp/test.part19.rar_yenc',
  # 		       '/tmp/test.part20.rar_yenc',
  # 		       '/tmp/test.part21.rar_yenc',
  # 		       '/tmp/test.part22.rar_yenc',
  # 		       '/tmp/test.part23.rar_yenc',
  # 		       '/tmp/test.part24.rar_yenc',
  # 		       '/tmp/test.part25.rar_yenc',
  # 		       '/tmp/test.part26.rar_yenc',
  # 		       '/tmp/test.part27.rar_yenc',
  # 		       '/tmp/test.part28.rar_yenc'
  # 		      ];
  

  _launch_upload_processes($server, $port, $username, $userpasswd, 1, $searchFolders);
  my $time = time()-$init;

  say "Transfered ".int($size/1024)."MB in ".int($time/60)."m ".($time%60)."s. Speed: [".int($size/$time)." KBytes/Sec]";
  _create_nzb($searchFolders, $newsGroupsRef);
  remove_tree(@$searchFolders,1,0);
  
  
}

sub _create_nzb{
  my ($folders, $newsGroups)=@_;

  my $subjectRegexp = qr/Subject: .*"(.*)" yenc\s?\((\d+)\/\d+\)/;
  my $sizeRegexp = qr/size=(\d+)/;
  my %nzb=();
  find(sub{

	 
	 if (-e $File::Find::name && !-d $File::Find::name && $_ =~ /uploaded$/) {
	   open my $ifh, '<', $File::Find::name;

	   while ((my $line = <$ifh>)) {
	     if ($line =~ /$subjectRegexp/) {
	       push @{$nzb{$1}}, [substr($_,0,-9), $2];
	       last;

	     }
	   }
	   
	   close $ifh;
	 }
	 
       },@$folders);

  open my $ofh, '>', 'newsup.nzb';
  print $ofh "<nzb xmlns=\"http://www.newzbin.com/DTD/2003/nzb\">\r\n";
  my $date = time();
  for my $k (keys %nzb) {
    print $ofh "<file poster=\"newsup\" date=\"$date\" subject=\"$k\">\r\n";
    print $ofh "<groups>\r\n";
    print $ofh "<group>$_</group>\r\n" for @$newsGroups;
    print $ofh "</groups>\r\n";
    print $ofh "<segments>\r\n";
    for (sort {$a->[1] <=> $b->[1]} @{$nzb{$k}}) {
      my $segment = $_->[0];
      my $segmentNumber = $_->[1];
      print $ofh "<segment size=\"$NNTP_MAX_UPLOAD_SIZE\" number=\"$segmentNumber\">$segment</segment>\r\n";
    }
    print $ofh "</segments>\r\n";
    print $ofh "</file>\r\n";
  }
  
  print $ofh "</nzb>";
  close $ofh;
}

sub _launch_upload_processes{
  my ($server, $port, $user, $password, $connections, $folders)=@_;

  my @processes = ();

  for (0..$connections-1) {
    push @processes, _launch_upload($server, $port, $user, $password, $folders);
  }

  for my $child (@processes) {
    waitpid($child,0);
    say "Parent: Child $child was reaped - ", scalar localtime, ".";
  }

  
}

sub _launch_upload{
  my ($server, $port, $user, $password, $folders) =@_;

  my $pid;
  
  unless (defined($pid = fork())) {
    say "cannot fork: $!";
    return -1;
  }
  elsif ($pid) {
    return $pid; # I'm the parent
  }

  my $socket = _create_socket($server, $port);
  croak "Unable to login. Please check the credentials" if _authenticate($socket, $user, $password) == -1;
  say "Authenticated!";
  

  find(sub{

	 if (-e $File::Find::name && !-d $File::Find::name && $_ =~ /newsup$/) {
	   if (rename $File::Find::name, $File::Find::name.".lock") {
	     _post_file($socket, $File::Find::name.".lock");
	     
	     rename $File::Find::name.'.lock', $File::Find::name.".uploaded";
	     
	   } 
	   
	 }
	 
       },@$folders);
  
  _logout ($socket);
  
  exit 0;
}

sub _post_file{
  my ($socket,  $file) = @_;

  #_read_from_socket($socket,$select);
  croak "Unable to print to socket" if (_print_to_socket ($socket, "POST\r\n") == -1);
  my $output = _read_from_socket($socket);

  croak "Unable to POST (no 340): $output" if($output !~ /340/);
  my $data;
  {
    open my $ifh, '<', $file or die "Cannot open the file '$file': $!";
    local $/=undef;
    my $data = <$ifh>;
    _print_to_socket ($socket, $data);

    close $ifh;
  }
  
  
  $output = _read_from_socket($socket);
  
  croak "Error posting article: $output " if($output!~ /240/);
  say "$file: $output";
  
}


sub _logout{
  my ($socket) = @_;
  _print_to_socket ($socket, "quit\r\n");
  shutdown $socket, 2;  
}


sub _launch_yenc_processes{
  my ($processes, $files, $tmpDir, $headers, $comments) = @_;

  my $filesPerProcesses = _split_files_per_process($processes, $files);

  my @processes = ();
  for (0..$processes-1) {
    push @processes, _create_yenc_articles($filesPerProcesses->[$_], $tmpDir, $headers, $comments);
  }

  my @searchFolders = map{$tmpDir.'/' .(fileparse($_))[0]."_yenc";} @$files;

  for my $child (@processes) {
    waitpid($child,0);
    say "Parent: Yenc $child was reaped - ", scalar localtime, ".";
  }

  return \@searchFolders;
}

sub _create_yenc_articles{
  my ($files, $tmpDir, $headers, $commentsRef) = @_;

  my $pid;
  
  unless (defined($pid = fork())) {
    say "cannot fork: $!";
    return -1;
  }
  elsif ($pid) {
    return $pid; # I'm the parent
  }

  
  for my $fileData (@$files) {
    open my $ifh , '<:bytes', $fileData->[1];
    
    my $fileName = (fileparse($fileData->[1]))[0];
    my $dir ="$tmpDir/${fileName}_yenc";
    mkdir $dir or die "Unable to create directory '$dir': $!";
    my $bytes;
    my $part = 1;
    my $totalParts = ceil((-s $fileData->[1])/$NNTP_MAX_UPLOAD_SIZE);
    my $startPosition=1;
    my $subject = '['.$fileData->[0].'] - "'.$fileName.'"';
    if (defined $commentsRef) {
      $subject = $commentsRef->[0].' '.$subject if scalar(@$commentsRef) > 0;
      $subject = $subject . ' ['.$commentsRef->[1].']' if scalar(@$commentsRef) > 1;
    }



    
    while ((my $readedSize = read($ifh, $bytes, $NNTP_MAX_UPLOAD_SIZE)) ) {
      my $messageID = _get_message_id();
      open my $ofh, '>:raw',$dir.'/'.$messageID;
      my $yencData=_yenc_encode($bytes);
      print $ofh $headers,
	"Subject: ",$subject,' yenc (',$part,'/',$totalParts,")\r\n",
	"Message-ID: <",$messageID,">\r\n",
	"\r\n",
	"=ybegin part=",$part," total=",$totalParts, " line=",$YENC_NNTP_LINESIZE, " size=", $readedSize, " name=",$fileName,"\r\n",
	"=ypart begin=",$startPosition," end=",tell $ifh,"\r\n",
	${$yencData->[1]},
	"\r\n=yend size=",$readedSize," pcrc32=",$yencData->[0],"\r\n.\r\n";

      $startPosition=1+tell $ifh;
      $part++;
      
      close $ofh;
    }
    close $ifh;
  }

  exit 0;
  
}

sub _split_files_per_process{
  my ($processes, $files) = @_;
  my @parts = ();
  my $total = scalar @$files;
  
  my $i=0;
  foreach my $elem (sort @$files) {
    push @{ $parts[$i++ % $processes] }, ["$i/$total",$elem];
  }

  return \@parts;
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




sub _yenc_encode{
  my $column = 0;
  my $content = '';
  
  for my $hexChar (unpack('W*',$_[0])) {

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

  return [sprintf("%x", crc32($_[0])), \$content];
}


sub _read_from_socket{
  my ($socket) = @_;

  my ($output, $buffer) = ('', '');
  while(1){
    $socket->sysread($buffer, 1024);

    $output .= $buffer;
    last if $output =~ /\r\n$/;
  }

  return $output;
}

sub _print_to_socket{
  my ($socket, $args) = @_;

  print $socket $args;

  return 1;
}


sub _authenticate{
  my ($socket,  $user, $password) = @_;

  my $output = _read_from_socket $socket;
  croak "Unable to print to socket" if (_print_to_socket ($socket, "authinfo user $user\r\n") == -1);

  $output =  _read_from_socket $socket;
  croak $output if $output !~ /381/;

  croak "Unable to print to socket" if (_print_to_socket ($socket, "authinfo pass $password\r\n") == -1);
  
  $output =  _read_from_socket $socket;
  
  croak $output if $output !~ /281/;

}

sub _create_socket{

  my ($server, $port) = @_;
  my $socket;
  
  if ($port != 119) {
    $socket = IO::Socket::SSL->new(
				   PeerHost=>$server,
				   PeerPort=>$port,
				   SSL_verify_mode=>SSL_VERIFY_NONE,
				   SSL_version=>'TLSv1',
				   Blocking => 1,
				   #SSL_version=>'TLSv1_2',
				   #SSL_cipher_list=>'DHE-RSA-AES128-SHA',
				   SSL_ca_path=>'/etc/ssl/certs',
				  ) or die "Failed to connect or ssl handshake: $!, $SSL_ERROR";
  }else {
    $socket = IO::Socket::INET->new (
				     PeerAddr => $server,
				     PeerPort => $port,
				     Blocking => 1,
				     Proto => 'tcp',
				    ) or die "ERROR in Socket Creation : $!\n";
  }
  
  $socket->autoflush(1);
  
  return $socket;
}

main();

