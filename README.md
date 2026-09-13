# Uniform::HTTP::Auth

Unified, framework-agnostic HTTP authentication for Perl web applications.

`Uniform::HTTP::Auth` implements HTTP authentication mechanics without depending on an HTTP client, server, framework, event loop, or transaction abstraction.

Initial scheme support:

- Basic (RFC 7617)
- Bearer (RFC 6750)
- Digest (RFC 7616)

See `docs/API-SPEC.md` for the 0.01 design contract.
