use v6;
use HTTP::Body;
use File::Temp;
unit class HTTP::Body::XFormsMultiPart is HTTP::Body;

has $!start;

method init(Str $backend, Str $content-type, $content-length) {
    nextsame;
    # unless ( $self->content_type =~ /start=\"?\<?([^\"\>;,]+)\>?\"?/ ) {
    #     my $content_type = $self->content_type;
    #     Carp::croak( "Invalid boundary in content_type: '$content_type'" );
    # }
    #
    # $self->{start} = $1;
    #
    # return $self;
}

method start {
    return $!start;
}

method handler(%part) {
    my $content-id = %part<headers><Content-ID>;
    $content-id ~~ s/^ .* <[<"]>//;
    $content-id ~~ s/<[>"]> .* $//;

    if $content-id eq self.start {
        %part<name> = 'XForms:Model';
        if %part<done> {
            self.body(%part<data>);
        }
    } elsif $content-id.defined {
        %part<name>     = $content-id;
        %part<filename> = $content-id;
    }

    return nextsame;
}

