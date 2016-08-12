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
use File::Spec::Functions qw/splitdir catfile/;
use File::Find;
use File::Copy::Recursive qw/rcopy/;
$File::Copy::Recursive::CPRFComp=1;
use File::Copy qw/cp/;
use File::Path qw/remove_tree/;
use File::Basename;


my @VIDEO_EXTENSIONS = qw/.avi .mkv .mp4/;



sub main2{
	my %OPTIONS=(delete=>1);

	GetOptions(
		'help'=>sub{help();},
		#Options in the config file
		'create_sfv!'=>\$OPTIONS{create_sfv},
		'group=s@'=>\$OPTIONS{group},
		'archive!'=>\$OPTIONS{archive},
		'par!'=>\$OPTIONS{par},
		'save_nzb!'=>\$OPTIONS{save_nzb},
		'rename_par!'=>\$OPTIONS{rename_par},
		'reverse!'=>\$OPTIONS{reverse},
		'force_repair!'=>\$OPTIONS{force_repair},
		'upload_nzb!'=>\$OPTIONS{upload_nzb},
		#'force_rename|rename!'=>\$FORCE_RENAME
		#OptionsAtRuntime
		'directory=s'=>\$OPTIONS{directory},
		'debug!'=>\$OPTIONS{debug},
		'args=s'=>\$OPTIONS{args},
		'delete!'=>\$OPTIONS{delete},
		'nfo=s'=>\$OPTIONS{nfo},
		'name=s@'=>\$OPTIONS{name},
		);
		if(!defined $OPTIONS{directory}){
			say 'You need to configure the switch -directory to point to a valid directory';
			exit 0;
		}
		$OPTIONS{debug}=0 if(!defined $OPTIONS{debug});
		$OPTIONS{args}='' if(!defined $OPTIONS{args});
		$OPTIONS{delete}=0 if(!defined $OPTIONS{delete});
		$OPTIONS{name}=[] if(!defined $OPTIONS{name});
		$OPTIONS{nfo}='' if(!defined $OPTIONS{nfo});
		
		%OPTIONS= %{_load_options(\%OPTIONS)};
	
		
		#Algorithm Steps:
		#1- copy the folder to the tmp_dir
		#2- search for files to rename.
		#3- create a Rename.with.this.par2 for the files in 2.
		#4- rename files in 2
		#5- reverse names
		#6- rar the files
		#7- copy the nfo to the rar location
		#8- create sfv
		#9- par the rars and the nfo
		#10- delete the nfo
		#11- upload rars and pars
		#12- upload nzb
		
		#step 1
		rcopy($OPTIONS{directory}, $OPTIONS{temp_dir}) or die "Unable to copy files to the temp dir: $!";
	
		#step 2,3 and 4
		my @folders = splitdir( $OPTIONS{directory} );
		pop @folders if($folders[-1] eq '');
		my $dir = $OPTIONS{temp_dir}.'/'.$folders[-1];
		push @{$OPTIONS{name}}, '' if scalar @{$OPTIONS{name}} == 0;
		
		my $file_list = [];
		my $counter = 0;
		for my $name (@{$OPTIONS{name}}){
			$dir = rename_files($name, $dir,\%OPTIONS);
		
			#step 5
			reverse_filenames($dir, \%OPTIONS);
			
			#step 6
			$file_list = archive_files($name, $dir, \%OPTIONS);
			
			#step 7
			if(defined $OPTIONS{nfo} && $OPTIONS{nfo} ne ''){
				my $filename = fileparse($OPTIONS{nfo});
				cp($OPTIONS{nfo}, $OPTIONS{temp_dir}) or die "Error copying the NFO file: $!";
				push @$file_list, catfile($OPTIONS{temp_dir},$filename);
			}
			
			#step 8
			$file_list = create_sfv($name, $file_list, \%OPTIONS);
			
			#step 9
			$file_list = par_files($name, $file_list, \%OPTIONS);
			
			#step 10
			$file_list = force_repair($file_list, \%OPTIONS);

			#step 11
			my $nzb = upload_file_list($name, $file_list, \%OPTIONS);
			say Dumper("NZB to be removed: $nzb");
			cp($nzb, $OPTIONS{save_nzb_path}) or warn "Unable to copy the NZB file: $!" if($OPTIONS{save_nzb});
			
			if($counter++ == 0){
				#step 12
				upload_file_list($name, [$nzb], \%OPTIONS) if($OPTIONS{upload_nzb});
				push @$file_list, $nzb;
			}
			
			#newsup specific
			unlink catfile($OPTIONS{temp_dir},$nzb);
		}
		#step 14
		if($OPTIONS{delete}){
			unlink @$file_list;
		}
		remove_tree($dir);
		

}

