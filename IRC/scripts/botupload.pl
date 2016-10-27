#!/usr/bin/env perl
use 5.010;
use warnings;
use strict;
use utf8;

my $UPLOAD_IT = '../scripts/uploadit.pl';

# Example of a typical invocation
# !upload my.personal.file.that.i.want.to.backup hash1 hash2

my $folder = shift @ARGV;
my @hashes = @ARGV;

my @ARGS = ('-dir', $folder);
push @ARGS, split(' ', '-name '.join(' -name ',@hashes));


{
  local @ARGV = @ARGS;
  unless (my $exitCode = do $UPLOAD_IT){
    say "Error: Couldn't parse file $UPLOAD_IT: $@" if $@;
    say "Warning: couldn't do $UPLOAD_IT: $!" unless defined $exitCode;
    say "Warning: ouldn't run $UPLOAD_IT" unless $exitCode;
  }
}



