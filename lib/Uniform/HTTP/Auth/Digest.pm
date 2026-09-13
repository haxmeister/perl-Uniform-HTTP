package Uniform::HTTP::Auth::Digest;

use strict;
use warnings;
use Carp qw(croak);
use Digest::MD5 ();
use Digest::SHA ();
use Encode qw(encode);
use Unicode::Normalize qw(NFC);

our $VERSION = '0.01';

my %ALGORITHM = map { $_ => 1 } qw(
    md5 md5-sess
    sha-256 sha-256-sess
    sha-512-256 sha-512-256-sess
);

sub new {
    my ($class, %args) = @_;
    if (exists $args{_random_bytes}) {
        croak "_random_bytes must be a coderef"
            unless ref($args{_random_bytes}) eq 'CODE';
    }
    return bless {
        nonce_state   => {},
        _random_bytes => $args{_random_bytes},
    }, $class;
}

sub validate_challenge {
    my ($class, $challenge) = @_;

    return 'Digest challenge must use authentication parameters'
        if defined $challenge->{token68};
    return 'Digest challenge requires realm'
        unless exists $challenge->{params}{realm};
    return 'Digest challenge requires nonce'
        unless exists $challenge->{params}{nonce};

    if (exists $challenge->{params}{charset}
        && lc($challenge->{params}{charset}) ne 'utf-8') {
        return 'Digest charset must be UTF-8';
    }

    if (exists $challenge->{params}{userhash}) {
        my $value = lc $challenge->{params}{userhash};
        return 'Digest userhash must be true or false'
            unless $value eq 'true' || $value eq 'false';
    }

    return;
}

sub select_challenge {
    my ($self, $challenges) = @_;

    for my $challenge (@$challenges) {
        next if $challenge->{malformed};
        next if defined __PACKAGE__->validate_challenge($challenge);

        my $algorithm = lc($challenge->{params}{algorithm} || 'MD5');
        next unless $ALGORITHM{$algorithm};

        if (exists $challenge->{params}{qop}) {
            my @qop = _qop_values($challenge->{params}{qop});
            next unless grep { $_ eq 'auth' || $_ eq 'auth-int' } @qop;
        }

        return $challenge;
    }

    return;
}

sub authorization {
    my ($self, %args) = @_;

    for my $field (qw(challenge username password method request_target)) {
        croak "Digest authorization requires '$field'"
            unless exists($args{$field}) && defined($args{$field});
    }
    croak "challenge must be a hash reference"
        unless ref($args{challenge}) eq 'HASH';
    for my $field (qw(username password method request_target)) {
        croak "$field must be a plain scalar" if ref($args{$field});
    }

    my $challenge = $args{challenge};
    my $error = __PACKAGE__->validate_challenge($challenge);
    croak $error if defined $error;

    my $params = $challenge->{params};
    my $algorithm = lc($params->{algorithm} || 'MD5');
    return unless $ALGORITHM{$algorithm};

    my $qop;
    if (exists $params->{qop}) {
        my @qops = _qop_values($params->{qop});
        $qop = 'auth' if grep { $_ eq 'auth' } @qops;
        $qop ||= 'auth-int' if grep { $_ eq 'auth-int' } @qops;
        return unless $qop;
        return if $qop eq 'auth-int' && !exists $args{entity_body};
    }

    my $username = $args{username};
    my $password = $args{password};
    croak "Digest username must not contain ':'" if $username =~ /:/;
    croak "Digest username contains a control character"
        if $username =~ /[\x00-\x1f\x7f]/;
    croak "Digest password contains a control character"
        if $password =~ /[\x00-\x1f\x7f]/;

    my $charset = $params->{charset};
    my ($u_bytes, $p_bytes, $realm_bytes);
    if (defined $charset) {
        $u_bytes = encode('UTF-8', NFC($username), Encode::FB_CROAK());
        $p_bytes = encode('UTF-8', NFC($password), Encode::FB_CROAK());
        $realm_bytes = $params->{realm};
    }
    else {
        croak 'non-ASCII Digest credentials require charset=UTF-8'
            if $username =~ /[^\x00-\x7f]/ || $password =~ /[^\x00-\x7f]/;
        $u_bytes = $username;
        $p_bytes = $password;
        $realm_bytes = $params->{realm};
    }

    my $nonce = $params->{nonce};
    my $is_session = $algorithm =~ /-sess\z/ ? 1 : 0;
    my ($nc, $cnonce);
    if (defined($qop) || $is_session) {
        ($nc, $cnonce) = $self->_nonce_values($nonce, defined($qop));
    }

    my $base_algorithm = $algorithm;
    $base_algorithm =~ s/-sess\z//;

    my $ha1_initial = _hash_hex($base_algorithm,
        $u_bytes . ':' . $realm_bytes . ':' . $p_bytes);

    my $ha1 = $ha1_initial;
    if ($is_session) {
        $ha1 = _hash_hex($base_algorithm,
            $ha1_initial . ':' . $nonce . ':' . $cnonce);
    }

    my $a2 = $args{method} . ':' . $args{request_target};
    if (defined $qop && $qop eq 'auth-int') {
        my $entity_hash = _hash_hex($base_algorithm, $args{entity_body});
        $a2 .= ':' . $entity_hash;
    }
    my $ha2 = _hash_hex($base_algorithm, $a2);

    my $response;
    if (defined $qop) {
        $response = _hash_hex($base_algorithm,
            join(':', $ha1, $nonce, $nc, $cnonce, $qop, $ha2));
    }
    else {
        $response = _hash_hex($base_algorithm,
            join(':', $ha1, $nonce, $ha2));
    }

    my @fields;
    my $userhash = exists($params->{userhash})
        && lc($params->{userhash}) eq 'true';

    if ($userhash) {
        my $hashed_username = _hash_hex($base_algorithm,
            $u_bytes . ':' . $realm_bytes);
        push @fields, 'username=' . _quote($hashed_username);
    }
    elsif (defined($charset) && $username =~ /[^\x00-\x7f]/) {
        push @fields, "username*=UTF-8''" . _pct_encode($u_bytes);
    }
    else {
        push @fields, 'username=' . _quote($username);
    }

    push @fields,
        'realm=' . _quote($params->{realm}),
        'uri=' . _quote($args{request_target}),
        'algorithm=' . _algorithm_wire_name($algorithm),
        'nonce=' . _quote($nonce);

    if (defined $qop) {
        push @fields,
            'nc=' . $nc,
            'cnonce=' . _quote($cnonce),
            'qop=' . $qop;
    }
    elsif ($is_session) {
        push @fields, 'cnonce=' . _quote($cnonce);
    }

    push @fields, 'response=' . _quote($response);
    push @fields, 'opaque=' . _quote($params->{opaque})
        if exists $params->{opaque};
    push @fields, 'userhash=' . ($userhash ? 'true' : 'false')
        if exists $params->{userhash};

    return 'Digest ' . join(', ', @fields);
}

