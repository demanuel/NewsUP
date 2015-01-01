package NZB::Generator;
use strict;
use utf8;
use XML::LibXML;
use NZB::File;
use 5.018;


sub new{

  my $class = shift;

  my $self = {};
  bless $self, $class;
  return $self;
}

#Create an NZB file according to the specs found on the internet
sub create_nzb{

  my $self = shift;
  my @nzbFileList = @{shift()};
  my %metadata = %{shift()};
  
  my $doc = XML::LibXML::Document->new('1.0','utf-8');
  my $nzb = $doc->createElementNS('http://www.newzbin.com/DTD/2003/nzb','nzb');
  $doc->setDocumentElement($nzb);
  my $head = $doc->createElement('head');
  $nzb->appendChild($head);

  for my $key (keys %metadata) {
    my $metadata = $doc->createElement('metadata');
    $metadata->setAttribute('type'=>$key);
    $metadata->appendTextNode($metadata{$key});
    $head->appendChild($metadata);
  }
  

  for my $nzbFile (@nzbFileList) {
    my $file = $doc->createElement('file');
    $file->setAttribute('poster'=>$nzbFile->{poster});
    $file->setAttribute('date'=>time());
    $file->setAttribute('subject'=>$nzbFile->{subject});
    my $groups = $doc->createElement('groups');
    $file->appendChild($groups);
    for my $groupName (@{$nzbFile->{groups}}) {
      my $group = $doc->createElement('group');
      $group->appendTextNode($groupName);
      $groups->appendChild($group);
    }

    my $segments = $doc->createElement('segments');
    $file->appendChild($segments);
    my $partNumber=1;    
    for my $segRef  (@{$nzbFile->{segments}}) {
      my ($readSize,$segment) = @$segRef;
      my $seg = $doc->createElement('segment');
      $seg->setAttribute('number'=>$partNumber);
      $seg->setAttribute('bytes'=>$readSize);
      $seg->appendTextNode($segment);
      $segments->appendChild($seg);
      $partNumber+=1;
    }

    $nzb->appendChild($file);
  }
  
  # save
  my $nzbFileName = time().'.nzb';
  open my $out, '>', $nzbFileName;
  binmode $out; # as above
  $doc->toFH($out);
  close($out);
  return $nzbFileName;
  
}


1;
