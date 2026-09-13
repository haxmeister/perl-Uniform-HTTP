# Uniform::HTTP::Auth 0.01 API Specification

Status: design contract for the initial implementation.

## Purpose

`Uniform::HTTP::Auth` is a transport-, framework-, and event-loop-agnostic HTTP authentication engine for Perl.

It deals only in HTTP authentication concepts and plain Perl data. It must not depend on or expose transaction, request, response, connection, event-loop, retry, or framework objects from any HTTP stack.

Any HTTP implementation should be able to use it by supplying challenge header values and request context, then consuming the returned `Authorization` value.

## Core ownership boundary

`Uniform::HTTP::Auth` owns:

- parsing `WWW-Authenticate` and `Proxy-Authenticate` challenge values
- preserving unknown authentication schemes
- supported-scheme discovery
- scheme preference and selection
- the credential-provider interface
- Basic credential construction
- Bearer credential construction
- Digest calculation
- Digest authentication state such as nonce count

The calling HTTP implementation owns:

- receiving HTTP 401 and 407 responses
- deciding whether a request can be retried
- request and transaction lifecycle
- replaying or resending requests
- connection management and reuse
- callback, promise, Future, or other completion APIs
- proxy routing and proxy connection state
- choosing whether the returned value is placed in `Authorization` or `Proxy-Authorization`

The caller is responsible for transport. Uniform is responsible for authentication.

## Initial modules

The distribution contains:

```text
Uniform::HTTP::Auth
Uniform::HTTP::Auth::Basic
Uniform::HTTP::Auth::Bearer
Uniform::HTTP::Auth::Digest
```

All four namespaces are part of the same `Uniform-HTTP-Auth` distribution.

## Initial supported schemes

Version 0.01 implements:

- Basic, RFC 7617
- Bearer, RFC 6750
- Digest, RFC 7616

Unknown schemes are parsed and exposed but are not automatically authorized by 0.01.

No public third-party scheme-handler ABI is frozen in 0.01. A plugin contract can be added later when a real additional scheme requires it.

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

The 0.01 default is:

```perl
[qw(digest bearer basic)]
```

This is a convenience policy, not a claim that Digest is universally preferable to Bearer. Applications can and should provide their own order when their authentication policy requires it.

Scheme names are case-insensitive and normalized to lowercase.

An unsupported scheme named in `schemes` is a programmer error and causes an exception.

### `credentials`

Optional coderef used to obtain application-owned credentials.

It is required only when `authorize()` is called. Parsing and selection methods can be used without a credential provider.

Calling `authorize()` without a credential provider is a programmer error and causes an exception.

## Credential provider contract

The provider is called as:

```perl
my $credentials = $provider->($need);
```

`$need` is a plain hash reference:

```perl
{
    scheme    => 'digest',
    origin    => 'https://example.com:443',
    realm     => 'Members',
    challenge => $challenge,
}
```

### `scheme`

Normalized lowercase authentication scheme selected by Uniform.

### `origin`

The protection-space origin supplied by the caller.

Uniform does not derive, normalize, or route origins. The caller must supply the appropriate origin for the endpoint issuing the challenge. For proxy authentication this is the proxy origin.

The origin must not contain user credentials or a resource path.

### `realm`

The challenge realm, or `undef` when the scheme does not supply one.

### `challenge`

The parsed challenge hash reference. This allows a credential provider to inspect scheme-specific information such as Bearer scope or Digest parameters without expanding the generic callback signature.

### Provider return values

The provider returns `undef` when it has no credentials for the requested protection space.

For Basic:

```perl
{
    username => 'josh',
    password => 'secret',
}
```

For Digest:

```perl
{
    username => 'josh',
    password => 'secret',
}
```

For Bearer:

```perl
{
    token => 'abcdef...',
}
```

Returning a credential structure that is missing fields required by the selected scheme is a programmer error and causes an exception.

The credential provider does not verify credentials. It supplies them.

## Challenge representation

`parse_challenges()` returns an array reference of plain hash references.

A successful challenge has this general shape:

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

For a token68 challenge, `token68` contains the token and `params` is empty.

Authentication scheme names and parameter names are normalized to lowercase. Parameter values retain their semantic value after quoted-string decoding.

The original challenge text is retained in `raw` for diagnostics and callers that need information not interpreted by 0.01.

Unknown schemes use exactly the same representation.

### Malformed challenges

Remote HTTP input is never treated as a programmer exception merely because it is malformed.

A malformed challenge is represented as data:

```perl
{
    scheme    => 'digest',    # when the scheme could be determined
    raw       => $raw,
    params    => {},
    token68   => undef,
    malformed => 1,
    error     => 'description of the syntax problem',
}
```

