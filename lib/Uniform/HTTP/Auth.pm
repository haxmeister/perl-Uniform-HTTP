package Uniform::HTTP::Auth;

use strict;
use warnings;
use Carp qw(croak);

use Uniform::HTTP::Auth::Basic ();
use Uniform::HTTP::Auth::Bearer ();
use Uniform::HTTP::Auth::Digest ();

our $VERSION = '0.01';

my %SCHEME_CLASS = (
    basic  => 'Uniform::HTTP::Auth::Basic',
    bearer => 'Uniform::HTTP::Auth::Bearer',
    digest => 'Uniform::HTTP::Auth::Digest',
);

sub new {
    my ($class, %args) = @_;

    my $schemes = exists $args{schemes}
        ? $args{schemes}
        : [qw(digest bearer basic)];

    croak "schemes must be an array reference"
        unless ref($schemes) eq 'ARRAY';

    my (@normalized, %seen);
    for my $scheme (@$schemes) {
        croak "scheme names must be plain scalars"
            if !defined($scheme) || ref($scheme);
        my $name = lc $scheme;
        croak "unsupported authentication scheme '$scheme'"
            unless exists $SCHEME_CLASS{$name};
        croak "duplicate authentication scheme '$scheme'"
            if $seen{$name}++;
        push @normalized, $name;
    }

    if (exists $args{credentials}) {
        croak "credentials must be a coderef"
            unless ref($args{credentials}) eq 'CODE';
    }

    my $self = bless {
        schemes     => \@normalized,
        credentials => $args{credentials},
        digest      => Uniform::HTTP::Auth::Digest->new,
    }, $class;

    return $self;
}

sub schemes {
    my ($self) = @_;
    return [ @{ $self->{schemes} } ];
}

sub parse_challenges {
    my ($self, @values) = @_;

    my @out;
    for my $value (@values) {
        if (!defined($value) || ref($value)) {
            push @out, {
                scheme    => undef,
                raw       => defined($value) ? "$value" : '',
                params    => {},
                token68   => undef,
                malformed => 1,
                error     => 'challenge header value must be a plain scalar',
            };
            next;
        }
        push @out, @{ _parse_field($value) };
    }

    for my $challenge (@out) {
        next if $challenge->{malformed};
        my $scheme = $challenge->{scheme};
        next unless defined $scheme && exists $SCHEME_CLASS{$scheme};

        my $class = $SCHEME_CLASS{$scheme};
        my $error = $class->validate_challenge($challenge);
        if (defined $error) {
            $challenge->{malformed} = 1;
            $challenge->{error} = $error;
        }
    }

    return \@out;
}

sub select {
    my ($self, $challenges) = @_;
    croak "select() requires an array reference"
        unless ref($challenges) eq 'ARRAY';

    for my $scheme (@{ $self->{schemes} }) {
        my @candidates = grep {
            ref($_) eq 'HASH'
                && !$_->{malformed}
                && defined($_->{scheme})
                && $_->{scheme} eq $scheme
        } @$challenges;

        next unless @candidates;

        my $handler = $self->_handler($scheme);
        my $chosen = $handler->select_challenge(\@candidates);
        return $chosen if $chosen;
    }

    return;
}

