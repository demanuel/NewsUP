#!/usr/bin/perl

###############################################################################
#     Uploadit - create backups of your files to the usenet.
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

use utf8;
use warnings;
use strict;
use Config::Tiny;
use Getopt::Long;
use 5.018;
use Data::Dumper;
use String::CRC32;
use File::Basename;
use File::Find;
use File::Copy qw/mv cp/;
use Time::HiRes qw /time/;
my @FILES=();
my $NAME='';
my @GROUPS=();
my $COMMENT='';

GetOptions('file=s'=>\@FILES,
	   'name=s'=>\$NAME,
	   'comment=s'=>$COMMENT,
	   'group=s'=>\@GROUPS);

sub main{
  if (!@FILES || $NAME eq '') {
    
    say "You need to configure the switches -file, -name";
    exit 0;
    
  }else {
    my $validFiles = 0;
    for (@FILES){
      if(!-e $_){
	say "File $_ not found!";
	exit 0;
      }
    }    
  }
  
  if (defined $ENV{"HOME"} && -e $ENV{"HOME"}.'/.config/newsup.conf') {
    my $config = Config::Tiny->read( $ENV{"HOME"}.'/.config/newsup.conf' );
    my %script_vars = %{$config->{script_vars}};
    
  if (! -e $script_vars{PATH_TO_RAR} && $script_vars{RAR_COMPRESSION} !=-1) {
    say "You need to define a valid path to the rar program. Please change the variable RAR_PATH on the newsup.conf file.";
    exit 0;
  }
    if (!-e $script_vars{PATH_TO_UPLOADER}) {
      say "You need to define a valid path to newsup. Please change the variable PATH_TO_UPLOADER on the newsup.conf file.";
      exit 0;
    }
    if (!-e $script_vars{PATH_TO_PAR2} && exists $script_vars{PAR_REDUNDANCY}>0) {
      say "You need to define a valid path to par2repair program. Please change the variable PATH_TO_PAR2 on the newsup.conf file.";
      say "If you want to disable the creation of the parity files set the option PAR_REDUNDANCY to 0 (zero)";
      exit 0;
    }
    
    say "Splitting files!";
    my $compressedFilesRef = compress_files (\%script_vars);
    say "Checksum'ing the files";
    my $checkSumFiles = create_sfv_file($compressedFilesRef, \%script_vars);
    say "Creating parity files";  
    my $filesToUpload = create_parity_archives($checkSumFiles, \%script_vars);
    
    randomize_archives($checkSumFiles, \%script_vars);
    
    say "Starting upload";
    upload_files($filesToUpload,\%script_vars);
    if ($script_vars{RAR_COMPRESSION} !=-1) {
      unlink @$filesToUpload;
    }

  }else {
    say "Unable to find newsup.conf file. Please check if the environment variable HOME is installed!";
  }
}


sub upload_files{
  my ($filesToUpload, $scriptVarsRef) = @_;

  if (@$filesToUpload) {
    my $newsUPcmd = $scriptVarsRef->{PATH_TO_UPLOADER}." -f ".join(' -f ',@$filesToUpload)." -nzb $NAME";
    $newsUPcmd .=" -g ".join(' -g ',@GROUPS) if ((scalar @GROUPS) > 0);
    if ($COMMENT ne '') {
      $newsUPcmd .= " -comment \"$COMMENT\"";
    }
    system($newsUPcmd);
  }else {
    say "No files to upload!";
  }
}

sub randomize_archives{
  my ($compressedFiles,$scriptVarsRef) = @_;
  
  return $compressedFiles if ($scriptVarsRef->{RANDOMIZE_NAMES}==0 || @$compressedFiles > 1);

  my @notParityFiles = ();
  for (@$compressedFiles) {
    push @notParityFiles, $_ if (!/.*par2$/);
  }
  for (0..int(rand(@notParityFiles))) {
    my $number1 = int(rand(@notParityFiles));
    my $number2 = int(rand(@notParityFiles));
    $number2 = int(rand(@notParityFiles)) while ($number2 == $number1);

    my $time = time();
    my $file1 = $notParityFiles[$number1];
    my $file2 = $notParityFiles[$number2];
    mv($file1, "$file1.$time");
    mv($file2, $file1);
    mv("$file1.$time", $file1);
  }
  return $compressedFiles;
}


sub create_sfv_file{
  my ($compressedFiles,$scriptVarsRef) = @_;
  open my $ofh, '>', $scriptVarsRef->{TEMP_DIR}."$NAME.sfv";
  binmode $ofh;

  for (@$compressedFiles) {
    my $file = $_;
    my $fileName=(fileparse($file))[0];
    open my $ifh, '<', $file;
    my $crc32 = sprintf("%08x",crc32($ifh));
    print $ofh "$fileName $crc32\r\n";
    close $ifh;
  }
  
  close $ofh;
  my @files = @$compressedFiles;
  push @files, $scriptVarsRef->{TEMP_DIR}."$NAME.sfv";
  return \@files;
}

sub create_parity_archives{
  my ($compressedFiles,$scriptVarsRef) = @_;

  return $compressedFiles if ($scriptVarsRef->{PAR_REDUNDANCY}==0);
#  say Dumper($compressedFiles);
  my $parCmd =$scriptVarsRef->{PATH_TO_PAR2}." c -r".$scriptVarsRef->{PAR_REDUNDANCY}." ".
    $scriptVarsRef->{TEMP_DIR}."$NAME ".join(' ',@$compressedFiles);

#  say "$parCmd";
  
  `$parCmd`;
  if ($? != 0) {
    say  $!;
    return [];
  }
  
  my $globString = $scriptVarsRef->{TEMP_DIR}."$NAME*par2";

  my @files=();
  push @files, $_ for(@$compressedFiles); 
  push @files, $_ for <"$globString">;

  return \@files;
  
}


sub compress_files{
  my ($scriptVarsRef) = @_;
  my @compressedFiles;
  my $globString = $scriptVarsRef->{TEMP_DIR}."$NAME*";
  if ($scriptVarsRef->{RAR_COMPRESSION} > -1) {

    my $rarCmd=$scriptVarsRef->{PATH_TO_RAR}." a -m0 ";
    $rarCmd .= "-p".$scriptVarsRef->{RAR_PASSWORD} if defined $scriptVarsRef->{RAR_PASSWORD};
    $rarCmd .=" -v".($scriptVarsRef->{RAR_VOLUME_SIZE})."M -ep ".$scriptVarsRef->{TEMP_DIR}."$NAME -r ".join(' ',@FILES);
    
    `$rarCmd`;
    if ($? != 0) {
      say  $!;
      say "Potencial conflicts:";
      say "\t$_" for <"$globString">;
      return [];
    }
    @compressedFiles = <"$globString">;
    return \@compressedFiles;  
  }else {
    my @files = ();
    for my $file (@FILES) {
      if (-d $file) {

	find(sub{
	       if (-f) {
		 my $newName = $File::Find::name;
		 my $fileName = fileparse($newName);
		 cp($newName, $scriptVarsRef->{TEMP_DIR}) or die "Unable to copy the files to the temporary location: $!";
		 push @files, $scriptVarsRef->{TEMP_DIR}.$fileName;      

	       }
	     }, ($file))
	
      }else {
	my $fileName = fileparse($file);
	cp($file, $scriptVarsRef->{TEMP_DIR}) or die "Unable to copy the files to the temporary location";
	push @files, $scriptVarsRef->{TEMP_DIR}.$fileName;      
      }
    }

    return \@files;
  }
   


}


main();
