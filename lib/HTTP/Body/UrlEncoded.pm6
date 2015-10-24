use v6;
use HTTP::Body;
unit class HTTP::Body::UrlEncoded is HTTP::Body;

my %hex-chr;
for 0..255 -> $num {
    my $h = sprintf '%02X', $num;
    %hex-chr{ lc $h } = %hex-chr{ uc $h } = $num.chr;
}

method spin() {
    if self.length !== self.content-length {
        return;
    }

    my $buf = self.buffer.decode;
    $buf ~~ s:global/'+'/ /;
    self.buffer($buf.encode);

    for $buf.split(rx{<[&;]> [\s+]?}) -> $pair {
        my ($name, $value) = $pair.split('=', 2);

        next if !$name.defined || !$value.defined;

        $name  ~~ s:global/'%' (<[0..9 a..f A..F]> ** 2)/%hex-chr{$0}/;
        $value ~~ s:global/'%' (<[0..9 a..f A..F]> ** 2)/%hex-chr{$0}/;

        self.param($name, $value);
    }

    self.buffer(Blob.new);
    self.state(HTTP::Body::STATE::DONE);
}

