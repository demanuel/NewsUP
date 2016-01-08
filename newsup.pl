#!/usr/bin/perl -w

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
use Time::HiRes qw/gettimeofday usleep gettimeofday tv_interval/;
use POSIX qw/ceil/;
use IO::Socket::INET;
use IO::Socket::SSL;# qw(debug2);
use File::Path qw(remove_tree);
use Carp;
use IO::Select;

use Inline C => <<'C_CODE';
#include <stdint.h>;
static uint32_t crc32_tab[] = {
    0x00000000, 0x77073096, 0xee0e612c, 0x990951ba, 0x076dc419, 0x706af48f,
    0xe963a535, 0x9e6495a3, 0x0edb8832, 0x79dcb8a4, 0xe0d5e91e, 0x97d2d988,
    0x09b64c2b, 0x7eb17cbd, 0xe7b82d07, 0x90bf1d91, 0x1db71064, 0x6ab020f2,
    0xf3b97148, 0x84be41de, 0x1adad47d, 0x6ddde4eb, 0xf4d4b551, 0x83d385c7,
    0x136c9856, 0x646ba8c0, 0xfd62f97a, 0x8a65c9ec, 0x14015c4f, 0x63066cd9,
    0xfa0f3d63, 0x8d080df5, 0x3b6e20c8, 0x4c69105e, 0xd56041e4, 0xa2677172,
    0x3c03e4d1, 0x4b04d447, 0xd20d85fd, 0xa50ab56b, 0x35b5a8fa, 0x42b2986c,
    0xdbbbc9d6, 0xacbcf940, 0x32d86ce3, 0x45df5c75, 0xdcd60dcf, 0xabd13d59,
    0x26d930ac, 0x51de003a, 0xc8d75180, 0xbfd06116, 0x21b4f4b5, 0x56b3c423,
    0xcfba9599, 0xb8bda50f, 0x2802b89e, 0x5f058808, 0xc60cd9b2, 0xb10be924,
    0x2f6f7c87, 0x58684c11, 0xc1611dab, 0xb6662d3d, 0x76dc4190, 0x01db7106,
    0x98d220bc, 0xefd5102a, 0x71b18589, 0x06b6b51f, 0x9fbfe4a5, 0xe8b8d433,
    0x7807c9a2, 0x0f00f934, 0x9609a88e, 0xe10e9818, 0x7f6a0dbb, 0x086d3d2d,
    0x91646c97, 0xe6635c01, 0x6b6b51f4, 0x1c6c6162, 0x856530d8, 0xf262004e,
    0x6c0695ed, 0x1b01a57b, 0x8208f4c1, 0xf50fc457, 0x65b0d9c6, 0x12b7e950,
    0x8bbeb8ea, 0xfcb9887c, 0x62dd1ddf, 0x15da2d49, 0x8cd37cf3, 0xfbd44c65,
    0x4db26158, 0x3ab551ce, 0xa3bc0074, 0xd4bb30e2, 0x4adfa541, 0x3dd895d7,
    0xa4d1c46d, 0xd3d6f4fb, 0x4369e96a, 0x346ed9fc, 0xad678846, 0xda60b8d0,
    0x44042d73, 0x33031de5, 0xaa0a4c5f, 0xdd0d7cc9, 0x5005713c, 0x270241aa,
    0xbe0b1010, 0xc90c2086, 0x5768b525, 0x206f85b3, 0xb966d409, 0xce61e49f,
    0x5edef90e, 0x29d9c998, 0xb0d09822, 0xc7d7a8b4, 0x59b33d17, 0x2eb40d81,
    0xb7bd5c3b, 0xc0ba6cad, 0xedb88320, 0x9abfb3b6, 0x03b6e20c, 0x74b1d29a,
    0xead54739, 0x9dd277af, 0x04db2615, 0x73dc1683, 0xe3630b12, 0x94643b84,
    0x0d6d6a3e, 0x7a6a5aa8, 0xe40ecf0b, 0x9309ff9d, 0x0a00ae27, 0x7d079eb1,
    0xf00f9344, 0x8708a3d2, 0x1e01f268, 0x6906c2fe, 0xf762575d, 0x806567cb,
    0x196c3671, 0x6e6b06e7, 0xfed41b76, 0x89d32be0, 0x10da7a5a, 0x67dd4acc,
    0xf9b9df6f, 0x8ebeeff9, 0x17b7be43, 0x60b08ed5, 0xd6d6a3e8, 0xa1d1937e,
    0x38d8c2c4, 0x4fdff252, 0xd1bb67f1, 0xa6bc5767, 0x3fb506dd, 0x48b2364b,
    0xd80d2bda, 0xaf0a1b4c, 0x36034af6, 0x41047a60, 0xdf60efc3, 0xa867df55,
    0x316e8eef, 0x4669be79, 0xcb61b38c, 0xbc66831a, 0x256fd2a0, 0x5268e236,
    0xcc0c7795, 0xbb0b4703, 0x220216b9, 0x5505262f, 0xc5ba3bbe, 0xb2bd0b28,
    0x2bb45a92, 0x5cb36a04, 0xc2d7ffa7, 0xb5d0cf31, 0x2cd99e8b, 0x5bdeae1d,
    0x9b64c2b0, 0xec63f226, 0x756aa39c, 0x026d930a, 0x9c0906a9, 0xeb0e363f,
    0x72076785, 0x05005713, 0x95bf4a82, 0xe2b87a14, 0x7bb12bae, 0x0cb61b38,
    0x92d28e9b, 0xe5d5be0d, 0x7cdcefb7, 0x0bdbdf21, 0x86d3d2d4, 0xf1d4e242,
    0x68ddb3f8, 0x1fda836e, 0x81be16cd, 0xf6b9265b, 0x6fb077e1, 0x18b74777,
    0x88085ae6, 0xff0f6a70, 0x66063bca, 0x11010b5c, 0x8f659eff, 0xf862ae69,
    0x616bffd3, 0x166ccf45, 0xa00ae278, 0xd70dd2ee, 0x4e048354, 0x3903b3c2,
    0xa7672661, 0xd06016f7, 0x4969474d, 0x3e6e77db, 0xaed16a4a, 0xd9d65adc,
    0x40df0b66, 0x37d83bf0, 0xa9bcae53, 0xdebb9ec5, 0x47b2cf7f, 0x30b5ffe9,
    0xbdbdf21c, 0xcabac28a, 0x53b39330, 0x24b4a3a6, 0xbad03605, 0xcdd70693,
    0x54de5729, 0x23d967bf, 0xb3667a2e, 0xc4614ab8, 0x5d681b02, 0x2a6f2b94,
    0xb40bbe37, 0xc30c8ea1, 0x5a05df1b, 0x2d02ef8d
  };

