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
    my $homedir = $gnupg->options->homedir();
    my $err = [];
    # In classic gpg, gpgconf cannot kill gpg-agent. But these tests
    # will not start an agent when using classic gpg. For modern gpg,
    # kill off any long-lived gpg-agent, ignoring errors:
    system('gpgconf', '--homedir', $homedir, '--quiet', '--kill', 'gpg-agent') if $gnupg->cmp_version($gnupg->version, '2.1') >=0;
    remove_tree($homedir, {error => \$err});
    unlink('test/gnupghome');
    return ! @$err;
};
