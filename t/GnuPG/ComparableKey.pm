#  ComparableKey.pm
#    - comparable GnuPG::Key
#
#  Copyright (C) 2000 Frank J. Tobin <ftobin@cpan.org>
#
#  This module is free software; you can redistribute it and/or modify it
#  under the same terms as Perl itself.
#
#  This program is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
#
#  $Id: ComparableKey.pm,v 1.4 2001/09/14 12:34:36 ftobin Exp $
#

package GnuPG::ComparableKey;

use strict;
use GnuPG::Fingerprint;

use base qw( GnuPG::Key );

sub compare
{
    my ( $self, $other, $deep ) = @_;
    
    # expiration_date_string and expiration_date was taken out of the
    # following list because there is a bug in the listing of
    # expiration dates in 1.0.5
    my @comparison_fields
      = qw( length algo_num hex_id creation_date
	    creation_date_string usage_flags
	  );
    
    foreach my $field ( @comparison_fields )
    {
	# don't test for definedness because
	# all fields should be defined
	return 0 unless $self->$field() eq $other->$field();
    }
    
    return $self->_deeply_compare( $other ) if $deep;
    
    return 1;
}


sub _deeply_compare
{
    my ( $self, $other ) = @_;
    my $i;

    for ( $i = 0; $i < scalar(@{$self->signatures}); $i++ ) {
      return 0
        unless $self->signatures->[$i]->compare($other->signatures->[$i], 1);
    }

    for ( $i = 0; $i < scalar(@{$self->revocations}); $i++ ) {
      return 0
        unless $self->revocations->[$i]->compare($other->revocations->[$i], 1);
    }

    for ( $i = 0; $i < scalar(@{$self->revokers}); $i++ ) {
      return 0
        unless $self->revokers->[$i]->compare($other->revokers->[$i], 1);
    }

    bless $self->fingerprint(), 'GnuPG::Fingerprint';
    return ( $self->fingerprint->compare( $other->fingerprint() ) );
}


1;
