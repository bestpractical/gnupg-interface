#!/usr/bin/perl -w
#
#  $Id: wrap_call.t,v 1.1 2001/05/03 07:32:34 ftobin Exp $
#

use strict;

use lib './t';
use MyTest;
use MyTestSpecific;

TEST
{
    my $gpg = GnuPG::Interface->new(call => './test/fake-gpg-v1');
    return ($gpg->version() eq '1.4.23');
};


TEST
{
    my $gpg = GnuPG::Interface->new(call => './test/fake-gpg-v2');
    return ($gpg->version() eq '2.2.12');
};

TEST
{
    my $gpg = GnuPG::Interface->new(call => './test/fake-gpg-v1');
    my $v1 = $gpg->version();
    $gpg->call('./test/fake-gpg-v2');
    my $v2 = $gpg->version();

    return ($v1 eq '1.4.23' && $v2 eq '2.2.12');
}
