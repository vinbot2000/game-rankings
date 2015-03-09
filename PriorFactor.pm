# The following Factor classes implement the five update equations
# from Table 1 of the Herbrich et al. paper.

package PriorFactor;
use strict;
BEGIN {
    our @ISA = ("Factor");
    require Factor;
}
  #""" Connects to a single variable, pushing a fixed (Gaussian) value
  #to that variable. """

sub new {
	my $class = shift;
	my $variables = shift;
	my $param = shift;
	
	#my $self;
	#
	#bless $self, $class;
	
	my $self = $class->SUPER::new([$variables]);
	$self->{param} = $param;
	return($self);
}

sub Start {
	my $self = shift;
	
	#my $index = $self->toString();
	#print "\nPriorFactor::Start[$index]";
	
    $self->{variables}->[0]->UpdateValue($self, $self->{param});
}

1;