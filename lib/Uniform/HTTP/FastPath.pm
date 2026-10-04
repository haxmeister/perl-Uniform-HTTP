package Uniform::HTTP::FastPath;

use strict;
use warnings;
use Carp qw(croak);

use Uniform::HTTP::Message ();
use Uniform::HTTP::Request ();
use Uniform::HTTP::Response ();

our $VERSION = '0.04';

use constant ABI_VERSION => 1;

use constant KIND_MESSAGE  => 0;
use constant KIND_REQUEST  => 1;
use constant KIND_RESPONSE => 2;

use constant FLAG_HAS_BUFFERED_BODY => 0x001;
use constant FLAG_COMPLETE          => 0x002;
use constant FLAG_MUTABLE           => 0x004;
use constant FLAG_INITIAL_MUTABLE   => 0x008;
use constant FLAG_BODY_MUTABLE      => 0x010;
use constant FLAG_TRAILERS_MUTABLE  => 0x020;
use constant FLAG_HEADERS_LOSSLESS  => 0x040;
use constant FLAG_TRAILERS_LOSSLESS => 0x080;
use constant FLAG_TARGET_EXACT      => 0x100;

use constant SLOT_ABI       => 0;
use constant SLOT_KIND      => 1;
use constant SLOT_FLAGS     => 2;
use constant SLOT_VERSION   => 3;
use constant SLOT_METHOD    => 4;
use constant SLOT_TARGET    => 5;
use constant SLOT_SCHEME    => 6;
use constant SLOT_AUTHORITY => 7;
use constant SLOT_PROTOCOL  => 8;
use constant SLOT_STATUS    => 9;
use constant SLOT_REASON    => 10;
use constant SLOT_HEADERS   => 11;
use constant SLOT_TRAILERS  => 12;
use constant SLOT_BODY      => 13;
use constant SLOT_COUNT     => 14;

use constant _ALL_FLAGS => 0x1ff;

sub can_view {
    croak 'can_view() requires exactly one message' unless @_ == 1;
    my ($message) = @_;
    my $class = ref($message) || '';
    return 1 if $class eq 'Uniform::HTTP::Message';
    return 1 if $class eq 'Uniform::HTTP::Request';
    return 1 if $class eq 'Uniform::HTTP::Response';
    return 0;
}

sub view {
    croak 'view() requires a message and optional ABI version'
        unless @_ == 1 || @_ == 2;
    my ($message, $abi) = @_;
    $abi = ABI_VERSION unless defined $abi;

    croak 'unsupported Uniform::HTTP fast-path ABI'
        unless !ref($abi) && $abi =~ /\A[0-9]+\z/ && $abi == ABI_VERSION;
    croak 'fast path requires an exact canonical Uniform::HTTP message class'
        unless can_view($message);

    my $class = ref $message;
    my $kind = $class eq 'Uniform::HTTP::Request'  ? KIND_REQUEST
             : $class eq 'Uniform::HTTP::Response' ? KIND_RESPONSE
             : KIND_MESSAGE;

    my $flags = FLAG_HEADERS_LOSSLESS | FLAG_TRAILERS_LOSSLESS;
    $flags |= FLAG_HAS_BUFFERED_BODY if $message->{has_buffered_body};
    $flags |= FLAG_COMPLETE          if $message->{complete};
    $flags |= FLAG_MUTABLE           if $message->{mutable};
    $flags |= FLAG_INITIAL_MUTABLE
        if $message->{mutable} && !$message->{initial_frozen};
    $flags |= FLAG_BODY_MUTABLE if $message->{mutable};
    $flags |= FLAG_TRAILERS_MUTABLE
        if $message->{mutable} && !$message->{trailers_frozen};
    $flags |= FLAG_TARGET_EXACT if $kind == KIND_REQUEST;

    return [
        ABI_VERSION,
        $kind,
        $flags,
        $message->{version},
        $kind == KIND_REQUEST ? $message->{method}    : undef,
        $kind == KIND_REQUEST ? $message->{target}    : undef,
        $kind == KIND_REQUEST ? $message->{scheme}    : undef,
        $kind == KIND_REQUEST ? $message->{authority} : undef,
        $kind == KIND_REQUEST ? $message->{protocol}  : undef,
        $kind == KIND_RESPONSE ? $message->{status} : undef,
        $kind == KIND_RESPONSE ? $message->{reason} : undef,
        $message->{headers},
        $message->{trailers},
        $message->{has_buffered_body} ? $message->{body} : undef,
    ];
}

