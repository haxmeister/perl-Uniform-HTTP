use strict;
use warnings;
use Test::More;
use lib 'lib';

use Uniform::HTTP::Message;
use Uniform::HTTP::Request;
use Uniform::HTTP::Response;

my $headers = [ ['X-Name', 'one'], ['X-Name', 'two'] ];
my $response = Uniform::HTTP::Response->new(
    status => 201, reason => 'Created', version => '1.1',
    headers => $headers, trailers => [ ['X-End', 'yes'] ],
    body => 'ok',
);
is(ref($response), 'Uniform::HTTP::Response', 'canonical response class');
is($response->status, 201, 'status retained');
is($response->reason, 'Created', 'reason retained');
is($response->version, '1.1', 'common version retained');
is_deeply($response->header_values('X-Name'), ['one', 'two'],
    'duplicate header ordering retained');
is($response->trailer('X-End'), 'yes', 'trailers retained');
is($response->body, 'ok', 'body retained');
$headers->[0][1] = 'changed';
is($response->header('X-Name'), 'one', 'common headers copied');

my $request = Uniform::HTTP::Request->new(
    method => 'POST', target => '/upload', scheme => 'https',
    authority => 'example.org', version => '1.1',
    headers => [ ['Content-Type', 'text/plain'] ],
    body => 'payload',
);
is(ref($request), 'Uniform::HTTP::Request', 'canonical request class');
is($request->method, 'POST', 'request method retained');
is($request->target, '/upload', 'target retained');
is($request->scheme, 'https', 'scheme retained');
is($request->authority, 'example.org', 'authority retained');
is($request->header('Content-Type'), 'text/plain', 'header retained');
is($request->body, 'payload', 'request body retained');

for my $case (
    [sub { Uniform::HTTP::Response->new(status => 200, bogus => 1) },
        qr/unknown constructor option/],
    [sub { Uniform::HTTP::Request->new(method => 'GET', target => '/', bogus => 1) },
        qr/unknown constructor option/],
    [sub { Uniform::HTTP::Response->new(status => 200, headers => [ ['Bad Name', 'x'] ]) },
        qr/header name must be an HTTP token/],
    [sub { Uniform::HTTP::Response->new(status => 200, body => chr(0x100)) },
        qr/body must be a byte string/],
    [sub { Uniform::HTTP::Response->new(status => 99) },
        qr/status must be an integer/],
) {
    my ($call, $error) = @$case;
    eval { $call->() };
    like($@, $error, 'canonical constructor validation preserved');
}

{
    package Local::DerivedResponse;
    use parent 'Uniform::HTTP::Response';
    our $version_set = 0;
    sub version {
        my $self = shift;
        $version_set++ if @_;
        return $self->SUPER::version(@_);
    }
}
my $derived = Local::DerivedResponse->new(
    status => 202, version => '2', body => '',
);
isa_ok($derived, 'Local::DerivedResponse');
is($Local::DerivedResponse::version_set, 1,
    'derived response continues using its virtual setters');
is($derived->version, '2', 'derived response fields retained');

{
    package Local::DerivedRequest;
    use parent 'Uniform::HTTP::Request';
    our $version_set = 0;
    sub version {
        my $self = shift;
        $version_set++ if @_;
        return $self->SUPER::version(@_);
    }
}
my $derived_request = Local::DerivedRequest->new(
    method => 'GET', target => '/', version => '2',
);
isa_ok($derived_request, 'Local::DerivedRequest');
is($Local::DerivedRequest::version_set, 1,
    'derived request continues using its virtual setters');

$response->freeze;
eval { $response->status(204) };
like($@, qr/message is immutable/, 'immutable response remains protected');

done_testing;
