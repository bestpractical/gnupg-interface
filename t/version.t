use strict;

use lib './t';
use MyTest;
use MyTestSpecific;

TEST
{
    reset_handles();

    my $version = $gnupg->version;

    return $gnupg->version =~ /^[\d.]+$/;
};
