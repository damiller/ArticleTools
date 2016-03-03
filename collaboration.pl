#!/usr/bin/perl
use strict;
use warnings;

use Article;
use Encode;
use Getopt::Long;
use Unicode::Normalize;
use LWP::Simple;
use XML::XPath;
use XML::LibXML;
use List::Util qw(max);

binmode STDOUT, ':utf8';

Getopt::Long::Configure("bundling");

my $central_author;
my %options = ( 'author' => \$central_author,
		'build' => 1,
		'create-frequency-hashes' => 1,
		'login' => \$Article::crossreflogin,
		'scale' => 2.0);

GetOptions(\%options, 
	   'author|a=s',
	   'build|b!',
	   'create-frequency-hashes!', 
	   'file|f=s',
	   'login|l=s',
	   'normalize',
	   'orcid|o=s',
	   'print-authors!',
	   'print-edges!',
	   'print-edges-by-node!',
	   'print-frequency-hashes!',
	   'print-substitutions!',
	   'scale=f');

if ( !defined $central_author ) {
    print "Central author not provided. Program will guess based on frequency in DOIs\n";
}

if ( $Article::crossreflogin eq "" ) {
    print "Crossref login needs to be provided.\n";
    exit
}

print "Crossref login is $Article::crossreflogin\n";
#
#my $num_args = $#ARGV + 1;
#if ($num_args < 2) {
#    print "usage: crossref.pl [central author] DOI DOI ...\n";
#    exit;
#}

my @doilist;
if (exists($options{'file'})) {
    open(my $doifile, "<", $options{'file'})
	or die("Cannot open DOI file.");
    while (<$doifile>) {
	chomp;
	push(@doilist, $_);
    }
    close($doifile);
} 

if (exists($options{'orcid'})) {
    my $URL = "http://pub.orcid.org/$options{'orcid'}/orcid-works";
    my $result = get("$URL");
    
    my $doc = XML::LibXML->new->parse_string($result);
    my $xml = XML::LibXML::XPathContext->new;
    $xml->registerNs('x','http://www.orcid.org/ns/orcid');

    my $count = 0;
    foreach my $work ($xml->findnodes('//x:orcid-work', $doc)) {
	my $title = $xml->findnodes('./x:work-title/x:title', $work);
	foreach my $ids ($xml->findnodes('.//x:work-external-identifier', $work)) {
	    my $type = $xml->findnodes('./x:work-external-identifier-type', $ids);
	    my $id = $xml->findnodes('./x:work-external-identifier-id', $ids);
	    if ($type eq "doi") {
		$count++;
		push(@doilist, $id);
	    }
	}     
    }
    
    print "$count DOIs grabbed from ORCID\n";
}
   
if (scalar @doilist == 0) {
    print "No DOIs found.\n";
    exit;
}

my $outdotfilename = "collaboration.dot";
open(my $dotfile, ">:encoding(UTF-8)", $outdotfilename);

print $dotfile "graph crossref {\n";
print $dotfile "\tsplines=true\n";
# print $dotfile "\toverlap=scale\n";
print $dotfile "\toverlap=false\n";

my %edges = ();
my %substitutions = ();
my $maxfreq = 1;

my @allauthors;
my %testauthors;
my $outputName;
my $article;

