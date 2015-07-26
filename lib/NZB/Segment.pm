##############################################################################
#
# Author: David Santiago <demanuel@ymail.com>
# License: GPL V3
#
##############################################################################
package NZB::Segment;
use strict;
use utf8;
use 5.018;


sub new{

  my $class = shift;
  my $fileName= shift;
  my $size= shift;
  my $number= shift;
  my $total=shift;
  my $messageID= shift;

  my $self = {fileName=>$fileName,
	      size=>$size,
	      number=>$number,
	      messageID=>$messageID
	     };


  bless $self, $class;
  return $self;
}

sub get_xml{
  my $self = shift;
  my $bytes = $self->{size};
  my $number = $self->{number};
  my $messageID = $self->{messageID};
  return "<segment bytes=\"$bytes\" number=\"$number\">$messageID</segment>\n";
}


1;
