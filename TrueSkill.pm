package TrueSkill;

use strict;
use Variable;
use Gaussian;
use LikelihoodFactor;
use PriorFactor;
use SumFactor;
use TruncateFactor;

use Math::Cephes qw(:all);
use Statistics::Distrib::Normal;

my $norm = new Statistics::Distrib::Normal;

#norm = scipy_norm()
#pdf = norm.pdf
#cdf = norm.cdf
#icdf = norm.ppf    # inverse CDF

# Update rules for approximate marginals for the win and draw cases,
# respectively.

sub Vwin 
{
	my $t = shift;
	my $e = shift;
  return $norm->pdf($t-$e) / Math::Cephes::ndtr($t-$e);
}

sub Wwin
{
	my $t = shift;
	my $e = shift;
  return Vwin($t, $e) * (Vwin($t, $e) + $t - $e);
}

sub Vdraw
{
	my $t = shift;
	my $e = shift;
	
	my $a = Math::Cephes::ndtr($e-$t);
	my $b = Math::Cephes::ndtr(-1*$e-$t);
	
	#print "\n$a $b";
	
  return ($norm->pdf(-1*$e-$t) - $norm->pdf($e-$t)) / ($a-$b );
}
sub Wdraw
{
	my $t = shift;
	my $e = shift;
  return Vdraw($t, $e) ** 2 + (($e-$t) * $norm->pdf($e-$t) + ($e+$t) * $norm->pdf($e+$t)) / (Math::Cephes::ndtr($e-$t) - Math::Cephes::ndtr(-1*$e-$t));
}

use constant INITIAL_MU => 25.0;
use constant INITIAL_SIGMA => INITIAL_MU / 3.0;

my $BETA;
my $EPSILON;
my $GAMMA;

sub SetParameters
{
	my ($beta, $epsilon, $draw_probability, $gamma) = @_;
  #"""
  #Sets three global parameters used in the TrueSkill algorithm.

  #beta is a measure of how random the game is.  You can think of it as
  #the difference in skill (mean) needed for the better player to have
  #an ~80% chance of winning.  A high value means the game is more
  #random (I need to be *much* better than you to consistently overcome
  #the randomness of the game and beat you 80% of the time); a low
  #value is less random (a slight edge in skill is enough to win
  #consistently).  The default value of beta is half of INITIAL_SIGMA
  #(the value suggested by the Herbrich et al. paper).

  #epsilon is a measure of how common draws are.  Instead of specifying
  #epsilon directly you can pass draw_probability instead (a number
  #from 0 to 1, saying what fraction of games end in draws), and
  #epsilon will be determined from that.  The default epsilon
  #corresponds to a draw probability of 0.1 (10%).  (You should pass a
  #value for either epsilon or draw_probability, not both.)

  #gamma is a small amount by which a player's uncertainty (sigma) is
  #increased prior to the start of each game.  This allows us to
  #account for skills that vary over time; the effect of old games
  #on the estimate will slowly disappear unless reinforced by evidence
  #from new games.
  #"""

	if(!defined $beta) {
		$BETA = INITIAL_SIGMA / 2.0;
	} else {
		$BETA = $beta;
	}
	if(!defined $epsilon) {
		if(!defined $draw_probability) {
			$draw_probability = 0.10;
		}
		$EPSILON = DrawMargin($draw_probability, $BETA);
	} else {
		$EPSILON = $epsilon;
	}

	if(!defined $gamma) {
		$GAMMA = INITIAL_SIGMA / 100.0;
	} else {
		$GAMMA = $gamma;
	}
	
	# print "\nSetup: $BETA, $EPSILON, $GAMMA";
}

#
# call set parameters with no args
#
SetParameters();

