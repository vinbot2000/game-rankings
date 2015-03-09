package TruncateFactor;
use strict;
BEGIN {
    our @ISA = ("Factor");
    #require Factor;
}
  # A factor for (approximately) truncating the team difference
  #distribution based on a win or a draw (the choice of which is
  #determined by the functions you pass as V and W). """

sub new
{
	my $class = shift;
	my $variable = shift;
	my $V = shift;
	my $W = shift;
	my $epsilon = shift;
	

	# super(TruncateFactor, self).__init__([variable])
	my $self = $class->SUPER::new([$variable]);

    $self->{var} = $variable;
    $self->{V} = $V;
    $self->{W} = $W;
    $self->{epsilon} = $epsilon;
	
	return $self;
}

sub Update
{
	my $self = shift;
	
	#my $index = $self->toString();
	#print "\nTruncateFactor::Update[$index]";
	
    my $x = $self->{var}->{value};
    my $fx = $self->{var}->GetMessage($self);

	#print "\nTruncateFactor::Update: value[" . $x->toString() . "], message[" . $fx->toString() . "]";
	
    my $c = $x->{pi} - $fx->{pi};
    my $d = $x->{tau} - $fx->{tau};
    my $sqrt_c = sqrt($c);
	
	#print "\nc[$c], d[$d], sqrtc[$sqrt_c]";
	
    my @args = ($d / $sqrt_c, $self->{epsilon} * $sqrt_c);
    my $V = $self->{V}(@args);
    my $W = $self->{W}(@args);
    my $new_val = new Gaussian(undef, undef, $c / (1.0 - $W), ($d + $sqrt_c * $V) / (1.0 - $W));
    $self->{var}->UpdateValue($self, $new_val);
}

1;