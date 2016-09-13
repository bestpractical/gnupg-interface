#!/usr/bin/perl -w

use strict;
use English qw( -no_match_vars );

use lib './t';
use MyTest;
use MyTestSpecific;
use File::Path qw (remove_tree);

# this is actually no test, just cleanup.
TEST
{
    my $err = [];
    remove_tree('test/gnupghome', {error => \$err});
    return ! @$err;
};
