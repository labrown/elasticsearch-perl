package Elasticsearch::Transport::Async;

use Moo;
with 'Elasticsearch::Role::Is_Async', 'Elasticsearch::Role::Transport';

use Time::HiRes qw(time);
use Elasticsearch::Util qw(upgrade_error);
use Promises qw(deferred);
use namespace::clean;

#===================================
sub perform_request {
#===================================
    my $self   = shift;
    my $params = $self->tidy_request(@_);
    my $pool   = $self->cxn_pool;
    my $logger = $self->logger;

    my $deferred = deferred;

    my ( $start, $cxn );
    $pool->next_cxn

        # perform request
        ->then(
        sub {
            $cxn   = shift;
            $start = time();
            $cxn->perform_request($params);
        }
        )

        # log request regardless of success/failure
        ->finally( sub { $logger->trace_request( $cxn, $params ) } )

        # request failed, should retry?
        ->catch(
        sub {
            my $error = upgrade_error( shift(), { request => $params } );
            die $error unless $pool->request_failed( $cxn, $error );

            # log failed, then retry
            $logger->debugf( "[%s] %s", $cxn->stringify, "$error" );
            $logger->info('Retrying request on a new cxn');
            $self->perform_request($params);
        }
        )

        ->done(
        # request succeeded
        sub {
            my ( $code, $response ) = @_;
            $pool->request_ok($cxn);
            $logger->trace_response( $cxn, $code, $response,
                time() - $start );
            $deferred->resolve($response);
        },

        # log fatal error
        sub {
            my $error = shift;
            if ($cxn) {
                $logger->trace_request( $cxn, $params );
                $logger->trace_error( $cxn, $error );
                delete $error->{vars}{body};
            }
            $error->is('NoNodes')
                ? $logger->critical($error)
                : $logger->error($error);
            $deferred->reject($error);
        }
        );
    return $deferred->promise;
}

1;

__END__

#ABSTRACT: Interface between the client class the Elasticsearch cluster

=head1 DESCRIPTION

The Transport class manages the request cycle. It receives parsed requests
from the (user-facing) client class, and tries to execute the request on a
node in the cluster, retrying a request if necessary.

=head1 CONFIGURATION

=head2 C<send_get_body_as>

    $e = Elasticsearch->new(
        send_get_body_as => 'POST'
    );

Certain endpoints like L<Elasticsearch::Client::Direct/search()> default to
using a C<GET> method, even when they include a request body.  Some proxy
servers do not support C<GET> requests with a body.  To work around this,
the C<send_get_body_as>  parameter accepts the following:

=over

=item * C<GET>

The default.  Request bodies are sent as C<GET> requests.

=item * C<POST>

The method is changed to C<POST> when a body is present.

=item * C<source>

The body is encoded as JSON and added to the query string as the C<source>
parameter.  This has the advantage of still being a C<GET> request (for those
filtering on request method) but has the disadvantage of being restricted
in size.  The limit depends on the proxies between the client and
Elasticsearch, but usually is around 4kB.

=back

=head1 METHODS

=head2 C<perform_request()>

Raw requests can be executed using the transport class as follows:

    $result = $e->transport->perform_request(
        method => 'POST',
        path   => '/_search',
        qs     => { from => 0, size => 10 },
        body   => {
            query => {
                match => {
                    title => "Elasticsearch clients"
                }
            }
        }
    );

Other than the C<method>, C<path>, C<qs> and C<body> parameters, which
should be self-explanatory, it also accepts:

=over

=item C<ignore>

The HTTP error codes which should be ignored instead of throwing an error,
eg C<404 NOT FOUND>:

    $result = $e->transport->perform_request(
        method => 'GET',
        path   => '/index/type/id'
        ignore => [404],
    );

=item C<serialize>

Whether the C<body> should be serialized in the standard way (as plain
JSON) or using the special I<bulk> format:  C<"std"> or C<"bulk">.

=back

