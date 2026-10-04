# Uniform::HTTP

[![CPAN version](https://badge.fury.io/pl/Uniform-HTTP.svg)](https://metacpan.org/dist/Uniform-HTTP)
[![CPANTS Kwalitee](https://cpants.cpanauthors.org/dist/Uniform-HTTP.svg)](https://cpants.cpanauthors.org/dist/Uniform-HTTP)
[![CI](https://github.com/haxmeister/perl-Uniform-HTTP/actions/workflows/test.yml/badge.svg?branch=main)](https://github.com/haxmeister/perl-Uniform-HTTP/actions/workflows/test.yml)
[![License](https://img.shields.io/cpan/l/Uniform-HTTP.svg)](https://github.com/haxmeister/perl-Uniform-HTTP/blob/main/LICENSE)
[![Perl](https://img.shields.io/badge/perl-5.16%2B-blue.svg)](https://www.perl.org/)

Uniform::HTTP provides small, framework-neutral HTTP objects for Perl.

It gives different HTTP libraries a common way to represent:

- requests
- responses
- headers
- buffered bodies
- HTTP authentication

It does **not** open sockets, run an event loop, parse HTTP from the network, or
send requests. Those jobs stay with the HTTP client, server, or framework using
it.

The useful mental model is:

```text
HTTP client / server / framework
            |
      Uniform::HTTP
            |
   request / response data
```

This makes it possible for unrelated HTTP implementations to exchange the same
kind of request and response objects without depending on each other's object
model.

## Installation

From CPAN:

```text
cpanm Uniform::HTTP
```

Uniform::HTTP requires Perl 5.16 or newer.

## Start here

Most application code will use `Uniform::HTTP::Request` and
`Uniform::HTTP::Response`.

Create a request:

```perl
use Uniform::HTTP::Request;

my $request = Uniform::HTTP::Request->new(
    method    => 'GET',
    target    => '/users?id=42',
    scheme    => 'https',
    authority => 'example.com',
    headers   => [
        [ 'Accept', 'application/json' ],
    ],
);

say $request->method;               # GET
say $request->target;               # /users?id=42
say $request->header('Accept');     # application/json
```

Create a response:

```perl
use Uniform::HTTP::Response;

my $response = Uniform::HTTP::Response->new(
    status  => 200,
    headers => [
        [ 'Content-Type', 'text/plain' ],
    ],
    body => "hello\n",
);

say $response->status;              # 200
say $response->body;                # hello
```

These are plain detached HTTP message objects. Creating one does not perform
network I/O.

## Headers

Headers are stored as an ordered list instead of a hash.

That matters because HTTP can contain repeated fields:

```perl
my $response = Uniform::HTTP::Response->new(
    status => 200,
    headers => [
        [ 'Set-Cookie', 'a=1' ],
        [ 'Set-Cookie', 'b=2' ],
    ],
);

my $first = $response->header('Set-Cookie');

my $all = $response->header_values('Set-Cookie');
# [ 'a=1', 'b=2' ]
```

Uniform::HTTP preserves:

- duplicate header fields
- header order
- original field-name spelling

Header lookup is case-insensitive.

## Bodies

`body()` represents a body that is already buffered in memory.

```perl
my $body = $response->body;
```

Uniform::HTTP never reads a socket, filehandle, callback, or streaming body
source just because `body()` was called.

Use:

```perl
$response->has_buffered_body;
```

to tell whether a complete buffered body is available.

Streaming belongs to the HTTP implementation around the Uniform object.

## Changing a message

Canonical Uniform objects are mutable by default:

```perl
$request->header('Accept', 'text/html');
$response->status(404);
```

They can be frozen when no more message values should change:

```perl
$response->freeze;
```

After `freeze()`, setters throw an exception.

`is_mutable()` reports whether the current representation can still be
changed.

`is_complete()` reports whether the whole message is known to be complete.
Adapters may return `undef` when their framework cannot know yet.

## HTTP/2 and HTTP/3

Uniform::HTTP does not implement HTTP/2 or HTTP/3. It only represents the HTTP
message semantics those protocols carry.

Requests have separate `scheme()`, `authority()`, and `target()` values so
HTTP/1, HTTP/2, and HTTP/3 implementations can map their native request data
without losing meaning.

For ordinary HTTP/2 or HTTP/3 CONNECT, the exact `:authority` value is used as
the authority-form request target.

Protocol-specific validation and wire framing remain the job of the HTTP
implementation.

## Authentication

`Uniform::HTTP::Auth` prepares Basic, Bearer, and Digest authentication values.

A normal username/password example:

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
    ],
    method         => 'GET',
    request_target => '/private',
);

my $value = $result->{value};
```

`$value` is the complete authentication field value. The surrounding HTTP
implementation decides whether to put it in `Authorization` or
`Proxy-Authorization`, and whether to retry the request.

Authentication performs no network I/O.

Supported schemes are:

- Basic
- Bearer
- Digest

Most applications should use `Uniform::HTTP::Auth` directly. The
`Basic`, `Bearer`, and `Digest` submodules are also available for code that
only wants the lower-level calculations.

## What Uniform::HTTP does not do

Uniform::HTTP deliberately does not own:

- sockets or TLS
- connections
- HTTP parsing or serialization
- HTTP/1 framing
- HTTP/2 or HTTP/3 streams
- event loops
- request retries
- redirects
- streaming I/O
- framework response lifecycle

This is what keeps the objects usable across different HTTP implementations.

## Modules

The distribution contains:

- `Uniform::HTTP::Message` - shared message behavior
- `Uniform::HTTP::Request` - HTTP requests
- `Uniform::HTTP::Response` - HTTP responses
- `Uniform::HTTP::Auth` - HTTP authentication
- `Uniform::HTTP::Auth::Basic`
- `Uniform::HTTP::Auth::Bearer`
- `Uniform::HTTP::Auth::Digest`

## Adapters

A framework can expose its native request or response through the Uniform HTTP
contract without subclassing the canonical classes.

Adapters should be separate distributions. Uniform::HTTP itself does not depend
on Mojolicious, PSGI, PAGI, Linux::Event, or another HTTP stack.

Most users do not need to know the adapter rules. They are documented for HTTP
library authors in:

- `docs/MESSAGE-SPEC.md`
- `docs/ADAPTERS.md`
- `docs/AUTH-SPEC.md`

## Migration from Uniform-HTTP-Auth

`Uniform::HTTP::Auth` was originally released in the
`Uniform-HTTP-Auth` distribution.

Beginning with Uniform-HTTP 0.02, the same module is part of `Uniform-HTTP`.
Existing code using:

```perl
use Uniform::HTTP::Auth;
```

does not need to change.

## License

MIT License.
