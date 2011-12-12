use strict;
use warnings;
use inc::Module::Install;

print "which gpg ... ";
system("which", "gpg");
die "gpg (GnuPG) not found" if ( $? != 0 );

my $output = `gpg --version`;
die "Can't determine gpg version"
    unless $output =~ /^gpg \(GnuPG\) (\d+\.\d+)/;
die "gpg (GnuPG) 1.4 or later is required" unless $1 >= 1.4;


author 'Frank J. Tobin';
abstract 'supply object methods for interacting with GnuPG';
name 'GnuPG-Interface';
version_from 'lib/GnuPG/Interface.pm';
requires 'Any::Moose' => '0.04';
requires 'Math::BigInt' => '1.78';
license 'perl';


sign();
WriteAll();