sub request_from_validated {
    croak 'request_from_validated() requires exactly one fast-path view'
        unless @_ == 1;
    my ($view) = @_;
    _validate_view($view, KIND_REQUEST);

    my $self = _common_from_view($view);
    $self->{method}    = $view->[SLOT_METHOD];
    $self->{target}    = $view->[SLOT_TARGET];
    $self->{scheme}    = $view->[SLOT_SCHEME];
    $self->{authority} = $view->[SLOT_AUTHORITY];
    $self->{protocol}  = $view->[SLOT_PROTOCOL];

    return bless $self, 'Uniform::HTTP::Request';
}

sub response_from_validated {
    croak 'response_from_validated() requires exactly one fast-path view'
        unless @_ == 1;
    my ($view) = @_;
    _validate_view($view, KIND_RESPONSE);

    my $self = _common_from_view($view);
    $self->{status} = $view->[SLOT_STATUS];
    $self->{reason} = $view->[SLOT_REASON];

    return bless $self, 'Uniform::HTTP::Response';
}

sub _common_from_view {
    my ($view) = @_;
    my $flags = $view->[SLOT_FLAGS];

    return {
        version           => $view->[SLOT_VERSION],
        headers           => $view->[SLOT_HEADERS],
        trailers          => $view->[SLOT_TRAILERS],
        initial_frozen    => $flags & FLAG_INITIAL_MUTABLE ? 0 : 1,
        trailers_frozen   => $flags & FLAG_TRAILERS_MUTABLE ? 0 : 1,
        body              => $flags & FLAG_HAS_BUFFERED_BODY
            ? $view->[SLOT_BODY] : undef,
        has_buffered_body => $flags & FLAG_HAS_BUFFERED_BODY ? 1 : 0,
        complete          => $flags & FLAG_COMPLETE ? 1 : 0,
        mutable           => $flags & FLAG_MUTABLE ? 1 : 0,
    };
}