//Thank you Tomas Novysedlak for yenc encoding piece :-)
AV* _yenc_encode_c(unsigned char* data, size_t data_size)
{
	const unsigned char maxwidth = 128;

	unsigned char *pointer, *encbuffer;
	size_t encoded_size = data_size;
	int column = 0;
	unsigned char c;
	int i;
	unsigned int crc32 = 0xFFFFFFFF;


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
		crc32 = crc32_tab[(crc32 ^ c) & 0xFF] ^ (crc32 >> 8);
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
	crc32 = crc32 ^ 0xFFFFFFFF;
        encbuffer = (char*) realloc(encbuffer, encoded_size);
        SV* yenc_string = newSVpv(encbuffer, 0);
	SV* ret = sv_2mortal(newAV());
	av_push(ret, yenc_string);
	av_push(ret, newSVuv(crc32));
        free(encbuffer);
        return ret;
}

C_CODE

$|=1;
$/="\r\n";
#YENC related variables
my $YENC_NNTP_LINESIZE=128;
my $NNTP_MAX_UPLOAD_SIZE=750*1024;
# END of the yenc variables

my $CRLF="\x0D\x0A";

my %MESSAGE_IDS=();


$SIG{PIPE}='IGNORE';

my $CURRENT_OPEN_FILE;
my $CURRENT_OPEN_FILE_FH;
my $CURRENT_OPEN_FILE_SIZE=0;

