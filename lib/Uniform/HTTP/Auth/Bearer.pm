package Uniform::HTTP::Auth::Bearer;

use strict;
use warnings;
use Carp qw(croak);

our $VERSION = '0.01';

sub validate_challenge {
    my ($class, $challenge) = @_;
    return 'Bearer challenge must not contain token68 credentials'
        if defined $challenge->{token68};
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
    croak "Bearer authorization requires 'token'"
        unless exists($args{token}) && defined($args{token});
    croak "Bearer token must be a plain scalar" if ref $args{token};
    croak "malformed Bearer token"
        unless $args{token} =~ /\A[A-Za-z0-9\-._~+\/]+={0,}\z/;

    return 'Bearer ' . $args{token};
}

1;

__END__

=head1 NAME

Uniform::HTTP::Auth::Bearer - HTTP Bearer authentication construction

=cut
