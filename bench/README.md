# Native FastPath benchmark

Run from the repository with a C compiler available for the author fixture:

```text
perl author/native/build.pl
perl bench/native-fastpath.pl
```

This does not add an XS build to Uniform::HTTP. The fixture and benchmark are
repository-only and are excluded from the CPAN distribution.

Each construction starts with the same C input descriptor and native byte spans:

- Ordinary: allocate named Perl arguments and fields, call the public constructor.
- Perl FastPath: allocate the ABI 1 view and fields, call its trusted constructor.
- Native: copy spans directly into final canonical storage through the header.

Every iteration creates and destroys a new complete mutable object. Field arrays
are fresh for every construction path; no path shares one prebuilt array across
requests. Request metadata includes version, method, target, scheme, authority,
and protocol. Response metadata includes version, status, and reason. Every
object has a seven-byte binary body and one trailer. Header count varies among
zero, four, and 32; the fixture preserves duplicate names and spelling.

Inspection consumes one already-created object through ordinary Perl methods,
a fresh Perl FastPath view, or a native view. All paths compute the same C
checksum of metadata, flags, every header/trailer name and value, and body.
Checksum equivalence is tested before measurement and in conformance tests.
This avoids comparing Perl field loops with C field loops. It also includes
Perl call costs incurred by an XS serializer using ordinary methods.

The script rotates path order and reports the median of three samples, each
lasting at least 0.25 seconds. Use `--rounds 5 --seconds 1` for longer runs.
Numbers include loop and XS-call overhead; these are not isolated CPU instruction
costs. The shared execution host can affect wall-clock timing. Do not compare
absolute numbers between separate runs as a Perl-version performance ranking.

These measurements test the API's intended construction and inspection boundary.
They do not measure parsing, body streaming, I/O, protocol correctness, or network
throughput. Object allocation still costs time, particularly for many headers.
Actual engine integration and end-to-end benchmarks remain separate work.

## Recorded result

Perl 5.44.0, threaded Linux, four headers and one trailer; median microseconds
per operation (lower is better):

| Operation | Ordinary API | Perl FastPath | Native FastPath |
| --- | ---: | ---: | ---: |
| Request construction | 33.912 | 5.664 | 1.849 |
| Response construction | 31.368 | 4.895 | 1.675 |
| Request inspection | 14.875 | 2.386 | 0.503 |
| Response inspection | 12.964 | 2.191 | 0.452 |

For this case, native construction reduced cost by 67% for requests and 66% for
responses against Perl FastPath (3.1x and 2.9x faster). Native inspection reduced
cost by about 79% (4.7x and 4.8x faster). With 32 headers, construction gains
narrowed to 1.9x and 1.7x because final canonical field allocation remains.

Raw results are in `native-fastpath-5.44.0.txt`. The separate system-Perl run in
`native-fastpath-5.38.2.txt` also showed lower native costs, with more visible
host timing variation. Treat the measurements as directional evidence for
engine integration, not as promised throughput or a Perl-version comparison.
