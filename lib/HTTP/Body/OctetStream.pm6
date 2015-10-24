use v6;
use HTTP::Body;
use File::Temp;
unit class HTTP::Body::OctetStream is HTTP::Body;

method spin() {
    unless self.body {
        self.body(tempfile(:tempdir(self.tmpdir))[1]);
    }

    if my $length = $.buffer.elems {
        self.body.write($.buffer.subbuf(0, $length));
        $.buffer($.buffer.subbuf($length));
    }

    if self.length === self.content-length {
        self.body.seek(0, 0); # rewind
        self.state(HTTP::Body::STATE::DONE);
    }
}