If even the scheme cannot be determined, `scheme` is `undef`.

Malformed challenges are never selected for authorization.

Duplicate authentication parameter names within one challenge are malformed.

## Root API

### `new`

```perl
my $auth = Uniform::HTTP::Auth->new(%options);
```

Constructs an authentication engine.

### `parse_challenges`

```perl
my $challenges = $auth->parse_challenges(@header_values);
```

Parses one or more complete `WWW-Authenticate` or `Proxy-Authenticate` field values.

Multiple field occurrences are supplied as multiple arguments. A field value may itself contain multiple challenges.

Returns an array reference in wire order.

This method does not perform credential lookup and does not choose a scheme.

### `select`

```perl
my $challenge = $auth->select($challenges);
```

Returns the best usable challenge according to configured scheme preference and the rules of the selected scheme.

Returns `undef` if no supported, well-formed challenge is usable.

`select()` does not call the credential provider.

When multiple challenges exist for the same scheme, the scheme module owns selection among that scheme's variants.

For Digest, 0.01 follows RFC 7616 behavior and ignores challenges whose algorithm is unsupported. Among supported Digest challenges, wire order is preserved unless the Digest module has a specific standards requirement to choose among variants.

### `authorize`

```perl
my $result = $auth->authorize(
    challenge_headers => \@www_authenticate_values,
    origin            => 'https://example.com:443',
    method            => 'GET',
    request_target    => '/private?x=1',
    entity_body       => $body,
);
```

High-level convenience operation.

It performs:

1. challenge parsing
2. supported-scheme ordering
3. scheme-specific challenge selection
4. credential lookup
5. scheme-specific Authorization construction

It tries enabled schemes in configured preference order. If the credential provider returns `undef` for one candidate, authorization may continue with the next usable candidate.

Returns `undef` when no supported challenge can produce credentials.

On success it returns a plain hash reference:

```perl
{
    scheme    => 'digest',
    value     => 'Digest username="...", ...',
    challenge => $challenge,
}
```

`value` is the complete authentication field value but does not include a header name. The caller chooses whether to send it as `Authorization`, `Proxy-Authorization`, or another contextually appropriate field.

### `origin`

`origin` is required by `authorize()` because credentials are scoped to an HTTP protection space.

Uniform treats the supplied origin as an opaque normalized origin identifier. It does not parse URLs or infer proxy behavior.

### `method`

Required when Digest is selected. Ignored by Basic and Bearer.

### `request_target`

Required when Digest is selected. This is the request target used in the Digest calculation.

Uniform does not derive it from a framework or request object.

### `entity_body`

Optional. Used by Digest when `qop=auth-int` is selected.

If a selected Digest challenge requires `auth-int` and no entity body is supplied, the challenge cannot be satisfied unless another supported qop or authentication scheme is available.

## Scheme selection

Scheme selection has two levels.

The root chooses the authentication scheme according to `schemes` preference.

The scheme module chooses among variants of that scheme.

Example:

```text
Root:
    Which scheme should be attempted?

Digest:
    Which Digest challenge/algorithm/qop should be used?
```

Credential availability is considered by `authorize()`, not by `select()`.

This permits introspection without invoking application credential logic.

## `Uniform::HTTP::Auth::Basic`

`Uniform::HTTP::Auth::Basic` owns Basic-specific challenge validation and credential construction.

### Public construction helper

```perl
my $value = Uniform::HTTP::Auth::Basic->authorization(
    username  => 'josh',
    password  => 'secret',
    challenge => $challenge,
);
```

Returns the complete field value:

```text
Basic <base64-user-pass>
```

The username must not contain a colon and neither username nor password may contain HTTP control characters.

When the challenge specifies `charset="UTF-8"`, username and password are normalized to NFC and encoded as UTF-8 before Base64 encoding.

When `charset` is absent, ASCII credentials are always supported. Exact policy for non-ASCII credentials without a charset indication must be explicit in the implementation and must not silently guess an encoding.

### Basic challenge rules

A Basic challenge requires `realm`.

`charset`, when present, must be `UTF-8` case-insensitively.

Unknown Basic challenge parameters are preserved and ignored for Basic calculation.

## `Uniform::HTTP::Auth::Bearer`

`Uniform::HTTP::Auth::Bearer` owns Bearer-specific challenge interpretation and Authorization construction.

### Public construction helper

```perl
my $value = Uniform::HTTP::Auth::Bearer->authorization(
    token => $token,
);
```

Returns:

```text
Bearer <token>
```

The token is validated against the Bearer credential syntax before construction.

Uniform does not decode JWTs, refresh OAuth tokens, contact authorization servers, validate token expiration, or determine token permissions.

