package Uniform::HTTP::Auth::Basic;

use strict;
use warnings;
use Carp qw(croak);
use Encode qw(encode);
use MIME::Base64 qw(encode_base64);
use Unicode::Normalize qw(NFC);

our $VERSION = '0.01';

sub validate_challenge {
    my ($class, $challenge) = @_;
    return 'Basic challenge must use authentication parameters'
        if defined $challenge->{token68};
    return 'Basic challenge requires realm'
        unless exists $challenge->{params}{realm};

    if (exists $challenge->{params}{charset}
        && lc($challenge->{params}{charset}) ne 'utf-8') {
        return 'Basic charset must be UTF-8';
    }

    return;
}

sub select_challenge {
    my ($class, $challenges) = @_;
    for my $challenge (@$challenges) {
        next if $challenge->{malformed};
        next if defined $class->validate_challenge($challenge);
        return $challenge;
    }
    return;
}

sub authorization {
    my ($class, %args) = @_;

    for my $field (qw(username password challenge)) {
        croak "Basic authorization requires '$field'"
            unless exists $args{$field} && defined $args{$field};
    }
    croak "username must be a plain scalar" if ref $args{username};
    croak "password must be a plain scalar" if ref $args{password};
    croak "challenge must be a hash reference"
        unless ref($args{challenge}) eq 'HASH';

    my $error = $class->validate_challenge($args{challenge});
    croak $error if defined $error;

    croak "Basic username must not contain ':'"
        if $args{username} =~ /:/;
    croak "Basic username contains an HTTP control character"
        if $args{username} =~ /[\x00-\x1f\x7f]/;
    croak "Basic password contains an HTTP control character"
        if $args{password} =~ /[\x00-\x1f\x7f]/;

    my ($username, $password) = @args{qw(username password)};
    my $charset = $args{challenge}{params}{charset};
    my $bytes;

    if (defined $charset) {
        $username = NFC($username);
        $password = NFC($password);
        $bytes = encode('UTF-8', $username . ':' . $password, Encode::FB_CROAK());
    }
    else {
        croak 'non-ASCII Basic credentials require a charset="UTF-8" challenge'
            if $username =~ /[^\x00-\x7f]/ || $password =~ /[^\x00-\x7f]/;
        $bytes = $username . ':' . $password;
    }

    return 'Basic ' . encode_base64($bytes, '');
}

1;

__END__

=head1 NAME

Uniform::HTTP::Auth::Basic - HTTP Basic authentication calculations

=cut
