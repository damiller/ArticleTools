#!/usr/bin/perl
use Article;
use Encode;

binmode STDOUT, ":utf8";

my @edges;
my @nodes;

my $article;

use Getopt::Long;
Getopt::Long::Configure("bundling");

my %options = ( 'build' => 1,
		'unflatten' => 1,
		'sort-by-date' => 1,
		'cite-level' => \$Article::maxcitation );
GetOptions(\%options,
	   'build|b!',
	   'cite-level|l=i',
	   'file|f=s',
	   'unflatten|u!',
	   'sort-by-date|s!');

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
my $outdotfilename = "cites.dot";
my $maxcitations = 0;
my $citations;

# first we fetch all the info
foreach my $doi (@doilist) {
    $article = new Article("adsabs", $doi);
    $citations = scalar @{$article->{_citations}};
    $maxcitations = $citations if $citations > $maxcitations;
}

# now we build the edges and nodes
print "Building dot graph...\n";

my @sortedkeys; 

if ($options{'sort-by-date'}) {
    @sortedkeys = sort {$article->{_library}{$a}->{_pubtime} <=> $article->{_library}{$b}->{_pubtime}} keys %{$article->{_library}};
} else {
    @sortedkeys = keys %{$article->{_library}};
}

foreach (@sortedkeys) {
    $article = $article->{_library}{$_};
    next if $article->{_notfound};

    my $abbr = encode("utf8",$article->getAbbreviation());
    my $url = $article->getUrl();

    if (defined $url) {
	if ($article->{_citationlevel} < 1) {
	    push(@nodes, "\"$abbr\" [href=\"$url\", fontcolor=blue]");
	} else {
	    push(@nodes, "\"$abbr\" [href=\"$url\"]");
	}
    }

    foreach my $citation (@{$article->{_citations}}) {
	next if $citation->{_notfound};

	my $citeabbr = encode("utf8",$citation->getAbbreviation());
	push(@edges, "\"$citeabbr\" -> \"$abbr\"");
    }
}

print "  " . @nodes . " nodes and " . @edges . " edges.\n";

# print map {"$_ => $article->{_library}{$_}->{_url}\n"} keys %{$article->{_library}};

open(my $dotfile, ">$outdotfilename");

print $dotfile "digraph adsabsCites {\n";
print $dotfile "\tsplines=true\n";
print $dotfile "\tconcentrate=true\n";
print $dotfile "\t$_\n" foreach @nodes;
print $dotfile "\t$_\n" foreach @edges;
print $dotfile "}\n";

my $stack = int(sqrt($maxcitations));

if ($options{'build'}) {
    print "Making dot graph.\n";
    if ($options{'unflatten'}) {
	system("unflatten -f -l $stack $outdotfilename | dot -Tpng -ocites.png");
    } else {	
	system("dot -Tpng -ocites.png $outdotfilename");
    }
}