sub _nonce_values {
    my ($self, $nonce, $increment) = @_;

    my $state = $self->{nonce_state}{$nonce};
    unless ($state) {
        $state = $self->{nonce_state}{$nonce} = {
            count  => 0,
            cnonce => $self->_new_cnonce,
        };
    }

    if ($increment) {
        $state->{count}++;
        croak "Digest nonce count overflow"
            if $state->{count} > 0xffffffff;
    }

    return (sprintf('%08x', $state->{count}), $state->{cnonce});
}

sub _new_cnonce {
    my ($self) = @_;
    my $bytes;
    if ($self->{_random_bytes}) {
        $bytes = $self->{_random_bytes}->(24);
    }
    else {
        require Crypt::SysRandom;
        $bytes = Crypt::SysRandom::random_bytes(24);
    }
    croak "secure random source did not return 24 bytes"
        unless defined($bytes) && length($bytes) == 24;
    return unpack('H*', $bytes);
}

sub _qop_values {
    my ($text) = @_;
    return map {
        my $q = $_;
        $q =~ s/\A[ \t]+//;
        $q =~ s/[ \t]+\z//;
        lc $q;
    } split /,/, $text;
}

sub _hash_hex {
    my ($algorithm, $data) = @_;
    if ($algorithm eq 'md5') {
        return Digest::MD5::md5_hex($data);
    }
    if ($algorithm eq 'sha-256') {
        return Digest::SHA::sha256_hex($data);
    }
    if ($algorithm eq 'sha-512-256') {
        return Digest::SHA->new(512256)->add($data)->hexdigest;
    }
    croak "unsupported Digest algorithm '$algorithm'";
}

sub _algorithm_wire_name {
    my ($algorithm) = @_;
    my %wire = (
        'md5'              => 'MD5',
        'md5-sess'         => 'MD5-sess',
        'sha-256'          => 'SHA-256',
        'sha-256-sess'     => 'SHA-256-sess',
        'sha-512-256'      => 'SHA-512-256',
        'sha-512-256-sess' => 'SHA-512-256-sess',
    );
    return $wire{$algorithm};
}

sub _quote {
    my ($value) = @_;
    croak "Digest quoted value contains a newline" if $value =~ /[\r\n]/;
    $value =~ s/([\\"])/\\$1/g;
    return '"' . $value . '"';
}

sub _pct_encode {
    my ($bytes) = @_;
    my $out = '';
    for my $byte (unpack('C*', $bytes)) {
        my $ch = chr($byte);
        if ($ch =~ /[A-Za-z0-9!#$&+\-.^_`|~]/) {
            $out .= $ch;
        }
        else {
            $out .= sprintf('%%%02X', $byte);
        }
    }
    return $out;
}

1;

__END__

=head1 NAME

Uniform::HTTP::Auth::Digest - HTTP Digest authentication calculations and state

=cut
