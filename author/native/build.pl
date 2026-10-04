use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../../lib";
use Uniform::HTTP::FastPath;
use ExtUtils::CBuilder;
use ExtUtils::ParseXS;
use File::Path qw(make_path);
use File::Spec;
use Config;

# Explicit author tool. Normal installation and make test never run this.
my $build = File::Spec->rel2abs("$FindBin::Bin/../_build/native-$Config{version}");
my $auto = "$build/auto/Uniform/HTTP/NativeTest";
make_path($auto, "$build/Uniform/HTTP");
my $c = "$build/NativeTest.c";
ExtUtils::ParseXS::process_file(
    filename => "$FindBin::Bin/NativeTest.xs", output => $c,
    prototypes => 0,
);
my $cb = ExtUtils::CBuilder->new(quiet => 0);
my $object = $cb->compile(
    source => $c, include_dirs => [ Uniform::HTTP::FastPath::native_include_dir() ],
    ($ENV{UHTTP_CFLAGS} ? (extra_compiler_flags => $ENV{UHTTP_CFLAGS}) : ()),
);
$cb->link(objects => $object, module_name => 'Uniform::HTTP::NativeTest',
    lib_file => "$auto/NativeTest.$Config{dlext}");
open my $pm, '>', "$build/Uniform/HTTP/NativeTest.pm" or die $!;
print {$pm} <<'MODULE';
package Uniform::HTTP::NativeTest;
use strict;
use warnings;
use XSLoader;
XSLoader::load(__PACKAGE__);
1;
MODULE
close $pm or die $!;
print "Native fixture: $build\n";
