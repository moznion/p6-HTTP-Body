use v6;
use Test;
use JSON::Fast;
use HTTP::Body;

my $path = "$*CWD/t/data/octetstream";

for 1..3 -> $i {
    my $test = sprintf("%03d", $i);

    my $headers = from-json(open("$path/$test\-headers.json", :bin).slurp-rest);
    my $results = open("$path/$test\-results.dat", :bin).slurp-rest;
    my $content = open("$path/$test\-content.dat", :bin);

    my $body = HTTP::Body.new($headers<Content-Type>, $headers<Content-Length>);

    while my $buffer = $content.read(1024) {
        $body.add($buffer);
    }

    isa-ok($body.body, IO::Handle, "$test OctetStream body isa");
    my $data = $body.body.slurp-rest;

    is($data, $results, "$test UrlEncoded body");

    is($body.state, HTTP::Body::DONE, "$test UrlEncoded state");
    is($body.length, $body.content-length, "$test UrlEncoded length");
}

done-testing;

