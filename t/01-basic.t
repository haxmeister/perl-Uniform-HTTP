use strict;
use warnings;
use Test::More;
use lib 'lib';

use Uniform::HTTP::Auth;
use Uniform::HTTP::Auth::Basic;

my $auth = Uniform::HTTP::Auth->new;
my $challenges = $auth->parse_challenges('Basic realm="Members"');

is scalar(@$challenges), 1, 'one Basic challenge parsed';
is $challenges->[0]{scheme}, 'basic', 'scheme normalized';
is $challenges->[0]{params}{realm}, 'Members', 'realm parsed';
ok !$challenges->[0]{malformed}, 'Basic challenge is well formed';

is(Uniform::HTTP::Auth::Basic->authorization(
    username  => 'Aladdin',
    password  => 'open sesame',
    challenge => $challenges->[0],
), 'Basic QWxhZGRpbjpvcGVuIHNlc2FtZQ==', 'Basic construction matches RFC example');

my $bad = $auth->parse_challenges('Basic charset="UTF-8"');
ok $bad->[0]{malformed}, 'Basic challenge without realm is malformed';
like $bad->[0]{error}, qr/requires realm/, 'missing realm explained';

eval {
    Uniform::HTTP::Auth::Basic->authorization(
        username  => 'bad:user',
        password  => 'secret',
        challenge => $challenges->[0],
    );
};
like $@, qr/must not contain ':'/, 'colon in Basic username croaks';

done_testing;