#Returns a bunch of options that it will be used on the upload. Options passed through command line have precedence over
#options on the config file
sub _parse_command_line{

  my ($server, $port, $username,$userpasswd,
      $threads, $from, $headerCheck,
      $headerCheckSleep, $headerCheckServer,
      $headerCheckPort, $headerCheckUserName,
      $headerCheckPassword, $headerCheckRetries,
      $headerCheckConnections, $nzbName);

  #Parameters with default values
  my $configurationFile = $ENV{"HOME"}.'/.config/newsup.conf';

  #default value
  my @filesToUpload=();
  my @newsGroups = ();
  my %metadata=();
  my @comments=();
  
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
	     'headerCheck=i'=>\$headerCheck,
	     'headerCheckSleep=i'=>\$headerCheckSleep,
	     'headerCheckServer=s'=>\$headerCheckServer,
	     'headerCheckPort=i'=>\$headerCheckPort,
	     'headerCheckUserName=s'=>\$headerCheckUserName,
	     'headerCheckPassword=s'=>\$headerCheckPassword,
	     'headerCheckRetries|retries=i'=>\$headerCheckRetries,
	     'headerCheckConnections=i'=>\$headerCheckConnections,
	     'uploadsize=i'=>\$NNTP_MAX_UPLOAD_SIZE,
	     'configuration=s'=>\$configurationFile
	    );

  if (-e $configurationFile) {

    my $config = Config::Tiny->read( $configurationFile );
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
	if (exists $config->{headerCheck}{user} && $config->{headerCheck}{user} ne ''){
	  $headerCheckUserName = $config->{headerCheck}{user};
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
      if (!defined $headerCheckConnections) {
	if (exists $config->{headerCheck}{connections}){
	  $headerCheckConnections = $config->{headerCheck}{connections};
	}else {
	  $headerCheckConnections = 1;
	}
      }
    }

    if ($NNTP_MAX_UPLOAD_SIZE < 100*1024) {
      $NNTP_MAX_UPLOAD_SIZE=750*1024;
      say "Upload Size too small. Setting the upload size at 750KBytes!";
    }

    if ( @newsGroups == 0) {
      if (exists $config->{upload}{newsgroup}){
	@newsGroups = split(',', $config->{upload}{newsgroup});
	$_ =~ s/^\s+|\s+$//g for @newsGroups;
      }
    }
    undef $config;
  }

  $nzbName = 'newsup.nzb' if (!defined $nzbName);
  
  if (!defined $server || !defined $port || !defined $username || !defined $from || @newsGroups==0 || !defined $threads) {
    say "Please check the parameters ('server', 'port', 'username'/'password', 'connections','uploader' and 'newsgoup')";
    exit 0;
  }

  return ($server, $port, $username, $userpasswd, 
	  \@filesToUpload, $threads, \@newsGroups, 
	  \@comments, $from, \%metadata, $headerCheck, $headerCheckSleep,
	  $headerCheckServer, $headerCheckPort, $headerCheckUserName,
	  $headerCheckPassword, $headerCheckRetries,
	  $headerCheckConnections, $nzbName);
}

sub _get_files_to_upload{
  
  my $filesToUploadRef = shift;

  my @tempFiles=();
  for my $dir (@$filesToUploadRef) {

    find(sub{
	   if (-f $_) {
	     my $newName = $File::Find::name;
	     push @tempFiles, $newName;
	     
	   }
	 }, ($dir));
  }

  @tempFiles = sort @tempFiles;
  my $tempFilesRef = \@tempFiles;
  return $tempFilesRef;
}


sub main{

  my ($server, $port, $username, $userpasswd, 
      $filesToUploadRef, $connections, $newsGroupsRef, 
      $commentsRef, $from, $meta, $headerCheck, $headerCheckSleep,
      $headerCheckServer, $headerCheckPort,
      $headerCheckUsername, $headerCheckPassword,
      $headerCheckRetries, $headerCheckConnections,$nzbName)=_parse_command_line();
  
  #Check if the files passed on the cmd are folders or not and if they are folders,
  #it will search inside for files
  my $files = _get_files_to_upload($filesToUploadRef);
  my $size=0;
  $size += -s $_ for @$files;
  $size /=1024;

  my $uploadParts = _split_files($files);
  my @nzbParts = @{$uploadParts};
  
  my $init = time;
  _start_upload($connections, $server, $port, $username, $userpasswd, $from, $newsGroupsRef, $commentsRef, $uploadParts);
  undef $uploadParts;
  
  my $time = time()-$init;
  say "Operation completed ".int($size/1024)."MB in ".int($time/60)."m ".($time%60)."s. Avg. Speed: [".int($size/$time)." KBytes/Sec]";
  if ($headerCheck) {
    my @missingSegments = @nzbParts;

    $init = time();
    _start_header_check($headerCheckConnections, $headerCheckServer, $headerCheckPort,
			$headerCheckUsername, $headerCheckPassword, $headerCheckRetries,
			$headerCheckSleep, $newsGroupsRef, $connections, $server, $port, $username,
			$userpasswd, $from, $commentsRef, \@missingSegments);
    
    $time = time()-$init;
    say "HeaderCheck done in ".int($time/60)."m ".($time%60)."s";

  }

  _create_nzb($from, $nzbName, \@nzbParts, $newsGroupsRef, $meta);
  say "NZB $nzbName created!";
  
}

