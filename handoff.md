# Uniform::HTTP native FastPath handoff

## Scope and baseline

Only haxmeister/perl-Uniform-HTTP was changed. Work began at main 976e895,
Uniform::HTTP 0.05. The feature work was fast-forwarded into local main for
the 0.06 release preparation.

Uniform remains pure Perl. No compiler is used by its distribution build,
ordinary tests, or installation. No Unblock repositories were changed.

## Implemented

- Design/audit recorded first in commit d287f7f; now in author/native-design.md.
  The shipped docs/NATIVE-FASTPATH.md starts with purpose and usage.
- Installed header at lib/Uniform/HTTP/FastPath/uniform_http_fastpath.h.
- Header-only static inline C helpers, native ABI 1 plus storage revision check.
- Per-interpreter runtime handle; compatible/incompatible/old-runtime handling.
- Explicit trusted construction from copied byte spans and ordered fields into
  exact Message, Request, and Response objects, with structural/state checks.
- Borrowed scalar/section inspection of exact canonical objects. Safe rejection
  of subclasses, adapters, tied/magical storage, and malformed nested pairs.
- Ownership, trust, mutation, freeze, completion, and thread rules documented.
- Portable Perl API and FastPath ABI 1 behavior unchanged.
- Native fixture and benchmarks are repository-only under author/ and bench/.
  handoff.md is excluded from the distribution too.
- CI adds compiler-free installation and explicit native conformance.

## Validation

Portable suite: 21 files, 1292 tests. Native suite: 360 tests.
Both passed locally on Perl 5.16.3 (nonthreaded), 5.38.2 (threaded), and
5.44.0 (threaded): 1652 tests per interpreter, with thread checks skipped only
on the nonthreaded build. The 5.16 run caught and fixed repeated macro evaluation
of POPs in SvTRUE; the header now pops into a local variable first.

The author fixture builds with -Wall -Wextra -Werror on system Perl.
Compiler-free staging/configure/test/install passes using compiler and linker
commands that fail if called. Installed ordinary objects and header discovery
are checked. make disttest and POD checks passed.

Benchmarks use identical native input for all constructor paths and C consumers
for all inspection paths. See bench/README.md and the recorded result files.
The four-header Perl 5.44 run measured native construction at 1.849 us/request
and 1.675 us/response versus Perl FastPath 5.664 and 4.895 us. Native inspection
was 0.503 and 0.452 us versus 2.386 and 2.191 us. These are object costs, not
Unblock or network throughput measurements.

## Release preparation

Version 0.06 is prepared for GitHub and CPAN. All nine module versions and
current public contract documents agree. Changes is dated 2026-10-04.
The shipped native guide has been simplified; its design audit is repository-only.

Release checks for 0.06 passed: all 1652 portable/native tests on Perl 5.16.3,
5.38.2, and 5.44.0; compiler-free configure/test/install; distcheck, disttest,
POD syntax, and archive inspection. All nine module versions are 0.06.
The release archive includes the native header and excludes author tests,
benchmarks, the design audit, and handoff.md.

The user authorized pushing main. Tag v0.06, a GitHub release, and CPAN upload
remain the user's release steps. No tag or published release was created here.

The user will integrate the header into Unblock engines in their own chats.
The native path requires a successful runtime handshake. Consumers with a 0.05
runtime must fall back to the existing Perl FastPath or ordinary methods.
Do not expose trusted construction for unvalidated application input.

Native ABI 1 deliberately copies bytes and owns canonical storage; it does not
adopt external SV/AV storage, add native mutation, or parse HTTP. Expand only
when engine integration shows a concrete need. Changing header storage knowledge
requires changing the runtime compatibility decision as documented.
