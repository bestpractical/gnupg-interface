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
    # kill off any long-lived gpg-agent, ignoring errors:
    system('gpgconf', '--homedir=test/gnupghome', '--quiet', '--kill', 'gpg-agent');
    remove_tree('test/gnupghome', {error => \$err});
    return ! @$err;
};
