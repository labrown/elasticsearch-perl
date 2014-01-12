package Elasticsearch::CxnPool::Async::Static::NoPing;

use Moo;
with 'Elasticsearch::Role::CxnPool::Static::NoPing',
    'Elasticsearch::Role::Is_Async';

use Promises qw(deferred);
use Elasticsearch::Util qw(new_error);
use namespace::clean;

#===================================
sub next_cxn {
#===================================
    my $self = shift;

    my $cxns     = $self->cxns;
    my $total    = @$cxns;
    my $dead     = $self->_dead_cxns;
    my $deferred = deferred;

    while ( $total-- ) {
        my $cxn = $cxns->[ $self->next_cxn_num ];
        if ( $cxn->is_live || $cxn->next_ping < time() ) {
            $deferred->resolve($cxn);
            return $deferred->promise;
        }
        push @$dead, $cxn unless grep { $_ eq $cxn } @$dead;
    }

    if ( @$dead and $self->retries <= $self->max_retries ) {
        $_->force_ping for @$dead;
        $deferred->resolve( shift @$dead );
        return $deferred->promise;
    }

    $deferred->reject(
        new_error(
            "NoNodes", "No nodes are available: [" . $self->cxns_str . ']'
        )
    );
    return $deferred->promise;
}

1;
__END__