sub _validate_view {
    my ($view, $kind) = @_;

    croak 'fast-path view must be an array reference'
        unless ref($view) eq 'ARRAY';
    croak 'fast-path view has the wrong number of slots'
        unless @$view == SLOT_COUNT;
    croak 'unsupported Uniform::HTTP fast-path ABI'
        unless defined($view->[SLOT_ABI])
            && !ref($view->[SLOT_ABI])
            && $view->[SLOT_ABI] =~ /\A[0-9]+\z/
            && $view->[SLOT_ABI] == ABI_VERSION;
    croak 'fast-path view has the wrong message kind'
        unless defined($view->[SLOT_KIND])
            && !ref($view->[SLOT_KIND])
            && $view->[SLOT_KIND] =~ /\A[0-9]+\z/
            && $view->[SLOT_KIND] == $kind;

    my $flags = $view->[SLOT_FLAGS];
    croak 'fast-path flags must be a non-negative integer'
        unless defined($flags) && !ref($flags) && $flags =~ /\A[0-9]+\z/;
    croak 'fast-path view contains unknown flags'
        if $flags & ~_ALL_FLAGS;

    croak 'fast-path headers must be an array reference'
        unless ref($view->[SLOT_HEADERS]) eq 'ARRAY';
    croak 'fast-path trailers must be an array reference'
        unless ref($view->[SLOT_TRAILERS]) eq 'ARRAY';

    croak 'trusted canonical construction requires lossless headers'
        unless $flags & FLAG_HEADERS_LOSSLESS;
    croak 'trusted canonical construction requires lossless trailers'
        unless $flags & FLAG_TRAILERS_LOSSLESS;

    if ($flags & FLAG_HAS_BUFFERED_BODY) {
        croak 'buffered fast-path body must be a defined plain scalar'
            unless defined($view->[SLOT_BODY]) && !ref($view->[SLOT_BODY]);
    }
    else {
        croak 'fast-path body slot must be undef when no buffered body is present'
            if defined $view->[SLOT_BODY];
    }

    my $mutable = $flags & FLAG_MUTABLE ? 1 : 0;
    my $body_mutable = $flags & FLAG_BODY_MUTABLE ? 1 : 0;
    croak 'fast-path body mutability is not canonical'
        unless $mutable == $body_mutable;
    if (!$mutable) {
        croak 'immutable fast-path view advertises a mutable section'
            if $flags & (FLAG_INITIAL_MUTABLE
                | FLAG_BODY_MUTABLE | FLAG_TRAILERS_MUTABLE);
    }

    if ($kind == KIND_REQUEST) {
        croak 'trusted request requires exact target fidelity'
            unless $flags & FLAG_TARGET_EXACT;
        croak 'trusted request method must be a defined plain scalar'
            unless defined($view->[SLOT_METHOD]) && !ref($view->[SLOT_METHOD]);
        croak 'trusted request target must be a defined plain scalar'
            unless defined($view->[SLOT_TARGET]) && !ref($view->[SLOT_TARGET]);
    }
    else {
        croak 'response fast-path view must not set request target fidelity'
            if $flags & FLAG_TARGET_EXACT;
        croak 'trusted response status must be a defined plain scalar'
            unless defined($view->[SLOT_STATUS]) && !ref($view->[SLOT_STATUS]);
    }

    return;
}

1;

__END__

=head1 NAME

Uniform::HTTP::FastPath - Optional bulk access for native HTTP engines

=head1 SYNOPSIS

    use Uniform::HTTP::FastPath;

    my $view = Uniform::HTTP::FastPath::view($request);

    if ($view->[Uniform::HTTP::FastPath::SLOT_ABI()]
            == Uniform::HTTP::FastPath::ABI_VERSION()) {
        # Pass the fixed-layout view to native code.
    }

=head1 DESCRIPTION

Uniform::HTTP::FastPath is an optional implementer API for code that already
uses canonical Uniform HTTP messages but needs to avoid many Perl method calls.

It does not parse HTTP, serialize HTTP, perform I/O, or expose a C pointer.
Normal application code should continue to use the Request and Response APIs.

The fast path has two jobs:

=over 4

=item * expose a canonical message in one fixed-layout view

=item * construct a canonical Request or Response from data already validated
by a trusted protocol engine

=back

The ABI is explicitly versioned. A consumer that cannot use the supported ABI
must fall back to the normal Uniform methods.

=head1 ABI VERSION

=head2 ABI_VERSION

Returns the current fast-path ABI version. Version 1 is the only supported
version in this release.

The ABI version covers slot meanings, flag meanings, and ownership rules.
Incompatible changes require a new ABI version.

=head1 MESSAGE VIEW

=head2 can_view

    if (Uniform::HTTP::FastPath::can_view($message)) {
        ...
    }

Returns true only for exact canonical C<Uniform::HTTP::Message>,
C<Uniform::HTTP::Request>, and C<Uniform::HTTP::Response> objects.

Subclasses and adapters deliberately return false. Their storage or overridden
semantics may differ from the canonical classes. Consumers must use the normal
portable API for them.

=head2 view

    my $view = Uniform::HTTP::FastPath::view($message);
    my $view = Uniform::HTTP::FastPath::view($message, 1);

Returns an array reference using the requested ABI.

