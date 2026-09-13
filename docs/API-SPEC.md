# Uniform::HTTP::Auth 0.01 API Specification

Status: release contract for version 0.01.

## Purpose

`Uniform::HTTP::Auth` is a transport-, framework-, and event-loop-agnostic HTTP
authentication engine for Perl.

It deals only in HTTP authentication concepts and plain Perl data. It does not
expose request, response, transaction, connection, event-loop, retry, or
framework objects from any HTTP stack.

## Ownership boundary

`Uniform::HTTP::Auth` owns:

- parsing `WWW-Authenticate` and `Proxy-Authenticate` challenge values
- preserving unknown authentication schemes
- supported-scheme discovery and preference
- credential-provider orchestration
- Basic authentication construction
- Bearer authentication construction
- Digest calculation and client nonce state

The calling HTTP implementation owns:

- receiving HTTP 401 and 407 responses
- request replayability and retry policy
- request and transaction lifecycle
- connection management and reuse
- callback, Future, promise, or other completion APIs
- proxy routing
- choosing whether the returned value is placed in `Authorization` or
  `Proxy-Authorization`

The caller is responsible for transport. Uniform is responsible for
authentication mechanics.

## Modules

Version 0.01 contains:

```text
Uniform::HTTP::Auth
Uniform::HTTP::Auth::Basic
Uniform::HTTP::Auth::Bearer
Uniform::HTTP::Auth::Digest
```

All are part of the same `Uniform-HTTP-Auth` distribution.

## Supported schemes

Version 0.01 implements:

- Basic, RFC 7617
- Bearer, RFC 6750
- Digest, RFC 7616

Unknown schemes are parsed and exposed but are not automatically authorized.
There is no public custom-scheme plugin ABI in 0.01.

## Construction

```perl
my $auth = Uniform::HTTP::Auth->new(
    schemes => [qw(digest bearer basic)],
    credentials => sub {
        my ($need) = @_;
        ...
    },
);
```

### `schemes`

Optional array reference defining both enabled schemes and preference order.
The default is:

```perl
[qw(digest bearer basic)]
```

The order is a convenience policy, not a universal security ranking. Scheme
names are normalized to lowercase. Unsupported or duplicate configured schemes
are programmer errors.

### `credentials`

Optional coderef used by `authorize()` to obtain application-owned credentials.
It is not required for parsing or selection.

## Challenge representation

`parse_challenges()` returns an array reference of plain hash references:

```perl
{
    scheme    => 'digest',
    raw       => 'Digest realm="Members", ...',
    params    => {
        realm     => 'Members',
        algorithm => 'SHA-256',
        qop       => 'auth',
    },
    token68   => undef,
    malformed => 0,
    error     => undef,
}
```

Scheme names and authentication parameter names are normalized to lowercase.
Parameter values are returned after quoted-string decoding. Unknown schemes use
the same representation.

Malformed remote input is represented as data rather than thrown as a
programmer exception. Malformed challenges have `malformed => 1` and a
diagnostic `error` and are ignored by automatic selection.

Duplicate authentication parameters are malformed. Invalid control characters
in quoted authentication parameters are rejected.

## Root API

### `parse_challenges`

```perl
my $challenges = $auth->parse_challenges(@header_values);
```

Parses one or more complete `WWW-Authenticate` or `Proxy-Authenticate` field
values. Multiple field occurrences and multiple challenges on one field line
are supported. Results remain in wire order.

### `select`

```perl
my $challenge = $auth->select($challenges);
```

Returns the best usable challenge according to configured scheme preference.
It does not call the credential provider. Returns `undef` when no supported,
well-formed challenge is usable.

Scheme modules own selection among variants of the same scheme. Digest, for
example, skips unsupported algorithms or qop choices.

### `authorize`

```perl
my $result = $auth->authorize(
    challenge_headers => \@authenticate_values,
    origin            => 'https://example.com:443',
    method            => 'GET',
    request_target    => '/private?x=1',
    entity_body       => $body,
);
```

Performs:

1. challenge parsing
2. scheme ordering and scheme-specific selection
3. credential lookup
4. scheme-specific authentication construction

If the credential provider returns `undef` for a preferred scheme,
`authorize()` can continue to another usable configured scheme.

On success it returns:

```perl
{
    scheme    => 'digest',
    value     => 'Digest username="...", ...',
    challenge => $challenge,
}
```

`value` is the complete authentication field value without a field name.
Returns `undef` when no supported challenge can be satisfied.