sub authorize {
    my ($self, %args) = @_;

    croak "authorize() requires a credentials provider"
        unless ref($self->{credentials}) eq 'CODE';

    croak "challenge_headers must be an array reference"
        unless ref($args{challenge_headers}) eq 'ARRAY';

    _validate_origin($args{origin});

    my $challenges = $self->parse_challenges(@{ $args{challenge_headers} });

    for my $scheme (@{ $self->{schemes} }) {
        my @candidates = grep {
            !$_->{malformed}
                && defined($_->{scheme})
                && $_->{scheme} eq $scheme
        } @$challenges;
        next unless @candidates;

        my $handler = $self->_handler($scheme);
        my $challenge = $handler->select_challenge(\@candidates);
        next unless $challenge;

        my $need = {
            scheme    => $scheme,
            origin    => $args{origin},
            realm     => $challenge->{params}{realm},
            challenge => $challenge,
        };

        my $credentials = $self->{credentials}->($need);
        next unless defined $credentials;
        croak "credentials provider must return a hash reference or undef"
            unless ref($credentials) eq 'HASH';

        my $value;
        if ($scheme eq 'basic') {
            _require_fields($credentials, qw(username password));
            $value = Uniform::HTTP::Auth::Basic->authorization(
                %$credentials,
                challenge => $challenge,
            );
        }
        elsif ($scheme eq 'bearer') {
            _require_fields($credentials, qw(token));
            $value = Uniform::HTTP::Auth::Bearer->authorization(
                %$credentials,
                challenge => $challenge,
            );
        }
        elsif ($scheme eq 'digest') {
            _require_fields($credentials, qw(username password));
            croak "method is required for Digest authentication"
                unless defined($args{method}) && !ref($args{method});
            croak "request_target is required for Digest authentication"
                unless defined($args{request_target}) && !ref($args{request_target});

            my %digest_args = (
                %$credentials,
                challenge      => $challenge,
                method         => $args{method},
                request_target => $args{request_target},
            );
            $digest_args{entity_body} = $args{entity_body}
                if exists $args{entity_body};

            $value = $handler->authorization(%digest_args);
            next unless defined $value;
        }

        return {
            scheme    => $scheme,
            value     => $value,
            challenge => $challenge,
        };
    }

    return;
}

sub _handler {
    my ($self, $scheme) = @_;
    return $self->{digest} if $scheme eq 'digest';
    return $SCHEME_CLASS{$scheme};
}

sub _require_fields {
    my ($credentials, @fields) = @_;
    for my $field (@fields) {
        croak "credentials provider result requires '$field'"
            unless exists($credentials->{$field}) && defined($credentials->{$field});
        croak "credential '$field' must be a plain scalar"
            if ref($credentials->{$field});
    }
}

