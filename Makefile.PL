use strict;
use warnings;

use ExtUtils::MakeMaker;

my $gpg_find = 'which gpg';
print "$gpg_find ... ";
system($gpg_find);
if ($? != 0) {
    die "gpg (GnuPG) not found";
}

WriteMakefile
  ( AUTHOR       => 'Frank J. Tobin',
    ABSTRACT     => 'supply object methods for interacting with GnuPG',
    NAME         => 'GnuPG::Interface',
    VERSION_FROM => 'lib/GnuPG/Interface.pm',
    PREREQ_PM    => {
		     'Moose' => 0.61,
		     'MooseX::AttributeHelpers' => 0.14,
		    },
    clean        => { FILES => "test/*-keys*/*.out test/random_seed test/trustdb.gpg test/temp" }
  );