sub upload_file_list{
	my ($name, $file_list, $OPTIONS) = @_;
	
	my $CMD = $OPTIONS->{uploader}.' ';
	$CMD .= $OPTIONS->{args}.' ';
	$CMD .= "-group $_ " for (@{$OPTIONS->{group}});
	$CMD .= '-file '.quotemeta($_).' ' for (@$file_list);
	
	if($name eq ''){
		my @folders = splitdir( $OPTIONS->{directory} );
		pop @folders if($folders[-1] eq '');
		$name = $folders[-1];
	}
	
	$name .= '.nzb';
	$CMD .= '-nzb '.quotemeta($name).' ';
	
	say $CMD if $OPTIONS->{debug};
	my @CMD_output = `$CMD`;
	for(@CMD_output){
		print $_ if /speed|headercheck|nzb|error|exception/i;
	}
	
	return $name;
}

sub force_repair{
	my ($file_list, $OPTIONS) = @_;
	return $file_list if(!defined $OPTIONS->{force_repair} || !$OPTIONS->{force_repair});
	
	my @new_file_list = ();
	
	for(@$file_list){
		if($_ =~ /.nfo$/i){
			unlink $_;
		}else{
			push @new_file_list, $_;
		}
	}
	
	return \@new_file_list;
}

sub par_files{
	my ($name, $file_list, $OPTIONS) = @_;
	return $file_list if(!defined $OPTIONS->{par} || !$OPTIONS->{par});
	
	
	if($name eq ''){
		my @folders = splitdir( $OPTIONS->{directory} );
		pop @folders if($folders[-1] eq '');
		$name = $folders[-1];
	}
	
	my $par_name = quotemeta(catfile($OPTIONS->{temp_dir}, $name));
	
	my $CMD = $OPTIONS->{par_arguments}." $par_name " ;
	for(@$file_list){
		$CMD .= quotemeta($_).' ';
	}
	
	say $CMD if $OPTIONS->{debug};
	
	my $CMD_output = `$CMD`;
	say $CMD_output if $OPTIONS->{debug};
	
	opendir my $dh, $OPTIONS->{temp_dir} or die 'Couldn\'t open \''.$OPTIONS->{temp_dir}."' for reading: $!";
	my $regexp = qr/$OPTIONS->{par_filter}/;
	while(my $file = readdir $dh){
		push @$file_list, catfile($OPTIONS->{temp_dir}, $file) if($file =~ /$regexp/);
	}
	closedir $dh;
	
	return $file_list;
}

sub create_sfv{
	my ($name, $files, $OPTIONS) = @_;
	return $files if(!$OPTIONS->{create_sfv});
	
	my $sfv_file = $name;
	
	if($sfv_file eq '' || !defined $sfv_file){
		my @folders = splitdir( $OPTIONS->{directory} );
		pop @folders if($folders[-1] eq '');
		$sfv_file = $folders[-1];
	}
	
	# TODO
	# We can't reuse the old SFV, because the content will be different.
	opendir my $dh, $OPTIONS->{temp_dir} or die 'Couldn\'t open \''.$OPTIONS->{temp_dir}."' for reading: $!";
	while(my $file = readdir $dh){
		if($file =~ /sfv$/){
			my $old_sfv_filename = catfile($OPTIONS->{temp_dir}, $file);
			unlink $old_sfv_filename;
			last;
		}
		
	}
	closedir $dh;
	
	open my $ofh, '>', catfile($OPTIONS->{temp_dir},"$sfv_file.sfv") or die 'Unable to create sfv file!';
  #  binmode $ofh;
  
	for (@$files) {
	  my $file = $_;
	  my $fileName=(fileparse($file))[0];
	  open my $ifh, '<', $file or die "Couldn't open file $file : $!";
	  binmode $ifh;
	  my $crc32 = 0;
	  while (read ($ifh, my $input, 512*1024)!=0) {
		$crc32 = crc32($input,$crc32);
	  }
  
	  say sprintf('%s %08x',$fileName, $crc32) if $OPTIONS->{debug};
	  print $ofh sprintf('%s %08x\r\n',$fileName, $crc32);
	  close $ifh;
	}
  
	close $ofh;
	push @$files, catfile($OPTIONS->{temp_dir},"$sfv_file.sfv");
	return $files;	

}

