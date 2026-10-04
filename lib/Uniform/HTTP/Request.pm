package Uniform::HTTP::Request;

use strict;
use warnings;
use Carp qw(croak);
use parent 'Uniform::HTTP::Message';

our $VERSION = '0.03';

sub new {
    my ($class, @args) = @_;
    my $args = Uniform::HTTP::Message::_named_args('new', @args);

    for my $name (keys %$args) {
        croak "unknown constructor option '$name'"
            unless $name eq 'method'
                || $name eq 'target'
                || $name eq 'scheme'
                || $name eq 'authority'
                || $name eq 'version'
                || $name eq 'headers'
                || $name eq 'body';
    }

    croak 'method is required' unless exists $args->{method};
    croak 'target is required' unless exists $args->{target};

    my @common;
    for my $name (qw(version headers body)) {
        push @common, $name => $args->{$name} if exists $args->{$name};
    }

    my $self = $class->SUPER::new(@common);
    $self->method($args->{method});
    $self->target($args->{target});
    $self->scheme($args->{scheme}) if exists $args->{scheme};
    $self->authority($args->{authority}) if exists $args->{authority};
    return $self;
}

sub method {
    my ($self, @args) = @_;
    return $self->{method} unless @args;
    croak 'method() accepts at most one value' unless @args == 1;

    $self->_assert_mutable;
    my $method = Uniform::HTTP::Message::_byte_string('method', $args[0]);
    croak 'method must be an HTTP token'
        unless $method =~ /\A[!\#\$%&'*+\-.\^_`|~0-9A-Za-z]+\z/;
    $self->{method} = $method;
    return $self;
}

sub target {
    my ($self, @args) = @_;
    return $self->{target} unless @args;
    croak 'target() accepts at most one value' unless @args == 1;

    $self->_assert_mutable;
    my $target = Uniform::HTTP::Message::_byte_string('target', $args[0]);
    croak 'target must not be empty' unless length $target;
    croak 'target must not contain spaces or control bytes'
        if $target =~ /[\x00-\x20\x7f]/;
    $self->{target} = $target;
    return $self;
}

sub scheme {
    my ($self, @args) = @_;
    return $self->{scheme} unless @args;
    croak 'scheme() accepts at most one value' unless @args == 1;

    $self->_assert_mutable;
    if (!defined $args[0]) {
        $self->{scheme} = undef;
        return $self;
    }

    my $scheme = Uniform::HTTP::Message::_byte_string('scheme', $args[0]);
    croak 'scheme must be a valid URI scheme'
        unless $scheme =~ /\A[A-Za-z][A-Za-z0-9+.-]*\z/;
    $self->{scheme} = $scheme;
    return $self;
}

sub authority {
    my ($self, @args) = @_;
    return $self->{authority} unless @args;
    croak 'authority() accepts at most one value' unless @args == 1;

    $self->_assert_mutable;
    if (!defined $args[0]) {
        $self->{authority} = undef;
        return $self;
    }

    my $authority = Uniform::HTTP::Message::_byte_string(
        'authority', $args[0],
    );
    croak 'authority must not be empty' unless length $authority;
    croak 'authority contains a prohibited delimiter or control byte'
        if $authority =~ /[\x00-\x20\x7f\/?#]/;
    $self->{authority} = $authority;
    return $self;
}

sub target_is_exact {
    my ($self, @args) = @_;
    croak 'target_is_exact() does not accept arguments' if @args;
    return 1;
}

1;

__END__

=head1 NAME

Uniform::HTTP::Request - Framework-neutral HTTP request

=head1 SYNOPSIS

    use Uniform::HTTP::Request;

    my $request = Uniform::HTTP::Request->new(
        method    => 'POST',
        target    => '/items?draft=1',
        scheme    => 'https',
        authority => 'example.com',
        version   => '1.1',
        headers   => [ [ 'Content-Type', 'application/json' ] ],
        body      => '{"name":"example"}',
    );

=head1 DESCRIPTION

Uniform::HTTP::Request adds method and request-target semantics to
L<Uniform::HTTP::Message>. It is a detached message object, not a transaction
or connection.

=head1 CONSTRUCTOR

=head2 new

Requires named C<method> and C<target> arguments. It also accepts optional
C<scheme> and C<authority> request metadata plus the common C<version>,
C<headers>, and C<body> arguments. Scheme and authority are never inferred from
the target.

=head1 METHODS

=head2 method

Returns the case-sensitive HTTP method token. Passing a token sets it and
returns the request.

=head2 target

Returns the semantic HTTP request-target as bytes, not as a URI object.
Passing a target sets it and returns the request.

For HTTP/2 and HTTP/3 requests that carry C<:path>, an adapter should expose
the exact C<:path> bytes here when no reconstruction is required. Ordinary
CONNECT is the special case: it has no C<:path>, so an adapter exposes the
exact C<:authority> bytes as the authority-form target. That mapping remains
exact because the bytes are copied without parsing or normalization.

=head2 scheme

Returns the URI scheme associated with the request, or C<undef> when none is
represented. Passing a valid URI scheme sets it; passing C<undef> clears it.
Uniform never infers a scheme from the target or transport.

=head2 authority

Returns the request authority, or C<undef> when none is represented. Passing an
authority sets it; passing C<undef> clears it. Uniform does not synthesize an
authority from Host or from the request target.

The canonical class deliberately performs only minimal byte-level validation:
the value must be nonempty and must not contain controls, spaces, C</>, C<?>,
or C<#>. It does not parse hosts, ports, userinfo, IP literals, or percent
escapes, and it does not apply protocol-specific authority rules.

=head2 target_is_exact

Returns true for canonical requests because C<target()> is exactly the value
supplied by the caller. An adapter returns false when it had to reconstruct a
target from decomposed framework data. An HTTP/2 or HTTP/3 adapter may return
true for ordinary CONNECT when it copies the exact C<:authority> bytes into
C<target()> as described above.

=head1 INHERITED METHODS

See L<Uniform::HTTP::Message> for headers, body state, version, capability
reporting, and mutation.

=head1 AUTHOR

Joshua S. Day E<lt>HAX@cpan.orgE<gt>

=head1 LICENSE

This software is available under the MIT License.

=cut
