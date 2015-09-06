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
use Carp qw/carp/;
use Time::HiRes qw/gettimeofday usleep/;
use POSIX qw/ceil/;
use Compress::Zlib;
use IO::Socket::INET;
use IO::Socket::SSL;# qw(debug3);
use File::Path qw(remove_tree);

use Inline C => <<'C_CODE';
//Thank you Tomas Novysedlak for this piece of code :-)
char* _yenc_encode_c(unsigned char* data, size_t data_size)
{
	const unsigned char maxwidth = 128;

	unsigned char *pointer, *encbuffer;
	size_t encoded_size = data_size;
	int column = 0;
	unsigned char c;
	int i;

	if (NULL == (encbuffer = malloc(data_size << 1)))
	{
		return NULL;
	}
	else
	{
		pointer = encbuffer;
	}

	for(i = 0; i < data_size; ++i)
	{
		c = data[i];
		c = (c + 42) & 0xFF;

		switch (c)
		{
			case 0 :
			case '\n' :
			case '\r' :
			case '=' :
			  c += 64;
			  *(pointer++) = '=';
			  column++;
			  encoded_size++;
			  break;

			case '\t' :
			case ' ' :
			  if(!column || column - 1 == maxwidth)
			  {
				  column++;
				  encoded_size++;
				  *(pointer++) = '=';
				  c += 64;
			  }
			  break;

			case '.' :
			  if(!column)
			  {
				  column++;
				  encoded_size++;
				  *(pointer++) = '=';
				  c += 64;
			  }
			  break;
		}

		*(pointer++) = c;
		column++;

		if(column >= maxwidth)
		{
			column = 0;
			*(pointer++) = '\r';
			*(pointer++) = '\n';
			encoded_size += 2;
		}
	}

	*pointer = 0;
	encoded_size++;
	return realloc(encbuffer, encoded_size);
}

C_CODE

$|=1;

#YENC related variables
my $YENC_NNTP_LINESIZE=128;
my $NNTP_MAX_UPLOAD_SIZE=750*1024;
# END of the yenc variables

my %MESSAGE_IDS=();

#Returns a bunch of options that it will be used on the upload. Options passed through command line have precedence over
#options on the config file
sub _parse_command_line{

  my ($server, $port, $username,$userpasswd,
      @filesToUpload, $threads, @comments,
      $from, $headerCheck, $headerCheckSleep, $headerCheckServer, $headerCheckPort,
      $headerCheckUserName, $headerCheckPassword, $headerCheckRetries, $nzbName, $tempDir);

  #default value
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
	     'headerCheckRetries|retry=i'=>\$headerCheckRetries,
	     'uploadsize=i'=>\$NNTP_MAX_UPLOAD_SIZE
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

      if (!defined $headerCheckRetries) {
	$headerCheckRetries = $config->{headerCheck}{retries} if exists $config->{headerCheck}{retries};
      }      
    }

    if ($NNTP_MAX_UPLOAD_SIZE < 100*1024) {
      $NNTP_MAX_UPLOAD_SIZE=750*1024;
      say "Upload Size too small. Setting the upload size at 750KBytes!";
    }

    

    $tempDir = $config->{generic}{tempDir} if exists $config->{generic}{tempDir};
    die "Please define a valid temporary dir in the configuration file" if (!defined $tempDir || !-d $tempDir);

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
	  $headerCheckPassword, $headerCheckRetries, $nzbName, $uploadSize, $tempDir);
}

