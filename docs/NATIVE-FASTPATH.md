# Native FastPath

## Design audit

Baseline: Uniform::HTTP 0.05, main commit 976e895.

The ordinary constructors validate named arguments, call the common constructor,
copy and validate each field, and invoke setters for metadata. FastPath ABI 1
already avoids semantic validation and adopts ordered header/trailer arrays.
It still requires a 14-slot Perl array, structural checks in Perl, several Perl
calls, and Perl hash construction. Its view allocates another 14-slot array.
An XS parser must first turn native values into those intermediate Perl values.

The native interface will construct the same canonical hash-backed objects
inside the consumer's XS code. It will allocate the final Perl scalars and
ordered pairs directly, with no temporary Perl view or constructor call.
Inspection will fill a caller-owned C structure with borrowed scalar references
and field-section handles, without allocating a Perl view.

## Decisions

- Ship a header below `lib/Uniform/HTTP/FastPath/`. MakeMaker installs it as data.
  Uniform builds no XS and its normal tests compile nothing.
- Use static inline helpers compiled by each XS consumer. A dynamic vtable would
  require a native provider or pointers installed by another extension, neither
  of which belongs in this pure-Perl distribution. Macros are only constants.
- Version the native contract separately from Perl FastPath ABI 1. An explicit
  runtime handshake checks both the requested native version and storage revision
  before initializing a per-interpreter handle. Incompatible storage changes
  reject old consumers, even if their header compiled successfully.
- Keep object hash keys, allocation details, stashes, and state representation
  private to the header. Consumers use named message fields and section helpers.
- Accept native byte spans and ordered arrays of name/value spans. Copy bytes
  into owned canonical scalars. Do not retain parser memory or adopt caller SVs.
  Duplicate fields, original spelling, order, and separate trailers survive.
- Distinguish absent strings (`NULL, 0`) from empty strings (non-NULL, zero length).
  Body presence is independent of length. Status is an integer.
- Trusted construction is explicitly named and requires an explicit trust marker.
  Check descriptor shape, flags, required fields, and status range before any
  allocation. The parser remains responsible for Uniform's semantic validation.
  No C interface can prove that a parser actually performed those checks.
- Leave ordinary constructors and the existing Perl FastPath entirely intact.
  Untrusted input continues through ordinary constructors. Do not add a second
  validator, an HTTP parser, native setters, or native-only message classes.
- Borrow inspection values only while the source object is alive and unchanged.
  Do not modify borrowed SVs or section storage. Reinspect after any mutation;
  copy values before callbacks, asynchronous use, or releasing the owner.
- Accept exact canonical classes only. Adapters and subclasses use the portable
  Perl API. Reject magical/tied or malformed storage without invoking callbacks.
- Use documented Perl APIs, explicit interpreter context, and no global cached
  SV/stash pointers. Consumers initialize a handle in each interpreter, including
  cloned threads. Recompile the consumer for each Perl binary as usual for XS.

## Verification plan

Keep the existing portable tests unchanged. Add compiler-free packaging and
handshake tests. Put the XS conformance fixture, lifecycle/ownership tests, and
benchmarks under `author/` and `bench/`; run them explicitly in author CI, never
as an installation prerequisite. Check the installed header as well as source
builds, and use the existing Perl 5.16/current matrix for native conformance.

Measure request and response materialization, including fresh field storage,
for ordinary constructors, Perl FastPath, and native construction. Also measure
metadata/field inspection through methods, Perl views, and native views. Report
these as object costs, not HTTP throughput or parser speed.