foreach my $doi (@doilist) {
    # $article = new Article("adsabs", $doi);
    $article = new Article("crossref", $doi);

    my $name;
    my @authors;

    foreach my $contributor (@{$article->{_authors}}) {
	$name = normalizeName($contributor);
	$outputName = compareName($name, \@allauthors);

	if ($outputName eq $name) {
	    push (@allauthors, $name);
	    $testauthors{"$name"} = 0;
	} elsif ($outputName ne "") {
	    # name is similar to another name
	    # use NFKD length to prefer accents if they are missing in the database
	    if (length(NFKD($outputName)) > length(NFKD($name))) {
		$substitutions{"$name"} = $outputName;
	    } else {
		$substitutions{"$outputName"} = $name;
		# go replace previous edges
		if ($options{'print-substitutions'}) {
		    print "Replacing previous edges with $outputName => $name\n";
		}
		while ((my $key, my $value) = each %edges) {
		    if ($key =~ /$outputName/) {
			my ($lauth, $rauth) = split ' -- ', $key;
			s/\"//g for $lauth,$rauth;

			s/^$outputName$/$name/g for ($lauth,$rauth);
			my $newkey = qq("$lauth" -- "$rauth");

			if ($options{'print-substitutions'} && $newkey !~ $key ) {
			    print "$key => $newkey\n";
			}
			$edges{"$newkey"} = $value;
			delete($edges{$key});
		    }
		}
		# adjust it in the authors list
		$testauthors{"$name"} = delete $testauthors{"$outputName"};
		s/$outputName/$name/ for @allauthors;
	    }
	}
	if (defined($substitutions{"$name"})) {
	    if ($options{'print-substitutions'}) {
		print qq(Substituting $name => $substitutions{"$name"}\n);
	    }
	    $name = $substitutions{"$name"};
	}
	$testauthors{"$name"}++;
	push(@authors, $name);	
    } 

# export a dot graph
    foreach my $auth1 (@authors) {
#	my $lauth1 = encode("utf8", $auth1);
	my $lauth1 = $auth1;
	foreach my $auth2 (@authors) {	    
#	    my $lauth2 = encode("utf8", $auth2);
	    my $lauth2 = $auth2;
	    next if $lauth1 ge $lauth2;
	    my $string = qq("$lauth1" -- "$lauth2");

	    $edges{"$string"}++;
	    $maxfreq = $edges{"$string"} if $edges{"$string"} > $maxfreq;
	}
    }
}

my $max_key;
my $max_value = 0;
while ((my $key, my $value) = each %testauthors) {
    if ($value > $max_value) {
	$max_key = $key;
	$max_value = $value;
    }
}

$central_author = $max_key if (!defined $central_author); 

$central_author = normalizeName($central_author);
print "Creating graph for $central_author.\n";

if ($options{'print-substitutions'}) {
    print "Substitutions:\n";
    print map { "  $_ => $substitutions{$_}\n" } keys %substitutions;
}

my @sortedkeys = sort {$edges{$a} <=> $edges{$b} } keys %edges;
my @sortedauthors = sort {uc(surnameFirst($a)) cmp uc(surnameFirst($b))} @allauthors;

if ($options{'print-edges'}) {
#    foreach my $key (@sortedkeys) {
#	print "  $key $edges{$key}\n";
#    }
    print map { "  $_ $edges{$_}\n" } @sortedkeys;
}

my %frequencyhash;
my %integratedfreq;
my %total;

if ($options{'create-frequency-hashes'}) {
    foreach my $key (@sortedkeys) {
	my $value = $edges{$key};
	my ($lauth, $rauth) = split ' -- ', $key;
	s/\"//g for $lauth,$rauth;

	$frequencyhash{$lauth}{$value}++;
	$frequencyhash{$rauth}{$value}++;
    }

    my $max;

    foreach my $author (@sortedauthors) {
	if ($options{'print-frequency-hashes'} || $author =~ $central_author) {
	    print "Frequency map for $author:\n"; 
	}
	my @sortedkeysauthor = sort { $a <=> $b } keys %{ $frequencyhash{$author} };
	$total{$author} = 0;
	foreach my $key ( sort { $a <=> $b } @sortedkeysauthor ) {
	    $max = $key;
	    if ($options{'print-frequency-hashes'} || $author =~ $central_author) {
		print "  $key => $frequencyhash{$author}{$key}\n";
	    }
	    $total{$author} += $frequencyhash{$author}{$key}; 	 
	    $integratedfreq{$author}{$key} = $total{$author};
	}
    }
    print "  Total: $total{$central_author}\n";
    
    open (my $freqfile, ">frequency.dat");
    if ($options{'normalize'}) {
	printf $freqfile "%2d %f\n", $_, exists($frequencyhash{$central_author}{$_}) ? $frequencyhash{$central_author}{$_}/$total{$central_author} : 0 for (1..$max);
    } else { 
	printf $freqfile "%2d %d\n", $_, exists($frequencyhash{$central_author}{$_}) ? $frequencyhash{$central_author}{$_}             : 0 for (1..$max);
    }
    close($freqfile);
}

