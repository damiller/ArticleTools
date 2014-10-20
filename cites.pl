#!/usr/bin/perl
use Article;
use Encode;

my @edges;
my @nodes;

my $article;

use Getopt::Long;
Getopt::Long::Configure("bundling");

my %options = ( 'build' => 1 );

GetOptions(\%options,
	   'build|b!',
	   'file|f=s');

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

# first we fetch all the info
foreach my $doi (@doilist) {
    $article = new Article("adsabs", $doi);
}

# now we build the edges and nodes
print "Building dot graph...\n";
while ( ($bibcode, $article) = each %{$article->{_library}} ) {
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
print $dotfile "\toverlap=false\n";
print $dotfile "\t$_\n" foreach @nodes;
print $dotfile "\t$_\n" foreach @edges;
print $dotfile "}\n";

if ($options{'build'}) {
    print "Making dot graph.\n";
    system("dot -Tpng -ocites.png $outdotfilename");
}
