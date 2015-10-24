use v6;
use File::Temp;
use HTTP::Header;
unit class HTTP::Body;

enum STATE <BUFFERING DONE>;

my Pair constant @TYPES = (
    'application/octet-stream'          => 'HTTP::Body::OctetStream',
    'application/x-www-form-urlencoded' => 'HTTP::Body::UrlEncoded',
    'multipart/form-data'               => 'HTTP::Body::MultiPart',
    'multipart/related'                 => 'HTTP::Body::XFormsMultipart',
    'application/xml'                   => 'HTTP::Body::XForms',
    'application/json'                  => 'HTTP::Body::OctetStream',
);

has Bool $!cleanup = False;

has Blob $!buffer       = Blob.new;
has Blob $!chunk-buffer = Blob.new;

has IO::Handle $!body;

has Bool $!chunked;
has Int $!content-length;
has Str $!content-type;

has Int $!length = 0;

has %!param       = {};
has @!param-order = [];

has %!upload    = {};
has %!part-data = {};

has STATE $!state = BUFFERING;
has $!tmpdir = tempdir;

has HTTP::Header $!trailing-headers = HTTP::Header.new;

submethod BUILD(:$chunked, :$content-length, :$content-type) {
    $!chunked        = $chunked;
    $!content-length = $content-length;
    $!content-type   = $content-type;
}

method new(Str $content-type, $content-length) {
    my $type;
    my $earliest-index;

    for @TYPES -> $TYPE {
        my $supported = $TYPE.key;
        my $index = index($content-type.lc, $supported);
        if $index.defined && (!$earliest-index.defined || $index < $earliest-index) {
            $type           = $supported;
            $earliest-index = $index;
        }
    }

    my $backend = %@TYPES{ $type || 'application/octet-stream' };

    require ::($backend);
    return ::($backend).bless(
        :chunked(!$content-length.defined),
        :content-length($content-length.defined ?? $content-length !! -1),
        :content-type($content-type||'hoge'),
    );
}

method add(Blob $content is copy) {
    if $!chunked {
        $!chunk-buffer ~= $content;

        while $!chunk-buffer.decode ~~ /^ $<chunk-len-hex> = <[0..9 a..f A..F]>+ .*? \x0D \x0A / {
            my Int $chunk-len = :16($<chunk-len-hex>.Str);

            if $chunk-len === 0 {
                # Strip chunk len
                my $cb = $!chunk-buffer.decode;
                $cb ~~ s/^ <[0..9 a..f A..F]>+ .*? \x0D \x0A //;

                # End of data, there may be trailing headers
                if $cb ~~ / $<headers> = .*? \x0D \x0A / {
                    my ($k, $v) = $<headers>.Str.split(/':'\s*/, 2);
                    if $k && $v {
                        if $.trailing-headers.field($k) {
                            $.trailing-headers.push-field: |($k => $v.split(',')>>.trim);
                        } else {
                            $.trailing-headers.field: |($k => $v.split(',')>>.trim);
                        }
                    }
                }

                $!chunk-buffer = Blob.new;

                # Set content-length equal to the amount of data we read,
                # so the spin methods can finish up.
                $!content-length = $!length;
            } else {
                # Make sure we have the whole chunk in the buffer (+CRLF)
                if $!chunk-buffer.elems >= $chunk-len {
                    # Strip chunk len
                    my $cb = $!chunk-buffer.decode;
                    $cb ~~ s/^ <[0..9 a..f A..F]>+ .*? \x0D \x0A //;

                    # Pull chunk data out of chunk buffer into real buffer
                    my $cb-enc = $cb.encode;
                    $!buffer ~= $cb-enc.subbuf(0, $chunk-len);
                    $cb = $cb-enc.subbuf($chunk-len).decode;

                    # Strip remaining CRLF
                    $cb ~~ s/^ \x0D \x0A //;

                    $!chunk-buffer = $cb.encode;

                    $!length += $chunk-len;
                }
                else {
                    # Not enough data for this chunk, wait for more calls to add()
                    return;
                }
            }

            unless $!state === DONE {
                self.spin;
            }
        }

        return;
    }

    my $content-length = $!content-length;

    $!length += $content.elems;

    # Don't allow buffer data to exceed content-length
    if $!length > $content-length {
        $content = $content.subbuf(0, $content.elems + ($content-length - $!length));
        $!length = $content-length;
    }

    $!buffer ~= $content;

    if $!state !== DONE {
        self.spin;
    }

    return $!length - $content-length;
}

multi method body() returns IO::Handle {
    return $!body;
}

multi method body(IO::Handle $body) returns IO::Handle {
    $!body = $body;
    return self.body;
}

method chunked() returns Bool {
    return $!chunked;
}

multi method cleanup() {
    return $!cleanup;
}

multi method cleanup(Bool $cleanup) {
    $!cleanup = $cleanup;
    return self.cleanup;
}

method content-length() returns Int {
    return $!content-length;
}

method content-type() returns Str {
    return $!content-type;
}

method length() returns Int {
    return $!length;
}

method trailing-headers() returns HTTP::Header {
    return $!trailing-headers;
}

method spin() {
    ...
}

multi method state() returns STATE {
    return $!state;
}

multi method state(STATE $state) returns STATE {
    $!state = $state;
    return self.state;
}

multi method param() {
    return %!param;
}

multi method param(Str $name, Str $value) {
    if (my $param = %!param{$name}).defined {
        if $param !~~ List {
            %!param{$name} = [$param];
        }
        @(%!param{$name}).push($value);
    } else {
        %!param{$name} = $value;
    }

    @!param-order.push($name);

    return self.param;
}

multi method upload() {
    return %!upload;
}

multi method upload(Str $name, $upload) {
    if (my $_upload = %!upload{$name}).defined {
        for $_upload -> $u {
            $u = [$u] if $u !~~ List;
            $u.push($upload);
        }
    } else {
        %!upload{$name} = $upload;
    }

    return self.upload;
}

multi method part-data() {
    return %!part-data;
}

multi method part-data(Str $name, $data) {
    if (my $part-data = %!part-data{$name}).defined {
        for $part-data -> $p {
            $p = [$p] if $p !~~ List;
            $p.push($data);
        }
    } else {
        %!part-data{$name} = $data;
    }

    return self.part-data;
}

multi method tmpdir() {
    return $!tmpdir;
}

multi method tmpdir($tmpdir) {
    $!tmpdir = $tmpdir;
    return self.tmpdir;
}

method param-order() {
    return @!param-order;
}

multi method buffer() {
    return $!buffer;
}

multi method buffer(Blob $buffer) {
    $!buffer = $buffer;
    return self.buffer;
}

=begin pod

=head1 NAME

HTTP::Body - blah blah blah

=head1 SYNOPSIS

  use HTTP::Body;

=head1 DESCRIPTION

HTTP::Body is ...

=head1 AUTHOR

moznion <moznion@gmail.com>

=head1 COPYRIGHT AND LICENSE

Copyright 2015 moznion

This library is free software; you can redistribute it and/or modify it under the Artistic License 2.0.

=end pod
