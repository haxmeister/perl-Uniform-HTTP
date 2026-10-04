use strict;
use warnings;
use FindBin;
use Config;
use lib "$FindBin::Bin/../lib";
use lib "$FindBin::Bin/../author/_build/native-$Config{version}";
use Uniform::HTTP::NativeTest;
use Time::HiRes qw(time);
use Getopt::Long qw(GetOptions);

my ($seconds, $rounds) = (0.25, 3);
GetOptions('seconds=f' => \$seconds, 'rounds=i' => \$rounds) or die "bad options\n";
die "seconds must be positive; rounds must be odd and >= 3\n"
    unless $seconds > 0 && $rounds >= 3 && $rounds % 2;
$| = 1;
print "Perl $Config{version}; threads=$Config{useithreads}; $Config{archname}\n";
print "Median of $rounds rounds, at least $seconds seconds per sample. us/op.\n";
print "Fresh native input -> full object, including destruction. Inspection uses\n";
print "the same C checksum over all metadata, fields, trailers, and body.\n";
print "No parser, I/O, or network throughput is measured.\n\n";
printf "%-9s %7s %-14s %13s %13s %13s\n", qw(kind headers operation ordinary perl_fastpath native);

sub measure {
    my ($code) = @_;
    my ($iterations, $elapsed) = (0, 0);
    my $start = time;
    do {
        for (1 .. 1000) { $code->() }
        $iterations += 1000;
        $elapsed = time - $start;
    } while ($elapsed < $seconds);
    return $elapsed * 1_000_000 / $iterations;
}
for my $kind (1, 2) {
    for my $count (0, 4, 32) {
        my $object = Uniform::HTTP::NativeTest::make_message($kind, $count);
        my $expected = Uniform::HTTP::NativeTest::checksum($object);
        for my $path (1, 2) {
            die "inspection mismatch\n" unless
                Uniform::HTTP::NativeTest::inspect_via_perl($object, $path, $kind) == $expected;
        }
        for my $op ('construction', 'inspection') {
            my @code = $op eq 'construction' ? (
                sub { my $r = Uniform::HTTP::NativeTest::make_message($kind, $count, -1, 0, 0x55485431, 2) },
                sub { my $r = Uniform::HTTP::NativeTest::make_message($kind, $count, -1, 0, 0x55485431, 1) },
                sub { my $r = Uniform::HTTP::NativeTest::make_message($kind, $count, -1, 0, 0x55485431, 0) },
            ) : (
                sub { Uniform::HTTP::NativeTest::inspect_via_perl($object, 2, $kind) },
                sub { Uniform::HTTP::NativeTest::inspect_via_perl($object, 1, $kind) },
                sub { Uniform::HTTP::NativeTest::checksum($object) },
            );
            my @samples;
            for my $round (0 .. $rounds-1) {
                # Rotate order to reduce systematic warmup and scheduling bias.
                for my $j (0 .. 2) {
                    my $i = ($round + $j) % 3;
                    push @{$samples[$i]}, measure($code[$i]);
                }
            }
            my @median = map { my @a = sort { $a <=> $b } @$_; $a[int(@a/2)] } @samples;
            printf "%-9s %7d %-14s %13.3f %13.3f %13.3f\n",
                $kind == 1 ? 'request' : 'response', $count, $op, @median;
        }
    }
}
