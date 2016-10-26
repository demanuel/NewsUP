#!/usr/bin/env perl
use 5.010;
use warnings;
use strict;
use utf8;
use Config::Tiny;

my $CONFIG = get_options();
my $SCRIPT="./scripts/completion_checker.pl";

sub main{

  my $args='';
  for(@ARGV){
    $_.='.nzb' if $_ !~ /.nzb$/;

    $args .= ' -nzb '.$CONFIG->{other}{PATH_TO_SAVE_NZBS}.$_;
  }
  my @output = `$SCRIPT $args`;
  my $totalCompletion = 0;
  my $count = 0;
  for my $line (@output){
    if ($line =~ /^File .* is (.*)% completed/){
      $totalCompletion += $1;
      $count++;
    }
  }

  say "The nzbs are ".($totalCompletion/$count)."% complete!";

}





sub get_options{

  my $config;
  if (defined $ENV{"HOME"} && -e $ENV{"HOME"}.'/.config/newsup.conf') {

    $config = Config::Tiny->read( $ENV{"HOME"}.'/.config/newsup.conf' );

    if (exists $config->{other}{PATH_TO_UPLOAD_ROOT}){
      my @upload_folders = split(',', $config->{other}{PATH_TO_UPLOAD_ROOT});
      if (!@upload_folders) {
        say "Please configure PATH_TO_UPLOAD_ROOT folders";
        exit 0;
      }

      for (@upload_folders) {
        $_ =~ s/^\s+|\s+$//g ;     # remove both leading and trailing whitespace

        if (!-d $_) {
          say "Folder $_ does not exist!\r\nPlease configure correctly the option PATH_TO_UPLOAD_ROOT Exiting.";
          exit;
        }
      }

    }else {
      say "Option PATH_TO_UPLOAD_ROOT is missing!";
    }

    if (exists $config->{other}{PATH_TO_SAVE_NZBS}){
      my $NZB_folder = $config->{other}{PATH_TO_SAVE_NZBS};
      if (!-d $NZB_folder) {
        say "Please configure PATH_TO_SAVE_NZBS folders";
        exit 0;
      }
    }else {
      say "Option PATH_TO_SAVE_NZBS is missing!";
    }
  }else {
    say "Please configure your newsup.conf file";
    exit 0;
  }

  return $config;
}


main;
