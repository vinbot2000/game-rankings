package Factor;
use strict;

my $index = 0;

# """ Base class for a factor node in the factor graph. """
sub new {
	my $class = shift;
	
	my $variables = shift;
	
	my $self = {
		variables => $variables,
		index => $index
	};
	$index++;
	
	bless $self, $class;
	
	foreach my $variable (@$variables){
		$variable->AttachFactor($self);
	}
	
	# my $index = $self->toString();
	# print "\nCreated factor $class " . "[$index]";

	return($self);
}

sub toString
{
	my $self = shift;
	return $self->{index};
}

1;