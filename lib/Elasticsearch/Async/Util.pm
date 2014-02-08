package Elasticsearch::Async::Util;

use Moo;
use Sub::Exporter -setup => { exports => ['thenable'] };

#===================================
sub thenable {
#===================================
    return
            unless @_ == 1
        and blessed $_[0]
        and $_[0]->can('then');
    return shift();
}
1;

# ABSTRACT: A utility class for internal use by Elasticsearch
