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

## Example

```perl
use Uniform::HTTP::Auth;

my $auth = Uniform::HTTP::Auth->new(
    schemes => [qw(digest bearer basic)],
    credentials => sub {
        my ($need) = @_;

        return { token => $token }
            if $need->{scheme} eq 'bearer';

        return {
            username => 'user',
            password => 'secret',
        } if $need->{scheme} eq 'digest'
          || $need->{scheme} eq 'basic';

        return;
    },
);

my $result = $auth->authorize(
    challenge_headers => [
        'Digest realm="Members", nonce="abc", qop="auth", algorithm=SHA-256',
        'Basic realm="Members"',
    ],
    origin         => 'https://example.com:443',
    method         => 'GET',
    request_target => '/private',
);

my $authorization_value = $result->{value};
```

The caller decides whether that value is sent as `Authorization` or
`Proxy-Authorization`, and whether or how the HTTP request is retried.

## Boundary

Uniform owns:

- challenge parsing
- supported-scheme discovery and selection
- credential-provider orchestration
- Basic construction
- Bearer construction
- Digest calculation and nonce state

The calling HTTP implementation owns:

- receiving 401 and 407 responses
- request replay and retry policy
- connections and transaction lifecycle
- proxy routing
- callbacks, Futures, promises, or other completion APIs

## Credential provider

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
