use strict;
use warnings;
use Test::More;
use FindBin;
use Config;
use lib "$FindBin::Bin/../lib";
use lib "$FindBin::Bin/_build/native-$Config{version}";
use Uniform::HTTP::FastPath;
use Uniform::HTTP::NativeTest;
use Scalar::Util qw(refaddr);

sub perl_view { Uniform::HTTP::FastPath::view($_[0]) }
sub native_view { Uniform::HTTP::NativeTest::snapshot($_[0]) }
sub build { Uniform::HTTP::NativeTest::make_message(@_) }
sub dies_like {
    my ($code, $pattern, $name) = @_;
    eval { $code->() };
    like $@, $pattern, $name;
}
sub ordinary {
    my ($kind, $count) = @_;
    my @args = (
        version => '1.1',
        headers => [ map { [ $_ % 2 ? 'x-Test' : 'X-Test', $_ % 2 ? "two\t\xff" : 'one' ] } 0 .. $count-1 ],
        trailers => [ [ 'X-End', 'yes' ] ], body => "hello\0\xff",
    );
    return Uniform::HTTP::Message->new(@args) if $kind == 0;
    return Uniform::HTTP::Request->new(@args, method => 'POST', target => '/items?id=42',
        scheme => 'https', authority => 'example.com', protocol => 'future') if $kind == 1;
    return Uniform::HTTP::Response->new(@args, status => 200, reason => 'OK');
}

ok Uniform::HTTP::NativeTest::compatible(), 'runtime handshake succeeds';
ok !Uniform::HTTP::NativeTest::compatible(999), 'compile-time ABI mismatch rejected';
{
    no warnings 'redefine';
    local *Uniform::HTTP::FastPath::native_compatible = sub { 0 };
    ok !Uniform::HTTP::NativeTest::compatible(), 'installed runtime mismatch rejected';
}
{
    local *Uniform::HTTP::FastPath::native_compatible;
    ok !Uniform::HTTP::NativeTest::compatible(), 'pre-native runtime without handshake rejected';
}
for my $kind (0 .. 2) {
    for my $count (0, 4, 32) {
        my $normal = ordinary($kind, $count);
        my $native = build($kind, $count);
        is ref($native), ref($normal), 'exact canonical class';
        if ($kind) {
            for my $path (1, 2) {
                is_deeply perl_view(build($kind, $count, -1, 0, 0x55485431, $path)),
                    perl_view($normal), 'benchmark construction paths agree';
                is Uniform::HTTP::NativeTest::inspect_via_perl($native, $path, $kind),
                    Uniform::HTTP::NativeTest::checksum($native), 'benchmark inspection paths agree';
            }
        }
        is_deeply perl_view($native), perl_view($normal), 'native construction has ordinary public contents';
        is_deeply native_view($native), perl_view($native), 'native view agrees with Perl view';
        is_deeply native_view($normal), perl_view($normal), 'native view reads ordinary object';
        ok Uniform::HTTP::NativeTest::out_of_range($native), 'field bounds are checked';
        for my $op (sub { $_[0]->header('X-New', 'ok')->remove_header('X-Test') },
            sub { $_[0]->body('new')->trailer('X-New', 'trailer') },
            sub { $_[0]->mark_incomplete->freeze_initial },
            sub { $_[0]->mark_complete->freeze_trailers },
            sub { $_[0]->freeze->mark_incomplete->mark_complete }) {
            $op->($normal); $op->($native);
            is_deeply native_view($native), perl_view($normal), 'ordinary mutation and lifecycle behavior preserved';
        }
        dies_like(sub { $native->header('X', 'y') }, qr/immutable/, 'native initial freeze enforced');
        dies_like(sub { $native->body('no') }, qr/immutable/, 'native body freeze enforced');
        dies_like(sub { $native->add_trailer('X', 'y') }, qr/immutable/, 'native trailer freeze enforced');
    }
    # Every representable combination of completeness, body presence, and locks.
    for my $flags (0 .. 511) {
        next unless ($flags & 0xc0) == 0xc0;
        next unless !!($flags & 0x100) == ($kind == 1);
        next unless !!($flags & 4) == !!($flags & 16);
        next if !($flags & 4) && ($flags & 0x28);
        my $native = build($kind, 2, $flags);
        is native_view($native)->[2], $flags, "kind $kind flags $flags round trip";
        is_deeply native_view($native), perl_view($native), 'Perl/native state agrees';
        if ($kind) {
            my $from_perl = $kind == 1
                ? Uniform::HTTP::FastPath::request_from_validated(perl_view($native))
                : Uniform::HTTP::FastPath::response_from_validated(perl_view($native));
            is_deeply native_view($native), native_view($from_perl), '0.05 trusted construction semantics preserved';
        }
    }
}
my $copied = build(1, 4, -1, 12);
is $copied->method, 'POST', 'native stack string was copied before buffer changed';
my $independent = native_view($copied);
$copied->header('X-Test', 'replaced');
is_deeply $independent->[11], ordinary(1, 4)->{headers}, 'explicit snapshot copies survive owner mutation';
undef $copied;
is $independent->[4], 'POST', 'copied inspection scalar survives owner destruction';
$copied = build(1, 4);
ok !utf8::is_utf8($copied->body), 'native body is an octet string';
ok !utf8::is_utf8($copied->header_value(1)), 'native field is an octet string';
my $second = build(1, 4);
my $first_view = perl_view($copied);
my $second_view = perl_view($second);
isnt refaddr($first_view->[11]), refaddr($second_view->[11]), 'objects own independent header arrays';
isnt refaddr($first_view->[11][0]), refaddr($second_view->[11][0]), 'objects own independent pairs';
$copied->add_header('X-New', 'value');
is $second->header_count, 4, 'mutation has no cross-object effects';
is build(1, 4, -1, 11)->body, '', 'present empty native body preserved';
ok build(1, 4, -1, 11)->has_buffered_body, 'empty body still present';
my $neutral = build(1, 0, -1, 15);
is $neutral->version, undef, 'absent native version preserved';
is $neutral->scheme, undef, 'absent optional metadata preserved';

