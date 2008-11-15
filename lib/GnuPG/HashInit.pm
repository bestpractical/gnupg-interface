package GnuPG::HashInit;
use Moose::Role;

sub hash_init {
    my ($self, %args) = @_;
    while ( my ( $method, $value ) = each %args ) {
        $self->$method($value);
    }
}

no Moose::Role;
1;
__END__
