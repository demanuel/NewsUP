package NZB::File;
use strict;
use utf8;
use XML::LibXML;
use 5.018;


sub new{

  my $class = shift;  
  my $self = {poster=>shift,
	      groups=>shift,
	      segments=>[],
	     };



  bless $self, $class;
  return $self;

}

sub add_password{
  my $self = shift;

  $self->{password}=shift;
}

sub add_segment{
  my $self = shift;
  push @{$self->{segments}}, [shift, shift]; 
}


sub set_subject{
  my $self = shift;
  my $subject = shift;

  $self->{subject} = $subject;
}

sub get_xml_document{
  my $self = shift;
  
}

1;
