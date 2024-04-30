#! /usr/bin/env perl

use v5.10;
use strict;
use warnings;

use Data::Dumper;
use Config::Simple;
use FindBin;
use lib "$FindBin::Bin/lib";
use Magister;

my %config;
Config::Simple->import_from("$FindBin::Bin/test.cfg",\%config) or die("No config: $!");
#print Dumper \%config;

my $session = Magister->new(
    'user'          => $config{'MagUser'},
    'secret'        => $config{'MagSecret'},
    'endpoint'      => $config{'MagSite'},
    'lesperiode'   => $config{'MagLesPeriode'}
);



if ($session->_get_access_token){
    say $session->_get_access_token;
    # say "Docenten ophalen";
    # my $docenten = $session->getDocenten();
    # print Dumper $docenten;
     my $doc_vakken = $session->getRooster("124329","GetPersoneelGroepVakken"); #Sonja
    # my $doc_vakken = $session->getRooster("115019","GetPersoneelGroepVakken"); #Angele => administratie
     print Dumper $doc_vakken;
    #my $lln = $session->getLLN();
    #print Dumper $lln;
    #my $lln_vakken = $session->getRooster("133941","GetLeerlingGroepen"); # Luuk V6 OSG (bovenbouw)
    my $lln_vakken = $session->getRooster("139266","GetLeerlingGroepen"); # Jenna H1 OSG (onderbouw)
    print Dumper $lln_vakken;
}