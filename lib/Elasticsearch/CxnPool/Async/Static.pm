package Elasticsearch::CxnPool::Async::Static;

use Moo;
with 'Elasticsearch::Role::CxnPool::Static', 'Elasticsearch::Role::Is_Async';

use Elasticsearch::Util qw(new_error);
use Scalar::Util qw(weaken);
use Promises qw(deferred);
use namespace::clean;

#===================================
sub next_cxn {
#===================================
    my ($self) = @_;

    my $cxns  = $self->cxns;
    my $total = @$cxns;

    my $now = time();
    my @skipped;
    my %seen;
    my $deferred = deferred;

    my $weak_find_cxn;
    my $find_cxn = sub {

        my $cxn;

        #  tried all live nodes
        if ( keys %seen == $total ) {

            # try dead nodes
            if ( $cxn = shift @skipped ) {
                return $cxn->pings_ok->then(
                    sub { $deferred->resolve($cxn) },    # node ok
                    $weak_find_cxn                       # try again
                );
            }

            # no live nodes
            $_->force_ping for @$cxns;
            $deferred->reject(
                new_error(
                    "NoNodes",
                    "No nodes are available: [" . $self->cxns_str . ']'
                )
            );
            return;
        }

        # get next unseen node
        while ( $cxn = $cxns->[ $self->next_cxn_num ] ) {
            last unless $seen{$cxn}++;
        }

        return $deferred->resolve($cxn)
            if $cxn->is_live;

        if ( $cxn->next_ping < $now ) {
            return $cxn->pings_ok->then(
                sub { $deferred->resolve($cxn) },    # node ok
                $weak_find_cxn                       # try again
            );
        }

        push @skipped, $cxn;
        $weak_find_cxn->();
    };
    weaken( $weak_find_cxn = $find_cxn );

    $find_cxn->();
    $deferred->promise;
}

1;
__END__
