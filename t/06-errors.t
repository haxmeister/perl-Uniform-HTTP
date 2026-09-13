use strict;
use warnings;
use Test::More;
use lib 'lib';

use Uniform::HTTP::Auth;

my $auth = Uniform::HTTP::Auth->new;

my $newline = $auth->parse_challenges("Basic realm=\"x\"\r\nInjected: yes");
ok $newline->[0]{malformed}, 'newline in remote header is data error, not exception';

my $error = eval { Uniform::HTTP::Auth->new(schemes => ['negotiate']); 1 };
ok !$error, 'unsupported configured built-in scheme croaks';
like $@, qr/unsupported authentication scheme/, 'unsupported scheme error is explicit';

my $bad_origin = Uniform::HTTP::Auth->new(credentials => sub { return });
eval {
    $bad_origin->authorize(
        challenge_headers => ['Basic realm="x"'],
        origin => 'https://user:pass@example.com/private',
    );
};
like $@, qr/normalized origin/, 'origin with credentials/path is rejected';

done_testing;
