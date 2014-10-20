package Article;

use strict;
use Encode;
use LWP::Simple;
use XML::XPath;

my %library;
my %abbreviations;

our $maxcitation = 1;

sub new {
    my $class = shift;
    my $mode  = shift;
    my $self = {
	_doi => shift,
	_library => \%library,
	_abbreviations => \%abbreviations
    };    
    bless $self, $class;

    # bail out if we just want to create a blank article
    if (!defined $mode) {
	return $self;
    }
    $self->{_citationlevel} = 0;
    $self->{_referencelevel} = 0;

    if ($mode =~ "crossref") {
	$self->fetchCrossrefData( $self->{_doi} );
    } elsif ($mode =~ "adsabs") {
	$self->fetchAdsabsData( $self->{_doi} );
	$self->fetchAdsabsCitations();
#	$self->fetchAdsabsReferences() if !$self->{_notfound};
    }    

    return $self;
}

sub fetchCrossrefData {
    my ($self, $doi) = @_;
    my $URL="http://www.crossref.org/openurl?pid=damiller\@mailaps.org&id=$doi&redirect=false";
    print "Fetching data for DOI $doi\n";
    my $result = decode_utf8(get("$URL"));
    my $xp = XML::XPath->new(xml => $result);

    foreach my $contributor ($xp->find('//contributor')->get_nodelist) {
	my $name = $contributor->find('given_name')->string_value;
	$name .= ' ';
	$name .= $contributor->find('surname')->string_value; 
	push(@{$self->{_authors}}, $name);	
    }    
}

sub fetchAdsabsData {
    my ($self, $doi) = @_;
    my $URL="http://adsabs.harvard.edu/cgi-bin/abs_connect?doi=$doi&data_type=XML";
    print "Fetching data for DOI $doi\n";
    my $result = decode_utf8(get("$URL"));
    if ($result !~ "<?xml") {
	print "  No XML document found.\n";
	return;
    }

    my $xp = XML::XPath->new(xml => $result);
    my $nodeset = $xp->find('//record');
    
    if ($nodeset->size == 0) {
	print "No record found.\n";	
	$self->{_notfound} = 1;
	return;
    } elsif ($nodeset->size > 1) {
	print "MULTIPLE articles found.\n";
    }

    foreach my $article ($xp->find('//record')->get_nodelist) {
	$self->readAdsabsRecord($xp, $article);
    }    
}

sub fetchAdsabsCitations {
    my $self = shift;
    my $doi = $self->{_doi};

    if (!defined $doi || $self->{_notfound}) {
	return;
    }

    my $URL="http://adsabs.harvard.edu/cgi-bin/abs_connect?doi=$doi&data_type=XML&query_type=CITES";
    print "Fetching citations for DOI $doi : citation level = $self->{_citationlevel}\n";
    my $result = decode_utf8(get("$URL"));
    if ($result !~ "<?xml") {
	print "  No XML document found.\n";
	return;
    }

    my $xp = XML::XPath->new(xml => $result);
    my $nodeset = $xp->find('//record');
    print "  " . $nodeset->size . " citations found\n";

    foreach my $article ($nodeset->get_nodelist) {
	my $bibcode = $article->find('bibcode')->string_value;
	my $thisarticle;
	# see if this already exists in the library and then only mantain one record
	if ( defined $self->{_library}{$bibcode} ) {
	    push(@{$self->{_citations}}, $self->{_library}{$bibcode});	    
	    $thisarticle = $self->{_citations}[-1];
	    if ($self->{_citationlevel} + 1 < $thisarticle->{_citationlevel}) {
		$thisarticle->{_citationlevel} = $self->{_citationlevel} + 1;
	    }
	} else {
	    push(@{$self->{_citations}}, new Article() );
	    $thisarticle = $self->{_citations}[-1];
	    $thisarticle->readAdsabsRecord($xp, $article);
	    $thisarticle->{_citationlevel} = $self->{_citationlevel} + 1;
	    if ($thisarticle->{_citationlevel} < $maxcitation) {
		$thisarticle->fetchAdsabsCitations();
	    }
	}
    }
}

