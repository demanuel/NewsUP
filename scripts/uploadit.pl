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
use Compress::Zlib;
use File::Basename;
use File::Find;
use File::Copy qw/mv cp/;
use Time::HiRes qw /time/;
use Compress::Zlib;

sub main{
  my $DIRECTORY='';
  my $NAME='';
  my @GROUPS=();
  my $DEBUG=0;
  my $UP_ARGS='';
  my $DELETE=1;
  my $FORCE_RENAME=0;
  my $SFV=0;
  my $NFO;
  
  GetOptions('help'=>sub{help();},
	     'directory=s'=>\$DIRECTORY,
	     'debug!'=>\$DEBUG,
	     'args=s'=>\$UP_ARGS,
	     'delete!'=>\$DELETE,
	     'group=s'=>\@GROUPS,
	     'sfv!'=>\$SFV,
	     'nfo=s'=>\$NFO,
	     'force_rename|rename!'=>\$FORCE_RENAME);

  $UP_ARGS .=' ' if $UP_ARGS ne '';
  $UP_ARGS .="-group ".join(' -group ', @GROUPS) if @GROUPS;
  
  if ($DIRECTORY eq '' || !-e $DIRECTORY ) {
    
    say "You need to configure the switch -directory";
    exit 0;
    
  }

  if (defined $ENV{"HOME"} && -e $ENV{"HOME"}.'/.config/newsup.conf') {
      my $config = Config::Tiny->read( $ENV{"HOME"}.'/.config/newsup.conf' );
      my %other_configs = %{$config->{other}};
    
      if (! -e $other_configs{PATH_TO_RAR} && $other_configs{ENABLE_RAR_COMPRESSION} == 1) {
	  say "You need to define a valid path to the rar program. Please change the variable RAR_PATH on the newsup.conf file.";
	  exit 0;
      }
      if (exists $other_configs{ENABLE_PAR_CREATION} && $other_configs{ENABLE_PAR_CREATION} && !-e $other_configs{PATH_TO_PAR2}) {
	  say "You need to define a valid path to par2repair program. Please change the variable PATH_TO_PAR2 on the newsup.conf file.";
	  exit 0;
	}

      if (!$SFV) {

	$SFV=1 if (exists $other_configs{ENABLE_SFV_GENERATION} && $other_configs{ENABLE_SFV_GENERATION});
	
      }
      
      
      # say "Splitting files!";
      my $preProcessedFiles = pre_process_folder ($DIRECTORY, \%other_configs, $DEBUG);
      say Dumper($preProcessedFiles) if $DEBUG;
      
      push @$preProcessedFiles, create_sfv_file(basename($DIRECTORY), $preProcessedFiles, \%other_configs, $DEBUG) if ($other_configs{ENABLE_SFV_GENERATION});
      say Dumper($preProcessedFiles) if $DEBUG;


      if (defined $NFO && -e $NFO) {
	push @$preProcessedFiles, $NFO;
	
      }elsif (!defined $NFO && defined $other_configs{NFO_FILE} && $other_configs{NFO_FILE}) {
	my($filename, $dirs, $suffix) = fileparse($other_configs{NFO_FILE}, '.nfo');
	
	cp($other_configs{NFO_FILE}, $other_configs{TEMP_DIR});
	push @$preProcessedFiles, $other_configs{TEMP_DIR}."/$filename.nfo";
      }else {
	$FORCE_RENAME=0;
      }

      
      push @$preProcessedFiles, create_parity_archives($DIRECTORY, $preProcessedFiles, \%other_configs,$FORCE_RENAME, $DEBUG) if ($other_configs{ENABLE_PAR_CREATION});
      say Dumper($preProcessedFiles) if $DEBUG;
      upload_files($preProcessedFiles, \%other_configs, $UP_ARGS, $DEBUG);

      my $remove_regexp = $other_configs{TEMP_DIR};


	for my $file (@$preProcessedFiles) {
	  
	  my (undef, $path, undef) = fileparse($file);
	  if ($DELETE) {
	    if ($file =~ /$remove_regexp/ && index($path, $DIRECTORY)!=0) {
	      unlink $file;
	      say "Removing $file" if $DEBUG;
	    }
	  }else {
	    say "Uploaded files: $file";
	  }
      }
      # say "Creating parity files";  
      # my $filesToUpload = create_parity_archives($checkSumFiles, \%script_vars);
      
      # randomize_archives($checkSumFiles, \%script_vars);
      
      # say "Starting upload";
      # upload_files($filesToUpload,\%script_vars);
      # if ($script_vars{RAR_COMPRESSION} !=-1) {
      # 	  unlink @$filesToUpload;
      # }
      
  }else {
      say "Unable to find newsup.conf file. Please check if the environment variable HOME is installed!";
  }
}



