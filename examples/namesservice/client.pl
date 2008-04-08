#!/usr/bin/perl
# Client which demonstrates the functionality of the server.  First start
# the server, and then call the client:
#     ./server.pl --verbose=2
#     ./client.pl

# This scripts shows 3 SOAP calls which are defined via a WSDL, and
# one which is created by hand.

# This file is also included as example in the XML::Compile::SOAP
# distribution.  There, rpc-literal, rpc-encoded and shorter versions
# are shown as well.


# Thanks to Thomas Bayer, for providing this example service
#    See http://www.thomas-bayer.com/names-service/

# Author: Mark Overmeer, April 7 2008
# Using:  XML::Compile               0.73
#         XML::Compile::SOAP         0.69
#         XML::Compile::SOAP::Daemon 0.10 (initial version)
# Copyright by the Author, under the terms of Perl itself.
# Feel invited to contribute your examples!

# Of course, all Perl programs start like this!
use warnings;
use strict;

# constants, change this if needed (also in the server script)
use constant SERVERHOST => 'localhost';
use constant SERVERPORT => '8877';

# we need to redirect the endpoint as specified in the WSDL to our
# own server.
my $service_address = 'http://'.SERVERHOST.':'.SERVERPORT;

# To make Perl find the modules without the package being installed.
use lib '../../lib'   # clients do not need this server implementation
      , '.';

use lib '../../../XMLCompile/lib'   # my home test environment
      , '../../../XMLSOAP/lib'      #    please ignore all three.
      , '../../../LogReport/lib';

# All the other XML modules will be included automatically.
use XML::Compile::WSDL11;
use XML::Compile::Transport::SOAPHTTP;

# Only needed because we implement a message outside the WSDL
use XML::Compile::SOAP11::Client;

# Other useful modules
use Data::Dumper;          # Data::Dumper is your friend.
$Data::Dumper::Indent = 1;

use Log::Report   'example', syntax => 'SHORT';
use Getopt::Long  qw/:config no_ignore_case bundling/;
use List::Util    qw/first/;

my $format_list;
format =
   ^<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<~~
   $format_list
.

# Forward declarations
sub show_trace($$);
sub get_countries();
sub get_name_info();
sub get_names_in_country();
sub get_name_count();

#### MAIN

#
# Some standard command-line processing
#

my $mode = 0;

GetOptions
 # 3 ways to set the verbosity for Log::Report dispatchers
   'v+'        => \$mode  # -v -vv -vvv
 , 'verbose=i' => \$mode  # --verbose=2  (0..3)
 , 'mode=s'    => \$mode  # --mode=DEBUG (DEBUG,ASSERT,VERBOSE,NORMAL)
   or die "stopped\n";

error __x"No filenames expected on the command-line"
   if @ARGV;

# XML::Compile::* uses Log::Report.
dispatcher PERL => 'default', mode => $mode;

#
# For nice user interaction; nothing to do with SOAP
#

use Term::ReadLine;
my $term = Term::ReadLine->new('namesservice');

#
# Let all calls share the transport object
# If you need an SSL connection, or other complex transport configuration,
# you can provide your own preconfigured user_agent (LWP::UserAgent object).
#

my $transporter = XML::Compile::Transport::SOAPHTTP->new
  ( address    => $service_address
# , user_agent => ...
  );
my $http = $transporter->compileClient;

#
# Get the WSDL and Schema definitions
#

my $wsdl = XML::Compile::WSDL11->new('namesservice.wsdl');
$wsdl->schemas->importDefinitions('namesservice.xsd');

#
# Pick one of these tests
#

my $answer = '';
while(lc $answer ne 'q')
{
    print <<__SELECTOR;

    Which call do you like to see:
      1) getCountries
      2) getNameInfo
      3) getNamesInCountry
      4) getNameCount, not defined by WSDL
      Q) quit demo
__SELECTOR

    print <<__HELP unless $mode;
    (Run this script with -v to get some stats.  -vvv shows much more)
__HELP
    print "\n";

    $answer = $term->readline("Pick one of above [1/2/3/4/Q] ");
    chomp $answer;

       if($answer eq '1') { get_countries() }
    elsif($answer eq '2') { get_name_info()  }
    elsif($answer eq '3') { get_names_in_country() }
    elsif($answer eq '4') { get_name_count() }
    elsif(lc $answer ne 'q' && length $answer)
    {   print "Illegal choice\n";
    }
}

exit 0;

sub show_trace($$)
{   my ($answer, $trace) = @_;
    $mode > 0 or return;

    $trace->printTimings;
    $trace->printRequest;
    $trace->printResponse;

    print Dumper $answer
        if $mode > 1;
}

#
# procedure getCountries
#

