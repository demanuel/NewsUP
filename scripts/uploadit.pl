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
use Compress::Zlib;
use File::Spec::Functions qw/splitdir catfile/;
use File::Find;
use File::Copy::Recursive qw/rcopy/;
$File::Copy::Recursive::CPRFComp=1;
use File::Copy qw/cp mv/;
use File::Path qw/remove_tree/;
use File::Basename;


my @VIDEO_EXTENSIONS = qw/.avi .mkv .mp4/;



sub main{
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
		$OPTIONS{delete}=1 if(!defined $OPTIONS{delete});
		$OPTIONS{name}=[] if(!defined $OPTIONS{name});
		$OPTIONS{nfo}='' if(!defined $OPTIONS{nfo});
		
		%OPTIONS= %{_load_options(\%OPTIONS)};
		
		#Algorithm Steps:
		#1- copy the folder to the tmp_dir
		#2- Copy the ads folder
		#3- search for files to rename.
		#4- create a Rename.with.this.par2 for the files in 2.
		#5- rename files in 2
		#6- reverse names
		#7- rar the files
		#8- copy the nfo to the rar location
		#9- create sfv
		#10- par the rars and the nfo
		#11- delete the nfo
		#12- upload rars and pars
		#13- copy the nzb to the right place
		#14- upload nzb
		
		# Invalid options:
		# Uploading only 1 file with renaming_par option set
		if(-f $OPTIONS{directory} && $OPTIONS{rename_par}){
			say "Invalid Option! Not possible to have only 1 file and use -rename_par. Please upload a folder instead";
			exit 0;
		}
		
		#step 1
		rcopy($OPTIONS{directory}, $OPTIONS{temp_dir}) or die "Unable to copy files to the temp dir: $!";
	
		
		my @folders = splitdir( $OPTIONS{directory} );
		pop @folders if($folders[-1] eq '');
		
		my $dir = catfile($OPTIONS{temp_dir},$folders[-1]);
		
		#step 2
		if(exists $OPTIONS{ads_folder} && defined $OPTIONS{ads_folder} && $OPTIONS{ads_folder} ne ''){
			opendir my $dh, $OPTIONS{ads_folder};
			while(readdir $dh){
				rcopy(catfile($OPTIONS{ads_folder},$_),$dir) if $_ ne '..' && $_ ne '.';
			}
			closedir $dh;
		}
		
		
		push @{$OPTIONS{name}}, '' if scalar @{$OPTIONS{name}} == 0;
		my $fileList = [];
		my $isFirstUpload=1;
		my $previousName = '';#variable to indicate the name of the previous upload, so we can avoid recreating the archives and the pars
		for my $name (@{$OPTIONS{name}}){
			#step 3,4 and 5
			$dir = rename_files($name, $dir,\%OPTIONS);
			
			#step 6
			$dir = reverse_filenames($dir, \%OPTIONS);
			
			#step 7
			if($isFirstUpload){
				$fileList = archive_files($name, $dir, \%OPTIONS);
			}else{
				$fileList = rename_archived_files($previousName, $name, $dir, \%OPTIONS);
			}
			
			#step 8
			if(defined $OPTIONS{nfo} && $OPTIONS{nfo} ne ''){
				my $filename = fileparse($OPTIONS{nfo});
				cp($OPTIONS{nfo}, $OPTIONS{temp_dir}) or die "Error copying the NFO file: $!";
				push @$fileList, catfile($OPTIONS{temp_dir},$filename);
			}
			
			#step 9
			$fileList = create_sfv($name, $fileList, \%OPTIONS);
			
			if($isFirstUpload){
				#step 10
				$fileList = par_files($name, $fileList, \%OPTIONS);
			}else{
				# step 10
				$fileList = rename_par_files($previousName, $name, $fileList, \%OPTIONS);
			}
			
			#step 11
			$fileList = force_repair($fileList, \%OPTIONS);

			#step 12
			my $nzb = undef;

			# Sometimes newsup fails in the authentication phase because of:
			# *- The USP takes time to reap "not being in use" sessions
			# *- The reasons indicated in http://search.cpan.org/~sullr/IO-Socket-SSL-2.038/lib/IO/Socket/SSL.pod#Common_Problems_with_SSL
			while(1){
				$nzb = upload_file_list($name, $fileList, \%OPTIONS);
				last if -e $nzb;
				sleep 15;
			}
			
			#step 13
			cp($nzb, catfile($OPTIONS{save_nzb_path}, $folders[-1]."_$name.nzb")) or warn "Unable to copy the NZB file: $!" if($OPTIONS{save_nzb});
			
			if($isFirstUpload && $OPTIONS{upload_nzb}){
				#step 14
				# Sometimes newsup fails in the authentication phase.
				# Please check comment above on the normal upload
				my $tempNzb=undef;
				while(1){
					$tempNzb = upload_file_list('', [$nzb], \%OPTIONS);
					last if -e $tempNzb;
					sleep 15;
				}
				unlink $tempNzb ;
				$isFirstUpload=0;
			}
			
			#newsup specific
			unlink $nzb;
			
			$previousName = $name;
		}
		
		if($OPTIONS{delete}){
			unlink @$fileList;
		}
		remove_tree($dir);
		
}