sub _start_header_check{
  
  my ($headerCheckConnections, $headerCheckServer, $headerCheckPort,
      $headerCheckUsername, $headerCheckPassword, $headerCheckRetries,
      $headerCheckSleep, $newsGroupsRef, $connections, $server, $port, $username,
      $userpasswd, $from, $commentsRef, $missingSegmentsRef) = @_;
  
  my @missingSegments= @$missingSegmentsRef;
  my $totalMissingSegments = scalar @missingSegments;
  
  for (0..$headerCheckRetries-1) {
    print "Header Checking\r";
    sleep($headerCheckSleep);
    say "Warping up header check engines with $headerCheckConnections connections!";
    my $connectionList = _get_connections($headerCheckConnections, $headerCheckServer, $headerCheckPort, $headerCheckUsername, $headerCheckPassword);
    my $statSelect = IO::Select->new(@$connectionList);
    my $readSelect = IO::Select->new();

    my %candidates=();
    my $countProgress = 0;
    while (@missingSegments > 0) {

      while ($statSelect->count()>0) {
	for my $socket ($statSelect->can_write(1/1000)) {
	  my $part = shift @missingSegments;
	  $statSelect->remove($socket);
	  if (defined $part) {
	    _print_args_to_socket($socket, "stat <",$part->{id},'>',$CRLF);
	    $readSelect->add($socket);
	    $candidates{$part->{id}}=$part;
	  }
	}
      }
      
      while ($readSelect->count()>0) {
	for my $socket ($readSelect->can_read(1/1000)) {
	  my $output = _read_from_socket($socket);
	  print int((++$countProgress / $totalMissingSegments)*100),"%\r";
	  $readSelect->remove($socket);
	  if ($output =~ /^223 \d <(.+)>/) {
	    delete $candidates{$1};
	    $statSelect->add($socket);
	  }elsif ($output =~ /^400 /) {
	    shutdown ($socket, 2);
	    undef $socket;
	    my $conList = _get_connections(1, $headerCheckServer, $headerCheckPort, $headerCheckUsername, $headerCheckPassword);
	    $statSelect->add($conList->[0]);
	  }else {
	    $statSelect->add($socket);
	  }
	}
      }
    }
    
    @missingSegments = values %candidates;
    undef %candidates;
	
    for my $socket ($statSelect->handles()){
      _print_args_to_socket($socket, "QUIT", $CRLF) ;
      shutdown $socket, 2;
    }
    for my $socket ($readSelect->handles()){
      _print_args_to_socket($socket, "QUIT", $CRLF) ;
      shutdown $socket, 2;
    }

    undef $statSelect;
    undef $readSelect;

    
    say "There are ", scalar @missingSegments, " segments missing";
    
    if (@missingSegments > 0) {
      
      $connections = scalar @missingSegments if ($connections > scalar @missingSegments);
      
      my @tempSegments = @missingSegments;
      _start_upload($connections, $server, $port, $username, $userpasswd, $from, $newsGroupsRef, $commentsRef, \@tempSegments);
      say "\tUpload of the missing segments done!";
      undef @tempSegments;
    }else {
      last;
    }
  }
  undef @missingSegments;
}