sub get_countries()
{   my $getCountries = $wsdl->compileClient
      ( 'getCountries'
      , transport => $http
      );

    my ($answer, $trace) = $getCountries->();
    show_trace $answer, $trace;

    if(my $fault_raw = $answer->{Fault})
    {   my $fault_nice = $answer->{$fault_raw->{_NAME}};
        warn "Cannot get list of countries: $fault_nice->{reason}\n";
        return;
    }

    my $countries = $answer->{parameters}{country} || [];

    print "getCountries() lists ".scalar(@$countries)." countries:\n";
    foreach my $country (sort @$countries)
    {   print "   $country\n";
    }
}

#
# Second example
#

sub get_name_info()
{
    my $name = $term->readline("Personal name for info: ");
    chomp $name;

    length $name or return;

    my $getNameInfo = $wsdl->compileClient
      ( 'getNameInfo'
      , transport => $http
      );

    my ($answer, $trace) = $getNameInfo->(name => $name);
    show_trace $answer, $trace;

    if($answer->{Fault})
    {   warn "Lookup for '$name' failed: $answer->{Fault}{faultstring}\n";
        return;
    }

    my $nameinfo = $answer->{parameters}{nameinfo};
    print "The name '$nameinfo->{name}' is\n";
    print "    male: ", ($nameinfo->{male}   ? 'yes' : 'no'), "\n";
    print "  female: ", ($nameinfo->{female} ? 'yes' : 'no'), "\n";
    print "  gender: $nameinfo->{gender}\n" if $nameinfo->{gender};
    print "and used in countries:\n";

    my $countries = $nameinfo->{countries}{country} || [];
    $format_list = join ', ', @$countries;
    write;
}

#
# Third example
#

sub get_names_in_country()
{
    my $getCountries      = $wsdl->compileClient
      ( 'getCountries'
      , transport => $http
      );

    my $getNamesInCountry = $wsdl->compileClient
     ( 'getNamesInCountry'
     , transport  => $http
     );

    my ($answer1, $trace1) = $getCountries->();
    show_trace $answer1, $trace1;

    if($answer1->{Fault})
    {   warn "Cannot get countries: $answer1->{Fault}{faultstring}\n";
        return;
    }

    my $countries = $answer1->{parameters}{country};

    my $country;
    while(1)
    {   $country = $term->readline("Most common names in which country? ");
        chomp $country;
        $country eq '' or last;
        print "  please specify a country name.\n";
    }

    # find the name case-insensitive in the list of available countries
    my $name = first { /^\Q$country\E$/i } @$countries;

    unless($name)
    {   $name = 'other countries';
        print "Cannot find name '$country', defaulting to '$name'\n";
        print "Available countries are:\n";
        $format_list = join ', ', @$countries;
        write;
    }

    print "Most common names in $name:\n";
    my ($answer2, $trace2) = $getNamesInCountry->(country => $name);
    show_trace $answer2, $trace2;

    if($answer2->{Fault})
    {   warn "Cannot get names in country: $answer2->{Fault}{faultstring}\n";
        return;
    }

    my $names    = $answer2->{parameters}{name};
    unless($names)
    {   warn "No data available for country `$name'\n";
        return;
    }

    $format_list = join ', ', @$names;
    write;
}

#
# This next example demonstrates how to use SOAP without WSDL
#

sub get_name_count()
{
    ### if you execute the following lines in the initiation phase of
    # your program, you can reuse it.  For clarity of the demo, all
    # initiations are made in this unusual spot.
    #
    use MyExampleCalls;
    $wsdl->importDefinitions($_) for @my_additional_schemas;

    my $soap11 = XML::Compile::SOAP11::Client->new(schemas => $wsdl->schemas);
    my $encode = $soap11->compileMessage(SENDER   => @get_name_count_input);
    my $decode = $soap11->compileMessage(RECEIVER => @get_name_count_output);

    # you could use the $http object, defined earlier, to share the
    # connection, but this is more fun ;-)
    my $send   = $transporter->compileClient
      ( soap      => $soap11
      , action    => '#getNameCount' # optional soapAction in HTTP header
      );

    my $getNameCount = $soap11->compileClient
      ( name      => 'getNameCount'  # symbolic name only for trace and errors
      , encode    => $encode
      , decode    => $decode
      , transport => $send
      );
    #
    ### end of re-usable structures

    my $country;
    while(1)
    {   $country = $term->readline("Number of names in which country? ");
        chomp $country;
        $country eq '' or last;
        print "  please specify a country name.\n";
    }

    my ($answer, $trace) = $getNameCount->(request => {country => $country});
    show_trace $answer, $trace;

    if($answer->{Fault})
    {   warn "Cannot get names in country: $answer->{Fault}{faultstring}\n";
        return;
    }

    print "Country $country has $answer->{answer}{count} names defined\n";
}