sub upload_file_list{
	my ($name, $fileList, $OPTIONS) = @_;
	
	my $CMD = $OPTIONS->{uploader}.' ';
	$CMD .= $OPTIONS->{args}.' ';
	$CMD .= "-group $_ " for (@{$OPTIONS->{group}});
	$CMD .= '-file "'.$_.'" ' for (@$fileList);
	
	if($name eq ''){
		my @folders = splitdir( $OPTIONS->{directory} );
		pop @folders if($folders[-1] eq '');
		$name = $folders[-1];
	}
	
	my $infoName = $name;
	$name .= '.nzb';
	$CMD .= '-nzb "'.$name.'" ';
	
	warn $CMD if $OPTIONS->{debug};
	
	if($^O eq 'linux'){
		open my $ofh , '-|', $CMD or die "Unable to launch process: $!";
		while(my $line = <$ofh>){
			$line =~ s/^.*\r//;
			print "$infoName: $line" if $line =~ /speed|headercheck|error|exception/i;
		}
		close $ofh;
	}elsif($^O eq 'MSWin32'){
		my @commandOutput=qx/$CMD/;
		for my $line (@commandOutput){
			$line =~ s/^.*\r//;
			print "$infoName: $line" if $line =~ /speed|headercheck|error|exception/i;
		}
	}
	
	#my @CMD_output = `$CMD`;
	#for(@CMD_output){
	#	print $_ if /speed|headercheck|nzb|error|exception/i;
	#}
	
	return $name;
}

sub force_repair{
	my ($fileList, $OPTIONS) = @_;
	return $fileList if(!defined $OPTIONS->{force_repair} || !$OPTIONS->{force_repair});
	
	my @newFileList = ();
	
	for(@$fileList){
		if($_ =~ /.nfo$/i){
			unlink $_;
		}else{
			push @newFileList, $_;
		}
	}
	
	return \@newFileList;
}

sub rename_par_files{
	my ($previousName, $name, $fileList, $OPTIONS) = @_;
	return $fileList if(!defined $OPTIONS->{par} || !$OPTIONS->{par});
	
	my @parFiles = @$fileList;
	my $regexp = qr/$OPTIONS->{par_filter}/;
	my $previousNameRegexp = qr/$previousName/;
	
	opendir my $dh, $OPTIONS->{temp_dir} or die 'Couldn\'t open \''.$OPTIONS->{temp_dir}."' for reading: $!";
	while(my $file = readdir $dh){
		if($file =~ /$regexp/ && $file =~ /$previousName/){
			my $oldFilename = catfile($OPTIONS->{temp_dir}, $file);
			(my $newFilename = $oldFilename) =~ s/$previousName/$name/;
			rename($oldFilename, $newFilename);
			push @parFiles, $newFilename;
		}
	}
	closedir $dh;
	
	return \@parFiles;
}