sub _start_upload{
  my ($connections, $server, $port, $username, $userpasswd, $from, $newsGroupsRef, $commentsRef, $parts) = @_;

  my $connectionList = _get_connections($connections, $server, $port, $username, $userpasswd);
  my $newsgroups = join(',',@$newsGroupsRef);


  my $postSelect=IO::Select->new(@$connectionList);
  my $readPostSelect=IO::Select->new();
  my $articleSelect=IO::Select->new();
  my $readArticleSelect=IO::Select->new();
  my $totalParts = scalar @$parts;

  my $currentPart = 0;
  
  while (@$parts > 0) {
    my $t0 = [gettimeofday];
    my $uploadCounterPart=0;
    for my $socket ($postSelect->can_write(1/1000)) {
      _print_args_to_socket($socket, "POST", $CRLF);
      $postSelect->remove($socket);
      $readPostSelect->add($socket);
    }
    
    for my $socket ($readPostSelect->can_read(1/1000)) {
      my $output = _read_from_socket($socket);
      $readPostSelect->remove($socket);

      #If we get a 400 we return to the begining: postSelect
      if ($output =~ /^400 /) {
	shutdown ($socket, 2);
	my $conList = _get_connections(1, $server, $port, $username, $userpasswd);
	$postSelect->add($conList->[0]);

      }elsif($output =~ /340 /) {
	$articleSelect->add($socket);
      }else {
	chomp $output;
	print "\r\tRead after post: $output";
      }
      undef $output;
    }

    for my $socket ($articleSelect->can_write(1/1000)) {
      $articleSelect->remove($socket);
      if (scalar @$parts != 0){
	my $part = shift @$parts;
	$currentPart++;
	_post_part ($socket, $from, $newsgroups, $commentsRef, $part);

	$readArticleSelect->add($socket);
	undef $part;
      }
    }
	
    for my $socket ($readArticleSelect->can_read(1/1000)) {
      my $output = _read_from_socket($socket);
      $readArticleSelect->remove($socket);

      if ($output =~ /^400 /) {
	shutdown ($socket, 2);
	my $conList = _get_connections(1, $server, $port, $username, $userpasswd);
	$socket = $conList->[0];

      }elsif ($output !~ /^240 /) {
	chomp $output;
	say "\tRead after article: $output";
      }
      $postSelect->add($socket);
      undef $output;
    }
    print int(($currentPart / $totalParts)*100),"%\r";
  }

  for my $socket (@$connectionList){
    if ($socket->connected){
      _print_args_to_socket($socket, "QUIT", $CRLF);
      shutdown ($socket, 2);
    }
  }
}

