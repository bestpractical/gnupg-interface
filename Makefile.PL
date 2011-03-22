use strict;
use warnings;
use inc::Module::Install;

for my $gpg qw(gpg gpg2) {
    my $gpg_find = "which $gpg";
    print "$gpg_find ... ";
    system($gpg_find);
    if ( $? != 0 ) {
        die "gpg (GnuPG) not found";
    } else { last }
}


author 'Frank J. Tobin';
abstract 'supply object methods for interacting with GnuPG';
name 'GnuPG-Interface';
version_from 'lib/GnuPG/Interface.pm';
requires 'Any::Moose' => '0.04';
requires 'Math::BigInt' => '1.78';
license 'perl';


sign();
WriteAll();