sub archive_files{
	my ($name, $dir, $OPTIONS) = @_;
	return [$dir] if(!$OPTIONS->{archive});
	
	if($name eq ''){
		my @folders = splitdir( $OPTIONS->{directory} );
		pop @folders if($folders[-1] eq '');
		
		#TODO fix the .rar part. This is only for rar compression
		$name = $folders[-1].'.rar';
	}
	
	my $CMD=$OPTIONS->{archive_arguments}.' '.quotemeta(catfile( $OPTIONS->{temp_dir}, $name)).' '.quotemeta($dir);
	$CMD.=" ".quotemeta($OPTIONS->{nfo}) if(defined $OPTIONS->{nfo} && $OPTIONS->{nfo} ne '' && -e $OPTIONS->{nfo});
	say $CMD if $OPTIONS->{debug};
	my $CMD_output = `$CMD`;
	say $CMD_output if $OPTIONS->{debug};
	
	my @archived_files = ();
	my $regexp = qr/$OPTIONS->{archive_filter}/;
	opendir my $dh, $OPTIONS->{temp_dir} or die 'Couldn\'t open \''.$OPTIONS->{temp_dir}."' for reading: $!";
	while(my $file = readdir $dh){
		push @archived_files, catfile($OPTIONS->{temp_dir}, $file) if($file =~ /$regexp/);
	}
	closedir $dh;
	
	return \@archived_files;
}

sub reverse_filenames{
	my ($dir, $OPTIONS) = @_;
	return if(!$OPTIONS->{reverse});

	my $regexp = qr/$OPTIONS->{files_filter}/;
	my @matched_files = ();
	find(sub{
		if($File::Find::name =~ /$regexp/){
			push @matched_files, $File::Find::name;
		}
		}, ($dir));
	
	for my $file (@matched_files){
		my($filename, $dirs, $suffix) = fileparse($file, qr/\.[^.]*$/);
		rename $file, $dirs.scalar (reverse ($filename)).$suffix;
	}
}

sub rename_files{
	my ($name, $dir, $OPTIONS) = @_;

	return $dir if(!$OPTIONS->{rename_par});
	my $regexp = qr/$OPTIONS->{files_filter}/;
	
	my @matched_files = ();
	find(sub{
		if($File::Find::name =~ /$regexp/){
			push @matched_files, quotemeta($File::Find::name);
		}
		}, ($dir));
	
	my $CMD = $OPTIONS->{rename_par_arguments}.' '.quotemeta("$dir/Rename.with.this.par2 ").join(' ', @matched_files);
	say $CMD if $OPTIONS->{debug};
	
	my $CMD_output = `$CMD`;
	say $CMD_output if $OPTIONS->{debug};
	
	my $i=0;
	for my $file (@matched_files){
		my($filename, $dirs, $suffix) = fileparse($file, qr/\.[^.]*$/);
		my $newName = 'Use.the.renaming.par';
		if($name ne ''){
			$newName=$name;
		}
		$newName.=$i if($i++>0);
		$newName.=$suffix;
		rename $dirs.$filename.$suffix, $dirs.$newName;
	}
	
	my $new_dirname = (fileparse($dir))[1].$OPTIONS->{name} if($name ne '');
	rename $dir, $new_dirname;
	return $new_dirname;
}