sub _get_xml_escaped_string{
  my $string = shift;
  my %replacements=('&'=>'&amp;', '<' => '&lt;', '>' => '&gt;','"' => '&quot;', "'"=>'&apos;' );

  $string =~ s/('|&|<|>|")/$replacements{$1}/g;
  
#  $string=~ s/&/&amp;/g;
#  $string=~ s/</&lt;/g;
#  $string=~ s/>/&gt;/g;
#  $string=~ s/"/&quot;/g;
#  $string=~ s/'/&apos;/g;

  return $string;
}


sub _create_nzb{
  my ($from, $nzbName, $parts, $newsGroups, $meta)=@_;
  $from = _get_xml_escaped_string($from);
  if ($nzbName !~ /\.nzb$/i) {
    $nzbName .='.nzb';
  }

  
  my %files=();

  for my $segment (@$parts) {
    my $basename = fileparse($segment->{fileName});
    my $bytes = $NNTP_MAX_UPLOAD_SIZE;
    $bytes =  $segment-> {fileSize} % $NNTP_MAX_UPLOAD_SIZE if($segment->{segmentNumber} == $segment->{totalSegments});
    push @{$files{$basename}},
      "<segment bytes=\"$bytes\" number=\"".$segment->{segmentNumber}."\">".$segment->{id}."</segment>";
  }

  open my $ofh, '>', $nzbName;
  
  print $ofh "<?xml version=\"1.0\" encoding=\"iso-8859-1\" ?>\n";
  print $ofh "<nzb xmlns=\"http://www.newzbin.com/DTD/2003/nzb\">\n";
  print $ofh "<head>\n";
#  print $ofh "<meta>";
  print $ofh "<meta type=\"$_\">".$meta->{$_}."</meta>\n" for (keys %$meta);
#  print $ofh "</meta>\n";
  print $ofh "</head>\n";
  for my $filename (sort keys %files) {
    my @segments = @{$files{$filename}};
    my $time=time();
    print $ofh "<file poster=\"$from\" date=\"$time\" subject=\"&quot;".$filename."&quot; yEnc (1/",scalar(@segments),") \">\n";
    print $ofh "<groups>\n";
    print $ofh "<group>$_</group>\n" for @$newsGroups;
    print $ofh "</groups>\n";
    print $ofh "<segments>\n";
    print $ofh "$_\n" for (sort{
      $a =~ /number="(\d+)"/;
      my $s1 = $1;
      $b =~ /number="(\d+)"/;
      my $s2 = $1;
      return $s1 <=> $s2;
    } @segments);
    print $ofh "</segments>\n";
    print $ofh "</file>\n";
        
  }
  print $ofh "</nzb>\n";
  
}


sub _post_part{
  my ($socket, $from, $newsgroups, $commentsRef, $part) = @_;
  my $baseName = fileparse($part->{fileName});
  my $startPosition=1+$NNTP_MAX_UPLOAD_SIZE*($part->{segmentNumber}-1);
  my ($binString, $readSize, $endPosition, $fileSize) = _get_file_data($part->{fileName}, $startPosition-1);
  my $yenc = _yenc_encode_c($binString, $readSize);
  my ($yenc_data, $crc32_data) = @{$yenc};
  
  my $subject = '['.$part->{fileNumber}.'/'.$part->{totalFiles}.'] - "'.$baseName.'" ('.$part->{segmentNumber}.'/'.$part->{totalSegments}.')';
  if(defined $commentsRef && scalar(@$commentsRef)>0 && defined $commentsRef->[0] && $commentsRef->[0] ne ''){
    $subject = $commentsRef->[0]." $subject" ;
    $subject .= ' ['.$commentsRef->[1].']' if(scalar(@$commentsRef)>0 && defined $commentsRef->[1] && $commentsRef->[1] ne '');
  }
  
  _print_args_to_socket($socket,
			"From: ",$from, $CRLF,
			"Newsgroups: ",$newsgroups,$CRLF,
			"Subject: ",$subject,$CRLF,
			"Message-ID: <", $part->{id},">",$CRLF,$CRLF,
			"=ybegin part=", $part->{segmentNumber}, " total=",$part->{totalSegments}," line=", $YENC_NNTP_LINESIZE, " size=", $fileSize, " name=",$baseName, $CRLF,
			"=ypart begin=",$startPosition," end=", $endPosition, $CRLF,
			$yenc_data, $CRLF,
			"=yend size=",$readSize, " pcrc32=",sprintf("%x",$crc32_data),$CRLF,'.',$CRLF
		       );

}

sub _get_file_data{
  my ($fileName, $position) = @_;
  open my $fh, '<:bytes', $fileName;
  binmode $fh;
  seek $fh, $position,0;
  my $readSize = read($fh, my $byteString, $NNTP_MAX_UPLOAD_SIZE);
  my $endPosition = tell $fh;
  close $fh;
  return ($byteString, $readSize, $endPosition, -s $fileName);
}

sub _print_args_to_socket{

  my ($socket, @args) = @_;
  local $,;
  local $\;
  
  return 1 if !$socket->connected;

  #Note: using syswrite or print is the same (im assuming if we don't disable nagle's algorithm):
  # Network Programming with Perl. Page: 311.
  #So I'm going to use the simplest code.
  
  # Using syswrite
  
  for my $arg (@args){
    my $len = length $arg;
    my $offset = 0;

    while ($len) {
      my $written = syswrite($socket, $arg, $len, $offset);

      #my $written = $socket->syswrite();
      return 1 unless($written); 
      $len -= $written;
      $offset += $written;
      undef $written;
    }
  }
  undef @args;
  return 0;

  #Using print
  # return 0 if (print $socket @args);
  #return 1;

}


sub _read_from_socket{
  my ($socket) = @_;

 
  my $output='';
  my $counter=1;
  
  return "400 Socket closed\r\n" if (! $socket->connected);

  # return <$socket>;
  
  while (1) {
      my $status = sysread($socket, my $buffer,1024);
      $output.= $buffer;
      undef $buffer;
      if ($output =~ /\r\n\z/){
  	last;
      }elsif (!defined $status) {
  	die "Error: $!";
      }
  }
  
  return $output;
}

sub _authenticate{
  my ($connectionList,  $user, $password) = @_;
  my @connectionList = @{$connectionList};
  my $firstReadSelect = IO::Select->new(@connectionList);
  my $firstWriteSelect = IO::Select->new(@connectionList);
  while ($firstReadSelect->count()>0) {
    for my $sock ($firstReadSelect->can_read(0.01)) {
      $firstReadSelect->remove($sock);
      _read_from_socket $sock;
    }
  }
  
  while ($firstWriteSelect->count()>0) {

    for my $sock ($firstWriteSelect->can_write(0.01)) {
      $firstWriteSelect->remove($sock);
      die "Error: Unable to print to socket" if (_print_args_to_socket ($sock, "authinfo user ",$user,$CRLF) != 0);
    }
  }
  undef $firstReadSelect;
  undef $firstWriteSelect;

  my $readSelect = IO::Select->new(@connectionList);
  while ($readSelect->count()>0) {
    for my $sock ($readSelect->can_read(0.01)) {
      $readSelect->remove($sock);
      my $output= _read_from_socket $sock;
      die "Error: $output" if ( $output !~ /^381/);
    }
  }
  my $writeSelect = IO::Select->new(@connectionList);
  while ($writeSelect->count()>0) {
    for my $sock ($writeSelect->can_write(0.01)) {
      $writeSelect->remove($sock);
      die "Error: Unable to print to socket" if (_print_args_to_socket ($sock, "authinfo pass ",$password,$CRLF) != 0);
    }
  }
  my $secondReadSelect = IO::Select->new(@connectionList);
  while ($secondReadSelect->count()>0) {
    for my $sock ($secondReadSelect->can_read(0.01)) {
      $secondReadSelect->remove($sock);
      my $output= _read_from_socket $sock;
      die "Error: $output" if ( $output !~ /^281/);
    }
  }
  undef @connectionList;
  undef $readSelect;
  undef $writeSelect;
  undef $secondReadSelect;
}

sub _authenticate_old{
  my ($socket,  $user, $password) = @_;

  my $output = _read_from_socket $socket;
  die "Error: Unable to print to socket" if (_print_args_to_socket ($socket, "authinfo user ",$user,$CRLF) != 0);
  
  $output =  _read_from_socket $socket;
    
  die "Error: $output" if ($output !~ /381/);

  die "Error: Unable to print to socket" if (_print_args_to_socket ($socket, "authinfo pass ",$password,$CRLF) != 0);
  
  $output =  _read_from_socket $socket;

  if ($output !~ /281/){
    die "Error: $output";
  }
}

sub _get_connections{
  my ($connections, $server, $port, $user, $password) = @_;

  my @connectionList = ();

  for (0..$connections-1) {

    my $socket = _create_socket($server, $port);
    push @connectionList, $socket;    
  }
  _authenticate(\@connectionList, $user, $password);
  
  return \@connectionList;
}


sub _split_files{
  my ($files) =@_;

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
  undef %MESSAGE_IDS;
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


sub _create_socket{

  my ($server, $port) = @_;
  my $socket;
  while (1) {
    eval{
      if ($port != 119) {
	$socket = IO::Socket::SSL->new(
				       PeerHost=>$server,
				       PeerPort=>$port,
				       SSL_verify_mode=>SSL_VERIFY_NONE,
				       #SSL_version=>'TLSv1_2',
				       Blocking => 1,
				       Timeout=> 30, #connection timeout
				       #SSL_hostname=>'',
				       #SSL_version=>'TLSv1_2',
				       #SSL_cipher_list=>'DHE-RSA-AES128-SHA',
				       #SSL_ca_path=>'/etc/ssl/certs',
				      ) or die "Error: Failed to connect or ssl handshake: $!, $SSL_ERROR";
      }else {
	$socket = IO::Socket::INET->new (
					 PeerAddr => $server,
					 PeerPort => $port,
					 Blocking => 1,
					 Proto => 'tcp',
					 Timeout => 30, #connection timeout
					) or die "Error: Failed to connect : $!\n";
      }
    };

    if ( $@) {
      warn $@;
      sleep 3;
    }else {
      last;
    }

  }
  $socket->autoflush(1);

  return $socket;
}

main;