sub pre_process_folder{
  say "Pre Processing the input";
  my $folder=shift;
  my $configs=shift;
  my $DEBUG = shift;
  my @files = ();
  
  if ($configs->{ENABLE_RAR_COMPRESSION} > 0) {

    my $args = $configs->{EXTRA_ARGS_TO_RAR}.' "'.$configs->{TEMP_DIR}.'/'.basename($folder).".rar\" \"$folder\"";
    my $invoke = '"'.$configs->{PATH_TO_RAR}.'" '.$args;
    $invoke =~ s/\/\//\//g;
    say "Invoking: $invoke" if $DEBUG;
    my $output = qx/$invoke/;
    while ($output =~ /Creating archive (.*\.rar|.*\.[r-z]\d+)/g) {
      my $archive = $1;
      if ($archive =~ /part0{0,4}2\.rar/) {
	(my $missingArchive = $archive) =~ s/2\.rar/1\.rar/; 
	push @files, $missingArchive if (-e $missingArchive);
      }
      push @files, $archive if (-e $archive);
    }

  }else {

    find(sub{
	   if (-f) {
	     my $newName = $File::Find::name;
	     push @files, $newName;
	   }
	 }, ($folder))
  }

  return \@files;
}

sub create_sfv_file{
  say "Creating SFV file";
  my $sfvFileName = shift;
  my $preProcessedFiles=shift;
  my $configs=shift;
  my $DEBUG = shift;

  my $sfv_file=$configs->{TEMP_DIR};
  $sfv_file .= "/" if substr($sfv_file,-1,1) ne '/';
  $sfv_file = "$sfv_file$sfvFileName.sfv";
  open my $ofh, '>', $sfv_file or die "Unable to create sfv file!";
#  binmode $ofh;

  for (@$preProcessedFiles) {
    my $file = $_;
    my $fileName=(fileparse($file))[0];
    open my $ifh, '<', $file or die "Couldn't open file $file : $!";
    binmode $ifh;
    my $crc32 = 0;
    while (read ($ifh, my $input, 512*1024)!=0) {
      $crc32 = crc32($input,$crc32);
    }

    say sprintf("%s %08x",$fileName, $crc32) if $DEBUG;
    print $ofh sprintf("%s %08x\r\n",$fileName, $crc32);
    close $ifh;
  }

  close $ofh;
  return $sfv_file;
}

sub create_parity_archives{
  say "Creating Partity archives";
  my $folder=shift;
  my $preProcessedFiles=shift;
  my $configs=shift;
  my $forceRename=shift;
  my $DEBUG = shift;

  my @escapedFiles=();
  push @escapedFiles, "\"$_\"" for @$preProcessedFiles;

  
  my $args = $configs->{EXTRA_ARGS_TO_PAR2}.' "'.$configs->{TEMP_DIR}.'/'.basename($folder).'.par2" '.join(' ',@escapedFiles).'';
  
  my $invoke = '"'.$configs->{PATH_TO_PAR2}.'" '.$args;
  $invoke =~ s/\/\//\//g;
  say "Invoking: $invoke" if $DEBUG;
  my $output = qx/$invoke/;

  my @parity_files=();
  opendir my $dh, $configs->{TEMP_DIR} or die "Cannot enter the temp folder '".$configs->{TEMP_DIR}."'\n$@";
  while (readdir $dh) {
    push @parity_files, $configs->{TEMP_DIR}."/$_" if($_ =~ /.*par2$/);
  }
  closedir $dh;

  if ($forceRename) {
    unlink (pop @$preProcessedFiles);
  }
  
  return @parity_files;
  
}


sub upload_files{
  my ($preProcessedFiles, $configs, $extra_args, $DEBUG) = @_;

  if (@$preProcessedFiles) {
    my @escapedFiles=();
    push @escapedFiles, "\"$_\"" for @$preProcessedFiles;

    my $args = '';
    $args .=  $configs->{EXTRA_ARGS_TO_UPLOADER}.' ' if $configs->{EXTRA_ARGS_TO_UPLOADER} ne '';
    $args .= "$extra_args -f ".join(' -f ', @escapedFiles);
    my $invoke = $configs->{PATH_TO_UPLOADER}.' '.$args;
    $invoke =~ s/\/\//\//g;
    say "$invoke" if $DEBUG;
    system($invoke);
  }
}



sub randomize_archives{
  say "Randomize archives";
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


sub help{
  say << "END";
This program is part of NewsUP.

The goal of this program is to make your uploading more easy.

This is an auxiliary script that will compress and/or split the files to be uploaded, 
create the parity files, create sfv files and finally invoke the newsup to upload the
files.

Options available:
\t-directory <folder> = the directory to upload

\t-debug = to show debug messages. Usefull when you're configuring the switches on the several 
\t\tprograms that this invokes.

\t-args <extra args> = extra args to be passed to newsup. Usually they need to be between double quotes ('"')

\t-delete = if you want the temporary folder (the folder where the compressed/split and pars are
\t\tgoing to be created) deleted.

\t-group <group> = group to where you want to upload. You can have multiple `group` switches.

\t-sfv = if you want a sfv to be generated.

\t-nfo <.NFO> = if you have a NFO to be uploaded. Usually the .nfo files aren't inside of the rars, so 
\t\tthey live somewhere else in the filesystem.

\t-force_rename = option that is used in the IRC bot. 

\t-rename = the same as `force_rename`

END

exit 0;
  
}


main();
