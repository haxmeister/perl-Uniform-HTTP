use strict;
use warnings;
use Test::More;
use lib 'lib';

use Uniform::HTTP::Auth;

my @contexts;
my $auth = Uniform::HTTP::Auth->new(
    schemes => [qw(bearer basic)],
    credentials => sub {
        my ($context) = @_;
        push @contexts, { %$context };
        return if $context->{scheme} eq 'bearer';
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
is_deeply [ map { $_->{scheme} } @contexts ], [qw(bearer basic)], 'callback called in scheme order';
is $contexts[0]{origin}, 'https://example.com:443', 'origin passed unchanged';

my $no_credentials = Uniform::HTTP::Auth->new;
eval {
    $no_credentials->authorize(
        challenge_headers => ['Basic realm="x"'],
        origin => 'https://example.com:443',
    );
};
like $@, qr/requires credentials/, 'authorize without credentials croaks';

done_testing;
