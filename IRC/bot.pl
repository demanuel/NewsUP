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
# Usage: perl bot.pl -folder <folder> -uploadit <uploadit> script
#############################################################################

use warnings;
use strict;
use utf8;
use 5.010;
use Data::Dumper;
use Getopt::Long;
use Config::Tiny;

# We will use a raw socket to connect to the IRC server.
use IO::Socket;
use IO::Socket::SSL;
use POSIX ":sys_wait_h";
use File::Copy::Recursive qw/dircopy/;
$File::Copy::Recursive::CPRFComp = 1;
use File::Copy qw/mv/;
use File::Path qw/remove_tree/;
use File::Find;
use File::Basename;
use Time::HiRes qw/usleep/;
use IO::Select;

$|=1;
my $CRLF="\x0D\x0A";
$\=$CRLF;
$/=$CRLF;


my $KID=0;
my $CONFIG = get_options();
my $JUMP=60; #1 minute
my @CMD_QUEUE=();
my %SCRIPTS=(
  "^!check (.*)" => 'perl ./scripts/botupload.pl',
  "^!queue" => sub{
        my @list=();
        push @list, $KID? "Command queue [1]": 'Command queue [0]';
        push @list, map{/.*upload\.pl (.*)$/; $1;} @CMD_QUEUE;
        push @list, "End of Command Queue";
        return \@list
      },
  "^!upload (.*)"=>'perl ./scripts/botupload.pl',
);


my %COLORS=(
  white => '00',
  black => '01',
  navy => '02',
  green => '03',
  red => '04',
  maroon => '05',
  purple => '06',
  orange => '07',
  yellow => '08',
  lime => '09',
  teal => '10',
  cyan => '11',
  royal => '12',
  fuchsia => '13',
  grey => '14',
  silver => '15'
);

 my %COLOR_OPTIONS=(
  bold => "\x02",
  color => "\x03",
  italic => "\x1D",
  underlined => "\x1F",
  reverse => "\x16",
  reset => "\x0F",
);

sub main{

  my $socket = get_IRC_socket($CONFIG);

  start($socket, $CONFIG);
}


sub get_options{

  my $config;
  my $configurationFile = '';
  if($^O eq 'MSWin32'){
    $configurationFile = $ENV{"USERPROFILE"}.'/.config/newsup.conf';
  }else{
    $configurationFile = $ENV{"HOME"}.'/.config/newsup.conf';
  }
  if (-e $configurationFile) {

    $config = Config::Tiny->read( $configurationFile);

  }else {
    say "Please configure your newsup.conf file";
    exit 0;
  }

  return $config;
}


sub get_IRC_socket{
  my $config = shift;
  my $sock;

  if ($config->{irc}{port} == 6667) {
    $sock = new IO::Socket::INET(
                                  PeerAddr => $config->{irc}{server},
                                  PeerPort => $config->{irc}{port},
                                  Timeout=> 5,
                                  Blocking=> 1,
                                  Proto => 'tcp') or die "Can't connect";
  }else{
    $sock = new IO::Socket::SSL->new(
                                PeerAddr => $config->{irc}{server},
                                PeerPort => $config->{irc}{port},
                                SSL_verify_mode=>SSL_VERIFY_NONE,
                                Timeout=> 5,
                                Blocking=> 1,
                                Proto => 'tcp') or die "Can't connect";

  }

  $sock->autoflush(1);
  _authenticate($sock, $config->{irc}{nick}, $config->{irc}{password});
  _join_channel($sock, $config->{irc}{channel}, $config->{irc}{channel_password});
  return $sock;
}

sub _authenticate{
  my ($sock, $nick, $password) = @_;

  say "Initial read: "._read_from_socket($sock);
  # Log on to the server.
  print $sock "NICK $nick";
  #print $sock "USER $login 8 * :NewsUp TEST \r\n";
  print $sock "USER $nick * * :NewsUP News_UP";
  print $sock "MSG NickServ identify $password" if (defined $password && $password ne '');

  # Read lines from the server until it tells us we have connected.
  while (my $input = _read_from_socket($sock)) {
    chomp $input;
    if ($input =~ /^PING(.*)$/i) { # If the server 
      print $sock "PONG $1";
    }elsif ($input =~ /004/) { # Check the numerical responses from the server.
      # We are now logged in.
      last;
    }
    elsif ($input =~ /433/) {
      die "Nickname is already in use.";
    }
  }
}

