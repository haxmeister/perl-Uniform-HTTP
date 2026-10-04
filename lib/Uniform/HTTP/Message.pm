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

Uniform::HTTP::Message - Lossless framework-neutral HTTP message

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

Uniform::HTTP::Message is the shared semantic base for requests and responses.
It preserves duplicate fields, field order, and original field-name spelling.
It performs no parsing, serialization, encoding, or I/O.

Canonical messages begin mutable, complete, and lossless. The portable Uniform
contract exposes that state through C<is_mutable> and C<is_complete>. Canonical
objects additionally provide C<freeze>, C<mark_incomplete>, and
C<mark_complete> as local state-management helpers. Adapters may implement the
portable contract without providing those helpers and need not subclass a
Uniform class.

=head1 CONSTRUCTOR

=head2 new

Accepts optional C<version>, C<headers>, and C<body> named arguments.
C<headers> must be an array reference of two-element array references. An
omitted body is distinct from a buffered empty string.

=head1 METHODS

=head2 version

Returns the HTTP version without an C<HTTP/> prefix, or C<undef> when no
version is represented. Passing a version sets it; passing C<undef> clears it.

=head2 header

Returns the first matching field value using ASCII case-insensitive matching.
Passing a value replaces every matching occurrence with one field at the
position of the first occurrence, or appends it when the field was absent.

=head2 header_values

Returns an array reference containing every matching value in message order.
Values are never comma-joined.

=head2 add_header

Appends one field occurrence and returns the message.

=head2 remove_header

Removes every matching field occurrence and returns the message.

=head2 header_count

Returns the number of field occurrences.

=head2 header_name

Returns the original field name at a zero-based index. An index beyond the end
returns C<undef>.

=head2 header_value

Returns the field value at a zero-based index. An index beyond the end returns
C<undef>.

=head2 body

Returns buffered body bytes, or C<undef> when no body buffer is present.
Passing a defined byte string installs a complete body buffer and returns the
message. It never reads a stream, filehandle, callback, or framework input.

=head2 has_buffered_body

Returns true only when C<body()> is locally available, including an empty
buffer.

=head2 is_complete

Returns the current message-completeness state. Canonical messages begin
complete. An adapter may return true, false, or C<undef> when the native
environment cannot determine completeness.

=head2 is_mutable

Returns whether represented message values can still be changed. Canonical
messages begin mutable. An adapter reports the mutability of its native or
snapshotted representation.

=head1 CANONICAL LIFECYCLE HELPERS

These helpers belong to the canonical Uniform message classes. They are not
required methods for framework or protocol adapters.

=head2 freeze

Makes the represented message values immutable and returns the message. It is
idempotent and does not send, serialize, commit a framework response, or
otherwise perform I/O. Setters for headers, body, version, request metadata,
and response metadata all throw after the object is frozen.

=head2 mark_incomplete

Marks the canonical message incomplete and returns it. This is useful when a
complete header block is available but an incremental body remains open.

=head2 mark_complete

Marks the canonical message complete and returns it. It remains available after
C<freeze> and does not imply that a body was buffered.

=head2 headers_are_lossless

Returns true when duplicate occurrences, inter-field order, and original
field-name spelling are faithfully represented.

=head1 BYTE CONTRACT

Methods accept Perl byte strings. Values containing characters outside the
byte range are rejected; no encoding is guessed. Field names are HTTP tokens.
Field values reject prohibited control bytes while permitting horizontal tab
and bytes from 0x80 through 0xff.

=head1 MUTATION

All successful portable mutators return the receiving object. Canonical
messages begin mutable. After C<freeze>, every represented message-value
mutator, including C<body($bytes)>, throws. Completeness state is independent
of value mutability, so a frozen canonical streaming message can still move
from incomplete to complete as its body finishes externally.

=head1 AUTHOR

Joshua S. Day E<lt>HAX@cpan.orgE<gt>

=head1 LICENSE

This software is available under the MIT License.

=cut
