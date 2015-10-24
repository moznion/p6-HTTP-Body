use v6;
use HTTP::Body;
use File::Temp;
unit class HTTP::Body::XForms is HTTP::Body;

method spin() {
    if self.length !== self.content-length {
        return;
    }

    self.body(tempfile(:tempdir(self.tmpdir))[1]);
    self.body.write(self.buffer);

    self.param('XForms:Model', self.buffer.decode);

    self.buffer(Blob.new);

    self.body.seek(0, 0); # rewind
    self.state(HTTP::Body::STATE::DONE);
}

