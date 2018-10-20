# This code is part of distribution XML-Compile-SOAP-Daemon.  Meta-POD
# processed with OODoc into POD and HTML manual-pages.  See README.md
# Copyright Mark Overmeer.  Licensed under the same terms as Perl itself.

package XML::Compile::SOAP::Daemon::MojoUtil;

use parent 'Exporter';

use warnings;
use strict;

=chapter NAME

XML::Compile::SOAP::Daemon::MojoUtil - Mojo helper routines

=chapter SYNOPSIS
  # used by ::Daemon::Mojo

=chapter DESCRIPTION
=cut

our @EXPORT = qw(
    mojo_action_from_header
    mojo_add_header
    mojo_make_response
    mojo_run_request
    mojo_wsdl_response
);

use Log::Report 'xml-compile-soap-daemon';
use XML::Compile::SOAP::Util qw/:daemon/; # MSEXT
use List::Util qw/any pairs first/;
use HTTP::Status qw/RC_OK RC_METHOD_NOT_ALLOWED RC_NOT_ACCEPTABLE/;

sub mojo_add_header($$@);
sub mojo_run_request($$;$);
sub mojo_make_response($$$$;$);
sub mojo_action_from_header($);

=chapter FUNCTIONS

=function mojo_add_header $field, $content, ...
=cut

our @default_headers;
BEGIN
{   no strict 'refs';
    @default_headers = (
        map {
            eval "require $_";
            my $version = ${"${_}::VERSION"} || 'undef';
            (my $field = "X-${_}-Version") =~ s/\:\:/-/g;
            $field => $version
        } qw/
            XML::Compile 
            XML::Compile::SOAP
            XML::Compile::SOAP::Daemon 
            XML::LibXML 
            Mojolicious
        /
    );
}

sub mojo_add_header($$@) { push @default_headers, @_ }

=function mojo_make_response $req, $status, $msg, $body, [$postproc]

Make a M<Mojo::Message::Response> matching given params, and optionally make 
callback to C<$postproc> along with given M<Mojo::Message::Request> object.
=cut

sub mojo_make_response($$$$;$)
{   my ($req, $status, $msg, $body, $postproc) = @_;

    my $res = Mojo::Message::Response->new;
    $res->code($status);
    $res->message($msg);
    $res->headers->add(@$_) for pairs @default_headers; 

    my $s;
    if(UNIVERSAL::isa($body, 'XML::LibXML::Document'))
    {   $s = $body->toString($status == RC_OK ? 0 : 1);
        $res->headers->content_type('text/xml; charset=utf-8');
    }
    else
    {   $s = "[$status] $body";
        $res->headers->content_type('text/plain');
    }

    # do any post processing
    $postproc->($req, $res, $status, \$s) if $postproc;

    $res->body($s);

    if(substr($req->method, 0, 2) eq 'M-')
    {   # HTTP extension framework.  More needed?
        $res->headers->add(Ext => '');
    }

    return $res;
}

=function mojo_action_from_header $req

Collect the soap action URI from the request, with C<undef> on failure.

Officially, the "SOAPAction" has no other purpose than the ability to
route messages over HTTP: it should not be linked to the portname of
the message (although it often can).
=cut

sub mojo_action_from_header($)
{   my ($req) = @_;

    my $action;
    if($req->method eq 'POST')
    {   $action = $req->headers->header('SOAPAction');
    }
    elsif($req->method eq 'M-POST')
    {   # Microsofts HTTP Extension Framework
        my $http_ext_id = '"' . MSEXT . '"';
        my $man = first { m/\Q$http_ext_id\E/ } $req->headers->header('Man')//'';
        defined $man or return undef;

        $man =~ m/\;\s*ns\=(\d+)/ or return undef;
        $action = $req->headers->header("$1-SOAPAction");
    }

    defined $action or return;

    $action =~ s/["'\s]//g;  # often wrong blanks and quotes
    return $action;
}

=function mojo_wsdl_response [$wsdlfile|$response] [$mime_type]

Sets WSDL query responses. Response is M<Mojo::Message::Response> object.

Takes either an existing response object or a C<$wsdlfile> and optional 
C<$mime_type> from which to build a response.
=cut

my $wsdl_response;
sub mojo_wsdl_response(;$$)
{   @_ or return $wsdl_response;

    my ($fn, $mime_type) = @_;

    return ($wsdl_response = $fn) unless $fn && !ref $fn;

    local *SRC;
    open SRC, '<:raw', $fn
        or fault __x"cannot read wsdl file {file}", file => $fn;
    local $/;
    my $spec = <SRC>;
    close SRC;

    $mime_type ||= 'application/wsdl+xml';
    my $res = Mojo::Message::Response->new;
    $res->code(RC_OK);
    $res->message("WSDL specification");
    $res->headers->add(@$_) for pairs @default_headers;
    $res->headers->content_type("$mime_type; charset=utf-8");
    $res->body($spec);
    return ($wsdl_response = $res);
}
    
=function mojo_run_request $req, $handler, [$postproc]

Handle one $req (M<Mojo::Message::Request> object).

Call the C<$handler> callback with request, xml to process and action when a
valid looking request was found.

Call the C<$postproc> callback with the M<Mojo::Message::Response> object, once
a response has been built.
=cut

sub mojo_run_request($$;$)
{   my ($req, $handler, $postproc) = @_;

    # check

    if ($wsdl_response
        && $req->method eq 'GET' 
        && any { uc($_->[0]) eq 'WSDL' } pairs @{$req->url->query->pairs})
    {   # request for WSDL
        return $wsdl_response;
    }

    if($req->method !~ m/^(?:M-)?POST/ )
    {   # bad HTTP method
        return mojo_make_response(
            $req, 
            RC_METHOD_NOT_ALLOWED, 
            'only POST or M-POST', 
            "attempt to connect via ".$req->method,
        );
    }

    my $media = $req->headers->content_type || 'text/plain';

    if ($media !~ m{/xml(?:;|$)}i)
    {   # bad Content-Type
        return mojo_make_response(
            $req, 
            RC_NOT_ACCEPTABLE, 
            'required is XML', 
            "content-type seems to be $media, must be some XML",
        );
    }

    my $action = mojo_action_from_header($req);
    my $xmlin  = $req->text;

    # process 

    my ($status, $msg, $xml) = eval { $handler->(\$xmlin, $req, $action); }; 
    info __x"connection ended with force; {error}", error => $@ if $@;

    # return response

    return mojo_make_response($req, $status, $msg, $xml, $postproc);
}

#------------------------------
=chapter DETAILS

=section Postprocessing responses

The C<Mojolicious> based daemons provide a C<$postprocess> option to their 
C<run()> methods.  The parameter is a CODE reference.

When defined, the CODE is called when the response message is ready
to be returned to the client:

  $code->($req, $res, $status, \$body)

The source C<$req> is passed as first parameter. The C<$res>
is an M<Mojo::Message::Response> object, with all headers but without the body.
The C<$status> is the result code of the handler. A value of 200 (C<HTTP_OK> 
from C<HTTP::Status>) indicates successful processing of the request. When the 
status is not HTTP_OK you may skip the postprocessing.

The C<$body> are the bytes which will be added as body to the response
after this postprocessing has been done. You may change the body.

=cut

1;