sub _join_channel{
  my ($sock, $channel, $channelPassword) = @_;
  # Join the channel.
  #my $channel = $config->{other}{IRC_CHANNEL};

  my $joinChannelString = "JOIN #$channel";

  if(defined $channelPassword && $channelPassword ne ''){
    $joinChannelString.=" $channelPassword";
  }

  print $sock $joinChannelString;

}

sub start{
  my $socket = shift;
  my $config = shift;
  my $nick = $config->{irc}{nick};
  my $select = IO::Select->new($socket);

  my $nextRun = time()+$JUMP;
  my $nextJump = $JUMP;

  while(1){

    start_next_command($KID, \@CMD_QUEUE, $config, $socket);
    my ($readers) = IO::Select->select($select, undef, undef, $nextJump);

    my $currentTime = time();
    if(defined($readers) && @$readers > 0){
      my $input = _read_from_socket($socket);
      chomp $input;
      say $input;
      if ($input =~ /^PING(.*)$/i) {
        print $socket "PONG $1";

      }elsif($input =~ /^:(.*)!.*PRIVMSG (#.*) :(.*)$/){
        my ($channel, $message) = ($2,$3);
        for my $regexp (keys %SCRIPTS){
          if($message =~ /$regexp/){
            my $params = $1;
            if(-e $SCRIPTS{$regexp} || lc substr($SCRIPTS{$regexp},-3) eq '.pl'){
              push @CMD_QUEUE, $SCRIPTS{$regexp}.' '.$params;
            }else{
              eval{
                my $output = $SCRIPTS{$regexp}->($params);
                _print_lines_to_channel($socket, $channel, $output, 5);
              };
              _print_lines_to_channel($socket, $channel, [$@]) if $@;
            }
            last;
          }
        }

      }elsif($input =~ /^:(.*)!.*PRIVMSG .* :(.*)$/){
        print $socket "PRIVMSG $1 :I'm a bot. I only process public messages!";
        print $socket "PRIVMSG $1 :These are the commands that i accept: ";
        print $socket "PRIVMSG $1 :$_" for keys(%SCRIPTS);
        print $socket "PRIVMSG $1 :Please use the channel! Thank you!";
      }
    }
    if($nextRun < $currentTime || $nextRun==$currentTime){
      #the full time has passed!
      $nextJump=$JUMP - ($currentTime-$nextRun);
      $nextRun+=$JUMP;

    }elsif($nextRun - $currentTime < $JUMP){
      #the full time hasn't passed yet
      $nextJump = $nextRun-$currentTime;
      say "Next jump 2: $nextJump";
    }
  }
}

sub _print_lines_to_channel{
  my ($socket, $channel, $lines, $maxLines) = @_;
  my $totalLines = $maxLines;

  if($maxLines < scalar(@$lines)){
    print $socket "PRIVMSG $channel :First $totalLines lines (total ".$COLOR_OPTIONS{color}.$COLORS{red}.scalar(@$lines).$COLOR_OPTIONS{color}." lines):";
  }

  for my $outputExec (@$lines){
    print $socket "PRIVMSG $channel :$outputExec";

    if(--$maxLines == 0){
      last;
    }
  }


}

sub start_next_command{
  my ($kid, $commands, $config, $socket) = @_;

  if($kid){
    my $pid = waitpid($kid, WNOHANG);
    say "pid returned: $pid [$KID]";
    ($KID, $kid) = (0,0) if $pid == $KID;

  }
  #Skips the execution of a new process if there's already one in the backgroud
  if(!$kid){
    if(@$commands){
      unless (defined($KID = fork())) {
        say "Unable to fork! Exiting the bot";
        exit 0;
      }
      elsif (!$KID) {
        my $command = shift @$commands;
        $socket->autoflush(1);
        _print_lines_to_channel($socket, '#'.$config->{irc}{channel}, ["Executing: $command"],1);
        if($^O eq 'linux'){
          _run_at_linux($command, $socket, $config);
        }elsif($^O eq 'MSWin32'){
          _run_at_windows($command, $socket, $config);
        }
        exit 0;
      }else{
        #I'm the parent. We need to discard the command the kid is going to execute
        shift @$commands;
      }
    }
  }
}

sub _run_at_windows{
  my ($command, $socket, $config) = @_;

  my @output = qx/$command/;
  my @linesToPrint=();
  for my $l (@output){
    if($l =~ /speed/i){
        $l =~ /([^:]*:)(.*)/;
        $l = $COLOR_OPTIONS{color}.$COLORS{fuchsia}.$1.$COLOR_OPTIONS{color}.$COLOR_OPTIONS{color}.$COLORS{lime}.$2.$COLOR_OPTIONS{color};
      push @linesToPrint, $l;
    }elsif($l =~ /exception|error|warning|die|fail/i){
        $l =~ /([^:]*:)(.*)/;
        $l = $COLOR_OPTIONS{color}.$COLORS{fuchsia}.$1.$COLOR_OPTIONS{color}.$COLOR_OPTIONS{color}.$COLORS{red}.$2.$COLOR_OPTIONS{color};
      push @linesToPrint, $l;
    }
  }

  _print_lines_to_channel($socket, '#'.$config->{irc}{channel}, \@linesToPrint,5);


}

sub _run_at_linux{
  my ($command, $socket, $config) = @_;


  open( my $ifh, '-|', $command);
  while(<$ifh>){
    my $line = $_;
    say "linha: $line";
    my  @linesToPrint=();
    for my $l (split("\r", $line)){
      if($l =~ /speed/i){
        #TODO do the same in run_at_windows
        $l =~ /([^:]*:)(.*)/;
        $l = $COLOR_OPTIONS{color}.$COLORS{fuchsia}.$1.$COLOR_OPTIONS{color}.$COLOR_OPTIONS{color}.$COLORS{lime}.$2.$COLOR_OPTIONS{color};
        push @linesToPrint, $l;
      }elsif($line =~ /exception|error|warning|die|fail/i){
        $l =~ /([^:]*:)(.*)/;
        $l = $COLOR_OPTIONS{color}.$COLORS{fuchsia}.$1.$COLOR_OPTIONS{color}.$COLOR_OPTIONS{color}.$COLORS{red}.$2.$COLOR_OPTIONS{color};

        push @linesToPrint, $l;
      }
    }
    if(@linesToPrint){
      _print_lines_to_channel($socket,'#'.$config->{irc}{channel}, \@linesToPrint,5);
    }
  }
  close $ifh;
  _print_lines_to_channel($socket,'#'.$config->{irc}{channel}, ["Command executed"],1);
}


sub _read_from_socket{
  my ($socket) = @_;

  my $output='';

  while (1) {
    # 512 - rfc2812 - section 2.3:
    #  IRC messages are always lines of characters terminated with a CR-LF
    #  (Carriage Return - Line Feed) pair, and these messages SHALL NOT
    #  exceed 512 characters in length, counting all characters including
    #  the trailing CR-LF. Thus, there are 510 characters maximum allowed
    #  for the command and its parameters.  There is no provision for
    #  continuation of message lines.

    # For performance it should be roughly as large as the largest chunk that can
    # be emitted by the server - Network programming with perl
    my $status = sysread($socket, my $buffer,512);
    $output.= $buffer;
    undef $buffer;
    if ($output =~ /\r\n$/ || $status == 0){
      last;
    }elsif (!defined $status) {
      die "Error: $!";
    }
  }

  return $output;

  #while(my $buffer = <$socket>){
  #  $output .= $buffer;
  #  last if $output =~ /\r\n$|^\z/;
  #}
  #
  #return $output;
}


main;
