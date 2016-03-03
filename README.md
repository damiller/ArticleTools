ArticleTools
============

Tools to make collaboration and citation graphs from a list of article DOIs

The tools currently consist of two Perl scripts:
./collaboration.pl
and 
./cites.pl

The recommended first step is to find the DOIs for all the articles of interest and put them in a text file, one per line. Alternatively, the collaboration script can pull the DOIs based on what is defined in an ORCID profile. Currently collaboration script also needs a CrossRef login to pull the relevant data from the web. Scripts are also dependent on the graphviz package to create their output figures. 
