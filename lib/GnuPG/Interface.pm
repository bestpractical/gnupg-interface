#  Interface.pm
#    - providing an object-oriented approach to interacting with GnuPG
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

package GnuPG::Interface;
use Moo;
use MooX::late;
with qw(GnuPG::HashInit);

use English qw( -no_match_vars );
use Carp;
use Fcntl;
use vars qw( $VERSION );
use Fatal qw( open close pipe fcntl );
use Class::Struct;
use IO::Handle;

use Math::BigInt try => 'GMP';
use GnuPG::Options;
use GnuPG::Handles;
use Scalar::Util 'tainted';

$VERSION = '1.04';

has passphrase => (
    isa     => 'Any',
    is      => 'rw',
    clearer => 'clear_passphrase',
);

has call => (
    isa     => 'Any',
    is      => 'rw',
    trigger => 1,
    clearer => 'clear_call',
);

# NB: GnuPG versions
#
# There are now three supported versions of GnuPG: legacy 1.4, 2.2, and 2.4.
# They are detected and each behave slightly differently.
#
# When using features specific to branches, check that the system's
# version of gpg corresponds to the branch.
#
# legacy: 1.4
# stable: >= 2.2
#
# You can find examples of version comparison in the tests.
has version => (
    isa      => 'Str',
    is       => 'ro',
    reader   => 'version',
    writer   => '_set_version',
);

has options => (
    isa        => 'GnuPG::Options',
    is         => 'rw',
    lazy_build => 1,
);

sub _build_options { GnuPG::Options->new() }

# deprecated!
sub gnupg_call { shift->call(@_); }

sub BUILD {
    my ( $self, $args ) = @_;
    $self->hash_init( call => 'gpg', %$args );
}

struct(
    fh_setup => {
        parent_end       => '$', child_end      => '$',
        direct           => '$', is_std         => '$',
        parent_is_source => '$', name_shows_dup => '$',
    }
);

# Update version if "call" is updated
sub _trigger_call {
    my ( $self, $gpg ) = @_;
    $self->_set_version( $self->_version() );
}

#################################################################
# real worker functions

# This function does any 'extra' stuff that the user might
# not want to handle himself, such as passing in the passphrase
sub wrap_call( $% ) {
    my ( $self, %args ) = @_;

    my $handles = $args{handles}
        or croak 'error: no handles defined';

    $handles->stdin('<&STDIN')   unless $handles->stdin();
    $handles->stdout('>&STDOUT') unless $handles->stdout();
    $handles->stderr('>&STDERR') unless $handles->stderr();

    $self->passphrase("\n") unless $self->passphrase();

    my $needs_passphrase_handled
        = ( $self->passphrase() =~ m/\S/ and not $handles->passphrase() ) ? 1 : 0;

    if ($needs_passphrase_handled) {
        $handles->passphrase( IO::Handle->new() );
    }

    my $pid = $self->fork_attach_exec(%args);

    if ($needs_passphrase_handled) {
        my $passphrase_handle = $handles->passphrase();
        print $passphrase_handle $self->passphrase();
        close $passphrase_handle;

        # We put this in in case the user wants to re-use this object
        $handles->clear_passphrase();
    }

    return $pid;
}

