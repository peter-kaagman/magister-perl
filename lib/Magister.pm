package Magister;


use v5.11;

use Moose;
use LWP::UserAgent;
use JSON;
use Data::Dumper;
use Text::CSV qw( csv );
use utf8;

use Switch;

# Attributes {{{1
has 'access_token'   => ( # {{{2
	is => 'rw', 
	isa => 'Str',
	reader => '_get_access_token',
	writer => '_set_access_token',
); #}}}
has 'user'         => ( # {{{2
	is => 'ro', 
	isa => 'Str', 
	required => '1',
	reader => '_get_user',
	writer => '_set_user',
); #}}}
has 'secret'     => ( # {{{2
	is => 'ro', 
	isa => 'Str', 
	required => '1',
	reader => '_get_secret',
	writer => '_set_secret',
); #}}}
has 'endpoint' => ( # {{{2
	is => 'ro', 
	isa => 'Str', 
	required => '1',
	reader => '_get_endpoint',
	writer => '_set_endpoint',
); #}}}
has 'lesperiode' => ( # {{{2
	is => 'ro', 
	isa => 'Str', 
	required => '1',
	reader => '_get_lesperiode',
	writer => '_set_lesperiode',
); #}}}
has 'maxretry' => ( # {{{2
	is => 'ro', 
	isa => 'Str', 
	required => '1',
	default => '4',
	reader => '_get_maxretry',
	writer => '_set_maxretry',
); #}}}
has 'lasterror' => ( # {{{2
	is => 'ro', 
	isa => 'Str', 
	required => '0',
	default => '0',
	reader => '_get_errorstate',
	writer => '_set_errorstate',
); #}}}
has 'lastresult' => ( # {{{2
	is => 'ro', 
	isa => 'Str', 
	required => '0',
	reader => '_get_lastresult',
	writer => '_set_lastresult',
); #}}}
# }}}


sub BUILD{ #	{{{1
	my $self = shift;
	my $url = $self->_get_endpoint;
    $url .= "/?Library=Algemeen&Function=Login";
    $url .= '&Username='.$self->_get_user;
    $url .= '&Password='.$self->_get_secret;

	my $ua = LWP::UserAgent->new(
		'send_te' => '0',
	);
	my $r = HTTP::Request->new(
		POST => $url,
		[
			'Accept'		=>	'*/*',
			'User-Agent'	=>	'Perl LWP',
			'Content-Type'	=>	'application/x-www-form-urlencoded'
		],
	);

	my $result = $ua->request($r);
	#print Dumper $result;
	if ($result->is_success){
		if ($result->content =~ /.+SessionToken">(.+)<\/td>.+/) {
			$self->_set_access_token($1);
		}else{
			$result->content =~  /.+ResultMessage">(.+)<\/td>.+/;
			die "Error getting token: $1";
		}
	}else{
		die $result->status_line;
	}
}#	}}}

sub callAPI { # {{{1
	my $self = shift;
	my $url = shift;
	#print Dumper $self; exit 1;
	my $ua = LWP::UserAgent->new(
		'send_te' => '0',
	);
	my $header =	[
		'Accept'        => '*/*',
		'Content-Type'  => 'application/json; charset=utf-8 ',
		];
	my $r  = HTTP::Request->new(
		GET => $url,
		$header,
	);	

	my $try = 0;
	my $result;
	while ($try lt $self->_get_maxretry){
		$try++;
		$result = $ua->request($r);
		# Last if succes
		# or 404: not found (no retry needed)
		if (
				($result->is_success) ||
				($result->{'_rc'} eq 404)
		){
			last;
		}
	}
	if (! $result->is_success){
		say "try $try: $result->{'_rc'} $url ". $result->content unless ($result->{'_rc'} eq 404);
		$self->_set_errorstate($result->{'_rc'});
		$self->_set_lastresult($result->content);
	}
	return $result;
	#print Dumper $result;
} # }}}

#https://[url]/?library=ADFuncties&function=GetActiveEmpoyees&SessionToken=[SessionToken] &Type=[HTML/XML/CSV/TAB] <= niet langer in gebruik
#
# GetActiveEmpoyees (staat daar nu echt een tikfout in?) is niet geschikt voor het ophalen van docenten. Hierin ontbreekt informatie om een koppeling met Azure te kunnen maken.
# In plaats daarvan wordt gebruik gemaakt van een query "SDS-Medewerker". Hierin staat het werk email adres wat gebruikt kan worden als UPN.
#
#https://[url]/?library=Data&function=GetData&SessionToken=[SessionToken]&Layout=[Layout]&Parameters=[Parameters] &Type=[HTML/XML/CSV/TAB]
sub getDocenten {
	my $self = shift;
	my $url = $self->_get_endpoint;
	#$url .= "/?library=ADFuncties&function=GetActiveEmpoyees&Type=CSV&SessionToken=".$self->_get_access_token;
	$url .= "/?library=Data&function=GetData&Layout=SDS-Medewerker&Type=CSV&SessionToken=".$self->_get_access_token;
	my $result = callAPI($self,$url);
	if ($result->is_success){
		my $docenten = csv(
			in => \$result->content,
			headers => "auto",
			sep_char => ";",
			encoding => "UTF-8"
		);
		my $reply;
		foreach my $docent (@$docenten){
			#print Dumper $docent;
			#13 hash omgeboud naar index op upn
			# Uit dienst wordt aangegeven door een sterrje voor de 3-letter code
			# Email_werk zou de UPN moeten zijn
			my $upn = lc($docent->{'Email_werk'});
			$reply->{$upn}->{'naam'}	= $docent->{'Volledige_naam'};
			$reply->{$upn}->{'stamnr'}	= $docent->{"\x{feff}Stamnr"};
		};	
		return $reply;
	}else{
		print Dumper $result;
	}
}