if ($options{'print-edges-by-node'}) {
    foreach my $author (@sortedauthors) {
	print "$author :\n";
	foreach my $key (@sortedkeys) {
	    next if ($key !~ m/$author/);
	    print "  $key $edges{$key}\n";
	}
    }
}

while ((my $key, my $value) = each %edges) {
    my $length;
    if (%integratedfreq) {
	my ($lauth, $rauth) = split ' -- ', $key;
	s/\"//g for $lauth,$rauth;
	
	if ( !defined $integratedfreq{$lauth}{$value} ) {
	    print nice_string("Integrated freq not defined for $lauth, $value") . "\n";
	}
	if ( !defined $total{$lauth} ) {
	    print nice_string("Total not defined for $lauth") . "\n";
	}
	if ( !defined $integratedfreq{$rauth}{$value} ) {
	    print nice_string("Integrated freq not defined for $rauth, $value") . "\n";
	}
	if ( !defined $total{$rauth} ) {
	    print nice_string("Total not defined for $rauth") . "\n";
	}

	my $l1 = sqrt($total{$lauth} - $integratedfreq{$lauth}{$value} + $frequencyhash{$lauth}{$value});
	my $l2 = sqrt($total{$rauth} - $integratedfreq{$rauth}{$value} + $frequencyhash{$rauth}{$value});
	# my $l1 = sqrt($total{$lauth} - $integratedfreq{$lauth}{$value} + 1);
	# my $l2 = sqrt($total{$rauth} - $integratedfreq{$rauth}{$value} + 1);
	# use the geometric mean
	$length = $options{'scale'} * sqrt($l1 * $l2);
    } else {
	$length = $options{'scale'} * sqrt(1 + $maxfreq - $value);
    }
    if ($key =~ $central_author) {
	printf $dotfile "\t$key [len=%.2f penwidth=%.2f color=\"#0000ff\" w=100.0]\n", $length, sqrt($value);
    } else {
	printf $dotfile "\t$key [len=%.2f style=dashed w=1.0]\n", $length;
#	printf $dotfile "\t$key [style=dashed, w=0.01]\n";
    }
}

print $dotfile "}\n";

$edges{qq("$central_author" -- "$central_author")} = 0;

@sortedauthors = sort {$edges{$central_author le $a ? qq("$central_author" -- "$a") : qq("$a" -- "$central_author")} <=> $edges{$central_author le $b ? qq("$central_author" -- "$b") : qq("$b" -- "$central_author")}} @allauthors;

if ($options{'print-authors'}) {
    print "Authors:\n";
    print join("\n", map {surnameFirst($_) . ' (' . ($_ eq $central_author ? "0" : $edges{$central_author le $_ ? qq("$central_author" -- "$_") : qq("$_" -- "$central_author")}) . ')' } @sortedauthors ) . "\n";
}

if ($options{'build'}) {
    print "Making dot graph.\n";
    system("neato -Tpng -ocollaboration.png $outdotfilename");
}

