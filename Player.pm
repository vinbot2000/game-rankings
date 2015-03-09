package Player;
use strict;
sub new {

	my $class = shift;
	my $self;	
	$self->{mu} = -1;
	$self->{sigma} = -1;
	bless $self, $class;
}

1;