sub _load_options{
	my %OPTIONS =  %{shift @_};

	if (defined $ENV{HOME} && -e $ENV{HOME}.'/.config/newsup.conf') {
		my $config = Config::Tiny->read( $ENV{HOME}.'/.config/newsup.conf' );

		if(!defined $config){
			say 'Error while reading the config file:';
			say Config::Tiny->errstr;
			exit 0;
		}

		my %other_configs = %{$config->{uploadit}};
		
		for my $key (keys(%other_configs)){
			if(!exists $OPTIONS{$key}){
				$OPTIONS{$key} = $other_configs{$key};
			}elsif(!defined $OPTIONS{$key} && $other_configs{$key} ne ''){
				$OPTIONS{$key}=$other_configs{$key} == 1?1:0;	
			}
		}
		
		#if(!defined $OPTIONS{create_sfv} && $other_configs{create_sfv} ne ''){
		#	$OPTIONS{create_sfv}=$other_configs{create_sfv} == 1?1:0;
		#}
		#if(!defined $OPTIONS{archive} && $other_configs{archive} ne ''){
		#	$OPTIONS{archive}=$other_configs{archive} == 1?1:0;
		#}
		#if(!defined $OPTIONS{par} && $other_configs{par} ne ''){
		#	$OPTIONS{par}=$other_configs{par} == 1?1:0;
		#}
		#if(!defined $OPTIONS{save_nzb} && $other_configs{save_nzb} ne ''){
		#	$OPTIONS{save_nzb}=$other_configs{save_nzb} == 1?1:0;
		#}		
		#if(!defined $OPTIONS{rename_par} && $other_configs{rename_par} ne ''){
		#	$OPTIONS{rename_par}=$other_configs{rename_par} == 1?1:0;
		#}
		#if(!defined $OPTIONS{reverse} && $other_configs{reverse} ne ''){
		#	$OPTIONS{reverse}=$other_configs{reverse} == 1?1:0;
		#}
		#if(!$OPTIONS{force_repair} && $other_configs{force_repair} ne ''){
		#	$OPTIONS{force_repair}=$other_configs{force_repair} == 1?1:0;
		#}
		#if(!$OPTIONS{upload_nzb} && $other_configs{upload_nzb} ne ''){
		#	$OPTIONS{upload_nzb}=$other_configs{upload_nzb} == 1?1:0;
		#}
		
	}
	
	if (!defined $OPTIONS{directory} || $OPTIONS{directory}  eq '' || !-e $OPTIONS{directory} ) {
		my @possible_folders = split(/,/,$OPTIONS{upload_root});
		my $found = 0;
		for my $folder (@possible_folders){
			if(-e catfile($folder,$OPTIONS{directory})){
				$found=1;
				$OPTIONS{directory}=catfile($folder,$OPTIONS{directory});
				last;
			}
		}
		if(!$found){
			say 'You need to configure the switch -directory to point to a valid directory';
			exit 0;
		}
	}
	
	if (!exists $OPTIONS{temp_dir} || $OPTIONS{temp_dir}  eq '' || !-e $OPTIONS{temp_dir} ) {
		say 'You need to configure the option temp_dir in the configuration file';
		exit 0;

	}
	
	return \%OPTIONS;
}

