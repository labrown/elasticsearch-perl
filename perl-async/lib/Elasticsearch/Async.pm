package Elasticsearch::Async;

use Elasticsearch 0.76;

#use Promises 0.05 ();
use Promises();
use Moo 1.003;
extends 'Elasticsearch';
use Elasticsearch::Util qw(parse_params);
use namespace::clean;

our $VERSION = '0.77';

#===================================
sub new {
#===================================
    my ( $class, $params ) = parse_params(@_);
    $class->SUPER::new(
        {   cxn_pool            => 'Async::Static',
            transport           => 'Async',
            cxn                 => 'AEHTTP',
            bulk_helper_class   => 'Async::Bulk',
            scroll_helper_class => 'Async::Scroll',
            %$params
        }
    );
}

1;

__END__
