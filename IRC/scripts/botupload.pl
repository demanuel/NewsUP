#!/usr/bin/env perl
use 5.010;
use warnings;
use strict;
use utf8;

my $NEWSUP = '../scripts/uploadit.pl';

# Example of a typical invocation
# !upload my.personal.file.that.i.want.to.backup hash1 hash2

my $folder = shift @ARGV;
my @hashes = @ARGV;

my @ARGS = ('-dir', $folder);
push @ARGS, split(' ', '-name '.join(' -name ',@hashes));

exec $NEWSUP,@ARGS or warn "Unable to start the uploadit process"; 

