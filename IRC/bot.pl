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
$|=1;
$\="\015\012";

my $KID=0;
my $CONFIG = get_options();
my $JUMP=60; #1 minute
my @CMD_QUEUE=();
my %SCRIPTS=(
  "^!completion (.*)" => sub{say "Params:"; say Dumper(@_);},
  "^!queue" => sub{my @list=(); push @list, $KID? "Command queue [1]": 'Command queue [0]';push @list, @CMD_QUEUE; push @list, "End of Command Queue"; return \@list},
  "^!upload (.*)"=>'./scripts/botupload.pl',
);


 my %COLOR_OPTIONS=(
  bold => "\x02",
  color => "\x03",
  italic => "\x1D",
  underlined => "\x1F",
  reverse => "\x16",
  reset => "\x0F",
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

sub main{

  my $socket = get_IRC_socket($CONFIG);

  start($socket, $CONFIG);
}


sub get_options{

  my $config;
  if (defined $ENV{"HOME"} && -e $ENV{"HOME"}.'/.config/newsup.conf') {

    $config = Config::Tiny->read( $ENV{"HOME"}.'/.config/newsup.conf' );
    #if (exists $config->{irc}{upload_root}){
    #  my @upload_folders = split(',', $config->{irc}{upload_root});
    #  if (!@upload_folders) {
    #    say "Please configure <upload_root> folders";
    #    exit 0;
    #  }
    #
    #  for (@upload_folders) {
    #    $_ =~ s/^\s+|\s+$//g ;     # remove both leading and trailing whitespace
    #
    #    if (!-d $_) {
    #      say "Folder $_ does not exist!\r\nPlease configure correctly the option <upload_root> Exiting.";
    #      exit;
    #    }
    #  }
    #
    #}else {
    #  say "Option <upload_root> is missing!";
    #}
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
                                  Proto => 'tcp') or die "Can't connect\n";
  }else{
    $sock = new IO::Socket::SSL->new(
                                PeerAddr => $config->{irc}{server},
                                PeerPort => $config->{irc}{port},
                                SSL_verify_mode=>SSL_VERIFY_NONE,
                                Timeout=> 5,
                                Blocking=> 1,
                                Proto => 'tcp') or die "Can't connect\n";

  }

  $sock->autoflush(1);
  _authenticate($sock, $config->{irc}{nick}, $config->{irc}{password});
  _join_channel($sock, $config->{irc}{channel}, $config->{irc}{channel_password});
  return $sock;
}

sub _authenticate{
  my ($sock, $nick, $password) = @_;

  # Log on to the server.
  print $sock "NICK $nick\n";
  #print $sock "USER $login 8 * :NewsUp TEST \r\n";
  print $sock "USER $nick * * :NewsUP\n";

  print $sock "MSG NickServ identify $password\n" if (defined $password && $password ne '');


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
}

sub _join_channel{
  my ($sock, $channel, $channelPassword) = @_;
  # Join the channel.
  #my $channel = $config->{other}{IRC_CHANNEL};

  print $sock "JOIN #$channel";
  print $sock " $channelPassword" if(defined $channelPassword && $channelPassword ne '');
  print $sock "\n";#This works because i defined the $/ as \r\n in octal
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
      # print localtime().": ";
      if ($input =~ /^PING(.*)$/i) {
        # say $input;
        print $socket "PONG $1\n";

      }elsif($input =~ /^:(.*)!.*PRIVMSG (#.*) :(.*)$/){
        #say "BOT: mensagem publica -> $1";
        # say $input;
        my ($channel, $message) = ($2,$3);
        for my $regexp (keys %SCRIPTS){
          say $regexp;
          if($message =~ /$regexp/){
            my $params = $1;
            if(-e $SCRIPTS{$regexp}){
              push @CMD_QUEUE, $SCRIPTS{$regexp}.' '.$params;
            }else{
              eval{
                my $output = $SCRIPTS{$regexp}->($params);
                _print_lines_to_channel($socket, $channel, $output, 5);
              };
              print $socket "PRIVMSG $channel :$@\n" if $@;
            }
            last;
          }
        }

      }elsif($input =~ /^:(.*)!.*PRIVMSG .* :(.*)$/){
        # say $input;
        print $socket "PRIVMSG $1 :I'm a bot. I only process public messages!\n";
        print $socket "PRIVMSG $1 :These are the commands that i accept: \n";
        print $socket "PRIVMSG $1 :$_\n" for keys(%SCRIPTS);
        print $socket "PRIVMSG $1 :Please use the channel! Thank you!\n";
        #say "BOT: mensagem privada -> $1";
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
    print $socket "PRIVMSG $channel :First $totalLines lines (total ".scalar(@$lines)." lines):\n";
  }

  for my $output_exec (@$lines){
    print $socket "PRIVMSG $channel :$output_exec\n";

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
  #Skips the execution of a new process if there's already one in the backgroun
  if(!$kid){
    say "Tamanho commandos: ".scalar(@$commands);
    if(@$commands){
      unless (defined($KID = fork())) {
        say "Unable to fork! Exiting the bot";
        exit 0;
      }
      elsif (!$KID) { 
        my $command = shift @$commands;
        print $socket "PRIVMSG #".$config->{irc}{channel}." :Executing: $command\n";
        open( my $ifh, '-|', $command);
        while(<$ifh>){
          my $print = 0;
          my $line = $_;
          if($line =~ /([[:^cntrl:]]+)$/){
            my $match = $1;
            if($match =~ /speed/i){
              $line = $COLOR_OPTIONS{color}.$COLORS{lime}.$match.$COLOR_OPTIONS{color};
              $print++;
            }elsif($line =~ /exception|error|warning|die|fail/i){
              $line = $COLOR_OPTIONS{color}.$COLORS{red}.$match.$COLOR_OPTIONS{color};
              $print++;
          }
            
          }
          if($print){
            _print_lines_to_channel($socket,'#'.$config->{irc}{channel}, [$line],1);
          }
        }
        close $ifh;
        _print_lines_to_channel($socket,'#'.$config->{irc}{channel}, ["Command executed"],1);
        #my  @output = `$command`;
        #print $socket "PRIVMSG #".$config->{irc}{channel}." :Execution Terminated! Output: \n";
        #_print_lines_to_channel($socket,'#'.$config->{irc}{channel} , \@output, 5);
        exit 0;
      }else{
        #I'm the parent. We need to discard the command the kid is going to execute
        shift @$commands;
      }
    }
  }
}


sub _read_from_socket{
  my ($socket) = @_;

  my $output='';
  while(my $buffer = <$socket>){
    $output .= $buffer;
    last if $output =~ /\r\n$|^\z/;
  }

  return $output;
}


main;