sub normalizeName
{
    my $inputName;
    my $preName = shift;

    $inputName = $preName; 
#    print $inputName;

# remove leading and trailing spaces
    $inputName =~ s/^\s+//;
    $inputName =~ s/\s+$//;

    my $givenName;
    my $surname;

#    if ($inputName =~ /\./) {
#	($givenName, $surname) = ($inputName =~ /^(.*\.)\s(.*)$/);
#    } else {
#	($givenName, $surname) = ($inputName =~ /^(.*)\s(\S*)$/);
#    }
    if ($inputName =~ /,/) {
	($surname, $givenName) = ($inputName =~ /^(.*),\s(.*)/);
    } else {
	# deal with names with format "J. Doe" or "John Doe" instead of "Doe, J."
	if ($inputName =~ /\./) {
	    ($givenName, $surname) = ($inputName =~ /^(.*\.)\s(.*)/);
	} else {
	    # here we assume that the last name is the last word if multiple names are given
	    ($givenName, $surname) = ($inputName =~ /^(.*)\s(.*)/);
	}
    }

    if (!defined($givenName) || !defined($surname)) {
	print "UNDEFINED name for $inputName\n";
	print "Given name = $givenName\n" if (defined($givenName));
	print "Surname    = $surname\n" if (defined($surname));
	exit;
    }
# whack first name to initials
    $givenName =~ s/^([A-Z])([a-z]+)[^.]/$1./g;
    
# strip single spaces after periods
#    do {} while ($inputName =~ s/(\s)(\w.)(\s)/$2$3/g) > 0;
#    do {} while ($inputName =~ s/(\s)(\w+\..)(\s)/$2$3/g) > 0;
# place spaces after periods
    $givenName =~ s/\.(\w.)/. $1/g;

# separate capital letters
    do {} while ($givenName =~ s/([A-Z])([A-Z])/$1 $2/g) > 0;

# put in periods
    $givenName =~ s/([A-Z])(\s)/$1.$2/g;
# put in final period
    $givenName =~ s/([A-Z])$/$1./g;

# make second word have proper caps
    $surname =~ s/(\w)(\w+)/\u$1\L$2/g;
# capitalize 3rd letter of McNames
    if ($surname =~ m/^Mc/) {
	substr($surname, 2) = ucfirst(substr($surname, 2));
    }
# if surname has a roman suffix, capitalize it all
    $surname =~ s/(\w+)(\s)([IiVvXx]+)/$1$2\U$3/g;
    
    $inputName = "$givenName $surname";

    if ($preName ne $inputName ) {
	# peek at the global variable
	if ($options{'print-substitutions'}) {
	    print "$preName => $givenName, $surname => $inputName\n";
	}
    }

    # fix any funky unicode spaces
    $inputName =~ s/\p{Zs}/ /g;

    return $inputName;
}

sub compareName
{
    my $name1 = shift;
    my $outputName = $name1;
    my $ref = shift;
    my @nameList = @{$ref};
    my $testname1 = "";
    my $testname2 = "";

    return $outputName if scalar @nameList == 0;

    foreach my $name2 (@nameList) {
	if ($name1 eq $name2) {
	    $outputName = "";
	    next;
	}

	my $testname1 = $name1;
	my $testname2 = $name2;	

	# remove hyphens
	s/-//g for ($testname1,$testname2);

	# reduce to one single initial
	$testname1 =~ s/(\w+\.)(\s?\w{1,2}\.?)+\./$1/g;
	$testname2 =~ s/(\w+\.)(\s?\w{1,2}\.?)+\./$1/g;
	# drop strange two-letter abbreviations 
	$testname1 =~ s/([A-Z])[a-z]\./$1./g;
	$testname2 =~ s/([A-Z])[a-z]\./$1./g;
	# remove Roman numeral suffixes
	$testname1 =~ s/(\w+\.[\s-])+(\w+)(\s[IiVvXx]+)/$1$2/g;
	$testname2 =~ s/(\w+\.[\s-])+(\w+)(\s[IiVvXx]+)/$1$2/g;

	# remove non-standard characters
	$testname1 = encode("iso-8859-1",NFKD($testname1));
	$testname2 = encode("iso-8859-1",NFKD($testname2));
	$testname1 =~ s/[^\w\.\s]//g;
	$testname2 =~ s/[^\w\.\s]//g;

	if ($testname1 =~ m/$testname2/i) {
	    $outputName = $name2;
	    return $outputName;
	}
    }

    return $outputName;
}

sub surnameFirst {
    my $author = shift;

    s/([\w\s\.-]+\.)\s([\w\-\s]+)$/  $2, $1/g for $author;

    return $author;
}

sub nice_string {
    join("",
         map { $_ > 255 ?                  # if wide character...
		   sprintf("\\x{%04X}", $_) :  # \x{...}
		   chr($_) =~ /[[:cntrl:]]/ ?  # else if control character ...
		   sprintf("\\x%02X", $_) :    # \x..
		   chr($_)                     # else as themselves
         } unpack("U*", $_[0]));           # unpack Unicode characters
}

