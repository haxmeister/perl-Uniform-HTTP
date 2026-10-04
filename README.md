# Uniform::HTTP

Framework-neutral HTTP messages and authentication for Perl, independent of
transports, event loops, and web frameworks.

`Uniform::HTTP` provides a small semantic layer that HTTP clients, servers,
frameworks, middleware, and applications can share without adopting one
another's object model.

## Modules

- `Uniform::HTTP::Message` represents common message state.
- `Uniform::HTTP::Request` adds method, target, scheme, and authority semantics.
- `Uniform::HTTP::Response` adds status and optional reason semantics.
- `Uniform::HTTP::Auth` implements Basic, Bearer, and Digest authentication.

The canonical message classes are mutable, lossless, detached objects.
Framework adapters are separate distributions and implement the same portable
contract.

## Request and response objects

```perl
use Uniform::HTTP::Request;
use Uniform::HTTP::Response;

my $request = Uniform::HTTP::Request->new(
    method    => 'POST',
    target    => '/items?draft=1',
    scheme    => 'https',
    authority => 'example.com',
    version   => '1.1',
    headers => [
        [ 'Content-Type', 'application/json' ],
        [ 'X-Trace',      'one' ],
        [ 'X-Trace',      'two' ],
    ],
    body => '{"name":"example"}',
);

my $response = Uniform::HTTP::Response->new(
    status  => 201,
    reason  => 'Created',
    headers => [ [ 'Content-Type', 'application/json' ] ],
    body    => '{}',
);
```

Headers are an ordered list of field occurrences. Duplicate fields and
original field-name spelling are preserved. Lookup is ASCII case-insensitive,
and repeated values are never silently comma-joined.

Bodies and header values are bytes. A message never consumes an input stream,
filehandle, callback, PSGI input object, or PAGI body source merely because
`body()` was called.

`is_complete()` and `is_mutable()` are part of the portable contract so
adapters can report native message state truthfully. Adapters are not required
to provide methods that change those states.

Canonical Uniform objects additionally provide `freeze()`,
`mark_incomplete()`, and `mark_complete()` as local helpers. `freeze()`
makes every represented message value immutable, including a buffered body,
without sending or committing anything in a framework.

## HTTP/2 and HTTP/3 request metadata

`scheme()` and `authority()` are optional request metadata. Uniform never
infers them from Host, a request target, or the transport.

HTTP/2 and HTTP/3 adapters normally expose exact `:path` bytes through
`target()`. Ordinary CONNECT is the special case because it has
`:authority` but no `:path`; adapters expose the exact `:authority` bytes
as the authority-form target and may still report `target_is_exact()` as
true.

Authority handling is deliberately minimal and byte-oriented. Uniform is not a
URI parser and does not impose protocol-specific host, port, userinfo, IP
literal, or percent-escape rules.

## Authentication

```perl
use Uniform::HTTP::Auth;

my $auth = Uniform::HTTP::Auth->new(
    origin => 'https://example.com:443',
    credentials => {
        username => 'user',
        password => 'secret',
    },
);

my $result = $auth->prepare_authentication(
    challenge_headers => [
        'Digest realm="Members", nonce="abc", qop="auth", algorithm=SHA-256',
        'Basic realm="Members"',
    ],
    request => $request,
);

my $authorization_value = $result->{value};
```

`prepare_authentication()` also accepts explicit `method`,
`request_target`, and `entity_body` values, preserving the API released in
`Uniform-HTTP-Auth` 0.01. It performs no network I/O and does not retry or send
the request.

Supported authentication schemes are:

- Basic (RFC 7617)
- Bearer (RFC 6750)
- Digest (RFC 7616), including MD5, SHA-256, SHA-512/256, session variants,
  `qop=auth`, `qop=auth-int`, UTF-8, `userhash`, and nonce-count state

## Ownership boundary

Uniform owns:

- lossless HTTP message semantics
- exact request targets when supplied by the source
- optional request scheme and authority semantics
- buffered body state
- capability reporting for adapters
- authentication challenge parsing and scheme selection
- Basic, Bearer, and Digest value construction

The calling HTTP implementation owns:

- parsing and serializing wire protocols
- sockets, TLS, connections, and transaction state
- incremental request and response body transfer
- native message lifecycle and framework response commitment
- cancellation, backpressure, retry, redirect, and replay policy
- HTTP/1 framing, HTTP/2 streams, and HTTP/3 streams

## Adapters

Adapters are explicit and separately installed. A core application never
runtime-probes for Mojo, PSGI, PAGI, Dancer2, Catalyst, Linux::Event, or
`HTTP::Message`.

Adapters report mutability and completeness through the portable capability
methods. They do not need to implement the canonical `freeze()`,
`mark_incomplete()`, or `mark_complete()` helpers.

See `docs/MESSAGE-SPEC.md` for the normative message contract and
`docs/ADAPTERS.md` for adapter requirements.

## Installation

```text
cpanm Uniform::HTTP
```

For a checkout:

```text
perl Makefile.PL
make
make test
```

## Migration from Uniform-HTTP-Auth

`Uniform::HTTP::Auth` keeps its module name and public 0.01 API. Beginning with
version 0.02 it is released as part of `Uniform-HTTP`. Code that loads or
declares a dependency on `Uniform::HTTP::Auth` does not need to change.

## License

MIT License.
