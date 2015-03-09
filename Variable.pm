package Variable;
use strict;
use Gaussian;

sub new
{
	my $class = shift;
	
	my $self = {
		value => new Gaussian(),
		factors => {}
	};
	
	bless $self, $class;
}

sub toString 
{
	my $self = shift;
	
	print "\nVariable Gaussian:" . $self->{value}->toString();
	
	print "\nVariable factors: ";
	foreach my $factor(@{$self->{factors}}) {
		print $factor->toString() . " ";
	}
}

sub AttachFactor {
	my $self = shift;
	my $factor = shift;
	$self->{factors}{$factor->toString()} = new Gaussian();
}

sub UpdateMessage
{	
	my $self = shift;
	my $factor = shift;
	my $message = shift;
	
	# self.value = self.value / old_message * message
	
	#print "\nVariable::UpdateMessage: oldMessage=" . $self->{factors}{$factor->toString()}->toString() . ", newMessage=" . $message->toString();
	
    my $old_message = $self->{factors}{$factor->toString()};
	
	my $first = $self->{value}->divide($old_message);		
	#my $denom = $old_message->multiply($message);
	my $result = $first->multiply($message);
	
	
	#print "\nNumerator: " . $self->{value}->toString();
	#print "\nDenominator: " . $first->toString();
	#print "\nResult: " . $result->toString();
	
	#print "\nVariable::UpdateValue: oldValue=" . $self->{value}->toString() . ", newValue=" . $result->toString();
	$self->{value} = $result;
	
    #$self->{value} = $self->{value} / $old_message * $message;
    $self->{factors}{$factor->toString()} = $message;
}

sub UpdateValue
{	
	my $self = shift;
	my $factor = shift;
	my $value = shift;
	
	#print "\nVariable::UpdateValue: oldValue=" . $self->{value}->toString() . ", newValue=" . $value->toString();
		
    my $old_message = $self->{factors}{$factor->toString()};
	
	my $numer = $value->multiply($old_message);
	
	#print "\nNumerator: " . $numer->toString();
	#print "\nDenominator: " . $self->{value}->toString();
	
	my $result = $numer->divide($self->{value});
	$self->{factors}{$factor->toString()} = $result;
	
	#print "\nResult: " . $result->toString();	
	#print "\nVariable::UpdateValue: oldMessage=" . $old_message->toString() . ", newMessage=" . $result->toString();
	
    #$self->{factors}{$factor->toString()} = $value * $old_message / $self->{value};
    $self->{value} = $value;
	
	#print "\nVariable::UpdateValue using factor[" . $factor->toString() . "]: oldValue=" . $value->toString();
}

sub GetMessage 
{	
	my $self = shift;	
	my $factor = shift;	
    my $gaussian = $self->{factors}{$factor->toString()};
	
	#print "\nVariable::GetMessage for factor[" . $factor->toString() . "] got gaussian[" . $gaussian->toString() . "]";
	
	return $gaussian;
}

1;