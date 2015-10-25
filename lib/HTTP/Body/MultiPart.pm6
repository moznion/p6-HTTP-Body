use v6;
use HTTP::Body;
use File::Temp;
unit class HTTP::Body::MultiPart is HTTP::Body;

has %!part;
has Str $!boundary;

method init(Str $backend, Str $content-type, $content-length) {
    my $self = self.bless(
        :chunked(!$content-length.defined),
        :content-length($content-length.defined ?? $content-length !! -1),
        :content-type($content-type),
    );

    if $self.content-type !~~ /'boundary=' '"'? $<boundary> = <-[";]>+ '"'?/ {
        die "Invalid boundary in content-type: '$content-type'";
    }

    $self.boundary(~$<boundary>);
    $self.state(HTTP::Body::PREAMBLE);

    return $self;
}

method spin() {
    while True {
        my $result;
        given self.state {
            when HTTP::Body::PREAMBLE { $result = self.parse-preamble }
            when HTTP::Body::BOUNDARY { $result = self.parse-boundary }
            when HTTP::Body::HEADER   { $result = self.parse-header }
            when HTTP::Body::BODY     { $result = self.parse-body }
            default                   { die 'Unknown state' }
        }
        return unless $result;
    }
}


method !crlf() returns Str {
    return "\x0d\x0a";
}

method parse-preamble() returns Bool {
    my $buffer-str = self.buffer.decode;
    my $index = $buffer-str.index(self.boundary-begin);

    if !$index.defined {
        return False;
    }

    # replace preamble with CRLF so we can match dash-boundary as delimiter
    self.buffer((self!crlf x ($index + 1) ~ $buffer-str.substr($index)).encode);

    self.state(HTTP::Body::BOUNDARY);

    return True;
}

method parse-boundary() returns Bool {
    my $buffer-str = self.buffer.decode;

    if $buffer-str.index(self.delimiter-begin ~ self!crlf) === 0 {
        self.buffer($buffer-str.substr(self.delimiter-begin.chars + 2).encode);

        self.part({});
        self.state(HTTP::Body::HEADER);

        return True;
    }

    if $buffer-str.index(self.delimiter-end ~ self!crlf) === 0 {
        self.buffer($buffer-str.substr(self.delimiter-end.chars + 2).encode);
        self.part({});
        self.state(HTTP::Body::DONE);

        return False;
    }

    return False;
}

method parse-header() returns Bool {
    my Str $crlf  = self!crlf;
    my Str $buffer-str = self.buffer.decode;

    my $index = $buffer-str.index($crlf ~ $crlf);

    if !$index.defined {
        return False;
    }

    my $header = $buffer-str.substr(0, $index);
    self.buffer($buffer-str.substr($index + 4).encode);

    my @headers;
    for $header.split($crlf) -> $h is copy {
        if $h ~~ s/^ <[\ \t]>+// {
            @headers[*-1] ~= $h;
        } else {
            @headers.push($h);
        }
    }

    for @headers -> $header is copy {
        $header ~~ s/^ $<field-matched> = <-[\x00..\x1f \x7f ( ) < > @ , ; : \\ " \/ ? = { } \t]>+ ':' <[\t\ ]>*//;

        my $field = ~$<field-matched>;
        $field ~~ s:g/\b (\w)/{$0.uc}/;

        my %part = self.part;
        if %part<headers>{$field}.defined {
            for %part<headers>{$field} {
                warn 'HHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHH';
            #     $_ = [$_] unless $_ !~~ List;
            #     # push( @$_, $header );
            }
        } else {
            %part<headers>{$field} = $header;
        }
        self.part(%part);
    }

    self.state(HTTP::Body::BODY);

    return True;
}

method parse-body() returns Bool {
    my $buffer-str = self.buffer.decode;

    my $index = $buffer-str.index(self.delimiter-begin);
    if !$index.defined {
        # make sure we have enough buffer to detect end delimiter
        my $length = self.buffer.elems - (self.delimiter-end.chars + 2);

        if $length <= 0 {
            return False;
        }

        my $cut = $buffer-str.substr(0, $length);
        self.buffer($buffer-str.substr($length).encode);

        my %part = self.part;
        %part<data> ~= $cut;
        %part<size> += $length;
        %part<done> = False;

        self.part(%part);
        self.handler(self.part);

        return False;
    }

    my $cut = $buffer-str.substr(0, $index);
    self.buffer($buffer-str.substr($index).encode);

    my %part = self.part;
    %part<data> ~= $cut;
    %part<size> += $index;
    %part<done> = True;

    self.part(%part);

    self.handler(%part);

    self.state(HTTP::Body::BOUNDARY);

    return True;
}

method handler(%part is copy) {
    if !%part<name>.defined {
        my $disposition = %part<headers><Content-Disposition>;

        $disposition ~~ /' name=' '"'? $<name> = <-[";]>+ '"'?/;
        %part<name> = ~$<name>;

        if ($disposition ~~ /' filename=' '"'? $<filename> = <-["]>* '"'?/).defined {
            # Need to match empty filenames avobe, so this part is flagged as an upload type

            %part<filename> = ~$<filename>;

            if %part<filename> ne '' {
                my $basename = IO::Path.new(%part<filename>).basename;


                my $suffix = ($basename ~~ /<-[.]>+ $<suffix> = ['.' <-[\\/]>]+ $/).defined ?? $<suffix> !! '';

                my $fh = tempfile(:tempdir(self.tmpdir), :suffix($suffix), :!unlink);

                %part<fh>       = $fh[1];
                # %part<tempname> = $fh[0]; # TODO
            }
        }
    }

    if %part<fh> && (my $length = %part<data>.chars) {
        %part<fh>.write(%part<data>.substr(0, $length).encode);
        %part<data> = %part<data>.substr($length);
    }

    if %part<done> {
        if %part<filename>.defined {
            if %part<filename> ne '' {
                %part<fh>.close if %part<fh>.defined;

                for qw{data done fh} -> $key {
                    %part{$key}:delete;
                }

                self.upload(%part<name>, %part);
            }
        } else {
            # If we have more than the content-disposition, we need to create a
            # data key so that we don't waste the headers.
            self.param(%part<name>, %part<data>);
            self.part-data(%part<name>, %part);
        }
    }

    self.part(%part);
}

multi method part() {
    return %!part;
}

multi method part(%part) {
    %!part = %part;
    return self.part;
}

multi method boundary() returns Str {
    return $!boundary;
}

multi method boundary(Str $boundary) returns Str {
    $!boundary = $boundary;
    return self.boundary;
}

method delimiter-begin() returns Str {
    return self!crlf ~ self.boundary-begin;
}

method delimiter-end() returns Str {
    return self!crlf ~ self.boundary-end;
}

method boundary-begin() returns Str {
    return '--' ~ self.boundary;
}

method boundary-end() returns Str {
    return self.boundary-begin ~ '--';
}