# does does command-line creation, forking, and execcing
# the reasing cli creation is done here is because we should
# fork before finding the fd's for stuff like --status-fd
sub fork_attach_exec( $% ) {
    my ( $self, %args ) = @_;

    my $handles = $args{handles} or croak 'no GnuPG::Handles passed';
    my $use_loopback_pinentry = 0;

    # Don't use loopback pintentry for legacy (1.4) GPG
    #
    # Check that $version is populated before running cmp_version. If
    # we are invoked as part of BUILD to populate $version, then any
    # methods that depend on $version will fail. We don't care about
    # loopback when we're called just to check gpg version.
    $use_loopback_pinentry = 1
      if ($handles->passphrase() && $self->version && $self->cmp_version($self->version, '2.2') > 0 );

    # deprecation support
    $args{commands} ||= $args{gnupg_commands};

    my @commands
        = ref $args{commands} ? @{ $args{commands} } : ( $args{commands} )
        or croak "no gnupg commands passed";

    # deprecation support
    $args{command_args} ||= $args{gnupg_command_args};

    my @command_args
        = ref $args{command_args}
        ? @{ $args{command_args} }
        : ( $args{command_args} || () );
    unshift @command_args, "--"
        if @command_args and $command_args[0] ne "--";

    my %fhs;
    foreach my $fh_name (
        qw( stdin stdout stderr status
        logger passphrase command
        )
        ) {
        my $fh = $handles->$fh_name() or next;
        $fhs{$fh_name} = fh_setup->new();
        $fhs{$fh_name}->parent_end($fh);
    }

    foreach my $fh_name (qw( stdin stdout stderr )) {
        $fhs{$fh_name}->is_std(1);
    }

    foreach my $fh_name (qw( stdin passphrase command )) {
        my $entry = $fhs{$fh_name} or next;
        $entry->parent_is_source(1);
    }

    # Below is code derived heavily from
    # Marc Horowitz's IPC::Open3, a base Perl module
    foreach my $fh_name ( keys %fhs ) {
        my $entry = $fhs{$fh_name};

        my $parent_end = $entry->parent_end();
        my $name_shows_dup = ( $parent_end =~ s/^[<>]&// );
        $entry->parent_end($parent_end);

        $entry->name_shows_dup($name_shows_dup);

        $entry->direct( $name_shows_dup
                || $handles->options($fh_name)->{direct}
                || 0 );
    }

    foreach my $fh_name ( keys %fhs ) {
        $fhs{$fh_name}->child_end( IO::Handle->new() );
    }

    foreach my $fh_name ( keys %fhs ) {
        my $entry = $fhs{$fh_name};
        next if $entry->direct();

        my $reader_end;
        my $writer_end;
        if ( $entry->parent_is_source() ) {
            $reader_end = $entry->child_end();
            $writer_end = $entry->parent_end();
        }
        else {
            $reader_end = $entry->parent_end();
            $writer_end = $entry->child_end();
        }

        pipe $reader_end, $writer_end;
    }

    my $pid = fork;

    die "fork failed: $ERRNO" unless defined $pid;

    if ( $pid == 0 )    # child
    {

        # these are for safety later to help lessen autovifying,
        # speed things up, and make the code smaller
        my $stdin  = $fhs{stdin};
        my $stdout = $fhs{stdout};
        my $stderr = $fhs{stderr};

        # Paul Walmsley says:
        # Perl 5.6's POSIX.pm has a typo in it that prevents us from
        # importing STDERR_FILENO. So we resort to requiring it.
        require POSIX;

        my $standard_out
            = IO::Handle->new_from_fd( &POSIX::STDOUT_FILENO, 'w' );
        my $standard_in
            = IO::Handle->new_from_fd( &POSIX::STDIN_FILENO, 'r' );

        # Paul Walmsley says:
        # this mess is due to a typo in POSIX.pm on Perl 5.6
        my $stderr_fd = eval {&POSIX::STDERR_FILENO};
        $stderr_fd = 2 unless defined $stderr_fd;
        my $standard_err = IO::Handle->new_from_fd( $stderr_fd, 'w' );

        # If she wants to dup the kid's stderr onto her stdout I need to
        # save a copy of her stdout before I put something else there.
        if (    $stdout->parent_end() ne $stderr->parent_end()
            and $stderr->direct()
            and my_fileno( $stderr->parent_end() )
            == my_fileno($standard_out) ) {
            my $tmp = IO::Handle->new();
            open $tmp, '>&' . my_fileno( $stderr->parent_end() );
            $stderr->parent_end($tmp);
        }

        if ( $stdin->direct() ) {
            open $standard_in, '<&' . my_fileno( $stdin->parent_end() )
                unless my_fileno($standard_in)
                    == my_fileno( $stdin->parent_end() );
        }
        else {
            close $stdin->parent_end();
            open $standard_in, '<&=' . my_fileno( $stdin->child_end() );
        }

        if ( $stdout->direct() ) {
            open $standard_out, '>&' . my_fileno( $stdout->parent_end() )
                unless my_fileno($standard_out)
                    == my_fileno( $stdout->parent_end() );
        }
        else {
            close $stdout->parent_end();
            open $standard_out, '>&=' . my_fileno( $stdout->child_end() );
        }

        if ( $stdout->parent_end() ne $stderr->parent_end() ) {

            # I have to use a fileno here because in this one case
            # I'm doing a dup but the filehandle might be a reference
            # (from the special case above).
            if ( $stderr->direct() ) {
                open $standard_err, '>&' . my_fileno( $stderr->parent_end() )
                    unless my_fileno($standard_err)
                        == my_fileno( $stderr->parent_end() );
            }
            else {
                close $stderr->parent_end();
                open $standard_err, '>&=' . my_fileno( $stderr->child_end() );
            }
        }
        else {
            open $standard_err, '>&STDOUT'
                unless my_fileno($standard_err) == my_fileno($standard_out);
        }

        foreach my $fh_name ( keys %fhs ) {
            my $entry = $fhs{$fh_name};
            next if $entry->is_std();

            my $parent_end = $entry->parent_end();
            my $child_end  = $entry->child_end();

            if ( $entry->direct() ) {
                if ( $entry->name_shows_dup() ) {
                    my $open_prefix
                        = $entry->parent_is_source() ? '<&' : '>&';
                    open $child_end, $open_prefix . $parent_end;
                }
                else {
                    $child_end = $parent_end;
                    $entry->child_end($child_end);
                }
            }
            else {
                close $parent_end;
            }

            # we want these fh's to stay open after the exec
            fcntl $child_end, F_SETFD, 0;

            # now set the options for the call to GnuPG
            my $fileno = my_fileno($child_end);
            my $option = $fh_name . '_fd';
            $self->options->$option($fileno);
        }

        my @args = $self->options->get_args();

        # Get around a bug in 2.2, see also https://dev.gnupg.org/T4667
        # this covers both --delete-secret-key(s) and --delete-secret-and-public-key(s)
        if ( $self->version && $self->cmp_version( $self->version, 2.2 ) >= 0 && $commands[0] =~ /^--delete-secret-.*keys?$/ ) {
            push @args, '--yes';
        }

        push @args, '--pinentry-mode', 'loopback'
          if $use_loopback_pinentry;

        my @command = (
            $self->call(), @args,
            @commands,     @command_args
        );

        # On Unix, PATH is by default '.' and Perl >= v5.38 rejects '.'
        # being in the path when in taint mode. Set a path, if running
        # in taint mode whomever is calling us should be providing the
        # path to the gpg program to use.
        local $ENV{PATH} = '/usr/bin' if tainted $ENV{PATH};
        exec @command or die "exec() error: $ERRNO";
    }

    # parent

    # close the child end of any pipes (non-direct stuff)
    foreach my $fh_name ( keys %fhs ) {
        my $entry = $fhs{$fh_name};
        close $entry->child_end() unless $entry->direct();
    }

    foreach my $fh_name ( keys %fhs ) {
        my $entry = $fhs{$fh_name};
        next unless $entry->parent_is_source();

        my $parent_end = $entry->parent_end();

        # close any writing handles if they were a dup
        #any real reason for this?  It bombs if we're doing
        #the automagic >& stuff.
        #close $parent_end if $entry->direct();

        # unbuffer pipes
        select( ( select($parent_end), $OUTPUT_AUTOFLUSH = 1 )[0] )
            if $parent_end;
    }

    return $pid;
}

sub my_fileno {
    no strict 'refs';
    my ($fh) = @_;
    croak "fh is undefined" unless defined $fh;
    return $1 if $fh =~ /^=?(\d+)$/;    # is it a fd in itself?
    my $fileno = fileno $fh;
    croak "error determining fileno for $fh: $ERRNO" unless defined $fileno;
    return $fileno;
}


sub unescape_string {
  my($str) = splice(@_);
  $str =~ s/\\x(..)/chr(hex($1))/eg;
  return $str;
}

###################################################################

sub get_public_keys ( $@ ) {
    my ( $self, @key_ids ) = @_;

    return $self->get_keys(
        commands     => ['--list-public-keys'],
        command_args => [@key_ids],
    );
}

sub get_secret_keys ( $@ ) {
    my ( $self, @key_ids ) = @_;

    return $self->get_keys(
        commands     => ['--list-secret-keys'],
        command_args => [@key_ids],
    );
}

sub get_public_keys_with_sigs ( $@ ) {
    my ( $self, @key_ids ) = @_;

    return $self->get_keys(
        commands     => ['--check-sigs'],
        command_args => [@key_ids],
    );
}

sub get_keys {
    my ( $self, %args ) = @_;

    my $saved_options = $self->options();
    my $new_options   = $self->options->copy();
    $self->options($new_options);
    $self->options->push_extra_args(
        '--with-colons',
        '--fixed-list-mode',
        '--with-fingerprint',
        '--with-fingerprint',
        '--with-key-data',
    );

    my $stdin  = IO::Handle->new();
    my $stdout = IO::Handle->new();

    my $handles = GnuPG::Handles->new(
        stdin  => $stdin,
        stdout => $stdout,
    );

    my $pid = $self->wrap_call(
        handles => $handles,
        %args,
    );

    my @returned_keys;
    my $current_primary_key;
    my $current_signed_item;
    my $current_key;

    require GnuPG::PublicKey;
    require GnuPG::SecretKey;
    require GnuPG::SubKey;
    require GnuPG::Fingerprint;
    require GnuPG::UserId;
    require GnuPG::UserAttribute;
    require GnuPG::Signature;
    require GnuPG::Revoker;

    while (<$stdout>) {
        my $line = $_;
        chomp $line;
        my @fields = split ':', $line, -1;
        next unless @fields > 3;

        my $record_type = $fields[0];

        if ( $record_type eq 'pub' or $record_type eq 'sec' ) {
            push @returned_keys, $current_primary_key
                if $current_primary_key;

            my (
                $user_id_validity, $key_length, $algo_num, $hex_key_id,
                $creation_date, $expiration_date,
                $local_id, $owner_trust, $user_id_string,
                $sigclass, #unused
                $usage_flags,
            ) = @fields[ 1 .. $#fields ];

            # --fixed-list-mode uses epoch time for creation and expiration date strings.
            # For backward compatibility, we convert them back using GMT;
            my $expiration_date_string;
            if ($expiration_date eq '') {
              $expiration_date = undef;
            } else {
              $expiration_date_string = $self->_downrez_date($expiration_date);
            }
            my $creation_date_string = $self->_downrez_date($creation_date);

            $current_primary_key = $current_key
                = $record_type eq 'pub'
                ? GnuPG::PublicKey->new()
                : GnuPG::SecretKey->new();

            $current_primary_key->hash_init(
                length                 => $key_length,
                algo_num               => $algo_num,
                hex_id                 => $hex_key_id,
                local_id               => $local_id,
                owner_trust            => $owner_trust,
                creation_date          => $creation_date,
                expiration_date        => $expiration_date,
                creation_date_string   => $creation_date_string,
                expiration_date_string => $expiration_date_string,
                usage_flags            => $usage_flags,
            );

            $current_signed_item = $current_primary_key;
        }
        elsif ( $record_type eq 'fpr' ) {
            my $hex = $fields[9];
            my $f = GnuPG::Fingerprint->new( as_hex_string => $hex );
            $current_key->fingerprint($f);
        }
        elsif ( $record_type eq 'sig' or
                $record_type eq 'rev'
              ) {
            my (
                $validity,
                $algo_num,              $hex_key_id,
                $signature_date,
                $expiration_date,
                $user_id_string,
                $sig_type,
            ) = @fields[ 1, 3 .. 6, 9, 10 ];

            my $expiration_date_string;
            if ($expiration_date eq '') {
              $expiration_date = undef;
            } else {
              $expiration_date_string = $self->_downrez_date($expiration_date);
            }
            my $signature_date_string = $self->_downrez_date($signature_date);

            my ($sig_class, $is_exportable);
            if ($sig_type =~ /^([[:xdigit:]]{2})([xl])$/ ) {
              $sig_class = hex($1);
              $is_exportable = ('x' eq $2);
            }

            my $signature = GnuPG::Signature->new(
                validity       => $validity,
                algo_num       => $algo_num,
                hex_id         => $hex_key_id,
                date           => $signature_date,
                date_string    => $signature_date_string,
                expiration_date => $expiration_date,
                expiration_date_string => $expiration_date_string,
                user_id_string => unescape_string($user_id_string),
                sig_class      => $sig_class,
                is_exportable  => $is_exportable,
            );

            if ( $current_signed_item->isa('GnuPG::Key') ||
                 $current_signed_item->isa('GnuPG::UserId') ||
                 $current_signed_item->isa('GnuPG::Revoker') ||
                 $current_signed_item->isa('GnuPG::UserAttribute')) {
              if ($record_type eq 'sig') {
                $current_signed_item->push_signatures($signature);
              } elsif ($record_type eq 'rev') {
                $current_signed_item->push_revocations($signature);
              }
            } else {
              warn "do not know how to handle signature line: $line\n";
            }
        }
        elsif ( $record_type eq 'uid' ) {
            my ( $validity, $user_id_string ) = @fields[ 1, 9 ];

            $current_signed_item = GnuPG::UserId->new(
                validity  => $validity,
                as_string => unescape_string($user_id_string),
            );

            $current_primary_key->push_user_ids($current_signed_item);
        }
        elsif ( $record_type eq 'uat' ) {
            my ( $validity, $subpacket ) = @fields[ 1, 9 ];

            my ( $subpacket_count, $subpacket_total_size ) = split(/ /,$subpacket);

            $current_signed_item = GnuPG::UserAttribute->new(
                validity  => $validity,
                subpacket_count => $subpacket_count,
                subpacket_total_size => $subpacket_total_size,
            );

            $current_primary_key->push_user_attributes($current_signed_item);
        }
        elsif ( $record_type eq 'sub' or $record_type eq 'ssb' ) {
            my (
                $validity, $key_length, $algo_num, $hex_id,
                $creation_date, $expiration_date,
                $local_id,
                $dummy0, $dummy1, $dummy2, #unused
                $usage_flags,
            ) = @fields[ 1 .. 11 ];

            my $expiration_date_string;
            if ($expiration_date eq '') {
              $expiration_date = undef;
            } else {
              $expiration_date_string = $self->_downrez_date($expiration_date);
            }
            my $creation_date_string = $self->_downrez_date($creation_date);

            $current_signed_item = $current_key
                = GnuPG::SubKey->new(
                validity               => $validity,
                length                 => $key_length,
                algo_num               => $algo_num,
                hex_id                 => $hex_id,
                creation_date          => $creation_date,
                expiration_date        => $expiration_date,
                creation_date_string   => $creation_date_string,
                expiration_date_string => $expiration_date_string,
                local_id               => $local_id,
                usage_flags            => $usage_flags,
                );

            $current_primary_key->push_subkeys($current_signed_item);
        }
        elsif ($record_type eq 'rvk') {
          my ($algo_num, $fpr, $class) = @fields[ 3,9,10 ];
          my $rvk = GnuPG::Revoker->new(
           fingerprint => GnuPG::Fingerprint->new( as_hex_string => $fpr ),
           algo_num    => ($algo_num + 0),
           class       => hex($class),
          );
          # pushing to either primary key or subkey, to handle
          # designated revokers to the subkeys too:
          $current_key->push_revokers($rvk);
          # revokers should be bound to the key with signatures:
          $current_signed_item = $rvk;
        }
        elsif ($record_type eq 'pkd') {
          my ($pos, $size, $data) = @fields[ 1,2,3 ];
          $current_key->pubkey_data->[$pos+0] = Math::BigInt->from_hex('0x'.$data);
        }
        elsif ( $record_type ne 'tru' and $record_type ne 'grp' ) {
            warn "unknown record type $record_type";
        }
    }

    waitpid $pid, 0;

    push @returned_keys, $current_primary_key
        if $current_primary_key;

    $self->options($saved_options);

    return @returned_keys;
}

sub _downrez_date {
	my $self = shift;
	my $date = shift;
    if ($date =~  /^\d+$/) {
        my ($year,$month,$day) = (gmtime($date))[5,4,3];
        $year += 1900;
        $month += 1;
		return    sprintf('%04d-%02d-%02d',   $year, $month, $day);
    }
	return $date;
}


################################################################

sub list_public_keys {
    my ( $self, %args ) = @_;
    return $self->wrap_call(
        %args,
        commands => ['--list-public-keys'],
    );
}

sub list_sigs {
    my ( $self, %args ) = @_;
    return $self->wrap_call(
        %args,
        commands => ['--list-sigs'],
    );
}

sub list_secret_keys {
    my ( $self, %args ) = @_;
    return $self->wrap_call(
        %args,
        commands => ['--list-secret-keys'],
    );
}

sub encrypt( $% ) {
    my ( $self, %args ) = @_;
    return $self->wrap_call(
        %args,
        commands => ['--encrypt']
    );
}

sub encrypt_symmetrically( $% ) {
    my ( $self, %args ) = @_;
    # Strip the homedir and put it back after encrypting;
    my $homedir = $self->options->homedir;
    $self->options->clear_homedir
        unless $self->cmp_version($self->version, '2.2') >= 0;
    my $pid = $self->wrap_call(
        %args,
        commands => ['--symmetric']
    );
    $self->options->homedir($homedir)
        unless $self->cmp_version($self->version, '2.2') >= 0;
    return $pid;
}

sub sign( $% ) {
    my ( $self, %args ) = @_;
    return $self->wrap_call(
        %args,
        commands => ['--sign']
    );
}

sub clearsign( $% ) {
    my ( $self, %args ) = @_;
    return $self->wrap_call(
        %args,,
        commands => ['--clearsign']
    );
}

sub detach_sign( $% ) {
    my ( $self, %args ) = @_;
    return $self->wrap_call(
        %args,
        commands => ['--detach-sign']
    );
}

sub sign_and_encrypt( $% ) {
    my ( $self, %args ) = @_;
    return $self->wrap_call(
        %args,
        commands => [
            '--sign',
            '--encrypt'
        ]
    );
}

sub decrypt( $% ) {
    my ( $self, %args ) = @_;
    return $self->wrap_call(
        %args,
        commands => ['--decrypt']
    );
}

sub verify( $% ) {
    my ( $self, %args ) = @_;
    return $self->wrap_call(
        %args,
        commands => ['--verify']
    );
}

sub import_keys( $% ) {
    my ( $self, %args ) = @_;
    return $self->wrap_call(
        %args,
        commands => ['--import']
    );
}

sub export_keys( $% ) {
    my ( $self, %args ) = @_;
    return $self->wrap_call(
        %args,
        commands => ['--export']
    );
}

sub recv_keys( $% ) {
    my ( $self, %args ) = @_;
    return $self->wrap_call(
        %args,
        commands => ['--recv-keys']
    );
}

sub send_keys( $% ) {
    my ( $self, %args ) = @_;
    return $self->wrap_call(
        %args,
        commands => ['--send-keys']
    );
}

sub search_keys( $% ) {
    my ( $self, %args ) = @_;
    return $self->wrap_call(
        %args,
        commands => ['--search-keys']
    );
}

sub _version {
    my ( $self ) = @_;

    my $out = IO::Handle->new;
    my $handles = GnuPG::Handles->new( stdout => $out );
    my $pid = $self->wrap_call( commands => [ '--no-options', '--version' ], handles => $handles );
    my $line = $out->getline;
    $line =~ /(\d+\.\d+\.\d+)/;

    my $version = $1;
    unless ($self->cmp_version($version, '2.2') >= 0 or
        ($self->cmp_version($version, '1.4') >= 0 and $self->cmp_version($version, '1.5') < 0 )) {
        croak "GnuPG Version 1.4 or 2.2+ required";
    }
    waitpid $pid, 0;

    return $version;
}

sub cmp_version($$) {
    my ( $self, $a, $b ) = (@_);
    my @a = split '\.', $a;
    my @b = split '\.', $b;
    @a > @b
        ? push @b, (0) x (@a-@b)
        : push @a, (0) x (@b-@a);
    for ( my $i = 0; $i < @a; $i++ ) {
        return $a[$i] <=> $b[$i] if $a[$i] <=> $b[$i];
    }
    return 0;
}

sub test_default_key_passphrase() {
    my ($self) = @_;

    # We can't do something like let the user pass
    # in a passphrase handle because we don't exist
    # anymore after the user runs off with the
    # attachments
    croak 'No passphrase defined to test!'
        unless defined $self->passphrase();

    my $stdin  = IO::Handle->new();
    my $stdout = IO::Handle->new();
    my $stderr = IO::Handle->new();
    my $status = IO::Handle->new();

    my $handles = GnuPG::Handles->new(
        stdin  => $stdin,
        stdout => $stdout,
        stderr => $stderr,
        status => $status
    );

    # save this setting since we need to be in non-interactive mode
    my $saved_meta_interactive_option = $self->options->meta_interactive();
    $self->options->clear_meta_interactive();

    my $pid = $self->sign( handles => $handles );

    close $stdin;

    # restore this setting to its original setting
    $self->options->meta_interactive($saved_meta_interactive_option);

    # all we realy want to check is the status fh
    while (<$status>) {
        if (/^\[GNUPG:\]\s*(GOOD_PASSPHRASE|SIG_CREATED)/) {
            waitpid $pid, 0;
            return 1;
        }
    }

    # If we didn't catch the regexp above, we'll assume
    # that the passphrase was incorrect
    waitpid $pid, 0;
    return 0;
}

1;

##############################################################

=head1 NAME

GnuPG::Interface - Perl interface to GnuPG

=head1 SYNOPSIS

  # A simple example
  use IO::Handle;
  use GnuPG::Interface;

  # setting up the situation
  my $gnupg = GnuPG::Interface->new();
  $gnupg->options->hash_init( armor   => 1,
			      homedir => '/home/foobar' );

  # Note you can set the recipients even if you aren't encrypting!
  $gnupg->options->push_recipients( 'ftobin@cpan.org' );
  $gnupg->options->meta_interactive( 0 );

  # how we create some handles to interact with GnuPG
  my $input   = IO::Handle->new();
  my $output  = IO::Handle->new();
  my $handles = GnuPG::Handles->new( stdin  => $input,
                                     stdout => $output );

  # Now we'll go about encrypting with the options already set
  my @plaintext = ( 'foobar' );
  my $pid = $gnupg->encrypt( handles => $handles );

  # Now we write to the input of GnuPG
  print $input @plaintext;
  close $input;

  # now we read the output
  my @ciphertext = <$output>;
  close $output;

  waitpid $pid, 0;

=head1 DESCRIPTION

GnuPG::Interface and its associated modules are designed to
provide an object-oriented method for interacting with GnuPG,
being able to perform functions such as but not limited
to encrypting, signing,
decryption, verification, and key-listing parsing.

=head2 How Data Member Accessor Methods are Created

Each module in the GnuPG::Interface bundle relies
on Moo to generate the get/set methods
used to set the object's data members.
I<This is very important to realize.>  This means that
any data member which is a list has special
methods assigned to it for pushing, popping, and
clearing the list.

=head2 Understanding Bidirectional Communication

It is also imperative to realize that this package
uses interprocess communication methods similar to
those used in L<IPC::Open3>
and L<perlipc/"Bidirectional Communication with Another Process">,
and that users of this package
need to understand how to use this method because this package
does not abstract these methods for the user greatly.
This package is not designed
to abstract this away entirely (partly for security purposes), but rather
to simply help create 'proper', clean calls to GnuPG, and to implement
key-listing parsing.
Please see L<perlipc/"Bidirectional Communication with Another Process">
to learn how to deal with these methods.

Using this package to do message processing generally
invovlves creating a GnuPG::Interface object, creating
a GnuPG::Handles object,
setting some options in its B<options> data member,
and then calling a method which invokes GnuPG, such as
B<clearsign>.  One then interacts with with the handles
appropriately, as described in
L<perlipc/"Bidirectional Communication with Another Process">.

=head1 GnuPG Versions

As of this version of GnuPG::Interface, there are three supported
versions of GnuPG: 1.4.x, 2.2.x, and 2.4.x. The
L<GnuPG download page|https://gnupg.org/download/index.html> has
updated information on the currently supported versions.

GnuPG released 2.0 and 2.1 versions in the past and some packaging
systems may still provide these if you install the default C<gpg>,
C<gnupg>, C<gnupg2>, etc. packages. 2.0 and 2.1 versions are not
supported, so you may need to find additional package repositories
or build from source to get the updated version.

=head1 OBJECT METHODS

=head2 Initialization Methods

=over 4

=item new( I<%initialization_args> )

This methods creates a new object.  The optional arguments are
initialization of data members.

=item hash_init( I<%args> ).


=back

=head2 Object Methods which use a GnuPG::Handles Object

=over 4

=item list_public_keys( % )

=item list_sigs( % )

=item list_secret_keys( % )

=item encrypt( % )

=item encrypt_symmetrically( % )

=item sign( % )

=item clearsign( % )

=item detach_sign( % )

=item sign_and_encrypt( % )

=item decrypt( % )

=item verify( % )

=item import_keys( % )

=item export_keys( % )

=item recv_keys( % )

=item send_keys( % )

=item search_keys( % )

These methods each correspond directly to or are very similar
to a GnuPG command described in L<gpg>.  Each of these methods
takes a hash, which currently must contain a key of B<handles>
which has the value of a GnuPG::Handles object.
Another optional key is B<command_args> which should have the value of an
array reference; these arguments will be passed to GnuPG as command arguments.
These command arguments are used for such things as determining the keys to
list in the B<export_keys> method.  I<Please note that GnuPG command arguments
are not the same as GnuPG options>.  To understand what are options and
what are command arguments please read L<gpg/"COMMANDS"> and L<gpg/"OPTIONS">.

Each of these calls returns the PID for the resulting GnuPG process.
One can use this PID in a C<waitpid> call instead of a C<wait> call
if more precise process reaping is needed.

These methods will attach the handles specified in the B<handles> object
to the running GnuPG object, so that bidirectional communication
can be established.  That is, the optionally-defined B<stdin>,
B<stdout>, B<stderr>, B<status>, B<logger>, and
B<passphrase> handles will be attached to
GnuPG's input, output, standard error,
the handle created by setting B<status-fd>, the handle created by setting B<logger-fd>, and the handle created by setting
B<passphrase-fd> respectively.
This tying of handles of similar to the process
done in I<IPC::Open3>.

If you want the GnuPG process to read or write directly to an already-opened
filehandle, you cannot do this via the normal I<IPC::Open3> mechanisms.
In order to accomplish this, set the appropriate B<handles> data member
to the already-opened filehandle, and then set the option B<direct> to be true
for that handle, as described in L<GnuPG::Handles/options>.  For example,
to have GnuPG read from the file F<input.txt> and write to F<output.txt>,
the following snippet may do:

  my $infile  = IO::File->new( 'input.txt' );
  my $outfile = IO::File->new( '>output.txt' );
  my $handles = GnuPG::Handles->new( stdin  => $infile,
                                     stdout => $outfile,
                                   );
  $handles->options( 'stdin'  )->{direct} = 1;
  $handles->options( 'stdout' )->{direct} = 1;

If any handle in the B<handles> object is not defined, GnuPG's input, output,
and standard error will be tied to the running program's standard error,
standard output, or standard error.  If the B<status> or B<logger> handle
is not defined, this channel of communication is never established with GnuPG,
and so this information is not generated and does not come into play.

If the B<passphrase> data member handle of the B<handles> object
is not defined, but the the B<passphrase> data member handle of GnuPG::Interface
object is, GnuPG::Interface will handle passing this information into GnuPG
for the user as a convenience.  Note that this will result in
GnuPG::Interface storing the passphrase in memory, instead of having
it simply 'pass-through' to GnuPG via a handle.

If neither the B<passphrase> data member of the GnuPG::Interface nor
the B<passphrase> data member of the B<handles> object is defined,
then GnuPG::Interface assumes that access and control over the secret
key will be handled by the running gpg-agent process.  This represents
the simplest mode of operation with the GnuPG "stable" suite (version
2.2 and later).  It is also the preferred mode for tools intended to
be user-facing, since the user will be prompted directly by gpg-agent
for use of the secret key material.  Note that for programmatic use,
this mode requires the gpg-agent and pinentry to already be correctly
configured.

=back

=head2 Other Methods

=over 4

=item get_public_keys( @search_strings )

=item get_secret_keys( @search_strings )

=item get_public_keys_with_sigs( @search_strings )

These methods create and return objects of the type GnuPG::PublicKey
or GnuPG::SecretKey respectively.  This is done by parsing the output
of GnuPG with the option B<with-colons> enabled.  The objects created
do or do not have signature information stored in them, depending
if the method ends in I<_sigs>; this separation of functionality is there
because of performance hits when listing information with signatures.

=item test_default_key_passphrase()

This method will return a true or false value, depending
on whether GnuPG reports a good passphrase was entered
while signing a short message using the values of
the B<passphrase> data member, and the default
key specified in the B<options> data member.

=item version()

Returns the version of GnuPG that GnuPG::Interface is running.

=back


=head1 Invoking GnuPG with a custom call

GnuPG::Interface attempts to cover a lot of the commands
of GnuPG that one would want to perform; however, there may be a lot
more calls that GnuPG is and will be capable of, so a generic command
interface is provided, C<wrap_call>.

=over 4

=item wrap_call( %args )

Call GnuPG with a custom command.  The %args hash must contain
at least the following keys:

=over 4

=item commands

The value of this key in the hash must be a reference to a a list of
commands for GnuPG, such as C<[ qw( --encrypt --sign ) ]>.

=item handles

As with most other GnuPG::Interface methods, B<handles>
must be a GnuPG::Handles object.

=back

The following keys are optional.

=over 4

=item command_args

As with other GnuPG::Interface methods, the value in hash
for this key must be a reference to a list of arguments
to be passed to the GnuPG command, such as which
keys to list in a key-listing.

=back

=back


=head1 OBJECT DATA MEMBERS

=over 4

=item call

This defines the call made to invoke GnuPG.  Defaults to 'gpg'; this
should be changed if 'gpg' is not in your path, or there is a different
name for the binary on your system.

=item passphrase

In order to lessen the burden of using handles by the user of this package,
setting this option to one's passphrase for a secret key will allow
the package to enter the passphrase via a handle to GnuPG by itself
instead of leaving this to the user.  See also L<GnuPG::Handles/passphrase>.

=item options

This data member, of the type GnuPG::Options; the setting stored in this
data member are used to determine the options used when calling GnuPG
via I<any> of the object methods described in this package.
See L<GnuPG::Options> for more information.

=back

=head1 EXAMPLES

The following setup can be done before any of the following examples:

  use IO::Handle;
  use GnuPG::Interface;

  my @original_plaintext = ( "How do you doo?" );
  my $passphrase = "Three Little Pigs";

  my $gnupg = GnuPG::Interface->new();

  $gnupg->options->hash_init( armor    => 1,
                              recipients => [ 'ftobin@uiuc.edu',
                                              '0xABCD1234ABCD1234ABCD1234ABCD1234ABCD1234' ],
                              meta_interactive => 0 ,
                            );

   $gnupg->options->debug_level(4);

   $gnupg->options->logger_file("/tmp/gnupg-$$-decrypt-".time().".log");


=head2 Encrypting

  # We'll let the standard error of GnuPG pass through
  # to our own standard error, by not creating
  # a stderr-part of the $handles object.
  my ( $input, $output ) = ( IO::Handle->new(),
                             IO::Handle->new() );

  my $handles = GnuPG::Handles->new( stdin    => $input,
                                     stdout   => $output );

  # this sets up the communication
  # Note that the recipients were specified earlier
  # in the 'options' data member of the $gnupg object.
  my $pid = $gnupg->encrypt( handles => $handles );

  # this passes in the plaintext
  print $input @original_plaintext;

  # this closes the communication channel,
  # indicating we are done
  close $input;

  my @ciphertext = <$output>;  # reading the output

  waitpid $pid, 0;  # clean up the finished GnuPG process

=head2 Signing

  # This time we'll catch the standard error for our perusing
  my ( $input, $output, $error ) = ( IO::Handle->new(),
                                     IO::Handle->new(),
                                     IO::Handle->new(),
				   );

  my $handles = GnuPG::Handles->new( stdin    => $input,
                                     stdout   => $output,
                                     stderr   => $error,
				   );

  # indicate our pasphrase through the
  # convenience method
  $gnupg->passphrase( $passphrase );

  # this sets up the communication
  my $pid = $gnupg->sign( handles => $handles );

  # this passes in the plaintext
  print $input @original_plaintext;

  # this closes the communication channel,
  # indicating we are done
  close $input;

  my @ciphertext   = <$output>;  # reading the output
  my @error_output = <$error>;   # reading the error

  close $output;
  close $error;

  waitpid $pid, 0;  # clean up the finished GnuPG process

=head2 Decryption

  # This time we'll catch the standard error for our perusing
  # as well as passing in the passphrase manually
  # as well as the status information given by GnuPG
  my ( $input, $output, $error, $passphrase_fh, $status_fh )
    = ( IO::Handle->new(),
        IO::Handle->new(),
        IO::Handle->new(),
        IO::Handle->new(),
        IO::Handle->new(),
      );

  my $handles = GnuPG::Handles->new( stdin      => $input,
				     stdout     => $output,
				     stderr     => $error,
				     passphrase => $passphrase_fh,
				     status     => $status_fh,
				   );

  # this time we'll also demonstrate decrypting
  # a file written to disk
  # Make sure you "use IO::File" if you use this module!
  my $cipher_file = IO::File->new( 'encrypted.gpg' );

  # this sets up the communication
  my $pid = $gnupg->decrypt( handles => $handles );

  # This passes in the passphrase
  print $passphrase_fh $passphrase;
  close $passphrase_fh;

  # this passes in the plaintext
  print $input $_ while <$cipher_file>;

  # this closes the communication channel,
  # indicating we are done
  close $input;
  close $cipher_file;

  my @plaintext    = <$output>;    # reading the output
  my @error_output = <$error>;     # reading the error
  my @status_info  = <$status_fh>; # read the status info

  # clean up...
  close $output;
  close $error;
  close $status_fh;

  waitpid $pid, 0;  # clean up the finished GnuPG process

=head2 Printing Keys

  # This time we'll just let GnuPG print to our own output
  # and read from our input, because no input is needed!
  my $handles = GnuPG::Handles->new();

  my @ids = ( 'ftobin', '0xABCD1234ABCD1234ABCD1234ABCD1234ABCD1234' );

  # this time we need to specify something for
  # command_args because --list-public-keys takes
  # search ids as arguments
  my $pid = $gnupg->list_public_keys( handles      => $handles,
                                      command_args => [ @ids ] );

   waitpid $pid, 0;

=head2 Creating GnuPG::PublicKey Objects

  my @ids = [ 'ftobin', '0xABCD1234ABCD1234ABCD1234ABCD1234ABCD1234' ];

  my @keys = $gnupg->get_public_keys( @ids );

  # no wait is required this time; it's handled internally
  # since the entire call is encapsulated

=head2 Custom GnuPG call

  # assuming $handles is a GnuPG::Handles object
  my $pid = $gnupg->wrap_call
    ( commands     => [ qw( --list-packets ) ],
      command_args => [ qw( test/key.1.asc ) ],
      handles      => $handles,
    );

    my @out = <$handles->stdout()>;
    waitpid $pid, 0;


=head1 FAQ

=over 4

=item How do I get GnuPG::Interface to read/write directly from
a filehandle?

You need to set GnuPG::Handles B<direct> option to be true for the
filehandles in concern.  See L<GnuPG::Handles/options> and
L<"Object Methods which use a GnuPG::Handles Object"> for more
information.

=item Why do you make it so difficult to get GnuPG to write/read
from a filehandle?  In the shell, I can just call GnuPG
with the --outfile option!

There are lots of issues when trying to tell GnuPG to read/write
directly from a file, such as if the file isn't there, or
there is a file, and you want to write over it!  What do you
want to happen then?  Having the user of this module handle
these questions beforehand by opening up filehandles to GnuPG
lets the user know fully what is going to happen in these circumstances,
and makes the module less error-prone.

=item When having GnuPG process a large message, sometimes it just
hanges there.

Your problem may be due to buffering issues; when GnuPG reads/writes
to B<non-direct> filehandles (those that are sent to filehandles
which you read to from into memory, not that those access the disk),
buffering issues can mess things up.  I recommend looking into
L<GnuPG::Handles/options>.

=back

=head1 NOTES

This package is the successor to PGP::GPG::MessageProcessor,
which I found to be too inextensible to carry on further.
A total redesign was needed, and this is the resulting
work.

After any call to a GnuPG-command method of GnuPG::Interface
in which one passes in the handles,
one should all B<wait> to clean up GnuPG from the process table.


=head1 BUGS

=head2 Large Amounts of Data

Currently there are problems when transmitting large quantities
of information over handles; I'm guessing this is due
to buffering issues.  This bug does not seem specific to this package;
IPC::Open3 also appears affected.

=head2 OpenPGP v3 Keys

I don't know yet how well this module handles parsing OpenPGP v3 keys.

=head2 RHEL 7 Test Failures

Testing with the updates for version 1.00 we saw intermittent test failures
on RHEL 7 with GnuPG version 2.2.20. In some cases the tests would all pass
for several runs, then one would fail. We're unable to reliably reproduce
this so we would be interested in feedback from other users.

=head1 SEE ALSO

L<GnuPG::Options>,
L<GnuPG::Handles>,
L<GnuPG::PublicKey>,
L<GnuPG::SecretKey>,
L<gpg>,
L<perlipc/"Bidirectional Communication with Another Process">

=head1 LICENSE

This module is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=head1 AUTHOR

GnuPG::Interface is currently maintained by Best Practical Solutions <BPS@cpan.org>.

Frank J. Tobin, ftobin@cpan.org was the original author of the package.

=cut

1;