sub AdjustPlayers
{
	my @players_orig = @_;
  #"""
  #Adjust the skills of a list of players.

  #'players' is a list of player objects, for all the players who
  #participated in a single game.  A 'player object' is any object with
  #a "skill" attribute (a (mu, sigma) tuple) and a "rank" attribute.
  #Lower ranks are better; the lowest rank is the overall winner of the
  #game.  Equal ranks mean that the two players drew.

  #This function updates all the "skill" attributes of the player
  #objects to reflect the outcome of the game.  The input list is not
  #altered.
  #"""

  my @players = sort {$a->{rank}<=>$b->{rank}} @players_orig;

  
  # Sort players by rank, the factor graph will connect adjacent team
  # performance variables.
  # players.sort(key=lambda p: p.rank)

  # Create all the variable nodes in the graph.  "Teams" are each a
  # single player; there's a one-to-one correspondence between players
  # and teams.  (It would be straightforward to make multiplayer
  # teams, but it's not needed for my current purposes.)
	my(@ss, @ps, @ts, @ds);
	foreach my $p (@players) {
		push(@ss, new Variable());
		push(@ps, new Variable());
		push(@ts, new Variable());
		push(@ds, new Variable());
	}
	pop(@ds);

  # Create each layer of factor nodes.  At the top we have priors
  # initialized to the player's current skill estimate.
  my @skill;
  my @skill_to_perf;
  my @perf_to_team;
  for my $i (0..scalar(@ss)-1) {
	my $s = $ss[$i];
	my $p = $ps[$i];
	my $pl = $players[$i];
	my $t = $ts[$i];
	
	# print "\nPlayer[$i] skills: $pl->{skill}->[0], $pl->{skill}->[1]";
	push(@skill, new PriorFactor($s, new Gaussian($pl->{skill}->[0], $pl->{skill}->[1] + $GAMMA)));
	push(@skill_to_perf, new LikelihoodFactor($s, $p, $BETA**2));
	push(@perf_to_team, new SumFactor($t, [$p], [1]));
  }
  
  my @team_diff;
  my @t1 = @ts; pop(@t1);
  my @t2 = @ts; shift(@t2);
  for my $i (0..scalar(@ds)-1) {
	my $d = $ds[$i];
	my $t1var = $t1[$i];
	my $t2var = $t2[$i];
	push(@team_diff, new SumFactor($d, [$t1var, $t2var], [+1, -1]));
  }  
  
  #skill = [PriorFactor(s, Gaussian(mu=pl.skill[0],
  #                                 sigma=pl.skill[1] + GAMMA))
  #         for (s, pl) in zip(ss, players)]
  #skill_to_perf = [LikelihoodFactor(s, p, BETA**2)
  #                 for (s, p) in zip(ss, ps)]
  #perf_to_team = [SumFactor(t, [p], [1])
  #                for (p, t) in zip(ps, ts)]
  #team_diff = [SumFactor(d, [t1, t2], [+1, -1])
  #             for (d, t1, t2) in zip(ds, ts[:-1], ts[1:])]
  # At the bottom we connect adjacent teams with a 'win' or 'draw'
  # factor, as determined by the rank values.
  my @trunc;
  my @pl1 = @players; pop(@pl1);
  my @pl2 = @players; shift(@pl2);  
  for my $i (0..scalar(@ds)-1) {
	my $d = $ds[$i];
	my $pl1var = $pl1[$i];
	my $pl2var = $pl2[$i];
	
	my $v;
	if($pl1var->{rank} == $pl2var->{rank}){
		$v = \&Vdraw;
	} else{
		$v = \&Vwin;
	}

	my $w;
	if($pl1var->{rank} == $pl2var->{rank}){
		$w = \&Wdraw;
	} else{
		$w = \&Wwin;
	}
	
	push(@trunc, new TruncateFactor($d, 
								$v,
								$w,
								$EPSILON));
  }
  #trunc = [TruncateFactor(d,
  #                        Vdraw if pl1.rank == pl2.rank else Vwin,
  #                        Wdraw if pl1.rank == pl2.rank else Wwin,
  #                        EPSILON)
  #         for (d, pl1, pl2) in zip(ds, players[:-1], players[1:])]

  # Start evaluating the graph by pushing messages 'down' from the
  # priors.

  #print "\nDoing skill";
	foreach my $f (@skill) {		
		$f->Start();
	}
	#print "\nDoing skill_to_perf";
	foreach my $f (@skill_to_perf) {		
		$f->UpdateValue();
	}
	#print "\nDoing perf_to_team";
	foreach my $f (@perf_to_team) {		
		$f->UpdateSum();
	}

  # Because the truncation factors are approximate, we iterate,
  # adjusting the team performance (t) and team difference (d)
  # variables until they converge.  In practice this seems to happen
  # very quickly, so I just do a fixed number of iterations.
  #
  # This order of evaluation is given by the numbered arrows in Figure
  # 1 of the Herbrich paper.

	for my $i (0..4) {
		#print "\nDoing team_diff";
		foreach my $f (@team_diff) {			
		  $f->UpdateSum();             # arrows (1) and (4)
		}
		#print "\nDoing trunc";
		foreach my $f (@trunc) {		
		  $f->Update();                # arrows (2) and (5)
		}
		foreach my $f (@team_diff) {
		  $f->UpdateTerm(0);           # arrows (3) and (6)
		  $f->UpdateTerm(1);
		}
	}

  # Now we push messages back up the graph, from the teams back to the
  # player skills.

	foreach my $f (@perf_to_team) {
		$f->UpdateTerm(0);
	}
	foreach my $f (@skill_to_perf) {
		$f->UpdateMean();
	}

  # Finally, the players' new skills are the new values of the s
  # variables.

  for my $i (0..scalar(@ss)-1) {
	my @details = $ss[$i]->{value}->MuSigma();
	$players[$i]->{skill} = \@details;
  }
}

sub DrawProbability
{
  # """ Compute the draw probability given the draw margin (epsilon). """
  
  my ($epsilon, $beta, $total_players) = @_;
  $total_players = 2 if !defined $total_players;
  
  return 2 * Math::Cephes::ndtr($epsilon / (sqrt($total_players) * $beta)) - 1;
}

sub DrawMargin
{
  # """ Compute the draw margin (epsilon) given the draw probability. """
  my ($p, $beta, $total_players) = @_;
  $total_players = 2 if !defined $total_players;
  
  return Math::Cephes::ndtri(($p+1.0)/2) * sqrt($total_players) * $beta;
}
