#!/usr/bin/perl -w

use strict;
use English qw( -no_match_vars );

use lib './t';
use MyTest;
use MyTestSpecific;
use Cwd;
use File::Path qw (make_path);
use File::Copy;

# $gnupg->options->debug_level(4);
# $gnupg->options->logger_file("/tmp/gnupg-$$-setup-".time().".log");

TEST
{
    my $homedir = $gnupg->options->homedir();
    make_path($homedir, { mode => 0700 });

    if ($gnupg->cmp_version($gnupg->version, '2.2') >= 0 and $ENV{TEST_USE_GPG_AGENT}) {
        my $agentconf = IO::File->new( "> " . $homedir . "/gpg-agent.conf" );
        # Classic gpg can't use loopback pinentry programs like fake-pinentry.pl.
        $agentconf->write(
            "allow-preset-passphrase\n".
                "allow-loopback-pinentry\n".
                "pinentry-program " . getcwd() . "/test/fake-pinentry.pl\n"
            );
        $agentconf->close();
        copy('test/gpg.conf', $homedir . '/gpg.conf');

        # In classic gpg, gpgconf cannot kill gpg-agent. But these tests
        # will not start an agent when using classic gpg. For modern gpg,
        # reset the state of any long-lived gpg-agent, ignoring errors:
	$ENV{'GNUPGHOME'} = $homedir;
	my $error = system('gpgconf', '--quiet', '--kill', 'gpg-agent', ' > /tmp/gpgconf.log  2> /tmp/gpgconf.error_log');
        if ($error) {
            warn "gpgconf returned error : $error";
        }
        $error = system('gpg-connect-agent', 'reloadagent', '/bye');
        if ($error) {
            warn "gpg-connect-agent returned error : $error";
        }

	delete $ENV{'GNUPGHOME'};
    }
    reset_handles();

    my $pid = $gnupg->import_keys(command_args => [ 'test/public_keys.pgp', 'test/secret_keys.pgp', 'test/new_secret.pgp' ],
                                  options => [ 'batch'],
                                  handles => $handles);
    waitpid $pid, 0;

    return $CHILD_ERROR == 0;
};
