use strict;
use warnings;
use Time::HiRes qw(clock_gettime CLOCK_PROCESS_CPUTIME_ID);
use Uniform::HTTP::Request;
use Uniform::HTTP::Response;

my $iterations = 100_000;
my $clock = CLOCK_PROCESS_CPUTIME_ID();
my @cases = (
    [ response => sub {
        Uniform::HTTP::Response->new(status => 200, body => 'ok');
    }],
    [ request => sub {
        Uniform::HTTP::Request->new(method => 'GET', target => '/');
    }],
);

print "Response source: $INC{'Uniform/HTTP/Response.pm'}\n";
print "Request source: $INC{'Uniform/HTTP/Request.pm'}\n";
for my $case (@cases) {
    my ($name, $build) = @$case;
    my @sample;
    for (1 .. 5) {
        my $start = clock_gettime($clock);
        for (1 .. $iterations) {
            my $object = $build->();
            die "constructor returned no object" unless ref($object);
        }
        my $elapsed = clock_gettime($clock) - $start;
        push @sample, $elapsed * 1_000_000 / $iterations;
    }
    my @ordered = sort { $a <=> $b } @sample;
    printf "%s cpu_us_per_object median=%.4f samples=%s\n",
        $name, $ordered[2],
        join(',', map { sprintf('%.4f', $_) } @sample);
}
