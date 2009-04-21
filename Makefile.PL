use strict;
use warnings;
use inc::Module::Install;

my $gpg_find = 'which gpg';
print "$gpg_find ... ";
system($gpg_find);
if ( $? != 0 ) {
    die "gpg (GnuPG) not found";
}

author 'Frank J. Tobin';
abstract 'supply object methods for interacting with GnuPG';
name 'GnuPG-Interface';
version_from 'lib/GnuPG/Interface.pm';
requires 'Any::Moose' => '0.04';
license 'perl';


sign();
WriteAll();