main2();
#
#
#
#
#
#
#
#
#sub main{
#  my $DIRECTORY='';
#  my $NAME='';
#  my @GROUPS=();
#  my $DEBUG=0;
#  my $CREATE_NFO=0;
#  my $UP_ARGS='';
#  my $DELETE=1;
#  my $FORCE_RENAME=0;
#  my $SFV=0;
#  my $NFO;
#
#  GetOptions('help'=>sub{help();},
#	     'directory=s'=>\$DIRECTORY,
#	     'debug!'=>\$DEBUG,
#	     'args=s'=>\$UP_ARGS,
#	     'delete!'=>\$DELETE,
#		'createNFO!'=>\$CREATE_NFO,
#	     'group=s'=>\@GROUPS,
#	     'sfv!'=>\$SFV,
#	     'nfo=s'=>\$NFO,
#	     'force_rename|rename!'=>\$FORCE_RENAME);
#
#  $UP_ARGS .=' ' if $UP_ARGS ne '';
#  $UP_ARGS .="-group ".join(' -group ', @GROUPS) if @GROUPS;
#
#  if ($DIRECTORY eq '' || !-e $DIRECTORY ) {
#
#    say "You need to configure the switch -directory";
#    exit 0;
#
#  }
#
#  if (defined $ENV{"HOME"} && -e $ENV{"HOME"}.'/.config/newsup.conf') {
#    my $config = Config::Tiny->read( $ENV{"HOME"}.'/.config/newsup.conf' );
#
#    if(!defined $config){
#      say "Error while reading the config file:";
#      say Config::Tiny->errstr;
#      exit 0;
#    }
#
#    my %other_configs = %{$config->{other}};
#
#
#    if (! -e $other_configs{PATH_TO_RAR} && $other_configs{ENABLE_RAR_COMPRESSION} == 1) {
#	     say "You need to define a valid path to the rar program. Please change the variable RAR_PATH on the newsup.conf file.";
#	      exit 0;
#    }
#    if (exists $other_configs{ENABLE_PAR_CREATION} && $other_configs{ENABLE_PAR_CREATION} && !-e $other_configs{PATH_TO_PAR2}) {
#      say "You need to define a valid path to par2repair program. Please change the variable PATH_TO_PAR2 on the newsup.conf file.";
#	    exit 0;
#	  }
#
#    if (!$SFV) {
#      $SFV=1 if (exists $other_configs{ENABLE_SFV_GENERATION} && $other_configs{ENABLE_SFV_GENERATION});
#    }
#
#
#    # say "Splitting files!";
#    my $preProcessedFiles = pre_process_folder ($DIRECTORY, \%other_configs, $DEBUG, $CREATE_NFO);
#    say Dumper($preProcessedFiles) if $DEBUG;
#
#    push @$preProcessedFiles, create_sfv_file(basename($DIRECTORY), $preProcessedFiles, \%other_configs, $DEBUG) if ($other_configs{ENABLE_SFV_GENERATION});
#    say Dumper($preProcessedFiles) if $DEBUG;
#
#
#    if (defined $NFO && -e $NFO) {
#	     push @$preProcessedFiles, $NFO;
#
#    }elsif (!defined $NFO && defined $other_configs{NFO_FILE} && $other_configs{NFO_FILE}) {
#	    my($filename, $dirs, $suffix) = fileparse($other_configs{NFO_FILE}, '.nfo');
#
#    	cp($other_configs{NFO_FILE}, $other_configs{TEMP_DIR});
#    	push @$preProcessedFiles, $other_configs{TEMP_DIR}."/$filename.nfo";
#    }else {
#	     $FORCE_RENAME=0;
#    }
#
#    push @$preProcessedFiles, create_parity_archives($DIRECTORY, $preProcessedFiles, \%other_configs,$FORCE_RENAME, $DEBUG) if ($other_configs{ENABLE_PAR_CREATION});
#    say Dumper($preProcessedFiles) if $DEBUG;
#    upload_files($preProcessedFiles, \%other_configs, $UP_ARGS, $DEBUG);
#
#    my $remove_regexp = $other_configs{TEMP_DIR};
#
#
#    for my $file (@$preProcessedFiles) {
#
#  	  my (undef, $path, undef) = fileparse($file);
#  	  if ($DELETE) {
#  	    if ($file =~ /$remove_regexp/ && index($path, $DIRECTORY)!=0) {
#  	      unlink $file;
#  	      say "Removing $file" if $DEBUG;
#  	    }
#  	  }else {
#  	    say "Uploaded files: $file";
#  	  }
#    }
#      # say "Creating parity files";
#      # my $filesToUpload = create_parity_archives($checkSumFiles, \%script_vars);
#
#      # randomize_archives($checkSumFiles, \%script_vars);
#
#      # say "Starting upload";
#      # upload_files($filesToUpload,\%script_vars);
#      # if ($script_vars{RAR_COMPRESSION} !=-1) {
#      # 	  unlink @$filesToUpload;
#      # }
#
#  }else {
#      say "Unable to find newsup.conf file. Please check if the environment variable HOME is installed!";
#  }
#}
#
#
#
#sub pre_process_folder{
#  say "Pre Processing the input";
#  my $folder=shift;
#  my $configs=shift;
#  my $DEBUG = shift;
#  my @files = ();
#  my $CREATE_NFO = shift;
#
#  if($CREATE_NFO){
#    create_nfo($folder);
#  }
#
#  if ($configs->{ENABLE_RAR_COMPRESSION} > 0) {
#
#    my $args = $configs->{EXTRA_ARGS_TO_RAR}.' "'.$configs->{TEMP_DIR}.'/'.basename($folder).".rar\" \"$folder\"";
#    my $invoke = '"'.$configs->{PATH_TO_RAR}.'" '.$args;
#    $invoke =~ s/\/\//\//g;
#    say "Invoking: $invoke" if $DEBUG;
#    my $output = qx/$invoke/;
#    while ($output =~ /Creating archive (.*\.rar|.*\.[r-z]\d+)/g) {
#      my $archive = $1;
#      if ($archive =~ /part0{0,4}2\.rar/) {
#	(my $missingArchive = $archive) =~ s/2\.rar/1\.rar/;
#	push @files, $missingArchive if (-e $missingArchive);
#      }
#      push @files, $archive if (-e $archive);
#    }
#
#  }else {
#
#    find(sub{
#	   if (-f) {
#	     my $newName = $File::Find::name;
#	     push @files, $newName;
#	   }
#	 }, ($folder))
#  }
#
#  return \@files;
#}
#
##TODO: incorporate o simpleMovieNFOCreator
#sub create_nfo{
#  my $folder = shift;
#
#  find(sub{
#   if (-f $_) {
#     $_ =~ /(\.[^.]*)$/;
#     my $ext = $1;
#     for my $e (@VIDEO_EXTENSIONS){
#       if($ext =~ /$e/){
#          my $name = $File::Find::name;
#          `simpleMovieNFOCreator $name`
#       }
#     }
#   }
# }, ($folder))
#
#
#}
#
#sub create_sfv_file{
#  say "Creating SFV file";
#  my $sfvFileName = shift;
#  my $preProcessedFiles=shift;
#  my $configs=shift;
#  my $DEBUG = shift;
#
#  my $sfv_file=$configs->{TEMP_DIR};
#  $sfv_file .= "/" if substr($sfv_file,-1,1) ne '/';
#  $sfv_file = "$sfv_file$sfvFileName.sfv";
#  open my $ofh, '>', $sfv_file or die "Unable to create sfv file!";
##  binmode $ofh;
#
#  for (@$preProcessedFiles) {
#    my $file = $_;
#    my $fileName=(fileparse($file))[0];
#    open my $ifh, '<', $file or die "Couldn't open file $file : $!";
#    binmode $ifh;
#    my $crc32 = 0;
#    while (read ($ifh, my $input, 512*1024)!=0) {
#      $crc32 = crc32($input,$crc32);
#    }
#
#    say sprintf("%s %08x",$fileName, $crc32) if $DEBUG;
#    print $ofh sprintf("%s %08x\r\n",$fileName, $crc32);
#    close $ifh;
#  }
#
#  close $ofh;
#  return $sfv_file;
#}
#
#sub create_parity_archives{
#  say "Creating Partity archives";
#  my $folder=shift;
#  my $preProcessedFiles=shift;
#  my $configs=shift;
#  my $forceRename=shift;
#  my $DEBUG = shift;
#
#  my @escapedFiles=();
#  push @escapedFiles, "\"$_\"" for @$preProcessedFiles;
#
#
#  my $args = $configs->{EXTRA_ARGS_TO_PAR2}.' "'.$configs->{TEMP_DIR}.'/'.basename($folder).'.par2" '.join(' ',@escapedFiles).'';
#
#  my $invoke = '"'.$configs->{PATH_TO_PAR2}.'" '.$args;
#  $invoke =~ s/\/\//\//g;
#  say "Invoking: $invoke" if $DEBUG;
#  my $output = qx/$invoke/;
#
#  my @parity_files=();
#  opendir my $dh, $configs->{TEMP_DIR} or die "Cannot enter the temp folder '".$configs->{TEMP_DIR}."'\n$@";
#  while (readdir $dh) {
#    push @parity_files, $configs->{TEMP_DIR}."/$_" if($_ =~ /.*par2$/);
#  }
#  closedir $dh;
#
#  if ($forceRename) {
#    unlink (pop @$preProcessedFiles);
#  }
#
#  return @parity_files;
#
#}
#
#
#sub upload_files{
#  my ($preProcessedFiles, $configs, $extra_args, $DEBUG) = @_;
#
#  if (@$preProcessedFiles) {
#    my @escapedFiles=();
#    push @escapedFiles, "\"$_\"" for @$preProcessedFiles;
#
#    my $args = '';
#    $args .=  $configs->{EXTRA_ARGS_TO_UPLOADER}.' ' if $configs->{EXTRA_ARGS_TO_UPLOADER} ne '';
#    $args .= "$extra_args -f ".join(' -f ', @escapedFiles);
#    my $invoke = $configs->{PATH_TO_UPLOADER}.' '.$args;
#    $invoke =~ s/\/\//\//g;
#    say "$invoke" if $DEBUG;
#    system($invoke);
#  }
#}
#
#
#
#sub randomize_archives{
#  say "Randomize archives";
#  my ($compressedFiles,$scriptVarsRef) = @_;
#
#  return $compressedFiles if ($scriptVarsRef->{RANDOMIZE_NAMES}==0 || @$compressedFiles > 1);
#
#  my @notParityFiles = ();
#  for (@$compressedFiles) {
#    push @notParityFiles, $_ if (!/.*par2$/);
#  }
#  for (0..int(rand(@notParityFiles))) {
#    my $number1 = int(rand(@notParityFiles));
#    my $number2 = int(rand(@notParityFiles));
#    $number2 = int(rand(@notParityFiles)) while ($number2 == $number1);
#
#    my $time = time();
#    my $file1 = $notParityFiles[$number1];
#    my $file2 = $notParityFiles[$number2];
#    mv($file1, "$file1.$time");
#    mv($file2, $file1);
#    mv("$file1.$time", $file1);
#  }
#  return $compressedFiles;
#}


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


#main();
