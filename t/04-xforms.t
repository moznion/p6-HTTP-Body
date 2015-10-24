use v6;
use Test;
use JSON::Fast;
use HTTP::Body;

my $path = "$*CWD/t/data/xforms";

for 2..2 -> $i {
    my $test = sprintf("%03d", $i);

    my %headers = from-json(open("$path/$test\-headers.json", :bin).slurp-rest);
    my %results = from-json(open("$path/$test\-results.json", :bin).slurp-rest);
    my $content = open("$path/$test\-content.dat", :bin);

    my $body = HTTP::Body.new(%headers<Content-Type>, %headers<Content-Length>);

    while my $buffer = $content.read(1024) {
        $body.add($buffer);
    }

    my @temps;
    for %($body.upload).pairs -> $pair {
        my $value = $pair.value;
        for ($value ~~ List ?? @$value !! $value ) {
            @temps.push($_<tempname>.delete);
        }
    }

    is-deeply($body.body.slurp-rest, %results<body>, "$test XForms body");
    is-deeply($body.param, %results<param>, "$test XForms param");
	is-deeply($body.param-order, %results<param_order> ?? %results<param_order> !! [], "$test XForms param_order");
    is-deeply($body.upload, %results<upload>, "$test XForms upload");
    # if ($body->isa('HTTP::Body::XFormsMultipart')) {
    #     cmp_ok( $body->start, 'eq', $results->{start}, "$test XForms start" );
    # }
    # else {
        ok(1, "$test XForms start");
    # }
    is($body.state, HTTP::Body::DONE, "$test XForms state");
    is($body.length, %headers<Content-Length>, "$test XForms length");
}

done-testing;

