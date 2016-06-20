#!/usr/bin/env perl

###############################################################################
#     SimpleMovieNFOCreator - create backups of your files to the usenet.
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
use 5.010;
use File::Basename;
use LWP::UserAgent;
use Digest::MD5 qw(md5_hex);
use JSON qw/decode_json/;

my $REGEXP_MOVIE = qr/([0-9aA-zZ\.\-\_]+)\.(\d+)\./;
my $REGEXP_SERIES = qr/([0-9aA-zZ\.\-\_]+)(\.\d+)*\.([sSeE0-9]+)\./;
my $OMAP_API = "http://www.omdbapi.com/?plot=full&r=json";
my $BROWSER = LWP::UserAgent->new();
my $MD5 = Digest::MD5->new;

for my $file (@ARGV){

  if(!-e $file){
    say "The file doesn't exist! Please confirm the inputs!";
    exit 0;
  }

  my ($fileName, $dirs, $suffix) = fileparse($file, qr/\.[^.]*$/);
  my $title;
  my $year;

  if($fileName =~ $REGEXP_MOVIE){
    #It's a MOVIE
    $year = $2;
    ($title = $1) =~ s/\./ /g;
    say "Movie: $title";

  }elsif($fileName =~ $REGEXP_SERIES){

    my $episode = defined $2?$2:$3;
    $year = $2;
    ($title = $1) =~ s/\./ /g;
    say "$title: [$episode]";

  }else{
    say "Unable to determine if it's a movie or a series. Please check the filenaming conventions";
    exit 0;
  }

  open my $ofh, '>:utf8', "$dirs$fileName.nfo" or die "Unable to create the NFO: $!";
  print $ofh "FileName: $fileName$suffix\n";
  open my $ifh, '<', $file or die "Unable to open the media file for reading: $!";
  $MD5->addfile($ifh);
  close $ifh;
  print $ofh "MD5: ",$MD5->hexdigest,"\n\n";
  print $ofh "*"x80, "\n";


  my $requestURL = "$OMAP_API&t=$title";
  if(defined $year){
    $requestURL .="&y=$year";
  }
  say "Query: $requestURL";
  my $response = $BROWSER->get($requestURL);

  if($response->is_success){
    my $json= decode_json($response->decoded_content);

    if($json->{Response}){
      delete $json->{Response};
      for(keys %{$json}){
        print $ofh "$_: ",$json->{$_},"\n";
      }
    }
  }else{
    print $ofh "IMDB info not found!";
  }

  print $ofh "*"x80, "\n\n\n";
  print $ofh "Powered by NewsUP!", "\n";

  close $ofh;

}
