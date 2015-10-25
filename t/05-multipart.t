use v6;
use Test;
use File::Temp;
use JSON::Fast;
use Digest::MD5;
use HTTP::Body;

my $path = "$*CWD/t/data/multipart";

for 1..15 -> $i {
    my $test = sprintf("%03d", $i);

    my %headers = from-json(open("$path/$test\-headers.json", :bin).slurp-rest);

    my %results;
    if IO::Path.new("$path/$test\-results.json").e {
        %results = from-json(open("$path/$test\-results.json", :bin).slurp-rest);
    }

    my $content = open("$path/$test\-content.dat", :bin);

    my $body = HTTP::Body.new(%headers<Content-Type>, %headers<Content-Length>);

    my $tempdir = tempdir('*******', :unlink);
    $body.tmpdir($tempdir);

    while my $buffer = $content.read(1024) {
        $body.add($buffer);
    }

    # Tests >= 10 use auto-cleanup
    # if $i >= 10 {
    #     $body.cleanup(True);
    # }

    # Save tempnames for later deletion
    # my @temps;
    # for $body.upload.pairs -> $pair {
    #     my ($field, $value) = $pair.kv;
    #
    #     # for $value ~~ List ?? @$value !! $value {
    #         # like($_->{tempname}, qr{$regex_tempdir}, "has tmpdir $tempdir");
    #         # push @temps, $_->{tempname};
    #     }
    #
    #     # # Tell Test::Deep to ignore tempname values
    #     # if ( ref $value eq 'ARRAY' ) {
    #     #     for ( @{ $results->{upload}->{$field} } ) {
    #     #         $_->{tempname} = ignore();
    #     #     }
    #     # }
    #     # else {
    #     #     $results->{upload}->{$field}->{tempname} = ignore();
    #     # }
    # }

    is($body.body.defined ?? $body.body.slurp-rest !! '', %results<body> ?? %results<body> !! '', "$test MultiPart body");
    is-deeply($body.param, %results<param> ?? %results<param> !! {}, "$test MultiPart param");
    is-deeply($body.param-order, %results<param_order> ?? %results<param_order> !! [], "$test MultiPart param_order");

    is-deeply($body.upload, %results<upload>, "$test MultiPart upload") if %results<upload>;

    is($body.state, HTTP::Body::DONE, "$test MultiPart state");
    is($body.length, $body.content-length, "$test MultiPart length");

    # if $i < 10 {
    #     # Clean up temp files created
    #     unlink map { $_ } grep { -e $_ } @temps;
    # }
    #
    # undef $body;

    # # Ensure temp files were deleted
    # for my $temp ( @temps ) {
    #     ok( !-e $temp, "Temp file $temp was deleted" );
    # }
}

done-testing;

