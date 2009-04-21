#  Key.pm
#    - providing an object-oriented approach to GnuPG keys
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
#  $Id: Key.pm,v 1.10 2001/12/10 01:29:27 ftobin Exp $
#

package GnuPG::Key;
use Any::Moose;
with qw(GnuPG::HashInit);

has [
    qw( length
        algo_num
        hex_id
        hex_data
        creation_date_string
        expiration_date_string
        fingerprint
        )
    ] => (
    isa => 'Any',
    is  => 'rw',
    );

sub short_hex_id {
    my ($self) = @_;
    return substr $self->hex_id(), -8;
}

__PACKAGE__->meta->make_immutable;

1;

__END__

=head1 NAME

GnuPG::Key - GnuPG Key Object

=head1 SYNOPSIS

  # assumes a GnuPG::Interface object in $gnupg
  my @keys = $gnupg->get_public_keys( 'ftobin' );

  # now GnuPG::PublicKey objects are in @keys

=head1 DESCRIPTION

GnuPG::Key objects are generally not instantiated on their
own, but rather used as a superclass of GnuPG::PublicKey,
GnuPG::SecretKey, or GnuPG::SubKey objects.

=head1 OBJECT METHODS

=head2 Initialization Methods

=over 4

=item new( I<%initialization_args> )

This methods creates a new object.  The optional arguments are
initialization of data members.

=item hash_init( I<%args> ).


=item short_hex_id

This returns the commonly-used short, 8 character short hex id
of the key.

=back

=head1 OBJECT DATA MEMBERS

=over 4

=item length

Number of bits in the key.

=item algo_num

They algorithm number that the Key is used for.

=item hex_data

The data of the key.

=item hex_id

The long hex id of the key.  This is not the fingerprint nor
the short hex id, which is 8 hex characters.

=item creation_date_string
=item expiration_date_string

Formatted date of the key's creation and expiration.

=item fingerprint

A GnuPG::Fingerprint object.

=back

=head1 SEE ALSO

L<GnuPG::Fingerprint>,

=cut
