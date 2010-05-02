#  Signature.pm
#    - providing an object-oriented approach to GnuPG key signatures
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
#  $Id: Signature.pm,v 1.4 2001/08/21 13:31:50 ftobin Exp $
#

package GnuPG::Signature;
use Any::Moose;

has [qw( validity
         algo_num
         hex_id
         user_id_string
         date
         date_string
         expiration_date
         expiration_date_string )] => (
    isa => 'Any',
    is  => 'rw',
);

sub is_valid {
    my $self = shift;
    return $self->validity eq '!';
}

__PACKAGE__->meta->make_immutable;

1;

__END__

=head1 NAME

GnuPG::Signature - GnuPG Key Signature Objects

=head1 SYNOPSIS

  # assumes a GnuPG::SubKey object in $key
  my $signing_id = $key->signature->hex_id();

=head1 DESCRIPTION

GnuPG::Signature objects are generally not instantiated
on their own, but rather as part of GnuPG::Key objects.
They embody various aspects of a GnuPG signature on a key.

=head1 OBJECT METHODS

=over 4

=item new( I<%initialization_args> )

This methods creates a new object.  The optional arguments are
initialization of data members.

=item is_valid()

Returns 1 if GnuPG was able to cryptographically verify the signature,
otherwise 0.

=back

=head1 OBJECT DATA MEMBERS

=over 4

=item validity

A character indicating the cryptographic validity of the key.  GnuPG
uses at least the following characters: "!" means valid, "-" means not
valid, "?" means unknown (e.g. if the supposed signing key is not
present in the local keyring), and "%" means an error occurred (e.g. a
non-supported algorithm).  See the documentation for --check-sigs in
gpg(1).

=item algo_num

The number of the algorithm used for the signature.

=item hex_id

The hex id of the signing key.

=item user_id_string

The first user id string on the key that made the signature.
This may not be defined if the signing key is not on the local keyring.

=item date_string

The formatted date the signature was performed on.

=item date

The date the signature was performed, represented as the number of
seconds since midnight 1970-01-01 UTC.

=item expiration_date_string

The formatted date the signature will expire (signatures without
expiration return undef).

=item expiration_date

The date the signature will expire, represented as the number of
seconds since midnight 1970-01-01 UTC (signatures without expiration
return undef)

=back

=head1 SEE ALSO


=cut
