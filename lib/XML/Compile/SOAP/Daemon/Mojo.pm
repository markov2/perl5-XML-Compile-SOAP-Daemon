# This code is part of distribution XML-Compile-SOAP-Daemon.  Meta-POD
# processed with OODoc into POD and HTML manual-pages.  See README.md
# Copyright Mark Overmeer.  Licensed under the same terms as Perl itself.

package XML::Compile::SOAP::Daemon::Mojo;
package XML::Compile::SOAP::Daemon::Mojo::Log;

use Mojo::Base -base;
use Log::Report 'xml-compile-soap-daemon', import => []; # no function imports

my %level = (
    debug => \&Log::Report::trace,
    info  => \&Log::Report::info,
    warn  => \&Log::Report::warning,
    error => sub { eval { Log::Report::error(@_) } },   # non-fatal Mojo::Log
    fatal => sub { eval { Log::Report::failure(@_) } }, # non-fatal Mojo::Log
);

my $LR = 'Log::Report';
my $msg = 'method "{reason}" not implemented';

for (qw/
    format 
    handle
    history
    max_history_size
    path
    short
    append
    is_level
/) {
    eval "sub $_ { ${LR}::error(${LR}::__x('$msg', reason => '$_')) }"
}

for (qw/
    error 
    debug
    fatal
    info
    warn
/) {
    eval "sub $_ { my \$self = shift; \$level{$_}->(join \"\\n\", \@_); \$self }"
}

sub level {
    my ($self, $level) = @_;
    return $level 
        ? ($self->{level} = $level)
        : $self->{level};
}

1;
package XML::Compile::SOAP::Daemon::Mojo;

use warnings;
use strict;

use parent 'XML::Compile::SOAP::Daemon';

use Log::Report qw/xml-compile-soap-daemon/;
use Mojo::Server::Daemon;
use XML::Compile::SOAP::Daemon::MojoUtil;

=chapter NAME
XML::Compile::SOAP::Daemon::Mojo - SOAP server based on Mojo::Server::Daemon

=chapter SYNOPSIS
 #### have a look in the examples directory!
 use XML::Compile::SOAP::Daemon::Mojo;
 use XML::Compile::SOAP11;
 use XML::Compile::SOAP::WSA;  # optional

 my $daemon  = XML::Compile::SOAP::Daemon::Mojo->new;

 # daemon definitions from WSDL
 my $wsdl    = XML::Compile::WSDL11->new(...);
 $wsdl->importDefinitions(...); # more schemas
 $daemon->operationsFromWSDL($wsdl, callbacks => ...);

 # daemon definitions added manually (when no WSDL)
 my $soap11  = XML::Compile::SOAP11::Server->new(schemas => $wsdl->schemas);
 my $handler = $soap11->compileHandler(...);
 $daemon->addHandler('getInfo', $soap11, $handler);

 # see what is defined:
 $daemon->printIndex;

 # finally, run the server.  This never returns.
 $daemon->run(@daemon_options);
 
=chapter DESCRIPTION
This module handles the exchange of SOAP messages over HTTP with
M<Mojo::Server::Daemon> as daemon implementation based on the M<Mojolicious>
framework.

We use M<HTTP::Daemon> as HTTP-connection implementation. The
M<HTTP::Request> and M<HTTP::Response> objects (provided
by C<HTTP-Message>) are handled via functions provided by
M<XML::Compile::SOAP::Daemon::LWPutil>.

This abstraction level of the object (code in this pm file) is not
concerned with parsing or composing XML, but only worries about the
HTTP transport specifics of SOAP messages.  The processing of the SOAP
message is handled by the M<XML::Compile::SOAP::Daemon> base-class.

The server is as flexible as possible: accept M-POST (HTTP Extension
Framework) and POST (standard HTTP) for any message.  It can be used
for any SOAP1.1 and SOAP1.2 mixture.  Although SOAP1.2 itself is
not implemented yet.

=chapter METHODS

=c_method new %options
Create the server handler, which extends some class which implements
a M<Net::Server> daemon.

As %options, you can pass everything accepted by M<Any::Daemon::new()>,
like C<pid_file>, C<user>, C<group>, and C<workdir>,
=cut

sub new($%)
{   my ($class, %args) = @_;
    my $server_name = delete $args{server_name} || 'soap server';
    my $self = $class->SUPER::new(%args);
    $self->server_name($server_name);
    return $self;
}

sub server_name($;$)
{   my ($self, $server_name) = @_;
    return $server_name 
        ? ($self->{server_name} = $server_name)
        : $self->{server_name};
}

=method setWsdlResponse [$wdslfile|$response] [$mime_type]

Set response for WSDL:

  $scheme://$host:$port?wsdl

Takes either a prepaired response object M<Mojo::Message::Response>, or
C<$wsdlfile> and optionally C<$mime_type>.

Examples:

  $daemon->setWsdlResponse($res);
  $daemon->setWsdlResponse("soap_example.wsdl");
  $daemon->setWsdlResponse("soap_example.wsdl", "application/xml");
=cut

sub setWsdlResponse($;$)
{   my ($self, $fn, $ft) = @_;
    trace "setting wsdl response to $fn";
    mojo_wsdl_response($fn, $ft);
}

#-----------------------
=section Running the server

=method run %options

=option  server_name   STRING
=default server_name   C<undef>

=option  listen ARRAYREF
=default listen C<undef>

List of locations to listen on, see L<Mojo::Server::Daemon/listen>.

=option  postprocess CODE
=default postprocess C<undef>

See the section about this option in the DETAILS chapter of the
M<XML::Compile::SOAP::Daemon::MojoUtil> manual-page.
=cut

sub _run($)
{   my ($self, $args) = @_;

    mojo_add_header(Server => $self->server_name($args->{server_name}));

    my $postproc = $args->{postprocess};

    my $daemon = Mojo::Server::Daemon->new(listen => $args->{listen});

    # couple Mojo::Log to Log::Report
    $daemon->app->{log} = XML::Compile::SOAP::Daemon::Mojo::Log->new;

    $daemon->unsubscribe('request')->on(request => sub {
        my ($daemon, $tx) = @_;

        info __x"new client {remote}", remote => $tx->remote_address;

        # prepare for processing

        my $handler = sub { $self->process(@_) };
        my $req = $tx->req->default_charset('utf-8');
        my $res = mojo_run_request($req, $handler, $postproc);

        # build response

        $tx->res($res);
        $tx->resume;
    });

    $daemon->run;
}

sub url() { "url replacement not yet implemented" }
sub product_tokens() { shift->{prop}{name} } # TODO what?

#-----------------------------

=chapter DETAILS

=section Mojo with SSL

Accepts standard Mojo SSL options including C<cert>, C<key> and C<ca>, see 
L<Mojo::Server::Daemon/listen>.

  use Log::Report;
  use XML::Compile::SOAP::Daemon::Mojo;
  use XML::Compile::WSDL11;

  my $daemon = XML::Compile::SOAP::Daemon::Mojo->new;
  my $wsdl   = XML::Compile::WSDL11->new($wsdl);

  $daemon->operationsFromWSDL($wsdl, callbacks => \%handlers);

  requrie Net::SSLeay;
  my $verify = Net::SSLeay::VERIFY_PEER() 
             | Net::SSLeay::VERIFY_FAIL_IF_NO_PEER_CERT();

  my $listen = [
    "https://.*:443?reuse=1&cert=$cert&key=$key&ca=$ca&verify=$verify"
  ];

  $daemon->run
   ( name        => basename($0)
   , server_name => 'Custom SOAP Server',
   , listen      => $listen
   , postprocess => \&postprocess
   );
=cut

1;