sub _validate_origin {
    my ($origin) = @_;
    croak "origin is required"
        unless defined($origin) && !ref($origin) && length($origin);
    croak "origin must be a normalized origin without credentials or path"
        unless $origin =~ m{\A[A-Za-z][A-Za-z0-9+.-]*://[^/?#@]+\z};
}

my $TCHAR = q{!#$%&'*+\-.^_`|~0-9A-Za-z};
my $TOKEN_RE = qr/[$TCHAR]+/;
my $TOKEN68_RE = qr/[A-Za-z0-9\-._~+\/]+={0,}/;

sub _parse_field {
    my ($value) = @_;

    if ($value =~ /[\r\n]/) {
        return [{
            scheme    => undef,
            raw       => $value,
            params    => {},
            token68   => undef,
            malformed => 1,
            error     => 'challenge header value contains a newline',
        }];
    }

    my @parts = _split_top_level_commas($value);
    my @out;
    my $current;

    for my $part (@parts) {
        my $trim = $part;
        $trim =~ s/\A[ \t]+//;
        $trim =~ s/[ \t]+\z//;
        next unless length $trim;

        if ($current && $current->{_mode} && $current->{_mode} eq 'params') {
            my ($name, $param_value, $error) = _parse_auth_param($trim);
            if (defined $name) {
                $current->{raw} .= ',' . $part;
                if (exists $current->{params}{$name}) {
                    $current->{malformed} = 1;
                    $current->{error} ||= "duplicate authentication parameter '$name'";
                }
                else {
                    $current->{params}{$name} = $param_value;
                }
                next;
            }

            if ($trim =~ /\A$TOKEN_RE[ \t]*=/) {
                $current->{raw} .= ',' . $part;
                $current->{malformed} = 1;
                $current->{error} ||= $error || 'malformed authentication parameter';
                next;
            }
        }

        push @out, _finish_challenge($current) if $current;
        $current = _start_challenge($part);
    }

    push @out, _finish_challenge($current) if $current;

    if (!@out && length $value) {
        push @out, {
            scheme    => undef,
            raw       => $value,
            params    => {},
            token68   => undef,
            malformed => 1,
            error     => 'no authentication challenge found',
        };
    }

    return \@out;
}

sub _start_challenge {
    my ($raw) = @_;
    my $trim = $raw;
    $trim =~ s/\A[ \t]+//;
    $trim =~ s/[ \t]+\z//;

    my $challenge = {
        scheme    => undef,
        raw       => $raw,
        params    => {},
        token68   => undef,
        malformed => 0,
        error     => undef,
        _mode     => undef,
    };

    unless ($trim =~ /\A($TOKEN_RE)(?:[ \t]+(.*))?\z/) {
        $challenge->{malformed} = 1;
        $challenge->{error} = 'malformed authentication challenge';
        return $challenge;
    }

    $challenge->{scheme} = lc $1;
    my $rest = $2;
    return $challenge unless defined($rest) && length($rest);

    $rest =~ s/[ \t]+\z//;

    if ($rest =~ /\A($TOKEN68_RE)\z/) {
        $challenge->{token68} = $1;
        $challenge->{_mode} = 'token68';
        return $challenge;
    }

    my ($name, $value, $error) = _parse_auth_param($rest);
    unless (defined $name) {
        $challenge->{malformed} = 1;
        $challenge->{error} = $error || 'malformed authentication parameters';
        return $challenge;
    }

    $challenge->{params}{$name} = $value;
    $challenge->{_mode} = 'params';
    return $challenge;
}

sub _finish_challenge {
    my ($challenge) = @_;
    delete $challenge->{_mode};
    $challenge->{raw} =~ s/\A[ \t]+//;
    $challenge->{raw} =~ s/[ \t]+\z//;
    return $challenge;
}

sub _parse_auth_param {
    my ($text) = @_;

    unless ($text =~ /\A($TOKEN_RE)[ \t]*=[ \t]*(.*)\z/) {
        return (undef, undef, 'authentication parameter requires name=value syntax');
    }

    my $name = lc $1;
    my $raw_value = $2;

    if ($raw_value =~ /\A($TOKEN_RE)\z/) {
        return ($name, $1, undef);
    }

    if ($raw_value =~ /\A"(.*)"\z/s) {
        my $inner = $1;
        return (undef, undef, 'quoted authentication parameter contains a newline')
            if $inner =~ /[\r\n]/;

        my $decoded = '';
        while (length $inner) {
            if ($inner =~ s/\A\\([\x09\x20-\x7e\x80-\xff])//s) {
                $decoded .= $1;
            }
            elsif ($inner =~ s/\A([^"\\]+)//s) {
                $decoded .= $1;
            }
            else {
                return (undef, undef, 'malformed quoted authentication parameter');
            }
        }
        return ($name, $decoded, undef);
    }

    return (undef, undef, 'authentication parameter value must be a token or quoted string');
}

sub _split_top_level_commas {
    my ($text) = @_;
    my @parts;
    my $start = 0;
    my $quoted = 0;
    my $escaped = 0;

    for (my $i = 0; $i < length($text); $i++) {
        my $ch = substr($text, $i, 1);

        if ($quoted) {
            if ($escaped) {
                $escaped = 0;
            }
            elsif ($ch eq '\\') {
                $escaped = 1;
            }
            elsif ($ch eq '"') {
                $quoted = 0;
            }
            next;
        }

        if ($ch eq '"') {
            $quoted = 1;
            next;
        }

        if ($ch eq ',') {
            push @parts, substr($text, $start, $i - $start);
            $start = $i + 1;
        }
    }

    push @parts, substr($text, $start);
    return @parts;
}

1;

__END__

=head1 NAME

Uniform::HTTP::Auth - Framework-agnostic HTTP authentication engine

=head1 SYNOPSIS

    use Uniform::HTTP::Auth;

    my $auth = Uniform::HTTP::Auth->new(
        credentials => sub {
            my ($need) = @_;
            return {
                username => 'user',
                password => 'secret',
            } if $need->{scheme} eq 'basic';
            return;
        },
    );

    my $result = $auth->authorize(
        challenge_headers => ['Basic realm="Members"'],
        origin            => 'https://example.com:443',
        method            => 'GET',
        request_target    => '/',
    );

    # $result->{value} is a complete Authorization field value.

=head1 DESCRIPTION

Uniform::HTTP::Auth implements HTTP authentication mechanics without depending on
an HTTP client, server, framework, event loop, or transaction abstraction. Callers
supply plain HTTP authentication data and receive plain Perl data in return.

See F<docs/API-SPEC.md> in the distribution for the complete 0.01 contract.

=cut