sub _get_files_to_upload{
  
  my $filesToUploadRef = shift;

  my $tempFilesRef=[];
  for my $dir (@$filesToUploadRef) {

    find(sub{
	   if (-f $_) {
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
      $headerCheckUsername, $headerCheckPassword, $headerCheckRetries, $nzbName,
      $tempDir)=_parse_command_line();

  #Check if the files passed on the cmd are folders or not and if they are folders,
  #it will search inside for files
  my $files = _get_files_to_upload($filesToUploadRef);
  my $size=0;
  $size += -s $_ for @$files;
  $size /=1024;
  #my $headers="From: $from\r\nNewsgroups: ".."\r\n";
  my $init=time();

  say "Splitting files per connection";
  my $parts = _split_files_per_connection($files, $connections);
  
  _launch_upload_processes($server, $port, $username, $userpasswd, $connections, $parts, $commentsRef, {from=>$from, newsgroups=>join(',',@$newsGroupsRef)});

  my $missingSegments = [];
  if ($headerCheck) {
    sleep($headerCheckSleep);
    $missingSegments = _launch_header_check($headerCheckServer, $headerCheckPort, $headerCheckUsername, $headerCheckPassword,
					    $newsGroupsRef->[0], $parts);
    say "Found ".scalar(@$missingSegments)." missing segments!";

    while ((scalar(@$missingSegments) > 0) && ($headerCheckRetries-- > 0)) {
      
      my $splitMissingSegments=[];
      my $i=0;
      foreach my $segment (@$missingSegments) {
	push @{ $splitMissingSegments->[$i++ % $connections] }, $segment;
      }

      _launch_upload_processes($server, $port, $username, $userpasswd, $connections, $splitMissingSegments, $commentsRef, {from=>$from, newsgroups=>join(',',@$newsGroupsRef)});
      sleep($headerCheckSleep);

      $missingSegments = _launch_header_check($headerCheckServer, $headerCheckPort, $headerCheckUsername, $headerCheckPassword,
					      $newsGroupsRef->[0], [$missingSegments]);

      say "Found ".scalar(@$missingSegments)." missing segments!";
      
    }
  }

  say "Upload Finished!";
  my $time = time()-$init;

  $time=1 if($time==0);
  
  if (scalar(@$missingSegments) == 0) {
    say "Transfered ".int($size/1024)."MB in ".int($time/60)."m ".($time%60)."s. Speed: [".int($size/$time)." KBytes/Sec]";
    $nzbName='newsup.nzb' if (!defined $nzbName);
    _create_nzb($nzbName, $parts, $newsGroupsRef);
    say "NZB $nzbName created!";

  }else {
    say "There were failed segments!";
  }
}

sub _launch_header_check{
  my ($headerCheckServer, $headerCheckPort,
      $headerCheckUsername, $headerCheckPassword,
      $newsgroup, $parts)=@_;
  my @missingParts=();

  say "Launching header check on server $headerCheckServer:$headerCheckPort";
  my $socket = _create_socket($headerCheckServer, $headerCheckPort);
  if (_authenticate($socket, $headerCheckUsername, $headerCheckPassword)) {
    say "Unable to authenticate on the header check server!";
    return [];
  }
  die "Unable to print to socket" if (_print_to_socket($socket, "GROUP $newsgroup\r\n")!=0);
  my $output = _read_from_socket($socket);
  if ($output =~ /^211\s/) {

    for my $connectionSegmentList (@$parts) {
      for my $segment (@$connectionSegmentList) {
	
	_print_args_to_socket($socket, "head <",$segment->{id},">\r\n");
	$output = _read_from_socket($socket);

	if ($output =~ /^221\s.*$/m){
	  while ($output !~ /\.\r\n/m) {
	    $output = _read_from_socket($socket);
	  }
	}else {
	  push @missingParts, $segment;
	}
      }
    }
  }

  return \@missingParts;
  
}

sub _create_nzb{
  my ($nzbName, $parts, $newsGroups)=@_;

  my %files=();
  for my $connectionParts (@$parts) {
    for my $segment (@$connectionParts) {
      my $basename = fileparse($segment->{fileName});
      push @{$files{$basename}},
	"<segment bytes=\"$NNTP_MAX_UPLOAD_SIZE\" number=\"".$segment->{segmentNumber}."\">".$segment->{id}."</segment>";
    }
  }

  open my $ofh, '>', $nzbName;
  
  print $ofh "<?xml version=\"1.0\" encoding=\"iso-8859-1\" ?>\n";
  print $ofh "<nzb xmlns=\"http://www.newzbin.com/DTD/2003/nzb\">\n";
  for my $filename (sort keys %files) {
    say "Filename: $filename";

    my @segments = @{$files{$filename}};
    my $time=time();
    print $ofh "<file poster=\"newsup\" date=\"$time\" subject=\"&quot;".$filename."&quot;\">\n";
    print $ofh "<groups>\n";
    print $ofh "<group>$_</group>\n" for @$newsGroups;
    print $ofh "</groups>\n";
    print $ofh "<segments>\n";
    print $ofh "$_\n" for @segments;
    print $ofh "</segments>\n";
    print $ofh "</file>\n";
        
  }
  print $ofh "</nzb>\n";
  
}


sub _launch_upload_processes{
  my ($server, $port, $user, $password, $connections, $segments, $commentsRef, $metadata)=@_;
  my @processes = ();

  say "Launching upload process"; 
  
  my $min = (($connections,scalar(@$segments))[($connections)> scalar(@$segments)])-1;

  if ($min > 0) {
    for my $idx (0.. $min) {
      my $connection_segments = $segments->[$idx];
      push @processes, _launch_upload($server, $port, $user, $password, $connection_segments, $commentsRef, $metadata);
    }
  }


  for my $child (@processes) {
    waitpid($child,0);
    say "Parent: Uploading Child $child was reaped - ", scalar localtime, ".";
  }
  
}

sub _launch_upload{
  my ($server, $port, $user, $password, $segments, $commentsRef, $metadata) =@_;
  
  my $pid;
  
  unless (defined($pid = fork())) {
    say "cannot fork: $!";
    return -1;
  }
  elsif ($pid) {
    return $pid; # I'm the parent
  }
  
  my $socket = _create_socket($server, $port);
  die "Unable to login. Please check the credentials" if _authenticate($socket, $user, $password) >= 1;

  my $currentFileOpen='';
  my $ifh = undef;
  my $baseName='';
  my $fileSize=0;

  for my $segment (@$segments) {

    my $startPosition=1+$NNTP_MAX_UPLOAD_SIZE*($segment->{segmentNumber}-1);

    
    if ($segment->{fileName} ne $currentFileOpen && defined $ifh){
      close $ifh;
      open $ifh, '<', $segment->{fileName};
      $currentFileOpen = $segment->{fileName};
      $baseName = fileparse($currentFileOpen, qr/\.[^.]*/);
      $fileSize = -s $segment->{fileName};
    }elsif ($segment->{fileName} ne $currentFileOpen) {
      open $ifh, '<', $segment->{fileName};
      $currentFileOpen = $segment->{fileName};
      $baseName = fileparse($currentFileOpen, qr/\.[^.]*/);
      $fileSize = -s $segment->{fileName};
    }
    my $subject = '['.$segment->{fileNumber}.'/'.$segment->{totalFiles}.'] - "'.$baseName.'" ('.$segment->{segmentNumber}.'/'.$segment->{totalSegments}.')';

    if(defined $commentsRef && scalar(@$commentsRef)>0 && defined $commentsRef->[0] && $commentsRef->[0] ne ''){
      $subject = $commentsRef->[0]." $subject" ;
      $subject .= ' ['.$commentsRef->[1].']' if(scalar(@$commentsRef)>0 && defined $commentsRef->[1] && $commentsRef->[1] ne '');
    }
    #TODO
    seek ($ifh, $startPosition-1, 0);
    my $readSize = read($ifh, my $byteString, $NNTP_MAX_UPLOAD_SIZE);

    _print_to_socket($socket, "POST\r\n");
    my $output = _read_from_socket($socket);
    if ($output =~ /^340\s/) {
    
      _print_args_to_socket($socket,
			    "From: ",$metadata->{from},"\r\n",
			    "Newsgroups: ",$metadata->{newsgroups},"\r\n",
			    "Subject: ",$subject,"\r\n",
			    "Message-ID: <", $segment->{id},">\r\n",
			    "\r\n",
			    "=ybegin part=", $segment->{segmentNumber}, " total=",$segment->{totalSegments}," line=", $YENC_NNTP_LINESIZE, " size=",$fileSize, " name=",$baseName,"\r\n",
			    "=ypart begin=",$startPosition," end=",tell $ifh,"\r\n",
			    _yenc_encode_c($byteString, $readSize),"\r\n",
			    "=yend size=",$readSize, " pcrc32=",sprintf("%x",crc32 ($byteString)),"\r\n.\r\n"
			   );
      $output = _read_from_socket($socket);

      if ($output !~ /^240\s/) {
	close $ifh;
	_logout ($socket);
	die "Post failed: $output";
      }
    }else {
      close $ifh;
      _logout ($socket);
      die "Post failed: $output";
    }
    
  }
  close $ifh;
  
  _logout ($socket);

  exit 0;
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

  my ($seed, $usec) = gettimeofday();

  for my $fileData (@$files) {
    my $fileName = (fileparse($fileData->[1]))[0];
    my $dir ="$tmpDir/${fileName}_yenc";
    
    if (!-e $dir ) {
      open my $ifh , '<:bytes', $fileData->[1];
      binmode $ifh;
      my $fileSize = -s $fileData->[1];
    
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
	my $messageID = $part.$fileData->[2];
	open my $ofh, '>:raw',$dir.'/'.$messageID;
	my $yencData=_yenc_encode_c($bytes, $readedSize);
	print $ofh $headers,
	  "Subject: ",$subject,' yenc (',$part,'/',$totalParts,")\r\n",
	  "Message-ID: <",$messageID,">\r\n",
	  "\r\n",
	  "=ybegin part=",$part," total=",$totalParts, " line=",$YENC_NNTP_LINESIZE, " size=", $fileSize, " name=",$fileName,"\r\n",
	  "=ypart begin=",$startPosition," end=",tell $ifh,"\r\n",
	  #_yenc_encode_c($YENC_NNTP_LINESIZE,$bytes),
	  $yencData,
	  #"\r\n=yend size=",$readedSize," pcrc32=",$yencData->[0],"\r\n.\r\n";
	  "\r\n=yend size=",$readedSize," pcrc32=",sprintf("%x",crc32 ($bytes)),"\r\n.\r\n";
	
	$startPosition=1+tell $ifh;
	$part++;
	
	close $ofh;
      }
      close $ifh;
    }else {
      say "Found old folder from a failed(?) upload. Using it instead: $dir";
    }

  }

  exit 0;
  
}

sub _split_files_per_connection{
  my ($files,$connections) =@_;


  my @parts = ();
  for (my $fileNumber=0; $fileNumber < scalar(@$files); $fileNumber++) {
    my $fileSize=-s $files->[$fileNumber];
    my $segmentNumber=0;
    my $totalSegments=ceil($fileSize/$NNTP_MAX_UPLOAD_SIZE);
    while (++$segmentNumber <= $totalSegments) {
      push @parts, {fileName=> $files->[$fileNumber],
		    fileSize=> $fileSize,
		    segmentNumber=>$segmentNumber,
		    totalSegments=>$totalSegments,
		    fileNumber=>$fileNumber+1,
		    totalFiles=>scalar(@$files),
		    id=>"$segmentNumber"._get_message_id(),
		   };
      
    }
  }

  my $i=0;
  my @split=();
  foreach my $file (@parts) {
    push @{ $split[$i++ % $connections] }, $file;
  }

  return \@split;
}

sub _split_files_per_process{
  my ($processes, $files) = @_;

  my @parts = ();
  my $total = scalar @$files;
  
  my $i=0;
  foreach my $elem (sort @$files) {
    push @{ $parts[$i++ % $processes] }, ["$i/$total",$elem, _get_message_id() ];
  }
  return \@parts;
}

sub _get_message_id{

  (my $s, my $usec) = gettimeofday();
  my $time = _encode_base36("$s$usec");
  my $randomness = _encode_base36(rand("$s$usec"));

  my $mid = "$s$usec.$randomness\@$time.newsup";

  if (!exists $MESSAGE_IDS{$mid}) {
    $MESSAGE_IDS{$mid}=1;
    return $mid;
  }else {
    return _get_message_id();
  }

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

sub _get_available_cpus{

    my $yenc_processes = 2;
    if($^O =~ /MSWin32|cygwin/){
      $yenc_processes = $ENV{"NUMBER_OF_PROCESSORS"};
    }elsif($^O =~ /linux/){
      open my $ifh, '<', '/proc/cpuinfo';
      while(<$ifh>){
	$yenc_processes+=1 if(/processor/);
      }
      close $ifh;
    }
    elsif($^O =~ /hpux/){
      $yenc_processes = scalar(my @l = qx/ioscan -k -C processor/)-2;
    }
    return $yenc_processes;
}

sub _read_from_socket{
  my ($socket) = @_;

  my ($output, $buffer) = ('', '');
  while(1){
    usleep(100);
    $socket->sysread($buffer, 1024);
    
    $output .= $buffer;
    last if $output =~ /\r\n$|^\z/;
  }

  return $output;
}

sub _print_args_to_socket{

  my ($socket, @args) = @_;
  print $socket @args;
  return 0;
}

sub _print_to_socket{
  my ($socket, $args) = @_;

  print $socket $args;

  return 0;
}


sub _authenticate{
  my ($socket,  $user, $password) = @_;

  my $output = _read_from_socket $socket;
  die "Unable to print to socket" if (_print_to_socket ($socket, "authinfo user $user\r\n") != 0);

  $output =  _read_from_socket $socket;
  die $output if $output !~ /381/;

  die "Unable to print to socket" if (_print_to_socket ($socket, "authinfo pass $password\r\n") != 0);
  
  $output =  _read_from_socket $socket;

  if ($output !~ /281/){
    carp $output;
    return 1;
  }
  0;
  
}

sub _create_socket{

  my ($server, $port) = @_;
  my $socket;
  
  if ($port != 119) {
    $socket = IO::Socket::SSL->new(
				   PeerHost=>$server,
				   PeerPort=>$port,
				   SSL_verify_mode=>SSL_VERIFY_NONE,
				   SSL_version=>'TLSv1_2',
				   Blocking => 1,
				   Timout=> 20,
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
				     Timeout => 20,
				    ) or die "ERROR in Socket Creation : $!\n";
  }
  
  $socket->autoflush(1);
  
  return $socket;
}

main();
