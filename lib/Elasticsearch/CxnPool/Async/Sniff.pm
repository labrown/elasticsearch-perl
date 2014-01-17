package Elasticsearch::CxnPool::Async::Sniff;

use Moo;
with 'Elasticsearch::Role::CxnPool::Sniff', 'Elasticsearch::Role::Is_Async';

use Scalar::Util qw(weaken);
use Promises qw(deferred);
use Elasticsearch::Util qw(new_error);

use namespace::clean;
has 'concurrent_sniff' => ( is => 'rw', default => 4 );
has '_current_sniff'   => ( is => 'rw', clearer => '_clear_sniff' );

#===================================
sub next_cxn {
#===================================
    my ( $self, $no_sniff ) = @_;

    if ( !$no_sniff and $self->next_sniff <= time() ) {
        return $self->sniff->then( sub { $self->next_cxn('no_sniff') } );
    }

    my $cxns     = $self->cxns;
    my $total    = @$cxns;
    my $deferred = deferred;

    while ( 0 < $total-- ) {
        my $cxn = $cxns->[ $self->next_cxn_num ];
        if ( $cxn->is_live ) {
            $deferred->resolve($cxn);
            return $deferred->promise;
        }
    }
    $deferred->reject(
        new_error(
            "NoNodes",
            "No nodes are available: [" . $self->cxns_seeds_str . ']'
        )
    );
    $deferred->promise;
}

#===================================
sub sniff {
#===================================
    my $self = shift;
    if ( my $promise = $self->_current_sniff ) {
        return $promise;
    }

    my $deferred   = deferred;
    my $cxns       = $self->cxns;
    my $total      = @$cxns;
    my $done       = 0;
    my $current    = 0;
    my $done_seeds = 0;

    my ( @all, @skipped );

    while ( 0 < $total-- ) {
        my $cxn = $cxns->[ $self->next_cxn_num ];
        if ( $cxn->is_dead ) {
            push @skipped, $cxn;
        }
        else {
            push @all, $cxn;
        }
    }

    push @all, @skipped;
    unless (@all) {
        @all = $self->_seeds_as_cxns;
        $done_seeds++;
    }

    my $weak_check_sniff;
    my $check_sniff = sub {

        return if $done;
        my ( $cxn, $nodes ) = @_;
        if ( $nodes && $self->parse_sniff( $cxn->protocol, $nodes ) ) {
            $done++;
            $self->_clear_sniff;
            return $deferred->resolve();
        }
        if ( my $cxn = shift @all ) {
            return $self->sniff_cxn($cxn)->then($weak_check_sniff);
        }
        unless ( $done_seeds++ ) {
            $self->logger->infof(
                "No live nodes available. Trying seed nodes.");
            @all = $self->_seeds_as_cxns;
            return $self->sniff_cxn( shift(@all) )->then($weak_check_sniff);
        }
        if ( --$current == 0 ) {
            $self->_clear_sniff;
            $deferred->resolve();
        }
    };
    weaken( $weak_check_sniff = $check_sniff );

    my $max = $self->concurrent_sniff;
    for ( 1 .. $max ) {
        my $cxn = shift @all
            or last;
        $self->sniff_cxn($cxn)->then($check_sniff);
        $current++;
    }

    return $self->_current_sniff( $deferred->promise );
}

#===================================
sub _seeds_as_cxns {
#===================================
    my $self    = shift;
    my $factory = $self->cxn_factory;
    return map { $factory->new_cxn($_) } @{ $self->seed_nodes };
}

#===================================
sub sniff_cxn {
#===================================
    my ( $self, $cxn ) = @_;
    my $deferred = deferred;
    $cxn->sniff->then(
        sub { $deferred->resolve( $cxn, @_ ) },
        sub { $deferred->resolve($cxn) }
    );
    $deferred->promise;
}

1;