for my $case (
    [1, 1, qr/byte span/], [1, 2, qr/empty/], [1, 3, qr/field array/],
    [1, 4, qr/byte span/], [1, 5, qr/byte span/], [1, 6, qr/flags/],
    [2, 7, qr/status/], [2, 8, qr/request metadata/], [1, 9, qr/response metadata/],
    [1, 10, qr/too large/], [1, 13, qr/empty/], [1, 16, qr/too large/],
    [1, 17, qr/uninitialized/], [1, 18, qr/uninitialized/],
) {
    my ($kind, $fault, $pattern) = @$case;
    dies_like(sub { build($kind, 4, -1, $fault) }, $pattern, "malformed native descriptor $fault rejected");
}
dies_like(sub { build(3) }, qr/kind/, 'bad kind rejected');
dies_like(sub { build(1, 4, -1, 0, 0) }, qr/trusted/, 'no implicit trust for zero-initialized input');
for my $flags (0, 0x3ff, 0x1c4, 0x1d0, 0x1e0, 0xc0) {
    dies_like(sub { build(1, 4, $flags) }, qr/flags/, 'inconsistent flags rejected');
}
# Trusted APIs are not validators or security boundaries. Opting in deliberately
# skips syntax; the existing validated application API still rejects this value.
is build(1, 4, -1, 14)->method, 'NOT VALID', 'explicit trusted path skips semantic validation';
dies_like(sub { Uniform::HTTP::Request->new(method => 'NOT VALID', target => '/') },
    qr/token/, 'untrusted ordinary constructor still validates semantics');
dies_like(sub { $second->method('NOT VALID') }, qr/token/, 'native-created object still has validated setters');

{
    package Local::Subclass;
    use parent 'Uniform::HTTP::Request';
}
for my $object (undef, {}, [], bless([], 'Uniform::HTTP::Request'),
    Local::Subclass->new(method => 'GET', target => '/'),
    bless({}, 'Uniform::HTTP::Request')) {
    is native_view($object), undef, 'unsupported or malformed object falls back safely';
}
{
    package Local::Tied;
    sub TIEHASH { bless {}, shift }
    sub TIEARRAY { bless {}, shift }
    sub TIESCALAR { bless {}, shift }
    sub FETCH { die 'must not call magic' }
    sub FETCHSIZE { die 'must not call magic' }
}
my %tied;
tie %tied, 'Local::Tied';
is native_view(bless(\%tied, 'Uniform::HTTP::Request')), undef, 'tied canonical hash rejected without callbacks';
my $glob = build();
$glob->{method} = *STDOUT;
is native_view($glob), undef, 'glob storage rejected as non-scalar metadata';
my $magic = build();
tie $magic->{method}, 'Local::Tied';
is native_view($magic), undef, 'magical scalar rejected without callbacks';
$magic = build();
tie @{$magic->{headers}}, 'Local::Tied';
is native_view($magic), undef, 'tied section rejected without callbacks';
for my $pair (undef, {}, ['only one'], ['three', 'values', 'here'], [[], 'value']) {
    my $broken = build();
    $broken->{headers}[0] = $pair;
    dies_like(sub { native_view($broken) }, qr/not canonical/, 'malformed nested pair rejected safely');
}
$magic = build();
tie @{$magic->{headers}[0]}, 'Local::Tied';
dies_like(sub { native_view($magic) }, qr/not canonical/, 'tied pair rejected without callbacks');

SKIP: {
    skip 'Perl was built without ithreads', 2 unless $Config{useithreads};
    require threads;
    my $thread = threads->create(sub {
        my $r = build();
        return [ref($r), native_view($r)->[4]];
    });
    is_deeply $thread->join, ['Uniform::HTTP::Request', 'POST'], 'child interpreter initializes its own native handle';
    is native_view(build())->[4], 'POST', 'parent handle remains valid';
}
done_testing;
