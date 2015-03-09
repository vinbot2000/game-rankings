package LikelihoodFactor;
use strict;
use Gaussian;

BEGIN {
    our @ISA = ("Factor");
    require Factor;
}

 # """ Connects two variables, the value of one being the mean of the
 # message sent to the other. """
sub new
{
	my $class = shift;
	my $mean_variable = shift;
	my $value_variable = shift;
	my $variance = shift;
	
	#my $self;
	#$self->{mean} = 0;
	#bless $self, $class;
	
	my $self = $class->SUPER::new([$mean_variable, $value_variable]);

	$self->{mean} = $mean_variable;
	$self->{value} = $value_variable;
	$self->{variance} = $variance;	
	
	return $self;
}

sub UpdateValue
{	
	my $self = shift;
	#my $index = $self->toString();
	#print "\nLikelihoodFactor::UpdateValue[$index]";
#    """ Update the value after a change in the mean (going "down" in
    #the TrueSkill factor graph. """
    my $y = $self->{mean}->{value};
    my $fy = $self->{mean}->GetMessage($self);
    my $a = 1.0 / (1.0 + $self->{variance} * ($y->{pi} - $fy->{pi}));
		
	my $pi = $a*($y->{pi} - $fy->{pi});
	my $tau = $a*($y->{tau} - $fy->{tau});
	#print "\nLikelihood Factor: $a, $pi, $tau";
    $self->{value}->UpdateMessage($self, new Gaussian(undef, undef, $pi, $tau));
}

sub UpdateMean
{
	my $self = shift;
	#my $index = $self->toString();
	#print "\nLikelihoodFactor::UpdateMean[$index]";
 #   """ Update the mean after a change in the value (going "up" in
    #the TrueSkill factor graph. """

    # Note this is the same as UpdateValue, with $self->mean and
    # $self->value interchanged.
    my $x = $self->{value}->{value};
    my $fx = $self->{value}->GetMessage($self);
    my $a = 1.0 / (1.0 + $self->{variance} * ($x->{pi} - $fx->{pi}));
    $self->{mean}->UpdateMessage($self, new Gaussian(undef, undef, $a*($x->{pi} - $fx->{pi}), $a*($x->{tau} - $fx->{tau})));
}

1;