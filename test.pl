#! /usr/bin/env perl

use v5.10;
use strict;
use warnings;

use Data::Dumper;
use Config::Simple;
use Time::Piece;
use Parallel::ForkManager;
use FindBin;
use lib "$FindBin::Bin/lib";
use Magister;

my %config;
Config::Simple->import_from("$FindBin::Bin/test.cfg",\%config) or die("No config: $!");
#print Dumper \%config;

my $session = Magister->new(
    'user'          => $config{'MAGISTER_USER'},
    'secret'        => $config{'MAGISTER_SECRET'},
    'endpoint'      => $config{'MAGISTER_URL'},
    'lesperiode'   => $config{'MAGISTER_LESPERIODE'}
);




# Eerst eens sequentieel opvragen
my $sec_result;
my $sec_start = localtime->epoch;
if ($session->_get_access_token){
    say "Docenten ophalen";
    my $docenten = $session->getDocenten();
    #print Dumper $docenten;
    #say scalar keys %{$docenten};
    while (my($upn, $docent) = each %{$docenten}){
        #say $docent->{'naam'};
        my $doc_vakken = $session->getRooster($docent->{'stamnr'},"GetPersoneelGroepVakken");
        $sec_result->{$upn} = (scalar keys %{$doc_vakken})." groepen";
    } 
    say " done";
}
my $sec_einde = localtime->epoch;
my $sec_duur = $sec_einde - $sec_start;
#print Dumper $sec_result;
say "Sequentieel duurt $sec_duur seconden";

# Dan parallel (omschrijft het beter dan async)

# Uitproberen met een aantal max processes, kantlpunt lijkt 20 -40 te zijn
my @maxen = qw(5 10 20 30 40);
foreach my $max (@maxen){
    say "Run met max process op $max, eerst een sleep 60";
    sleep 60;
    say "gaat ie";
    my $par_result;
    my $par_aantal_docenten;
    my $par_start = localtime->epoch;
    if ($session->_get_access_token){
        say "Docenten ophalen";
        my $docenten = $session->getDocenten();
        #print Dumper $docenten;
        $par_aantal_docenten = scalar keys %{$docenten};

        my $pm = Parallel::ForkManager->new($max, "$FindBin::Bin/".$config{'CACHE_DIR'}."/");

        # Callback
        $pm->run_on_finish( sub{
            my ($pid,$exit_code,$ident,$exit,$core_dump,$vakken) = @_;
            # say "Dit is run_on_finish";
            # say "PID: ",$pid;
            # say "ExitCode: ",$exit_code;
            # say "ident: ",$ident;
            # say "Exit: ",$exit;
            # say "CoreDump: ",$core_dump;
            # say "Rooster voor $ident";
            # print Dumper $vakken;
            $par_result->{$ident} = scalar keys %{$vakken};
        });

        ROOSTER:
        while (my($upn, $docent) = each %{$docenten}){
            my $pid = $pm->start($upn) and next ROOSTER; # FORK
            my $doc_vakken = $session->getRooster($docent->{'stamnr'},"GetPersoneelGroepVakken");
            # De eerste waarde in finish is de exit_code, de twee de data reference
            $pm->finish(23,$doc_vakken); # exit child
        } 
        $pm->wait_all_children;
        say " done";
    }
    my $par_einde = localtime->epoch;
    my $par_duur = $par_einde - $par_start;
    #print Dumper $par_result;
    say "Parallel duurt $par_duur seconden";
    say "Docenten opgehaald: $par_aantal_docenten";
    say "Docenten in result: ". scalar keys %{$par_result};
}