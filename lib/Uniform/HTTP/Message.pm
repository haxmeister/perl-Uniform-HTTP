package Uniform::HTTP::Message;

use strict;
use warnings;
use Carp qw(croak);

our $VERSION = '0.03';

my $TOKEN_RE = qr/\A[!\#\$%&'*+\-.\^_`|~0-9A-Za-z]+\z/;

sub new {
    my ($class, @args) = @_;
    my $args = _named_args('new', @args);

    for my $name (keys %$args) {
        croak "unknown constructor option '$name'"
            unless $name eq 'version'
                || $name eq 'headers'
                || $name eq 'body';
    }

    my $self = bless {
        version           => undef,
        headers           => [],
        body              => undef,
        has_buffered_body => 0,
        complete          => 1,
        mutable           => 1,
    }, $class;

    $self->version($args->{version}) if exists $args->{version};
    $self->_set_initial_headers($args->{headers}) if exists $args->{headers};
    $self->body($args->{body}) if exists $args->{body};

    return $self;
}

sub version {
    my ($self, @args) = @_;
    return $self->{version} unless @args;
    croak 'version() accepts at most one value' unless @args == 1;

    $self->_assert_mutable;
    if (!defined $args[0]) {
        $self->{version} = undef;
        return $self;
    }

    my $version = _byte_string('version', $args[0]);
    croak 'version must contain digits with an optional decimal part'
        unless $version =~ /\A[0-9]+(?:\.[0-9]+)?\z/;
    $self->{version} = $version;
    return $self;
}

sub header {
    my ($self, @args) = @_;
    croak 'header() requires a field name' unless @args;
    croak 'header() accepts a field name and optional value' unless @args <= 2;

    my $name = _header_name($args[0]);
    my $key = _ascii_lc($name);

    if (@args == 1) {
        for my $field (@{ $self->{headers} }) {
            return $field->[1] if _ascii_lc($field->[0]) eq $key;
        }
        return;
    }

    $self->_assert_mutable;
    my $value = _header_value($args[1]);
    my @headers;
    my $inserted;

    for my $field (@{ $self->{headers} }) {
        if (_ascii_lc($field->[0]) eq $key) {
            if (!$inserted) {
                push @headers, [ $name, $value ];
                $inserted = 1;
            }
            next;
        }
        push @headers, [ @$field ];
    }

    push @headers, [ $name, $value ] unless $inserted;
    $self->{headers} = \@headers;
    return $self;
}

sub header_values {
    my ($self, @args) = @_;
    croak 'header_values() requires exactly one field name' unless @args == 1;

    my $key = _ascii_lc(_header_name($args[0]));
    return [
        map { $_->[1] }
        grep { _ascii_lc($_->[0]) eq $key }
        @{ $self->{headers} }
    ];
}

sub add_header {
    my ($self, @args) = @_;
    croak 'add_header() requires exactly a field name and value'
        unless @args == 2;

    $self->_assert_mutable;
    push @{ $self->{headers} }, [
        _header_name($args[0]),
        _header_value($args[1]),
    ];
    return $self;
}

sub remove_header {
    my ($self, @args) = @_;
    croak 'remove_header() requires exactly one field name' unless @args == 1;

    $self->_assert_mutable;
    my $key = _ascii_lc(_header_name($args[0]));
    $self->{headers} = [
        map { [ @$_ ] }
        grep { _ascii_lc($_->[0]) ne $key }
        @{ $self->{headers} }
    ];
    return $self;
}

sub header_count {
    my ($self, @args) = @_;
    croak 'header_count() does not accept arguments' if @args;
    return scalar @{ $self->{headers} };
}

sub header_name {
    my ($self, @args) = @_;
    croak 'header_name() requires exactly one index' unless @args == 1;
    my $index = _header_index($args[0]);
    return if $index >= @{ $self->{headers} };
    return $self->{headers}[$index][0];
}

sub header_value {
    my ($self, @args) = @_;
    croak 'header_value() requires exactly one index' unless @args == 1;
    my $index = _header_index($args[0]);
    return if $index >= @{ $self->{headers} };
    return $self->{headers}[$index][1];
}

sub body {
    my ($self, @args) = @_;
    return $self->{body} unless @args;
    croak 'body() accepts at most one value' unless @args == 1;

    $self->_assert_mutable;
    $self->{body} = _byte_string('body', $args[0]);
    $self->{has_buffered_body} = 1;
    return $self;
}

sub has_buffered_body {
    my ($self, @args) = @_;
    croak 'has_buffered_body() does not accept arguments' if @args;
    return $self->{has_buffered_body} ? 1 : 0;
}

sub is_complete {
    my ($self, @args) = @_;
    croak 'is_complete() does not accept arguments' if @args;
    return $self->{complete} ? 1 : 0;
}

sub is_mutable {
    my ($self, @args) = @_;
    croak 'is_mutable() does not accept arguments' if @args;
    return $self->{mutable} ? 1 : 0;
}

sub freeze {
    my ($self, @args) = @_;
    croak 'freeze() does not accept arguments' if @args;
    $self->{mutable} = 0;
    return $self;
}

sub mark_incomplete {
    my ($self, @args) = @_;
    croak 'mark_incomplete() does not accept arguments' if @args;
    $self->{complete} = 0;
    return $self;
}

sub mark_complete {
    my ($self, @args) = @_;
    croak 'mark_complete() does not accept arguments' if @args;
    $self->{complete} = 1;
    return $self;
}

sub headers_are_lossless {
    my ($self, @args) = @_;
    croak 'headers_are_lossless() does not accept arguments' if @args;
    return 1;
}

sub _set_initial_headers {
    my ($self, $headers) = @_;
    croak 'headers must be an array reference of field-name/value pairs'
        unless ref($headers) eq 'ARRAY';

    my @copy;
    for my $field (@$headers) {
        croak 'each header must be a two-element array reference'
            unless ref($field) eq 'ARRAY' && @$field == 2;
        push @copy, [
            _header_name($field->[0]),
            _header_value($field->[1]),
        ];
    }
    $self->{headers} = \@copy;
    return;
}

sub _assert_mutable {
    my ($self) = @_;
    croak 'message is immutable' unless $self->is_mutable;
    return;
}

sub _named_args {
    my ($method, @args) = @_;
    croak "$method() requires named arguments" if @args % 2;
    return { @args };
}

sub _byte_string {
    my ($name, $value) = @_;
    croak "$name must be a defined plain scalar"
        unless defined($value) && !ref($value);

    my $copy = "$value";
    croak "$name must be a byte string"
        unless utf8::downgrade($copy, 1);
    return $copy;
}

sub _header_name {
    my ($value) = @_;
    my $name = _byte_string('header name', $value);
    croak 'header name must be an HTTP token' unless $name =~ $TOKEN_RE;
    return $name;
}

sub _header_value {
    my ($value) = @_;
    my $field_value = _byte_string('header value', $value);
    croak 'header value contains a prohibited control byte'
        if $field_value =~ /[\x00-\x08\x0a-\x1f\x7f]/;
    return $field_value;
}

sub _header_index {
    my ($value) = @_;
    croak 'header index must be a non-negative integer'
        unless defined($value) && !ref($value) && $value =~ /\A[0-9]+\z/;
    return 0 + $value;
}

sub _ascii_lc {
    my ($value) = @_;
    $value =~ tr/A-Z/a-z/;
    return $value;
}

1;

__END__

=head1 NAME

Uniform::HTTP::Message - Common HTTP message behavior

=head1 SYNOPSIS

    use Uniform::HTTP::Message;

    my $message = Uniform::HTTP::Message->new(
        version => '1.1',
        headers => [
            [ 'Content-Type', 'text/plain' ],
            [ 'Set-Cookie',   'a=1' ],
            [ 'Set-Cookie',   'b=2' ],
        ],
        body => "hello\n",
    );

=head1 DESCRIPTION

Uniform::HTTP::Message is the common base for
L<Uniform::HTTP::Request> and L<Uniform::HTTP::Response>.

It stores HTTP version, headers, and an optional buffered body. It does not
parse HTTP, send data, read streams, or perform network I/O.

Headers preserve duplicate fields, field order, and original field-name
spelling.

Most applications will create Request or Response objects rather than using
Message directly.

=head1 CONSTRUCTOR

=head2 new

    my $message = Uniform::HTTP::Message->new(
        version => '1.1',
        headers => [
            [ 'Content-Type', 'text/plain' ],
        ],
        body => 'hello',
    );

All arguments are optional.

C<headers> must be an array reference containing C<[ name, value ]> pairs.

=head1 HEADERS

=head2 header

    my $value = $message->header('Content-Type');

Returns the first matching value. Header names are matched
case-insensitively.

Set or replace a header with:

    $message->header('Content-Type', 'application/json');

When duplicate fields already exist, the setter replaces them with one field.

=head2 header_values

    my $values = $message->header_values('Set-Cookie');

Returns an array reference containing every matching value in order.

=head2 add_header

    $message->add_header('Set-Cookie', 'c=3');

Appends one new field without replacing existing fields.

=head2 remove_header

    $message->remove_header('X-Debug');

Removes every matching field.

=head2 header_count

Returns the number of header field occurrences.

=head2 header_name

    my $name = $message->header_name($index);

Returns the original field name at a zero-based index.

=head2 header_value

    my $value = $message->header_value($index);

Returns the field value at a zero-based index.

=head2 headers_are_lossless

Returns true for canonical Uniform messages because duplicate fields, order,
and original field-name spelling are preserved.

Adapters may return false when their native framework cannot preserve all of
those details.

=head1 BODY

=head2 body

    my $bytes = $message->body;

Returns the buffered body, or C<undef> when no buffered body is present.

Set a buffered body with:

    $message->body($bytes);

Calling C<body()> never reads a socket, filehandle, callback, or streaming
source.

=head2 has_buffered_body

Returns true when C<body()> contains a buffered body. An empty string still
counts as a buffered body.

=head1 VERSION

=head2 version

    my $version = $message->version;

Returns values such as C<1.1>, C<2>, or C<3>, without an C<HTTP/> prefix.

Set or clear it with:

    $message->version('2');
    $message->version(undef);

=head1 MESSAGE STATE

=head2 is_mutable

Returns true while the represented message values can still be changed.

Canonical Uniform messages begin mutable.

=head2 freeze

    $message->freeze;

Freezes a canonical Uniform object. After this, setters throw an exception.

C<freeze()> only changes the local object. It does not send headers, commit a
framework response, or perform I/O.

=head2 is_complete

Returns true when the message is known to be complete.

Canonical objects begin complete. An adapter may return C<undef> when its
framework cannot determine completeness yet.

=head2 mark_incomplete

Marks a canonical message incomplete.

=head2 mark_complete

Marks a canonical message complete.

These two helpers are useful when a detached Uniform object is following
externally managed streaming progress.

=head1 BYTE STRINGS

Message values are byte strings. Uniform::HTTP does not guess a character
encoding.

Header names must be valid HTTP tokens. Header values reject prohibited
control bytes.

=head1 SEE ALSO

L<Uniform::HTTP>, L<Uniform::HTTP::Request>, L<Uniform::HTTP::Response>.

The full adapter contract is documented in F<docs/MESSAGE-SPEC.md>.

=head1 AUTHOR

Joshua S. Day E<lt>HAX@cpan.orgE<gt>

=head1 LICENSE

This software is available under the MIT License.

=cut
