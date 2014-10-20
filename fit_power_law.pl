#!/usr/bin/perl
use strict;
use warnings;

use List::Util qw(max);

if ($#ARGV < 0) {
    print "usage: $0 (datafile) [xmin xmax]\n";
    exit;			 
}
my $xmin = $ARGV[1];
my $xmax = $ARGV[2];

my %frequencyhash;
my %cdf;

open(my $datafile, "<", $ARGV[0]);
while (<$datafile>) {
    chomp;
    my @fields = split;
    my ($x, $freq) = @fields;

    $frequencyhash{$x} = $freq;
    $cdf{$x} = (defined($cdf{$x-1}) ? $cdf{$x-1} : 0) + $freq;
}

# calculate the target zetaprime / zeta
my $target = 0; 
my $n = 0;
while ( (my $key, my $value) = each %frequencyhash ) {
    next if $value == 0;
    next if defined($xmin) && $key < $xmin;
    next if defined($xmax) && $key > $xmax;

    $target += -log($key) * $value;    
    $n += $value;
}

$target /= $n;
$xmin = 1    unless defined($xmin);
$xmax = max(1000, max (keys %frequencyhash) ) unless defined($xmax);

print "Range bounds: $xmin - $xmax\n";
print "Number of samples: $n\n";
print "Target zeta log derivative: $target\n";

my $gamma = zeta_div_binary_search($xmin,$xmax, $target, 0.00001,0.00001);
my ($z, $zp, $zpp) = bounded_zeta_all($gamma, $xmin, $xmax);
my $errgamma = 1 / (sqrt($n) * ($zpp / $z - ($zp / $z) ** 2.));
printf "Gamma = %6f +/- %6f\n", $gamma, $errgamma;
printf "Bounded zeta = %6f\n", $z;

# normalize the CDF
$_ /= $n for (values %cdf);
my %pdffit;
my %cdffit;
for ($xmin..$xmax) {
    $pdffit{$_} = 1 / ($_**$gamma) / bounded_zeta($gamma, $xmin,$xmax);
    $cdffit{$_} = (defined($cdffit{$_ - 1}) ? $cdffit{$_ - 1} : 0) + $pdffit{$_};
}
my $KS = max map {abs($cdffit{$_} - $cdf{$_})} keys %cdf;
printf "KS variable: %6f\n", $KS;

sub bounded_zeta {
    my $gamma = shift;
    my $min = shift;
    my $max = shift;
    my $sum = 0;

    for ($min .. $max) {
	$sum += 1/($_**$gamma);
    }

    return $sum;
}

sub bounded_zeta_prime {
    my $gamma = shift;
    my $min   = shift;
    my $max   = shift;
    my $sum   = 0;

    for ($min .. $max) {
	$sum += -log($_) / ($_**$gamma);
    }

    return $sum;
}
		       
sub bounded_zeta_prime_prime {
    my $gamma = shift;
    my $min   = shift;
    my $max   = shift;
    my $sum   = 0;
    
    for ($min .. $max) {
	$sum += (log($_) ** 2) / ($_**$gamma)
    }

    return $sum
}

sub bounded_zeta_all {    
    return (bounded_zeta(@_), bounded_zeta_prime(@_),
	    bounded_zeta_prime_prime(@_));
}

sub zeta_div_binary_search {
    my $min      = shift;
    my $max      = shift;
    my $zeta     = shift;
    my $delta    = shift;
    my $epsilon  = shift;
    my $gamma    = 0;
    my $newgamma = 2;  # initial guess
    my $result   = 0;

    until ( abs($result - $zeta) < $epsilon &&
	    abs($gamma - $newgamma) < $delta ) {    
	$gamma = $newgamma;
	my ($z, $zp, $zpp) = bounded_zeta_all($gamma, $min, $max);
	$result = $zp / $z;
	my $deriv = $zpp / $z - ($zp / $z) * ($zp / $z);

	$newgamma = $gamma + ($zeta - $result) / $deriv;
	
	printf "%6f %6f %6f %6f %6f\n", $gamma, $result, $zeta, $deriv, $newgamma;      
    }
    
    return $newgamma;
}
