# Uniform::HTTP::Auth

Unified, framework-agnostic HTTP authentication for Perl.

`Uniform::HTTP::Auth` implements HTTP authentication mechanics without depending
on an HTTP client, server, framework, event loop, request object, or transaction
abstraction. It deals in plain HTTP authentication data and plain Perl values so
any Perl HTTP stack can use it.

## Supported schemes

- Basic (RFC 7617)
- Bearer (RFC 6750)
- Digest (RFC 7616)
  - MD5 and MD5-sess for compatibility
  - SHA-256 and SHA-256-sess
  - SHA-512/256 and SHA-512/256-sess
  - `qop=auth` and `qop=auth-int`
  - UTF-8, `userhash`, nonce-count state, and secure cnonce generation

Unknown authentication schemes are parsed and preserved for caller inspection,
but are not automatically authorized in 0.01.

## Simple use

For an ordinary application, give the auth object the origin and credentials it
will use later:

```perl
use Uniform::HTTP::Auth;

my $auth = Uniform::HTTP::Auth->new(
    origin => 'https://example.com:443',
    credentials => {
        username => 'user',
        password => 'secret',
    },
);

my $result = $auth->authorize(
    challenge_headers => [
        'Digest realm="Members", nonce="abc", qop="auth", algorithm=SHA-256',
        'Basic realm="Members"',
    ],
    method         => 'GET',
    request_target => '/private',
);

my $authorization_value = $result->{value};
```

The stored credentials are bound to the configured origin. The caller decides
whether the returned value is sent as `Authorization` or `Proxy-Authorization`,
and whether or how the HTTP request is retried.

Bearer credentials are equally direct:

```perl
my $auth = Uniform::HTTP::Auth->new(
    origin => 'https://api.example.com:443',
    credentials => {
        token => $token,
    },
);
```

The default scheme preference is Digest, Bearer, Basic. A stored credential set
is only considered for schemes it can satisfy, so username/password credentials
can satisfy Digest or Basic and a token can satisfy Bearer.

## Dynamic credential lookup

A generic HTTP library or an application with a credential store can use a
callback instead of storing one credential set:

```perl
my $auth = Uniform::HTTP::Auth->new(
    credentials => sub {
        my ($context) = @_;

        return $store->lookup(
            $context->{origin},
            $context->{realm},
            $context->{scheme},
        );
    },
);

my $result = $auth->authorize(
    challenge_headers => \@www_authenticate,
    origin            => 'https://example.com:443',
    method            => 'GET',
    request_target    => '/private',
);
```

The callback receives authentication-only context:

```perl
{
    scheme    => 'digest',
    origin    => 'https://example.com:443',
    realm     => 'Members',
    challenge => $parsed_challenge,
}
```

Return `undef` when credentials are unavailable. Return a hash reference with
`username` and `password` for Basic/Digest, or `token` for Bearer.

## Scheme policy

The `schemes` constructor option enables schemes and sets their preference order:

```perl
my $auth = Uniform::HTTP::Auth->new(
    origin => 'https://api.example.com:443',
    schemes => [qw(bearer basic)],
    credentials => {
        token => $token,
    },
);
```

Omit `schemes` to use the default `[qw(digest bearer basic)]` policy.

## Boundary

Uniform owns:

- challenge parsing
- supported-scheme discovery and selection
- credential lookup
- Basic construction
- Bearer construction
- Digest calculation and nonce state

The calling HTTP implementation owns:

- receiving 401 and 407 responses
- request replay and retry policy
- connections and transaction lifecycle
- proxy routing
- callbacks, Futures, promises, or other completion APIs

## Lower-level use

The root object also exposes parsing and selection independently:

```perl
my $challenges = $auth->parse_challenges(@www_authenticate_values);
my $selected   = $auth->select($challenges);
```

Scheme-specific helpers are available as:

- `Uniform::HTTP::Auth::Basic`
- `Uniform::HTTP::Auth::Bearer`
- `Uniform::HTTP::Auth::Digest`

## Installation

```text
cpanm Uniform::HTTP::Auth
```

For a checkout:

```text
perl Makefile.PL
make
make test
```

## Documentation

The module POD documents the public API. `docs/API-SPEC.md` records the 0.01
ownership boundary and contract in one place.

## License

MIT License.
