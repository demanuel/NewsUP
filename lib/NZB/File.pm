##############################################################################
#
# Author: David Santiago <demanuel@ymail.com>
# License: GPL V3
#
##############################################################################
package NZB::File;
use strict;
use utf8;
use NZB::Segment;
use Data::Dumper;
use 5.018;


sub new{

  my $class = shift;
  my $subject = shift;
  my $poster = shift;
  my $groups = shift;
  my $self = {poster=>$poster,
	      groups=>$groups,
	      subject => $subject,
	      segments=>[],
	     };

  bless $self, $class;
  return $self;

}

sub add_segment{
  my $self = shift;
  my $segment = shift;

  push @{$self->{segments}}, $segment;
}

#creates the xml.
#Yes it's manual, because i wanted to remove the libXml dependency
sub get_xml{
  my $self = shift;
  my $poster = $self->{poster};
  my $date=time();
  my $subject = $self->{subject};
  my $segmentsSize=scalar @{$self->{segments};
  my $xml = "<file poster=\"$poster\" subject=\"$subject yEnc (1/$segmentsSize)\">\n";
  $xml.= "<groups>\n";
  $xml.= "<group>$_</group>\n" for (@{$self->{groups}});
  $xml.= "</groups>\n";
  $xml.= "<segments>\n";

  my @ordered_segments = sort{$a->{number} <=> $b->{number} } @{$self->{segments}};

  $xml.= $_->get_xml() for (@ordered_segments);
  $xml.= "</segments>\n";
  $xml.= "</file>\n";

  return $xml;
}

1;
