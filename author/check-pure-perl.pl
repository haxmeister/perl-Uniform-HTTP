use strict;
use warnings;
use FindBin;
use File::Copy qw(copy);
use File::Path qw(make_path);
use File::Basename qw(dirname);
use File::Spec;
use File::Temp qw(tempdir);
use Cwd qw(abs_path);
use Config;

# Rebuild only the files shipped in MANIFEST, without an available compiler.
my $root = abs_path("$FindBin::Bin/..");
make_path("$root/author/_build");
my $tmp = tempdir('pure-perl-XXXXXX', DIR => "$root/author/_build", CLEANUP => 1);
my $source = "$tmp/source";
my $installed = "$tmp/installed";
make_path($source);
open my $manifest, '<', "$root/MANIFEST" or die $!;
while (my $file = <$manifest>) {
    chomp $file;
    $file =~ s/\s+.*//;
    next unless length $file;
    die "native build source shipped: $file\n" if $file =~ /\.(?:xs|c|o|so|dll)\z/;
    make_path(dirname("$source/$file"));
    copy("$root/$file", "$source/$file") or die "copy $file: $!";
}
close $manifest;
my $trap = "$tmp/compiler-must-not-run.pl";
open my $fh, '>', $trap or die $!;
print {$fh} "die qq(Uniform installation attempted to run a compiler or linker\\n);\n";
close $fh;
# Make dependency paths independent of the temporary working directory.
$ENV{PERL5LIB} = join $Config{path_sep}, map { abs_path($_) || $_ }
    grep { !ref($_) && -d $_ } @INC;
chdir $source or die $!;
sub run { system(@_) == 0 or die "command failed: @_\n" }
run($^X, 'Makefile.PL', "CC=$^X $trap", "LD=$^X $trap", "INSTALL_BASE=$installed");
run($Config{make}, 'test');
run($Config{make}, 'install');
my $lib = "$installed/lib/perl5";
run($^X, "-I$lib", '-MUniform::HTTP::FastPath', '-e',
    'die "header missing" unless -f Uniform::HTTP::FastPath::native_include_dir() . "/uniform_http_fastpath.h"; '
    . 'my $r = Uniform::HTTP::Request->new(method => "GET", target => "/"); '
    . 'die "request failed" unless $r->target eq "/"; '
    . 'die "XS loaded" if exists $INC{"Uniform/HTTP/NativeTest.pm"}; '
    . 'print "Installed pure-Perl object and native header verified\\n";');
chdir $root or die $!;
print "Compiler-free configure, test, and install passed.\n";
