#!/usr/bin/perl -w
#
# $Id: verify.t,v 1.4 2001/05/03 06:00:06 ftobin Exp $
#

use strict;
use English qw( -no_match_vars );

use lib './t';
use MyTest;
use MyTestSpecific;

TEST
{
    reset_handles();
    
    my $pid = $gnupg->verify( handles => $handles );
    
    print $stdin @{ $texts{signed}->data() };
    close $stdin;
    waitpid $pid, 0;
    
    return $CHILD_ERROR == 0;
};


TEST
{
    reset_handles();
    
    $handles->stdin( $texts{signed}->fh() );
    $handles->options( 'stdin' )->{direct} = 1;
    
    my $pid = $gnupg->verify( handles => $handles );
    
    waitpid $pid, 0;
    
    return $CHILD_ERROR == 0;
};
