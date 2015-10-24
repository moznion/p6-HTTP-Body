use v6;
use Test;
use JSON::Fast;
use Digest::MD5;
use HTTP::Body;

my $path = "$*CWD/t/data/urlencoded";

for 1..6 -> $i {
    my $test = sprintf("%03d", $i);

    my %headers = from-json(open("$path/$test\-headers.json", :bin).slurp-rest);
    my %results = from-json(open("$path/$test\-results.json", :bin).slurp-rest);
    my $content = open("$path/$test\-content.dat", :bin);

    my $body = HTTP::Body.new(%headers<Content-Type>, %headers<Content-Length>);

    while my $buffer = $content.read(1024) {
        $body.add($buffer);
    }

    is($body.body.defined, False, "$test UrlEncoded body" );

    my $expected-param = %results<param>;

    # XXX
    if ($i === 1 || $i === 3) {
        $expected-param<text2> = utf8.new(195, 131, 194, 165, 195, 131, 194, 164, 195, 131, 194, 182, 195, 131, 194, 165, 195, 131, 194, 164, 195, 131, 194, 182).decode;
    }

    is-deeply($body.param, $expected-param, "$test UrlEncoded param");
	is-deeply($body.param-order, %results<param_order> ?? %results<param_order> !! [], "$test UrlEncoded param_order");
    is-deeply($body.upload, %results<upload>, "$test UrlEncoded upload" );

    is($body.state, HTTP::Body::DONE, "$test UrlEncoded state");
    is($body.length, $body.content-length, "$test UrlEncoded length");

    # Check trailing header on the chunked request
    if $i === 3 {
        my $content = open("$path/002-content.dat", :bin);
        my $buf = $content.read(4096);

        my $md5 = $body.trailing-headers.field('Content-MD5').values;
        is($md5.elems, 1, "$test md5 header size");
        is($md5[0], Digest::MD5.new.md5_hex($buf.decode), "$test trailing header ok" );
    }
}

done-testing;


