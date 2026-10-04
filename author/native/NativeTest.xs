#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"
#include "uniform_http_fastpath.h"

typedef struct { uhttp_native_api api; } my_cxt_t;
START_MY_CXT

static uhttp_native_bytes bytes(const char *s, STRLEN len) {
    uhttp_native_bytes b;
    b.data = s; b.len = len;
    return b;
}

static void fixture(uhttp_native_input *in, U32 kind, int count,
    uhttp_native_field *fields, uhttp_native_field *trailers) {
    int i;
    uhttp_native_input_init(in, kind);
    in->version = bytes("1.1", 3);
    if (kind == UHTTP_KIND_REQUEST) {
        in->method = bytes("POST", 4);
        in->target = bytes("/items?id=42", 12);
        in->scheme = bytes("https", 5);
        in->authority = bytes("example.com", 11);
        in->protocol = bytes("future", 6);
    }
    if (kind == UHTTP_KIND_RESPONSE) {
        in->status = 200;
        in->reason = bytes("OK", 2);
    }
    for (i = 0; i < count; ++i) {
        fields[i].name = bytes(i % 2 ? "x-Test" : "X-Test", 6);
        fields[i].value = bytes(i % 2 ? "two\t\xff" : "one", i % 2 ? 5 : 3);
    }
    trailers[0].name = bytes("X-End", 5);
    trailers[0].value = bytes("yes", 3);
    in->headers = fields;
    in->header_count = count;
    in->trailers = trailers;
    in->trailer_count = 1;
    in->body = bytes("hello\0\xff", 7);
    in->flags |= UHTTP_HAS_BUFFERED_BODY;
}

static SV *section_copy(pTHX_ const uhttp_native_section *section) {
    AV *copy = newAV();
    Size_t i, count = uhttp_native_field_count(aTHX_ section);
    SV *rv = sv_2mortal(newRV_noinc((SV *)copy));
    for (i = 0; i < count; ++i) {
        SV *n, *v;
        AV *pair;
        uhttp_native_field_at(aTHX_ section, i, &n, &v);
        pair = newAV();
        av_push(copy, newRV_noinc((SV *)pair));
        av_push(pair, newSVsv(n));
        av_push(pair, newSVsv(v));
    }
    return newSVsv(rv);
}

static UV svlength(pTHX_ SV *sv) {
    STRLEN len;
    if (!SvOK(sv)) return 0;
    (void)SvPVbyte(sv, len);
    return (UV)len;
}


/* All construction benchmarks start at the same native spans. These helpers
 * model the intermediate Perl values required by existing engine integrations.
 */
static SV *copy_bytes(pTHX_ uhttp_native_bytes b) {
    return b.data ? newSVpvn(b.data, b.len) : newSV(0);
}

static SV *copy_fields(pTHX_ const uhttp_native_field *fields, Size_t count) {
    AV *a = newAV();
    SV *rv = sv_2mortal(newRV_noinc((SV *)a));
    Size_t i;
    for (i = 0; i < count; ++i) {
        AV *pair = newAV();
        av_push(a, newRV_noinc((SV *)pair));
        av_push(pair, copy_bytes(aTHX_ fields[i].name));
        av_push(pair, copy_bytes(aTHX_ fields[i].value));
    }
    return rv;
}

