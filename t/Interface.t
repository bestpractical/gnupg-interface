#!/usr/bin/perl -w
#
# $Id: Interface.t,v 1.1 2001/04/30 02:04:25 ftobin Exp $
#

use strict;

use lib './t';
use MyTest;

use GnuPG::Interface;

my $v1 = './test/fake-gpg-v1';
my $v2 = './test/fake-gpg-v2';

my $gnupg = GnuPG::Interface->new( call => $v1 );

# deprecation test
TEST
{
    $gnupg->gnupg_call() eq $v1;
};

# deprecation test
TEST
{
    # We wrap the next call in an "eval" because
    # setting call tries to execute the program
    # to figure out the version, which will
    # fail if "gnupg" is not found... but we
    # don't care about the version for the
    # purpose of this test.
    eval { $gnupg->gnupg_call( $v2 ); };
    $gnupg->call() eq $v2;
};
