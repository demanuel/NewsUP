##############################################################################
#
# Author: David Santiago <demanuel@ymail.com>
# License: GPL V3
#
##############################################################################
package NZB::Generator;
use strict;
use utf8;
use XML::LibXML;
use NZB::File;
use 5.018;


sub new{

  my $class = shift;
  my $name = shift;
  my $metadata = shift;
  my $segments = shift;
  my $poster = shift;
  my $groups = shift;
  my $self = {
	      name=>$name,
	      segments=>$segments,
	      metadata=>$metadata,
	      poster=>$poster,
	      groups=>$groups,
	     };
  bless $self, $class;
  return $self;
}

sub write_nzb{
  my $self = shift;

  my %files = ();

  for my $segment (@{$self->{segments}}) {
    if (!exists $files{$segment->{fileName}}) {
      $files{$segment->{fileName}} = NZB::File->new(_get_xml_escaped_string('"'.$segment->{fileName}.'" yEnc'),
						    _get_xml_escaped_string($self->{poster}), $self->{groups});
    }
    my $file = $files{$segment->{fileName}};
    $file->add_segment($segment);
  }

  my $xml = '<nzb xmlns="http://www.newzbin.com/DTD/2003/nzb">\r\n';
  $xml.="<meta type=\"$_\">"._get_xml_escaped_string($self->{metadata}{$_})."</meta>\r\n" for (keys %{$self->{metadata}});
  $xml.= $files{$_}->get_xml() for  (keys %files);
  $xml.= '</nzb>';

  my $nzbFile = "";
  if (defined $self->{name}) {
    $nzbFile = $self->{name};
  }else {
    $nzbFile = time();
  }
  
  $nzbFile .= ".nzb";
  
  open my $ofh, '>', $nzbFile;
  print $ofh $xml;
  close $ofh;

  return $nzbFile;
}

sub _get_xml_escaped_string{
  my $string = shift;

  $string=~ s/</&lt;/g;
  $string=~ s/>/&gt;/g;
  $string=~ s/&/&amp;/g;
  $string=~ s/"/&quot;/g;
  $string=~ s/'/&apos;/g;

  return $string;
}


1;
