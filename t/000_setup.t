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
    my $homedir = $gnupg->options->homedir();
    make_path($homedir, { mode => 0700 });
    my $agentconf = IO::File->new( "> " . $homedir . "/gpg-agent.conf" );
    $agentconf->write("pinentry-program " . getcwd() . "/test/fake-pinentry.pl\n");
    $agentconf->close();
    copy('test/gpg.conf', $homedir . '/gpg.conf');
    # reset the state of any long-lived gpg-agent, ignoring errors:
    system('gpgconf', '--homedir', $homedir, '--quiet', '--kill', 'gpg-agent');

    reset_handles();

    my $pid = $gnupg->import_keys(command_args => [ 'test/public_keys.pgp', 'test/secret_keys.pgp', 'test/new_secret.pgp' ],
                                  options => [ 'batch'],
                                  handles => $handles);
    waitpid $pid, 0;

    return $CHILD_ERROR == 0;
};
