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

    my $cxns     = $self->cxns;
    my $now      = time();
    my $deferred = deferred;

    my ( %seen, @skipped, $cxn, $weak_find_cxn );

    my $find_cxn = sub {
        my $total = @$cxns;

        if ( $total > keys %seen ) {

            # we haven't seen all cxns yet
            while ( $total-- ) {
                $cxn = $cxns->[ $self->next_cxn_num ];
                next if $seen{$cxn}++;

                return $deferred->resolve($cxn)
                    if $cxn->is_live;

                last if $cxn->next_ping <= time();

                push @skipped, $cxn;
                undef $cxn;
            }
        }

        if ( $cxn ||= shift @skipped ) {
            return $cxn->pings_ok->then(
                sub { $deferred->resolve($cxn) },    # success
                $weak_find_cxn                       # resolve
            );
        }

        $_->force_ping for @$cxns;

        return $deferred->reject(
            new_error(
                "NoNodes",
                "No nodes are available: [" . $self->cxns_str . ']'
            )
        );

    };
    weaken( $weak_find_cxn = $find_cxn );

    $find_cxn->();
    $deferred->promise;
}

1;
__END__
