package SumFactor;
use strict;
BEGIN {
    our @ISA = ("Factor");
    # require Factor;
}

  #""" A factor that connects a sum variable with 1 or more terms,
  #which are summed after being multiplied by fixed (real)
  #coefficients. """

sub new
{
	my $class = shift;
	my $sum_variable = shift;
	my $terms_variables = shift;
	my $coeffs = shift;
	

	# super(SumFactor, self).__init__([sum_variable] + terms_variables)
	# is this correct?
	my $self = $class->SUPER::new([($sum_variable), @$terms_variables]);	
	
    # assert len(terms_variables) == len(coeffs)
    $self->{sum} = $sum_variable;
    $self->{terms} = $terms_variables;
    $self->{coeffs} = $coeffs;	
	
	# print "\nSum new: sum[@$sum_variable], terms[@$terms_variables],";
	
	return $self;
}
    

sub _InternalUpdate
{	
	
	my $self = shift;
	#my $index = $self->toString();
	#print "\nSumFactor::_InternalUpdate[$index]";
	my $var = shift;
	my $y = shift;
	my $fy = shift;
	my $a = shift;
	

	my $total_pi = 0;
	my $total_tau = 0;
	for my $j(0..scalar(@$a)-1) {
		my $var = $a->[$j];
		my $numer = $var**2;
		
		#if($var =~ /-/ && $numer != /-/){
		#	$numer *= -1;
		#}
		
		#print "\n_InternalUpdate: $numer, $y->[$j]->{pi}, $fy->[$j]->{pi}, $y->[$j]->{tau}, $fy->[$j]->{tau}";
		
		$total_pi += ($numer / ($y->[$j]->{pi} - $fy->[$j]->{pi}));
		$total_tau += $var * ($y->[$j]->{tau} - $fy->[$j]->{tau}) / ($y->[$j]->{pi} - $fy->[$j]->{pi});
	}	
	
	#print "\ntotal_pi[$total_pi], total_tau[$total_tau]";
	
	my $new_pi = 0;
	#if($total_pi != 0 ) {
		$new_pi = 1.0 / $total_pi;
	#}
	my $new_tau = $new_pi * $total_tau;	
	
	#print "\n_InternalUpdate: new_pi[$new_pi], new_tau[$new_tau]";
	
	$var->UpdateMessage($self, new Gaussian(undef, undef, $new_pi, $new_tau));
}

sub UpdateSum {
	my $self = shift;
	
	#my $index = $self->toString();
	#print "\nSumFactor::UpdateSum[$index]";
    
	# """ Update the sum value ("down" in the factor graph). """
	
	my @y;
	my @fy;
	foreach my $term (@{$self->{terms}}) {
		push(@y, $term->{value});
		push(@fy, $term->GetMessage($self));
	}
    my $a = $self->{coeffs};
    $self->_InternalUpdate($self->{sum}, \@y, \@fy, $a);
}

sub UpdateTerm {

	my $self = shift;
	#my $index = $self->toString();
	#print "\nSumFactor::UpdateTerm[$index]";
	my $index = shift;
    #""" Update one of the term values ("up" in the factor graph). """

    # Swap the coefficients around to make the term we want to update
    # be the 'sum' of the other terms and the factor's sum, eg.,
    # change:
    #
    #    x = y_1 + y_2 + y_3
    #
    # to
    #
    #    y_2 = x - y_1 - y_3
    #
    # then use the same update equation as for UpdateSum.

    my $b = $self->{coeffs};
	
	my @a;
	for my $i(0..scalar(@$b)-1){
		if($i != $index ){
			push(@a, (-1*$b->[$i] / $b->[$index]));
		} else {
			push(@a, 1.0 / $b->[$index]);
		}
	}	

    my @v = @{ $self->{terms} }; # copy array
    $v[$index] = $self->{sum};
	
	my @y;
	my @fy;
	foreach my $i (@v) {
		push(@y, $i->{value});
		push(@fy, $i->GetMessage($self));
	}
    $self->_InternalUpdate($self->{terms}[$index], \@y, \@fy, \@a);
}

1;