#https://[url]/?library=ADFuncties&function=GetActiveStudents&SessionToken=[SessionToken]&LesPeriode=[LesPeriode] &Type=[HTML/XML/CSV/TAB]
#ToDo Hier wordt het koppelveld gemaakt tussen Magister en Azure, deze met de tijd configureerbaar maken
sub getLeerlingen {
	my $self = shift;
	my $url = $self->_get_endpoint;

	$url .= "/?library=ADFuncties&function=GetActiveStudents&Type=CSV&SessionToken=".$self->_get_access_token;
	$url .= "&LesPeriode=".$self->_get_lesperiode;
	my $result = callAPI($self,$url);
	my $leerlingen = csv(
		in => \$result->content,
		headers => "auto",
		sep_char => ";",
		encoding => "UTF-8"
	);
	my $reply;
	foreach my $lln (@$leerlingen){
		#print Dumper $lln;
		# Fabriceer een UPN, deze kan best ongeldig zijn.
		#say "stam nr",$lln->{"\x{feff}stamnr_str"};
		my $upn = 'b'. $lln->{"\x{feff}stamnr_str"}.'@atlascollege.nl';
		# controlle op de b ervoor
		# if ($upn !~ /^b.+/){$upn = 'b'.$upn; }
		$reply->{$upn}->{'naam'}	= $lln->{'Volledige_naam'};
		$reply->{$upn}->{'v_naam'}	= $lln->{'Roepnaam'};
		$reply->{$upn}->{'tv'}		= $lln->{'Tussenv'};
		$reply->{$upn}->{'a_naam'}	= $lln->{'Achternaam'};
		$reply->{$upn}->{'studie'}	= $lln->{'Studie'};
		$reply->{$upn}->{'stamnr'}	= $lln->{"\x{feff}stamnr_str"};
		$reply->{$upn}->{'klas'}	= $lln->{'Klas'};
		$lln->{'Studie'} =~ /^([0-9]).*/;
		$reply->{$upn}->{'locatie_index'}	= $1;
		# $reply->{$upn}->{'_locatie'}	= $lln->{'Administratieve_eenheid.Omschrijving'}; #locatie is onbetrouwbaar alleen geldig als er ook een klas is
		# Rest van de data wordt nergens gebruikt
		#$reply->{$lln->{"\x{feff}stamnr_str"}}->{'naam'} 		= $lln->{'Volledige_naam'};
		#$reply->{$lln->{"\x{feff}stamnr_str"}}->{'studie'} 	= $lln->{'Studie'};
		#$reply->{$lln->{"\x{feff}stamnr_str"}}->{'b_nummer'} 	= lc($lln->{'Loginaccount.Naam'});
		#$reply->{$lln->{"\x{feff}stamnr_str"}}->{'locatie'} 	= $lln->{'Administratieve_eenheid.Omschrijving'};
		# $reply->{$docent->{"\x{feff}stamnr_str"}}->{'inlogcode'} 	= lc($docent->{'Code'});
		# $reply->{$docent->{"\x{feff}stamnr_str"}}->{'locatie'}		= $docent->{'Administratieve_eenheid.Omschrijving'};
		# $reply->{$docent->{"\x{feff}stamnr_str"}}->{'rol'} 			= $docent->{'Functie.Omschr'};
	};	
	return $reply;
}

#https://[url]/?library=ADFuncties&function=GetPersoneelGroepVakken&SessionToken=[SessionToken]&LesPeriode=[LesPeriode]&StamNr=[StamNr] &Type=[HTML/XML/CSV/TAB]
#https://[url]/?library=ADFuncties&function=GetLeerlingGroepen&SessionToken=[SessionToken]&LesPeriode=[LesPeriode]&StamNr=[StamNr] &Type=[HTML/XML/CSV/TAB]
#https://[url]/?library=ADFuncties&function=GetLeerlingVakken&SessionToken=[SessionToken]&LesPeriode=[LesPeriode]&StamNr=[StamNr] &Type=[HTML/XML/CSV/TAB]
sub getRooster{
	my $self = shift;
	my $stamnr = shift;
	my $function = shift;
	my $url = $self->_get_endpoint;
	$url .= "/?library=ADFuncties";
	$url .= "&function=".$function;
	$url .= "&Type=CSV&SessionToken=".$self->_get_access_token;
	$url .= "&LesPeriode=".$self->_get_lesperiode;
	$url .= "&StamNr=".$stamnr;
	my $result = callAPI($self,$url);

	my $groepvakken = csv(
		in => \$result->content,
		headers => "auto",
		sep_char => ";",
		encoding => "UTF-8"
	);
	my $reply;
	foreach my $vak (@$groepvakken){
		# Structuur is afhankelijk van de vraag
		switch($function){
			case "GetLeerlingGroepen" {
				$reply->{$vak->{'groep'}}->{'groepid'}	=  $vak->{'Lesgroep'};
			}
			case "GetLeerlingVakken" {
				#print Dumper $vak;
				$reply->{$vak->{'Vak'}}	=  'blaat';
			}
			case  "GetPersoneelGroepVakken" {
				$reply->{ $vak->{'Klas'}.'_'.$vak->{'Vak.Vakcode'}}->{'vak'} 	=  $vak->{'Vak.Omschrijving'};
				$reply->{ $vak->{'Klas'}.'_'.$vak->{'Vak.Vakcode'}}->{'code'}	=  $vak->{'Vak.Vakcode'};
				$reply->{ $vak->{'Klas'}.'_'.$vak->{'Vak.Vakcode'}}->{'klas'}	=  $vak->{'Klas'};
			}
		}
	}
	return $reply;
}


__PACKAGE__->meta->make_immutable;
42;
