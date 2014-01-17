package Elasticsearch::Role::Cxn::Async;

use Moo::Role;

use Elasticsearch::Util qw(new_error);
use namespace::clean;

#===================================
sub pings_ok {
#===================================
    my $self = shift;
    $self->logger->infof( 'Pinging [%s]', $self->stringify );

    $self->perform_request(
        {   method  => 'HEAD',
            path    => '/',
            timeout => $self->ping_timeout,
        }
        )->then(
        sub {
            $self->logger->infof( 'Marking [%s] as live', $self->stringify );
            $self->mark_live;
        },
        sub {
            $self->logger->debug(@_);
            $self->mark_dead;
        }
        );
}

#===================================
sub sniff {
#===================================
    my $self     = shift;
    my $protocol = $self->protocol;
    $self->logger->infof( 'Sniffing [%s]', $self->stringify );
    $self->perform_request(
        {   method => 'GET',
            path   => '/_cluster/nodes',
            qs     => {
                timeout   => 1000 * $self->sniff_timeout,
                $protocol => 1
            },
            timeout => $self->sniff_request_timeout,
        }
        )->then(
        sub {
            $_[1]->{nodes};
        },
        sub {
            $self->logger->debug(@_);
            @_;
        }
        );
}
1;

# ABSTRACT: Provides common functionality to Async Cxn implementations

