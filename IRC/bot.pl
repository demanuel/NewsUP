#!/usr/local/bin/perl -w
##########################################################################
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
# A simple IRC robot. Influenced by http://archive.oreilly.com/pub/h/1964
# Usage: perl bot.pl -folder <folder> -uploadit <uploadit> script
#############################################################################

use warnings;
use strict;
use utf8;
use 5.010;
use Data::Dumper;
use Getopt::Long;

# We will use a raw socket to connect to the IRC server.
use IO::Socket;

my ($uploadFolder, $uploadit);
GetOptions('folder=s'=>\$uploadFolder, 'uploadit=s'=>\$uploadit);

if (!defined $uploadFolder || !defined $uploadit || !-e $uploadit || !-e $uploadFolder) {
  say "Please indicate a valid upload folder to be monitored and a valid uploadit script!";
  exit;
}

# The server to connect to and our details.
my $server = "irc.rizon.net";
my $nick = "NewsUp";
my $login = "NewsUp";

# The channel which the bot will join.
#my $channel = "#test";
my $channel = "#ikweethet";

# Connect to the IRC server.
my $sock = new IO::Socket::INET(PeerAddr => $server,
                                PeerPort => 6667,
                                Proto => 'tcp') or
                                    die "Can't connect\n";

# Log on to the server.
print $sock "NICK $nick\r\n";
#print $sock "USER $login 8 * :NewsUp TEST \r\n";
print $sock "USER $login * * :NewsUp\r\n";

# Read lines from the server until it tells us we have connected.
while (my $input = <$sock>) {
  say "input: $input";
    # Check the numerical responses from the server.
    if ($input =~ /004/) {
        # We are now logged in.
        last;
    }
    elsif ($input =~ /433/) {
        die "Nickname is already in use.";
    }
}

# Join the channel.
print $sock "JOIN $channel\r\n";
# Keep reading lines from the server.
while (my $input = <$sock>) {
  $input=~s/\R$//;
  say $input;
  if ($input =~ /^PING(.*)$/i) {
    # We must respond to PINGs to avoid being disconnected.
    print $sock "PONG $1\r\n";
  }else {
    my @tokens = split(' ', $input);
    if (@tokens) {
      if ($tokens[1] eq 'PRIVMSG') {
	$tokens[0]=~ /^:(.*)\!.*$/;

	my @inputParams= ($1 , substr join(' ',@tokens[3..$#tokens]), 1);
	if ($tokens[2] eq $nick) {#private message

	  if ($inputParams[1]=~ /^echo (.*)$/) {
	    print $sock 'PRIVMSG '.$inputParams[0].' :You told me "'.substr($inputParams[1],5)."\"\r\n"; #Write to user. The substr is to avoid printing the command
	    print $sock "PRIVMSG $channel :User ".$inputParams[0].' told me '.substr($inputParams[1],5)."\r\n"; #Write to the channel

	  }elsif($inputParams[1]=~ /^fortune.*$/){
	    my $fortune = `fortune chucknorris`;
	    say "$fortune";
	    $fortune=~s/\R//g;
	    say "PRIVMSG $channel :$fortune\r\n";
	    print $sock "PRIVMSG $channel :$fortune\r\n";# Write to the channel

	  }
	  
	}elsif ($tokens[2] eq $channel) {#public message
	  say "Public message: '".$inputParams[1]."'";
	  if($inputParams[1] =~ /newsup/){
	    
	    my @randomMessages = ("Er... Ok...", "Are you sure?", "I believe", "Damn!", "Why not?", ":-D","Maybe later", "Was that a public annoucement?!?");
	    print $sock "PRIVMSG $channel :".$randomMessages[rand @randomMessages]."\r\n";
	  }
	  elsif ($inputParams[1] =~ /^\!(\w+) (.*)$/) {# All the public commands must start with a !
	    
	    if ($1 eq 'upload') {
	      my @args = split(' ', $2);
	      start_upload (\@args, $sock);
	    }elsif ($1 eq 'check') {

	      print $sock "Not implemented!";
	      
	    }  
	  }
	  else {
	    say "Didn't match!";
	  }
	}
	

	
	
      }
      
    }
  }
  
  
  # elsif ($input =~ /:(\w+)\!.* PRIVMSG (\w+) :(\w+) (.*)$/) { :THC-!THC-@Pretty.As.Alwayz PRIVMSG #ikweethet :echo whaaassuuuppppppp

  #   say "Matches! $1 - $2 - $3";
  #   if ($3 eq 'echo') {
  #     print $sock "PRIVMSG $1 :You told me \"$4\"\r\n"; Write to user
  #     print $sock "PRIVMSG $channel :User $1 told me \"$4\"\r\n"; Write to the channel
  #   }
    
  # }elsif (($input =~ /:(\w+)\!.* PRIVMSG (\w+) :(.*)$/)) {
    
  #   if ($3 eq 'fortune') {
      
  #     my $fortune = `fortune chucknorris`;
  #     say "$fortune";
  #     $fortune=~s/\R//g;
  #     say "PRIVMSG $channel :$fortune\r\n";
  #     print $sock "PRIVMSG $channel :$fortune\r\n"; Write to the channel
  #   }
    
  # }
  # else {
  #   # Print the raw line received by the bot.
  #   print "$input\n";
    
  # }
}


sub start_upload{
  my @args = @{shift @_};
  my $socket = shift;
  
  unless (defined(my $pid = fork())) {
    say "Unable to fork! Exiting the bot";
    exit 0;
  }
  elsif ($pid) {
    #The main process
    return;
  }
  
  #Im the child
  if (@args >= 2) {
    my $folder = shift @args;
    for (@args) {
      if (!-e "$uploadFolder/$folder/$_") {
	say "$uploadFolder/$folder/$_ not found!";
	print $sock "PRIVMSG $channel : $_ not found!\r\n";
	next;
      }
      
      my $output = qx(perl $uploadit -directory $uploadFolder/$folder/$_);
      say "Executed cmd: perl $uploadit -directory $uploadFolder/$folder/$_";		  
      say $output;
      for (split($/,$output)){
	print $sock "PRIVMSG $channel : $_\r\n" if $_ =~ /Transfer speed|NZB file .* created/;
      }
      
    }
    
  }
  
  exit 0;
}