`origin` is required and identifies the normalized HTTP origin, such as
`https://example.com:443`. Together with the challenge realm it identifies the
HTTP protection space. Uniform does not derive or route origins.

`method` and `request_target` are required only for Digest.

`entity_body` is used only for Digest `qop=auth-int`; when supplied it must be a
defined plain scalar.

## Credential provider contract

The provider receives:

```perl
{
    scheme    => 'digest',
    origin    => 'https://example.com:443',
    realm     => 'Members',
    challenge => $challenge,
}
```

Return `undef` when credentials are unavailable for that protection space.

For Basic and Digest:

```perl
{
    username => 'user',
    password => 'secret',
}
```

For Bearer:

```perl
{
    token => 'abcdef...',
}
```

The provider supplies credentials; it does not verify them. Missing required
fields or invalid provider return types are programmer errors.

## Basic

`Uniform::HTTP::Auth::Basic->authorization(...)` constructs the complete Basic
field value.

A Basic challenge requires `realm`. If `charset` is present, its only supported
value is `UTF-8`, case-insensitively.

With `charset=UTF-8`, username and password are normalized to NFC and encoded as
UTF-8 before Base64 encoding. Without `charset`, version 0.01 accepts ASCII
credentials only rather than guessing the RFC 7617 default encoding.

Usernames may not contain a colon. Username and password may not contain HTTP
control characters.

## Bearer

`Uniform::HTTP::Auth::Bearer->authorization(token => $token)` constructs the
complete Bearer field value and validates the RFC 6750 `b64token` syntax.

Uniform treats the token as opaque. It does not decode JWTs, acquire or refresh
OAuth tokens, determine token permissions, or validate token expiry.

Bearer challenge parameters remain available through the parsed challenge and
the credential-provider callback.

## Digest

`Uniform::HTTP::Auth::Digest` implements stateful Digest calculation.

Supported algorithm families:

- MD5 / MD5-sess
- SHA-256 / SHA-256-sess
- SHA-512-256 / SHA-512-256-sess

Supported qop values:

- `auth`
- `auth-int`

When both are offered, 0.01 prefers `auth`.

Digest state includes nonce count and cnonce. Through the root API, state is
isolated by origin, realm, username, and nonce so identical opaque nonce strings
from unrelated HTTP protection spaces do not share state. Direct
`Uniform::HTTP::Auth::Digest` users can pass `origin` for the same isolation.

A new nonce begins at `nc=00000001`. `stale=true` challenges are accepted so the
calling HTTP implementation can retry with existing credentials; Uniform does
not own the retry itself.

`charset=UTF-8`, `userhash`, `username*`, legacy no-qop Digest, and session
algorithms are supported. MD5 remains available for interoperability, not as a
recommended modern security choice.

## Error model

Programmer misuse throws an exception. Examples include bad argument types,
invalid configured schemes, missing required credential fields, invalid
origins, and invalid `auth-int` body values.

Malformed remote challenge input does not throw merely because it came from the
network. It is represented as malformed challenge data and ignored by automatic
selection.

A credential provider returning `undef` is normal and means credentials are not
available for that protection space.

## Runtime dependencies

The implementation uses focused CPAN/core primitives rather than another HTTP
stack:

- `MIME::Base64`
- `Digest::MD5`
- `Digest::SHA` 5.60 or newer
- `Crypt::SysRandom` 0.006 or newer
- `Encode`
- `Unicode::Normalize`
- `Carp`

The distribution does not depend on LWP, Mojolicious, PSGI, PAGI,
Linux::Event, or another HTTP client/server framework.

## Explicit non-goals for 0.01

Version 0.01 does not own:

- HTTP retries or request replay
- connections or transaction state
- redirects or proxy routing
- server-side verification of incoming `Authorization`
- challenge construction for servers
- `Authentication-Info` or `Proxy-Authentication-Info` processing
- `nextnonce` or preemptive authentication caches
- user databases, sessions, permissions, or authorization policy
- OAuth authorization/token-refresh flows
- JWT decoding or validation
- framework adapters or event-loop integration
- Futures, promises, async/await, or callback policy
- a public custom-scheme plugin ABI

## References

The 0.01 implementation is governed primarily by:

- RFC 9110, HTTP Semantics / HTTP Authentication Framework
- RFC 7617, Basic HTTP Authentication
- RFC 7616, Digest HTTP Authentication
- RFC 6750, OAuth 2.0 Bearer Token Usage

Where legacy interoperability differs from current specifications, current RFC
behavior is the baseline and compatibility handling is isolated and documented.
