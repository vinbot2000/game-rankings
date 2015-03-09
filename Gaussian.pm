package Gaussian;
use strict;
# use bignum a => 100;
sub new {

	my $class = shift;

	my $self;
	
	my $mu = shift;
	my $sigma = shift;
	my $pi = shift;
	my $tau = shift;	
 
    if(defined $pi){
	
	 # print "\nnew Gaussian: pi[$pi], tau[$tau]";
	
      $self->{pi} = $pi;
      $self->{tau} = $tau;
    } elsif(defined $mu){
      $self->{pi} = $sigma ** -2;
      $self->{tau} = $self->{pi} * $mu;
	  
	 # print "\nnew Gaussian: pi[$self->{pi}], tau[$self->{tau}], mu[$mu], sigma[$sigma]";
	  
    } else {
      $self->{pi} = 0;
      $self->{tau} = 0;
	  
	 # print "\nnew Gaussian: pi[0], tau[0]";
	}
	
	bless $self, $class;
}

sub toString 
{
	my $self = shift;
	my $str = "\"pi[$self->{pi}], tau[$self->{tau}]\"";
	return($str);
}

sub MuSigma
{
	my $self = shift;
    # """ Return the value of this object as a (mu, sigma) tuple. """
    if($self->{pi} == 0.0){
      return(0, undef);
    } else {
      return (($self->{tau} / $self->{pi}), sqrt(1/$self->{pi}));
	}
}

sub multiply {
	my $self = shift;
	my $other = shift;
	
	#my $first = $self->toString();
	#my $second = $other->toString();
	#print "\nGaussian multiply: $first x $second";
	
    return new Gaussian(undef, undef, $self->{pi}+$other->{pi}, $self->{tau}+$other->{tau});
}

sub divide {
	my $self = shift;
	my $other = shift;
	
	my $first = $self->toString();
	my $second = $other->toString();	
	#print "\nGaussian divide: $first x $second";
	
    return new Gaussian(undef, undef, $self->{pi}-$other->{pi}, $self->{tau}-$other->{tau});
}

1;