The operation performs no HTTP validation and no network or framework work.
It reads the already-valid canonical object directly.

ABI 1 has these slots:

    0   ABI version
    1   message kind
    2   flags
    3   version
    4   request method
    5   request target
    6   request scheme
    7   request authority
    8   request protocol
    9   response status
    10  response reason
    11  headers
    12  trailers
    13  buffered body

The C<SLOT_*> constants provide these indexes.

Unused request or response metadata slots contain C<undef>.

Message kinds are:

    KIND_MESSAGE
    KIND_REQUEST
    KIND_RESPONSE

The flags are:

    FLAG_HAS_BUFFERED_BODY
    FLAG_COMPLETE
    FLAG_MUTABLE
    FLAG_INITIAL_MUTABLE
    FLAG_BODY_MUTABLE
    FLAG_TRAILERS_MUTABLE
    FLAG_HEADERS_LOSSLESS
    FLAG_TRAILERS_LOSSLESS
    FLAG_TARGET_EXACT

The header and trailer slots are the canonical ordered arrays containing
C<[ name, value ]> pairs.

=head1 BORROWED DATA

A view is intended for immediate consumption.

Header and trailer array references are borrowed from the canonical object.
The consumer must not modify them. The source message must not be mutated while
native code is consuming the view.

A consumer must not retain a view as a live representation of a mutable
message. Obtain a new view after message mutation.

The returned view itself keeps referenced Perl values alive for as long as the
view exists. These lifetime rules are about semantic freshness and ownership,
not dangling Perl references.

=head1 TRUSTED CONSTRUCTION

=head2 request_from_validated

    my $request =
        Uniform::HTTP::FastPath::request_from_validated($view);

Constructs a canonical C<Uniform::HTTP::Request> directly from an ABI 1 request
view.

=head2 response_from_validated

    my $response =
        Uniform::HTTP::FastPath::response_from_validated($view);

Constructs a canonical C<Uniform::HTTP::Response> directly from an ABI 1
response view.

These constructors are for protocol engines that have already validated the
HTTP values. They deliberately skip the normal token, byte-string, field-value,
status-range, and request-target validation performed by public constructors
and setters.

They still check the ABI structure and canonical state flags so malformed
bridge data cannot silently create an internally contradictory object.

Calling a trusted constructor is a promise that every supplied value already
satisfies the normal Uniform::HTTP invariants.

=head1 ADOPTED STORAGE

Trusted construction adopts the header and trailer array references from the
view instead of copying every field.

After successful construction, the caller must not mutate those arrays or
their field pairs. The new Uniform object owns their semantic contents.

If shared mutable storage is not acceptable, use the normal public constructor,
which validates and copies field storage.

=head1 NATIVE ENGINE PATTERN

A native-backed HTTP implementation can use the fast path without making it a
requirement:

    if (Uniform::HTTP::FastPath::can_view($response)) {
        my $view = Uniform::HTTP::FastPath::view($response);
        $native_engine->send_uniform_fast($view);
    }
    else {
        $native_engine->send_uniform_portable($response);
    }

The native side checks C<SLOT_ABI> before interpreting the layout.

A parser can perform the reverse operation by assembling an ABI 1 view from
values it has already validated and calling the appropriate trusted
constructor.

This keeps protocol parsing and serialization outside Uniform::HTTP while
providing a performance recovery path for XS-backed implementations.

=head1 SECURITY

The trusted constructors are intentionally unsafe for unvalidated input.

Do not pass user input, wire bytes, adapter output, or partially validated
values directly to them. Use the normal Request or Response constructor unless
the caller is the component that already enforced the same invariants.

The fast path does not weaken validation in the normal public API.

=head1 VERSION

Fast-path ABI version 1. Module version 0.04.

=head1 AUTHOR

Joshua S. Day E<lt>HAX@cpan.orgE<gt>

=head1 LICENSE

This software is available under the MIT License.

=cut