Bearer challenge parameters such as `realm`, `scope`, `error`, `error_description`, and `error_uri` remain available through the parsed challenge and can be used by the credential provider.

## `Uniform::HTTP::Auth::Digest`

`Uniform::HTTP::Auth::Digest` owns all Digest-specific calculation and state.

It is stateful because Digest nonce count must persist across repeated use of a nonce.

### Supported algorithms

0.01 supports the RFC 7616 algorithm families:

- MD5
- MD5-sess
- SHA-256
- SHA-256-sess
- SHA-512-256
- SHA-512-256-sess

MD5 is retained for RFC compatibility but is not preferred as a new security choice.

Unsupported algorithms cause that Digest challenge to be ignored rather than treated as a programmer exception.

### Supported qop

0.01 supports:

- `auth`
- `auth-int`

Unknown qop values are ignored when alternatives are present.

If no usable qop remains, the Digest challenge is unusable.

Legacy Digest challenges that omit qop may be supported for interoperability, but that behavior must be clearly tested and documented as compatibility handling rather than modern RFC 7616 preference.

### Public construction helper

Digest is stateful, so direct use is object-based:

```perl
my $digest = Uniform::HTTP::Auth::Digest->new;

my $value = $digest->authorization(
    challenge     => $challenge,
    username      => 'josh',
    password      => 'secret',
    method        => 'GET',
    request_target => '/private',
    entity_body   => $body,
);
```

Returns the complete Digest field value.

### Digest state

The module maintains at least:

- nonce value
- nonce count (`nc`)
- client nonce (`cnonce`) where required
- challenge values needed for repeated calculations

Nonce count begins at `00000001` for the first request using a nonce and increments for subsequent uses of that nonce.

A new server nonce starts a new nonce-count sequence.

`cnonce` is generated from a cryptographically secure random source.

### `stale=true`

A fresh Digest challenge carrying `stale=true` is eligible for retry using the existing application credentials. Uniform handles the Digest state transition; the caller still owns whether and how the HTTP request is retried.

### Deferred Digest features

The following are intentionally not required for 0.01 unless implementation work shows they are necessary for RFC-correct baseline operation:

- processing `Authentication-Info`
- processing `Proxy-Authentication-Info`
- proactive handling of `nextnonce`
- preemptive authentication cache APIs
- public Digest session inspection APIs

They can be added without changing the caller/transport boundary.

## Error model

The library distinguishes programmer errors from remote protocol errors.

Programmer misuse causes an exception, for example:

- wrong argument types
- calling `authorize()` without a credential provider
- missing Basic username/password in provider output
- missing Bearer token in provider output
- enabling an unsupported built-in scheme
- selecting Digest without required request context

Remote HTTP input does not cause an exception merely because it is malformed.

Malformed challenges are represented with `malformed` and `error` and are ignored by automatic selection.

A credential provider returning `undef` is not an error. It means credentials are unavailable for that protection space.

## Dependency direction

The implementation should prefer mature, focused CPAN primitives over reimplementing established functionality.

Likely initial dependencies:

- `HTTP::Headers::Util` for generic header parameter parsing and quoting where it is standards-compatible
- `MIME::Base64` for Basic
- `Digest::SHA` for SHA-256 and SHA-512/256 Digest algorithms
- `Digest::MD5` for legacy Digest compatibility
- `Crypt::SysRandom` for Digest client nonce generation
- `Unicode::Normalize` for RFC-required NFC processing when UTF-8 credentials are used

The distribution must not depend on LWP, Mojolicious, PSGI, PAGI, Linux::Event, or another HTTP stack merely to obtain request/response abstractions.

LWP authentication code is a useful behavioral reference but is not the architectural base of this distribution.

## Explicit non-goals for 0.01

0.01 does not own:

- HTTP retries
- request replay
- connection state
- redirects
- proxy routing
- user databases
- password verification on behalf of a server
- sessions
- authorization or permissions
- OAuth authorization flows
- OAuth token refresh
- JWT decoding or validation
- framework adapters
- event-loop integration
- Futures, Promises, async/await, or callback policy
- public custom-scheme plugin ABI

## Future-compatible directions

The following can be added later without changing the 0.01 ownership boundary:

- `Authentication-Info` processing
- preemptive authentication support
- server-side Authorization parsing helpers
- challenge construction helpers
- custom authentication scheme handlers
- credential caches
- additional standard authentication schemes

## References

The initial implementation is governed primarily by:

- RFC 9110, HTTP Semantics, HTTP Authentication Framework
- RFC 7617, Basic HTTP Authentication
- RFC 7616, Digest HTTP Authentication
- RFC 6750, OAuth 2.0 Bearer Token Usage

Where legacy interoperability differs from current specifications, current RFC behavior is the baseline and compatibility behavior must be isolated and documented.
