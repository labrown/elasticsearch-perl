package Elasticsearch::Async::Util;

use Moo;
use Sub::Exporter -setup => { exports => ['isa_promise'] };

#===================================
sub isa_promise {
#===================================
    return
            unless @_ == 1
        and blessed $_[0]
        and $_[0]->isa('Promises::Promise');
    return shift();
}
1;

# ABSTRACT: A utility class for internal use by Elasticsearch