sub par_files{
	my ($name, $fileList, $OPTIONS) = @_;
	return $fileList if(!defined $OPTIONS->{par} || !$OPTIONS->{par});
	
	
	if($name eq ''){
		my @folders = splitdir( $OPTIONS->{directory} );
		pop @folders if($folders[-1] eq '');
		$name = $folders[-1];
	}
	
	my $par_name = '"'.catfile($OPTIONS->{temp_dir}, $name).'"';
	
	my $CMD = $OPTIONS->{par_arguments}." -B \"".$OPTIONS->{temp_dir}."\" $par_name " ;
	for(@$fileList){
		$CMD .= '"'.$_.'" ';
	}
	
	warn $CMD if $OPTIONS->{debug};
	
	_run_command($CMD, $OPTIONS);
	
	opendir my $dh, $OPTIONS->{temp_dir} or die 'Couldn\'t open \''.$OPTIONS->{temp_dir}."' for reading: $!";
	my $regexp = qr/$OPTIONS->{par_filter}/;
	while(my $file = readdir $dh){
		push @$fileList, catfile($OPTIONS->{temp_dir}, $file) if($file =~ /$regexp/);
	}
	closedir $dh;
	
	return $fileList;
}

sub create_sfv{
	my ($name, $files, $OPTIONS) = @_;
	return $files if(!$OPTIONS->{create_sfv});
	
	my $sfvFile = $name;
	
	if($sfvFile eq '' || !defined $sfvFile){
		my @folders = splitdir( $OPTIONS->{directory} );
		pop @folders if($folders[-1] eq '');
		$sfvFile = $folders[-1];
	}
	
	# TODO
	# We can't reuse the old SFV, because the content will be different.
	opendir my $dh, $OPTIONS->{temp_dir} or die 'Couldn\'t open \''.$OPTIONS->{temp_dir}."' for reading: $!";
	while(my $file = readdir $dh){
		if($file =~ /sfv$/){
			my $oldSFVFilename = catfile($OPTIONS->{temp_dir}, $file);
			unlink $oldSFVFilename;
			last;
		}
	}
	closedir $dh;
	
	open my $ofh, '>', catfile($OPTIONS->{temp_dir},"$sfvFile.sfv") or die 'Unable to create sfv file!';
 
	for (@$files) {
		my $file = $_;
		my $fileName=(fileparse($file))[0];
		open my $ifh, '<', $file or die "Couldn't open file $file : $!";
		binmode $ifh;
		my $crc32 = 0;
		while (read ($ifh, my $input, 512*1024)!=0) {
			$crc32 = crc32($input,$crc32);
		}

		warn sprintf('%s %08x',$fileName, $crc32) if $OPTIONS->{debug};
		print $ofh sprintf("%s %08x\r\n",$fileName, $crc32);
		close $ifh;
	}
  
	close $ofh;
	push @$files, catfile($OPTIONS->{temp_dir},"$sfvFile.sfv");
	return $files;	
}

sub rename_archived_files{
	my ($previousName,$name, $dir, $OPTIONS) = @_;
	return [$dir] if(!$OPTIONS->{archive});
	
	my @archived_files = ();
	my $regexp = qr/$OPTIONS->{archive_filter}/;
	my $previousNameRegexp = qr/$previousName/;
	
	opendir my $dh, $OPTIONS->{temp_dir} or die 'Couldn\'t open \''.$OPTIONS->{temp_dir}."' for reading: $!";
	while(my $file = readdir $dh){
		if($file =~ /$regexp/ && $file =~ /$previousName/){
			my $oldFilename = catfile($OPTIONS->{temp_dir}, $file);
			(my $newFilename = $oldFilename) =~ s/$previousName/$name/;
			rename($oldFilename, $newFilename);
			push @archived_files, $newFilename;
		}
	}
	closedir $dh;
	
	return \@archived_files;
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
	
	my $inputFile = $dir;
	$inputFile.=catfile('','') if -d $inputFile; #put a file path separator to avoid the archive program to have a first level folder
	
	my $CMD=$OPTIONS->{archive_arguments}.' "'.catfile( $OPTIONS->{temp_dir}, $name)."\" \"$inputFile\"";
	
	warn $CMD if $OPTIONS->{debug};

	_run_command($CMD,$OPTIONS);	

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
	return $dir if(!$OPTIONS->{reverse});

	my $regexp = qr/$OPTIONS->{files_filter}/;
	my @matched_files = ();
	find(sub{
		if($File::Find::name =~ /$regexp/){
			push @matched_files, $File::Find::name;
		}
		}, ($dir));
	
	my($filename, $dirs, $suffix);
	for my $file (@matched_files){
		($filename, $dirs, $suffix) = fileparse($file, qr/\.[^.]*$/);
		mv $file, $dirs.scalar (reverse ($filename)).$suffix;
	}
	
	return -d $dir ? $dir : $dirs.scalar (reverse ($filename)).$suffix;
}

