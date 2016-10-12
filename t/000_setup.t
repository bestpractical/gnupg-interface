#!/usr/bin/perl -w

use strict;
use English qw( -no_match_vars );

use lib './t';
use MyTest;
use MyTestSpecific;
use Cwd;
use File::Path qw (make_path);
use File::Copy;

TEST
{
    make_path('test/gnupghome', { mode => 0700 });
    my $agentconf = IO::File->new( "> test/gnupghome/gpg-agent.conf" );
    $agentconf->write("pinentry-program " . getcwd() . "/test/fake-pinentry.pl\n");
    $agentconf->close();
    copy('test/gpg.conf', 'test/gnupghome/gpg.conf');
    reset_handles();

    my $pid = $gnupg->import_keys(command_args => [ 'test/public_keys.pgp', 'test/secret_keys.pgp', 'test/new_secret.pgp' ],
                                  options => [ 'batch'],
                                  handles => $handles);
    waitpid $pid, 0;

    return $CHILD_ERROR == 0;
};