sub fetchAdsabsReferences {
    my $self = shift;
    my $doi = $self->{_doi};

    my $URL="http://adsabs.harvard.edu/cgi-bin/abs_connect?doi=$doi&data_type=XML&query_type=REFS";
    print "Fetching references for DOI $doi\n";
    my $result = decode_utf8(get("$URL"));
    if ($result !~ "<?xml") {
	print "  No XML document found.\n";
	return;
    }

    my $xp = XML::XPath->new(xml => $result);

    foreach my $article ($xp->find('//record')->get_nodelist) {
	my $bibcode = $article->find('bibcode')->string_value;
	my $thisarticle;
	# see if this already exists in the library and then only mantain one record
	if ( defined $self->{_library}{$bibcode} ) {
	    push(@{$self->{_references}}, $self->{_library}{$bibcode});
	    my $thisarticle = $self->{_references}[-1];
	} else  {
	    push(@{$self->{_references}}, new Article() );
	    my $thisarticle = $self->{_references}[-1];
	    $thisarticle->readAdsabsRecord($xp, $article);
	}
	if ($self->{_referencelevel} + 1 < $thisarticle->{_referencelevel}) {
	    $thisarticle->{_referencelevel} = $self->{_referencelevel} + 1;
	}
    }
}

sub readAdsabsRecord {
    my $self = shift;
    my $xp = shift;
    my $article = shift;

    if ($xp->exists('./errormessage', $article)) {
	print $article->find('errormessage')->string_value;
	$self->{_notfound} = 1;
	return;
    }

    $self->{_bibcode} = $article->find('bibcode')->string_value;
    if ($article->find('origin')->string_value eq "ARXIV") {
	$self->{_arxiv} = (split(':', $article->find('journal')->string_value))[-1];
    }

    if ($xp->exists('./DOI', $article)) {
	$self->{_doi} = $article->find('DOI')->string_value;
    };

    foreach my $author ($xp->find('./author', $article)->get_nodelist) {
	push(@{$self->{_authors}}, $author->string_value);	
    }
    if ($xp->exists('./pubdate', $article)) {
	($self->{_pubmonth}, $self->{_pubyear}) = 
	    split(' ', $article->find('pubdate')->string_value);
    }

    $self->{_library}{$self->{_bibcode}} = $self;
}

sub getAbbreviation {
    my $self = shift;

    if ( defined $self->{_abbreviation} ) {
	return $self->{_abbreviation};
    }

    # this can require some rearranging for different author formats
    #   only take the surname
    my $temp=$self->{_authors}[0];
    $temp =~ s/\s//g;
    my $abbr = substr($temp, 0, 3);
    $abbr =~ s/,//g; # strip any comma for two-character last names
    $abbr .= substr($self->{_pubyear}, -2);
    my $index = 0;
    my $extabbr = $abbr;

    while ( defined $self->{_abbreviations}{$extabbr} &&
	 $self->{_abbreviations}{$extabbr} ne $self->{_bibcode} ) {
	# this abbreviation is already reserved for another article
	#   append a unique letter to resolve the conflict
	$extabbr = $abbr . chr(97 + $index);
	$index++;
    }
    $self->{_abbreviations}{$extabbr} = $self->{_bibcode};
    $self->{_abbreviation} = $extabbr;

    return $extabbr;
}

sub getUrl {
    my $self = shift;
    my $doi = $self->{_doi};
    my $arxiv = $self->{_arxiv};

    if (defined $doi) {	
	$self->{_url} = "http://dx.doi.org/$doi";
    } elsif (defined $arxiv) {
	$self->{_url} = "http://arxiv.org/abs/$arxiv";
    } else {
	return undef;
    }

    return $self->{_url};
}

1;