static SV *construct_via_perl(pTHX_ const uhttp_native_input *in, int path) {
    dSP;
    SV *result;
    const char *class_name = in->kind == 1 ? "Uniform::HTTP::Request" : "Uniform::HTTP::Response";
    ENTER;
    SAVETMPS;
    if (path == 1) {
        AV *view = newAV();
        SV *rv = sv_2mortal(newRV_noinc((SV *)view));
        av_push(view, newSViv(1));
        av_push(view, newSVuv(in->kind));
        av_push(view, newSVuv(in->flags));
        av_push(view, copy_bytes(aTHX_ in->version));
        av_push(view, copy_bytes(aTHX_ in->method));
        av_push(view, copy_bytes(aTHX_ in->target));
        av_push(view, copy_bytes(aTHX_ in->scheme));
        av_push(view, copy_bytes(aTHX_ in->authority));
        av_push(view, copy_bytes(aTHX_ in->protocol));
        av_push(view, in->kind == 2 ? newSViv(in->status) : newSV(0));
        av_push(view, copy_bytes(aTHX_ in->reason));
        av_push(view, newSVsv(copy_fields(aTHX_ in->headers, in->header_count)));
        av_push(view, newSVsv(copy_fields(aTHX_ in->trailers, in->trailer_count)));
        av_push(view, copy_bytes(aTHX_ in->body));
        PUSHMARK(SP);
        XPUSHs(rv);
        PUTBACK;
        call_pv(in->kind == 1 ? "Uniform::HTTP::FastPath::request_from_validated"
            : "Uniform::HTTP::FastPath::response_from_validated", G_SCALAR);
    }
    else {
        PUSHMARK(SP);
        XPUSHs(sv_2mortal(newSVpv(class_name, 0)));
#define PUSH_VALUE(key, value) XPUSHs(sv_2mortal(newSVpvs(key))); XPUSHs(sv_2mortal(value))
        PUSH_VALUE("version", copy_bytes(aTHX_ in->version));
        PUSH_VALUE("headers", newSVsv(copy_fields(aTHX_ in->headers, in->header_count)));
        PUSH_VALUE("trailers", newSVsv(copy_fields(aTHX_ in->trailers, in->trailer_count)));
        PUSH_VALUE("body", copy_bytes(aTHX_ in->body));
        if (in->kind == 1) {
            PUSH_VALUE("method", copy_bytes(aTHX_ in->method));
            PUSH_VALUE("target", copy_bytes(aTHX_ in->target));
            PUSH_VALUE("scheme", copy_bytes(aTHX_ in->scheme));
            PUSH_VALUE("authority", copy_bytes(aTHX_ in->authority));
            PUSH_VALUE("protocol", copy_bytes(aTHX_ in->protocol));
        }
        else {
            PUSH_VALUE("status", newSViv(in->status));
            PUSH_VALUE("reason", copy_bytes(aTHX_ in->reason));
        }
#undef PUSH_VALUE
        PUTBACK;
        call_method("new", G_SCALAR);
    }
    SPAGAIN;
    result = newSVsv(POPs);
    PUTBACK;
    FREETMPS;
    LEAVE;
    return result;
}

/* One method crossing, immediate scalar consumption, no retained SV. */
static UV read_method(pTHX_ SV *object, const char *method, int numeric, IV index) {
    dSP;
    UV result;
    SV *value;
    ENTER;
    SAVETMPS;
    PUSHMARK(SP);
    XPUSHs(object);
    if (index >= 0) XPUSHs(sv_2mortal(newSViv(index)));
    PUTBACK;
    call_method(method, G_SCALAR);
    SPAGAIN;
    value = POPs;
    result = numeric ? SvUV(value) : svlength(aTHX_ value);
    PUTBACK;
    FREETMPS;
    LEAVE;
    return result;
}

static UV checksum_methods(pTHX_ SV *object, U32 kind) {
    UV sum;
    U32 flags = UHTTP_HEADERS_LOSSLESS | UHTTP_TRAILERS_LOSSLESS;
    IV i, count;
    int s;
    if (kind == 1) flags |= UHTTP_TARGET_EXACT;
    if (read_method(aTHX_ object, "has_buffered_body", 1, -1)) flags |= UHTTP_HAS_BUFFERED_BODY;
    if (read_method(aTHX_ object, "is_complete", 1, -1)) flags |= UHTTP_COMPLETE;
    if (read_method(aTHX_ object, "is_mutable", 1, -1)) flags |= UHTTP_MUTABLE;
    if (read_method(aTHX_ object, "initial_is_mutable", 1, -1)) flags |= UHTTP_INITIAL_MUTABLE;
    if (read_method(aTHX_ object, "body_is_mutable", 1, -1)) flags |= UHTTP_BODY_MUTABLE;
    if (read_method(aTHX_ object, "trailers_are_mutable", 1, -1)) flags |= UHTTP_TRAILERS_MUTABLE;
    sum = flags + kind + read_method(aTHX_ object, "version", 0, -1) +
        read_method(aTHX_ object, "body", 0, -1);
    if (kind == 1) {
        sum += read_method(aTHX_ object, "method", 0, -1) + read_method(aTHX_ object, "target", 0, -1) +
            read_method(aTHX_ object, "scheme", 0, -1) + read_method(aTHX_ object, "authority", 0, -1) +
            read_method(aTHX_ object, "protocol", 0, -1);
    }
    else sum += read_method(aTHX_ object, "status", 0, -1) + read_method(aTHX_ object, "reason", 0, -1);
    for (s = 0; s < 2; ++s) {
        count = read_method(aTHX_ object, s ? "trailer_count" : "header_count", 1, -1);
        for (i = 0; i < count; ++i) {
            sum += read_method(aTHX_ object, s ? "trailer_name" : "header_name", 0, i);
            sum += read_method(aTHX_ object, s ? "trailer_value" : "header_value", 0, i);
        }
    }
    return sum;
}