sub rename_files{
	my ($name, $dir, $OPTIONS) = @_;

	return $dir if(!$OPTIONS->{rename_par});
	my $regexp = qr/$OPTIONS->{files_filter}/;
	
	my @matched_files = ();
	find(sub{
		if($File::Find::name =~ /$regexp/){
			push @matched_files, $File::Find::name;
		}
	}, ($dir));
	
	my $CMD = $OPTIONS->{rename_par_arguments}.' "'."$dir/Rename.with.this.par2".'" '.join(' ', map {"\"$_\""} @matched_files);
	warn $CMD if $OPTIONS->{debug};
	
	_run_command($CMD, $OPTIONS);
	
	my $i=0;
	for my $file (@matched_files){
		my($filename, $dirs, $suffix) = fileparse($file, qr/\.[^.]*$/);
		my $newName = 'Use.the.renaming.par';
		if($name ne ''){
			$newName=$name;
		}
		$newName.=$i if($i++>0);
		$newName.=$suffix;
		mv $file, $dirs.$newName;
	}

	return $dir;
}

sub _run_command{
	my ($CMD, $OPTIONS) = @_;
	if($^O eq 'linux'){
		open my $ofh , '-|', $CMD or die "Unable to launch process: $!";
		while(defined ($_ = <$ofh>)){
			warn $_ if $OPTIONS->{debug} && defined $_;
		}
		close $ofh;
	}elsif($^O eq 'MSWin32'){
		my @commandOutput=qx/$CMD/;
		if ($OPTIONS->{debug}){
			warn $_ for(@commandOutput);
		}
	}
}

sub _load_options{
	my %OPTIONS =  %{shift @_};

	my $configurationFile = '';
  if($^O eq 'MSWin32'){
    $configurationFile = $ENV{"USERPROFILE"}.'/.config/newsup.conf';  
  }else{
    $configurationFile = $ENV{"HOME"}.'/.config/newsup.conf';  
  }
	
	if (-e $configurationFile) {
		my $config = Config::Tiny->read($configurationFile);

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
			}elsif($OPTIONS{$key} eq ''){
				$OPTIONS{$key} = $other_configs{$key};
			}
		}
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

sub help{
	
  say << "END";
This program is part of NewsUP.

The goal of this program is to make your uploading more easy.

This is an auxiliary script that will compress and/or split the files to be uploaded,
create the parity files, create sfv files and finally invoke the newsup to upload the
files.

Options available:

\t-help = shows this message

\t-create_sfv = if you want a sfv to be generated.

\t-group <group> = group to where you want to upload. You can have multiple `group` switches.

\t-archive = If you want to archive (rar or 7z or other)

\t-par = If you want par2 files to be created automatically

\t-save_nzb = if you want to save the nzb in the location defined in the option save_nzb_path on the conf file.

\t-rename_par = If you want a par Rename.with.this.par2 to be created. This par can be used to rename the files
\tmatched by the files_filter in the configuration file. This only makes sense to use if the -name option is used

\t-reverse = If you want the files matched by the files_filter in the conf file to have the name reversed.

\t-force_repair = To force the client to repair the files. This is only done if a NFO is passed, since it will
\tdelete it to force a repair.

\t-upload-nzb = If the nzb of the upload is to be uploaded as well.

\t-directory <folder|file> = the folder or file to be uploaded.

\t-debug = to show debug messages. Usefull when you're configuring the switches. You'll know what commands are being invoked

\t-args <extra args> = extra args to be passed to newsup. Usually they need to be between double quotes ('"'). An alternative to
\tthis is to use the option uploader in the configuration file.

\t-delete = if you want the temporary folder's content (the folder where the compressed/split and pars are
\t\tgoing to be created) deleted after upload. This is enabled by default.

\t-nfo <.NFO> = if you have a NFO to be uploaded. Usually the .nfo files aren't inside of the rars, so
\t\tthey live somewhere else in the filesystem.

\t-name = If you want the files that match the files_filter in the conf file to have another name. Also if the archive is
\tset, the archive's name will be with this new name. You can have several -name. It will upload the files with the different
\tnames. If you have set the option -upload_nzb, this option is only used for the first name.

END

exit 0;

}


main();
