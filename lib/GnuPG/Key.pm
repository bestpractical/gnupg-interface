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
        creation_date
        expiration_date
        creation_date_string
        expiration_date_string
        fingerprint
        usage_flags
        )
    ] => (
    isa => 'Any',
    is  => 'rw',
    );

has signatures => (
    isa       => 'ArrayRef',
    is        => 'rw',
    default   => sub { [] },
);

sub push_signatures {
    my $self = shift;
    push @{ $self->signatures }, @_;
}

has revocations => (
    isa       => 'ArrayRef',
    is        => 'rw',
    default   => sub { [] },
);

sub push_revocations {
    my $self = shift;
    push @{ $self->revocations }, @_;
}

has revokers => (
    isa       => 'ArrayRef',
    is        => 'rw',
    default   => sub { [] },
);

sub push_revokers {
    my $self = shift;
    push @{ $self->revokers }, @_;
}

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

=item usage flags

The Key Usage flags associated with this key, represented as a string
of lower-case letters.  Possible values include: (a) authenticate, (c)
certify, (e) encrypt, and (s) sign.

A key may have any combination of them in any order.  In addition to
these letters, the primary key has uppercase versions of the letters
to denote the _usable_ capabilities of the entire key, and a potential
letter 'D' to indicate a disabled key.

See "key capabilities" DETAILS from the GnuPG sources for more
details.

=item hex_data

The data of the key.

=item hex_id

The long hex id of the key.  This is not the fingerprint nor
the short hex id, which is 8 hex characters.

=item creation_date_string

=item expiration_date_string

Formatted date of the key's creation and expiration.  If the key has
no expiration, expiration_date_string will return undef.

=item creation_date

=item expiration_date

Date of the key's creation and expiration, stored as the number of
seconds since midnight 1970-01-01 UTC.  If the key has no expiration,
expiration_date will return undef.

=item fingerprint

A GnuPG::Fingerprint object.

=item signatures

A list of GnuPG::Signature objects embodying the signatures on this
key.  For subkeys, the signatures are usually subkey-binding
signatures.  For primary keys, the signatures are statements about the
key itself.

=item revocations

A list of revocations associated with this key, stored as
GnuPG::Signature objects (since revocations are a type of
certification as well).  Note that a revocation of a primary key has a
different semantic meaning than a revocation associated with a subkey.

=item revokers

A list of GnuPG::Revoker objects associated with this key, indicating
other keys which are allowed to revoke certifications made by this
key.

=back

=head1 SEE ALSO

L<GnuPG::Fingerprint>,
L<GnuPG::Signature>,
L<GnuPG::Revoker>,

=cut
