use strict;
use warnings;
use Test::More;
use lib 'lib';

use Uniform::HTTP::Auth;

my @needs;
my $auth = Uniform::HTTP::Auth->new(
    schemes => [qw(bearer basic)],
    credentials => sub {
        my ($need) = @_;
        push @needs, { %$need };
        return if $need->{scheme} eq 'bearer';
        return { username => 'Aladdin', password => 'open sesame' };
    },
);

my $result = $auth->authorize(
    challenge_headers => [
        'Bearer realm="api", Basic realm="Members"',
    ],
    origin         => 'https://example.com:443',
    method         => 'GET',
    request_target => '/',
);

is $result->{scheme}, 'basic', 'falls through when preferred scheme has no credentials';
is $result->{value}, 'Basic QWxhZGRpbjpvcGVuIHNlc2FtZQ==', 'authorization value returned';
is_deeply [ map { $_->{scheme} } @needs ], [qw(bearer basic)], 'provider called in scheme order';
is $needs[0]{origin}, 'https://example.com:443', 'origin passed unchanged';

my $no_provider = Uniform::HTTP::Auth->new;
eval {
    $no_provider->authorize(
        challenge_headers => ['Basic realm="x"'],
        origin => 'https://example.com:443',
    );
};
like $@, qr/credentials provider/, 'authorize without provider croaks';

done_testing;