static UV checksum_perl_view(pTHX_ SV *object) {
    dSP;
    UV sum;
    IV i, j, count;
    AV *view;
    SV *rv;
    ENTER;
    SAVETMPS;
    PUSHMARK(SP);
    XPUSHs(object);
    PUTBACK;
    call_pv("Uniform::HTTP::FastPath::view", G_SCALAR);
    SPAGAIN;
    rv = POPs;
    view = (AV *)SvRV(rv);
    sum = SvUV(*av_fetch(view, 1, 0)) + SvUV(*av_fetch(view, 2, 0));
    for (i = 3; i <= 13; ++i) {
        if (i == 11 || i == 12) {
            AV *fields = (AV *)SvRV(*av_fetch(view, i, 0));
            count = av_len(fields) + 1;
            for (j = 0; j < count; ++j) {
                AV *pair = (AV *)SvRV(*av_fetch(fields, j, 0));
                sum += svlength(aTHX_ *av_fetch(pair, 0, 0)) + svlength(aTHX_ *av_fetch(pair, 1, 0));
            }
        }
        else sum += svlength(aTHX_ *av_fetch(view, i, 0));
    }
    PUTBACK;
    FREETMPS;
    LEAVE;
    return sum;
}

MODULE = Uniform::HTTP::NativeTest PACKAGE = Uniform::HTTP::NativeTest
PROTOTYPES: DISABLE

BOOT:
    MY_CXT_INIT;
    if (!uhttp_native_init(aTHX_ &MY_CXT.api, UHTTP_NATIVE_ABI_VERSION))
        croak("native test fixture ABI mismatch");

void
CLONE(...)
    CODE:
        MY_CXT_CLONE;
        if (!uhttp_native_init(aTHX_ &MY_CXT.api, UHTTP_NATIVE_ABI_VERSION))
            croak("native test fixture clone ABI mismatch");

int
compatible(version = UHTTP_NATIVE_ABI_VERSION)
    UV version
    PREINIT:
        uhttp_native_api api;
    CODE:
        RETVAL = uhttp_native_init(aTHX_ &api, (U32)version);
    OUTPUT: RETVAL

SV *
make_message(kind = 1, count = 4, flags = -1, fault = 0, trust = UHTTP_NATIVE_TRUSTED, path = 0)
    U32 kind
    int count
    IV flags
    int fault
    U32 trust
    int path
    PREINIT:
        dMY_CXT;
        uhttp_native_input in;
        uhttp_native_field fields[64], trailers[1];
        char scratch[] = "POST";
        uhttp_native_api wrong;
    CODE:
        if (count < 0 || count > 64) croak("fixture field count out of range");
        fixture(&in, kind, count, fields, trailers);
        if (flags >= 0) {
            in.flags = (U32)flags;
            if (!(in.flags & UHTTP_HAS_BUFFERED_BODY)) in.body = bytes(NULL, 0);
        }
        switch (fault) {
            case 1: in.method = bytes(NULL, 4); break;
            case 2: in.target = bytes("", 0); break;
            case 3: in.headers = NULL; in.header_count = 1; break;
            case 4: fields[0].name = bytes(NULL, 1); break;
            case 5: fields[0].value = bytes(NULL, 0); break;
            case 6: in.body = bytes(NULL, 0); break;
            case 7: in.status = 99; break;
            case 8: in.method = bytes("POST", 4); break;
            case 9: in.reason = bytes("bad", 3); break;
            case 10: in.header_count = (Size_t)I32_MAX + 1; break;
            case 11: in.body = bytes("", 0); break;
            case 12: in.method = bytes(scratch, 4); break;
            case 13: fields[0].name = bytes("", 0); break;
            case 14: in.method = bytes("NOT VALID", 9); break;
            case 15: in.version = bytes(NULL, 0); in.reason = bytes(NULL, 0);
                     in.scheme = in.authority = in.protocol = bytes(NULL, 0); break;
            case 16: in.body = bytes("x", (STRLEN)IV_MAX); break;
        }
        if (path) {
            if (kind < 1 || kind > 2 || fault || flags != -1) croak("invalid benchmark input");
            RETVAL = construct_via_perl(aTHX_ &in, path);
        }
        else if (fault == 17) {
            Zero(&wrong, 1, uhttp_native_api);
            RETVAL = uhttp_native_from_validated(aTHX_ &wrong, &in, trust);
        }
        else if (fault == 18) {
            uhttp_native_init(aTHX_ &wrong, UHTTP_NATIVE_ABI_VERSION);
            uhttp_native_init(aTHX_ &wrong, 999);
            RETVAL = uhttp_native_from_validated(aTHX_ &wrong, &in, trust);
        }
        else RETVAL = uhttp_native_from_validated(aTHX_ &MY_CXT.api, &in, trust);
        scratch[0] = 'X'; /* the returned object must not borrow stack memory */
    OUTPUT: RETVAL

