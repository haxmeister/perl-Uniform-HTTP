use strict;
use warnings;
use ExtUtils::MakeMaker;

WriteMakefile(
    NAME         => 'Uniform::HTTP::Auth',
    VERSION_FROM => 'lib/Uniform/HTTP/Auth.pm',
    ABSTRACT     => 'Framework-agnostic HTTP authentication for Perl',
    AUTHOR       => 'Joshua S. Day <HAX@cpan.org>',
    LICENSE      => 'artistic_2',
    MIN_PERL_VERSION => '5.016',
    PREREQ_PM => {
        'Carp'               => 0,
        'Crypt::SysRandom'   => '0.006',
        'Digest::MD5'        => 0,
        'Digest::SHA'        => 0,
        'Encode'             => 0,
        'MIME::Base64'       => 0,
        'Unicode::Normalize' => 0,
    },
    TEST_REQUIRES => {
        'Test::More' => 0,
    },
    META_MERGE => {
        'meta-spec' => { version => 2 },
        resources => {
            repository => {
                type => 'git',
                url  => 'https://github.com/haxmeister/perl-Uniform-HTTP-Auth.git',
                web  => 'https://github.com/haxmeister/perl-Uniform-HTTP-Auth',
            },
            bugtracker => {
                web => 'https://github.com/haxmeister/perl-Uniform-HTTP-Auth/issues',
            },
        },
    },
);
