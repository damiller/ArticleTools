package GeneralizedHarmonic;

use strict;
use warnings;

sub harmonic {
    my ($k, $gamma) = @ARGV;
    my $H  = 0;
    my $Hp = 0;

    for (1..$k) {
	$H += 1/($_**$gamma);
	$Hp += -log($_) / ($_**$gamma);
    }

    return ($H, $Hp);
}

1