SV *
snapshot(object)
    SV *object
    PREINIT:
        dMY_CXT;
        uhttp_native_view view;
        AV *result;
        SV *rv;
    CODE:
        if (!uhttp_native_inspect(aTHX_ &MY_CXT.api, object, &view)) XSRETURN_UNDEF;
        result = newAV();
        rv = sv_2mortal(newRV_noinc((SV *)result));
        av_push(result, newSVuv(1));
        av_push(result, newSVuv(view.kind));
        av_push(result, newSVuv(view.flags));
        av_push(result, newSVsv(view.version));
        av_push(result, newSVsv(view.method));
        av_push(result, newSVsv(view.target));
        av_push(result, newSVsv(view.scheme));
        av_push(result, newSVsv(view.authority));
        av_push(result, newSVsv(view.protocol));
        av_push(result, newSVsv(view.status));
        av_push(result, newSVsv(view.reason));
        av_push(result, section_copy(aTHX_ &view.headers));
        av_push(result, section_copy(aTHX_ &view.trailers));
        av_push(result, newSVsv(view.body));
        RETVAL = newSVsv(rv);
    OUTPUT: RETVAL

UV
checksum(object)
    SV *object
    PREINIT:
        dMY_CXT;
        uhttp_native_view v;
        UV sum;
        Size_t i, count;
        SV *name, *value;
        int s;
        uhttp_native_section *section;
    CODE:
        if (!uhttp_native_inspect(aTHX_ &MY_CXT.api, object, &v)) croak("not canonical");
        sum = v.kind + v.flags;
        sum += svlength(aTHX_ v.version) + svlength(aTHX_ v.method) +
            svlength(aTHX_ v.target) + svlength(aTHX_ v.scheme) +
            svlength(aTHX_ v.authority) + svlength(aTHX_ v.protocol) +
            svlength(aTHX_ v.status) + svlength(aTHX_ v.reason) + svlength(aTHX_ v.body);
        for (s = 0; s < 2; ++s) {
            section = s ? &v.trailers : &v.headers;
            count = uhttp_native_field_count(aTHX_ section);
            for (i = 0; i < count; ++i) {
                uhttp_native_field_at(aTHX_ section, i, &name, &value);
                sum += svlength(aTHX_ name) + svlength(aTHX_ value);
            }
        }
        RETVAL = sum;
    OUTPUT: RETVAL

int
out_of_range(object)
    SV *object
    PREINIT:
        dMY_CXT;
        uhttp_native_view v;
        SV *n, *value;
    CODE:
        if (!uhttp_native_inspect(aTHX_ &MY_CXT.api, object, &v)) croak("not canonical");
        RETVAL = !uhttp_native_field_at(aTHX_ &v.headers,
            uhttp_native_field_count(aTHX_ &v.headers), &n, &value)
            && !SvOK(n) && !SvOK(value);
    OUTPUT: RETVAL

UV
inspect_via_perl(object, path, kind)
    SV *object
    int path
    U32 kind
    CODE:
        RETVAL = path == 1 ? checksum_perl_view(aTHX_ object) : checksum_methods(aTHX_ object, kind);
    OUTPUT: RETVAL
