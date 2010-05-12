#!/usr/bin/perl -w
#
# $Id: get_public_keys.t,v 1.9 2001/05/03 06:00:06 ftobin Exp $
#

use strict;
use English qw( -no_match_vars );

use lib './t';
use MyTest;
use MyTestSpecific;

use GnuPG::PrimaryKey;
use GnuPG::SubKey;

my ( $given_key, $handmade_key );

TEST
{
    reset_handles();
    
    my @returned_keys = $gnupg->get_public_keys_with_sigs( '0xF950DA9C' );
    
    return 0 unless @returned_keys == 1;
    
    $given_key = shift @returned_keys;
    
    $handmade_key = GnuPG::PrimaryKey->new
      ( length                 => 1024,
	algo_num               => 17,
	hex_id                 => '53AE596EF950DA9C',
        creation_date          => 949813093,
	creation_date_string   => '2000-02-06',
	owner_trust            => '-',
        usage_flags            => 'scaESCA',
      );
    
    $handmade_key->fingerprint
      ( GnuPG::Fingerprint->new( as_hex_string =>
				 '93AFC4B1B0288A104996B44253AE596EF950DA9C',
			       )
      );
    

    my $uid0 = GnuPG::UserId->new( as_string =>  'GnuPG test key (for testing purposes only)',
                                   validity => '-');
    $uid0->push_signatures(
      GnuPG::Signature->new(
                            date => 1177086597,
                            algo_num => 17,
                            is_exportable => 1,
                            user_id_string => 'GnuPG test key (for testing purposes only)',
                            date_string => '2007-04-20',
                            hex_id => '53AE596EF950DA9C',
                            sig_class => 0x13,
                            validity => '!'),
      GnuPG::Signature->new(
                            date => 953180097,
                            algo_num => 17,
                            is_exportable => 1,
                            user_id_string => 'Frank J. Tobin <ftobin@neverending.org>',
                            date_string => '2000-03-16',
                            hex_id => '56FFD10A260C4FA3',
                            sig_class => 0x10,
                            validity => '!'),
      GnuPG::Signature->new(
                            date => 949813093,
                            algo_num => 17,
                            is_exportable => 1,
                            user_id_string => 'GnuPG test key (for testing purposes only)',
                            date_string => '2000-02-06',
                            hex_id => '53AE596EF950DA9C',
                            sig_class => 0x13,
                            validity => '!'));

    my $uid1 = GnuPG::UserId->new( as_string =>  'Foo Bar (1)',
                                   validity => '-');
    $uid1->push_signatures(
      GnuPG::Signature->new(
                            date => 1177086330,
                            algo_num => 17,
                            is_exportable => 1,
                            user_id_string => 'GnuPG test key (for testing purposes only)',
                            date_string => '2007-04-20',
                            hex_id => '53AE596EF950DA9C',
                            sig_class => 0x13,
                            validity => '!'),
      GnuPG::Signature->new(
                            date => 953180103,
                            algo_num => 17,
                            is_exportable => 1,
                            user_id_string => 'Frank J. Tobin <ftobin@neverending.org>',
                            date_string => '2000-03-16',
                            hex_id => '56FFD10A260C4FA3',
                            sig_class => 0x10,
                            validity => '!'),
      GnuPG::Signature->new(
                            date => 953179891,
                            algo_num => 17,
                            is_exportable => 1,
                            user_id_string => 'GnuPG test key (for testing purposes only)',
                            date_string => '2000-03-16',
                            hex_id => '53AE596EF950DA9C',
                            sig_class => 0x13,
                            validity => '!'));



    $handmade_key->push_user_ids($uid0, $uid1);

    my $subkey_signature = GnuPG::Signature->new
      ( validity       => '!',
        algo_num       => 17,
	hex_id         => '53AE596EF950DA9C',
        date           => 1177086380,
	date_string    => '2007-04-20',
        user_id_string => 'GnuPG test key (for testing purposes only)',
        sig_class      => 0x18,
        is_exportable  => 1,
      );
    
    my $uid2_signature = GnuPG::Signature->new
      ( validity       => '!',
        algo_num       => 17,
        hex_id         => '53AE596EF950DA9C',
        date           => 953179891,
        date_string    => '2000-03-16',
      );
    
    my $ftobin_signature = GnuPG::Signature->new
      ( validity       => '!',
        algo_num       => 17,
	hex_id         => '56FFD10A260C4FA3',
        date           => 953180097,
	date_string    => '2000-03-16',
	);
    
    my $designated_revoker_sig = GnuPG::Signature->new
      ( validity       => '!',
        algo_num       => 17,
	hex_id         => '53AE596EF950DA9C',
        date           => 978325209,
	date_string    => '2001-01-01',
        sig_class      => 0x1f,
        is_exportable  => 1
	);

    my $revoker = GnuPG::Revoker->new
      ( algo_num       => 17,
        class          => 0x80,
	fingerprint    => GnuPG::Fingerprint->new( as_hex_string =>
                                                   '4F863BBBA8166F0A340F600356FFD10A260C4FA3'),
	);
    $revoker->push_signatures($designated_revoker_sig);
    
    my $subkey = GnuPG::SubKey->new
      ( validity                 => 'u',
	length                   => 768,
	algo_num                 => 16,
	hex_id                   => 'ADB99D9C2E854A6B',
        creation_date            => 949813119,
	creation_date_string     => '2000-02-06',
        usage_flags              => 'e',
      );
    
    $subkey->fingerprint
      ( GnuPG::Fingerprint->new( as_hex_string =>
				 '7466B7E98C4CCB64C2CE738BADB99D9C2E854A6B'
			       )
      );
    
    $subkey->push_signatures( $subkey_signature );
    
    $handmade_key->push_subkeys( $subkey );
    $handmade_key->push_revokers( $revoker );
    
    $handmade_key->compare( $given_key );
};

TEST
{
    my $subkey1 = $given_key->subkeys()->[0];
    my $subkey2 = $handmade_key->subkeys()->[0];
    
    bless $subkey1, 'GnuPG::SubKey';

    my $equal = $subkey1->compare( $subkey2 );
    
    warn 'subkeys fail comparison; this is a known issue with GnuPG 1.0.1'
      if not $equal;
    
    return $equal;
};


TEST
{  
    $handmade_key->compare( $given_key, 1 );
};
