#!/usr/bin/perl
# Framework for a Daemon based on Mojolicious

use warnings;
use strict;

my $VERSION = "0.01";

use Log::Report 'mojo-example';

use XML::Compile::SOAP::Daemon::Mojo;
use XML::Compile::WSDL11;      # use WSDL version 1.1
use XML::Compile::SOAP11;      # use SOAP version 1.1
use XML::Compile::Schema ();
use XML::Compile::Util qw/pack_type/;

use Mojo::Log;
use Getopt::Long   qw/:config no_ignore_case bundling/;
use File::Basename qw/basename/;
use HTTP::Status   qw/:constants/;

my $wsdl_fn = 'web_service_desc.wsdl';

my %wsdl = (
    'http://example.domain.com/mojo-example/' => $wsdl_fn,
);

# dispatcher callback with Mojo::Log

my $log = Mojo::Log->new;

my %log = (
    TRACE => sub { $log->debug(@_) },
    ASSERT => sub { $log->error(@_) },
    INFO => sub { $log->info(@_) },
    NOTICE => sub { $log->info(@_) },
    WARNING => sub { $log->warn(@_) },
    MISTAKE => sub { $log->warn(@_) },
    ERROR => sub { $log->error(@_) },
    FAULT => sub { $log->error(@_) },
    ALERT => sub { $log->warn(@_) },
    FAILURE => sub { $log->fatal(@_) },
    PANIC => sub { $log->fatal(@_) },
);

sub log {
    my ($disp, $options, $reason, $message) = @_;
    chomp(my $text = $disp->translate($options, $reason, $message))
        or return;
    $log{$reason}->($text);
    1;
}

# Forward declarations
sub do_something($$$);

##
#### MAIN
##

my $mode = 2;

my $cert = "my_cert.pem";
my $key = "my_key.pem";

my %options = (
    port => 1234,
    host => 'localhost',
);

GetOptions
   'v+'          => \$mode  # -v -vv -vvv
 , 'verbose=i'   => \$mode  # --verbose=2  (0..3)
 , 'mode=s'      => \$mode  # --mode=DEBUG (DEBUG,ASSERT,VERBOSE,NORMAL)

 , 'port|p=i'    => \$options{port} # --port=444
 , 'host|h=s'    => \$options{host} # --host=localhost
   or error "Deamon is not started";

error __x"No filenames expected on the command-line"
    if @ARGV;

my %runopt =
  ( name        => basename($0)
  , listen      => [
      "https://$options{host}:$options{port}?reuse=1&cert=$cert&key=$key"
  ],
  , server_name => 'mojo-example',
  );

my $debug = $mode==3;

# log to Mojo::Log
dispatcher close         => 'default';
dispatcher CALLBACK      => 'cb',
           callback      => \&log,
           mode          => $mode,
           format_reason => 'IGNORE';

use XML::Compile ();
XML::Compile->addSchemaDirs("schemas/");
XML::Compile->knownNamespace(%wsdl);

my $daemon = XML::Compile::SOAP::Daemon::Mojo->new;
my $wsdl   = XML::Compile::WSDL11->new;

$wsdl->addWSDL($_) for keys %wsdl;

$wsdl->namespaces->printIndex;

$daemon->operationsFromWSDL
  ( $wsdl
  , callbacks => { 'DoUpdate' => \&do_update }
  );

# set response to http://example.domain.com/mojo-example/?wsdl
$daemon->setWsdlResponse("schemas/$wsdl_fn");

# now start the daemon to handle requests
info "starting daemon";

$daemon->run(%runopt);

info "Daemon stopped";

exit 0;

### implement your callbacks here

sub do_update($$$)
{   my ($server, $datain, $req) = @_;

    my $my_err_ns = "https://$options{host}:$options{port}/err";

    if ((my $name = $datain->{Name}) ne $allowed) {
        return
        { Fault =>
             { faultcode   => pack_type($my_err_ns, 'Client.Unauthorized')
             , faultstring => "failed secure code for $name"
             , faultactor  => MY_ROLE
             }
          , _RETURN_CODE => HTTP_UNAUTHORIZED # 401
          , _RETURN_TEXT => 'Unauthorized'
          };
    }

    # this will end-up as answer at client-side
    return { Response => 'OK', Message => 'Completed OK' };
}
