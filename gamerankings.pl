# The MIT License (MIT)
#
# Copyright (c) 2008-2015 Vincent Hurrell
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.
use strict;
use Net::SMTP;
use MIME::Lite::TT::HTML;
use Getopt::Long;
use File::Temp;
use File::Copy;
use File::Basename;
use FindBin;
use lib $FindBin::Bin;
use TrueSkill;

my $nBaseRating = 1500;
my $nKFactor = 32;
my %hashPlayerRatings;
my %hashAvgPosition;
my $emailTitle = "*** Auto-generated email from game rankings script ***";

$| = 1; # autoflush stdout

use constant DRAW_KEY   =>  "draw";
use constant WIN_KEY    =>  "win";
use constant LOSE_KEY   =>  "lose";

use constant COMMAND_PROCESS_DB => "processdb";
use constant COMMAND_PARSE_GAMES => "parsegames";
use constant COMMAND_PARSE_PLAYERS => "parseplayers";

my %scoreHash = (
    main::DRAW_KEY  =>  0.5,
    main::WIN_KEY   =>  1,
    main::LOSE_KEY  =>  0
);

my $email = 0;
my $dbfile = "games.out";
my $dbdiff;
my $flatfile = 0;
my $mergediff = 0;
my $command = "processdb";
my $backup_notifications_file;
my $templatedir = ".";
my $stats_notifications_file = "gamesemailnotifications.txt";
my $parsed_args = GetOptions (	"command=s" => \$command,
								"email=i" => \$email,
								"dbfile=s"   => \$dbfile,
								"dbdiff=s"  => \$dbdiff,
								"flatfile=i" => \$flatfile,
								"mergediff=i" => \$mergediff,
								"templatedir" => \$templatedir,
								"resultsnotifications=s" => \$stats_notifications_file,
								"backupnotifications=s" => \$backup_notifications_file);

eval
{
    (defined $dbfile) || die "invalid number of arguments";
		
	my %hashGameData;	
	loadGameData( $dbfile, \%hashGameData );    
	
	if( $command eq COMMAND_PROCESS_DB ) 
	{		
		if( defined $dbdiff ) 
		{	
			die "Unable to find diff file $dbdiff" if !-e $dbdiff;
			my %hashDiff;	
			loadGameData( $dbdiff, \%hashDiff );    	
			processDiff( \%hashDiff, \%hashGameData );
			if( $mergediff )
			{
				mergeDiffIntoDb($dbfile, \%hashGameData, \%hashDiff);
			}
		}
		else
		{
			processDb( \%hashGameData );
		}
	}
	elsif( $command eq COMMAND_PARSE_GAMES )
	{
		parseGames( \%hashGameData );
	}
	elsif( $command eq COMMAND_PARSE_PLAYERS )
	{
		parsePlayers( \%hashGameData );
	}
	else
	{
		die "Invalid command: $command";
	}
};
if($@)
{
	print "\nException: $@";
}

0;

sub parsePlayers
{
	my $refGameData = shift;
	
	my @players = getAllKnownPlayers($refGameData);
	my @sortedplayers = sort {$a cmp $b} @players;
	my $playerlist = join(",", @sortedplayers);
	
	print "\n$playerlist";
}

sub parseGames
{
	my $refGameData = shift;
	
	my @sortedgames = sort {$a cmp $b} keys( %$refGameData );
	my $gamelist = join(",", @sortedgames);
	
	print "\n$gamelist";
}

sub mergeDiffIntoDb
{
	my $dbfile = shift;
	my $refGameData = shift;
	my $hashdiff = shift;
	#my $outfile = "test.out";
	
	my ($fh, $filename) = File::Temp::tempfile();
	
	print "\nCreated tempfile $filename";
	
	my $currentGame = "";
	my $currentDate = "";
	
	#open $fh, "> $outfile" || die "failed to open $outfile";
	
	open FILE_IN, "< $dbfile" || die "failed to open $dbfile";
	
	while(1)
	{
		my $line = <FILE_IN>;
		if( !defined $line || $line =~ /\[(.+?)(?:,|\])/ ) 
		{
			if($currentGame && defined $hashdiff->{$currentGame})
			{
				my $gamesplayed = $hashdiff->{$currentGame}->{gamesplayed};
				foreach my $gameplayed (@$gamesplayed)
				{
					my $result = "";
					my $positions = $gameplayed->{positions};
					my $scores = $gameplayed->{scores};
					
					if( $gameplayed->{date} ne $currentDate) 
					{
						print $fh "\n; $gameplayed->{date}\n";
						$currentDate = $gameplayed->{date};
					}										
					
					for( my $i = 0; $i < scalar(@$positions); $i++ )
					{
						my $position = $positions->[$i];
						my $score = $scores->[$i];
						for( my $j = 0; $j < scalar(@$position); $j++ )
						{
							my $player = $position->[$j];
							my $playerscore = $score->[$j];
							$result .= ($player . "{" . $playerscore . "} / ");
						}

						chop $result;chop $result;chop $result;
						
						$result .= ", ";					
					}								

					chop $result; chop $result;
					
					print $fh "$result\n";
				}

				print $fh "\n";	

				delete $hashdiff->{$currentGame}				;
			}
			$currentGame = $1;	
			$currentDate = "";
		}
		
		last if !defined $line;
		
		print $fh $line;
	}		
	close FILE_IN;	
	
	$currentDate = "";
	foreach my $currentGame (keys(%$hashdiff))
	{
		print $fh "[" . $currentGame . "]\n";
		
		my $gamesplayed = $hashdiff->{$currentGame}->{gamesplayed};
		foreach my $gameplayed (@$gamesplayed)	
		{
			my $result = "";
			my $positions = $gameplayed->{positions};
			my $scores = $gameplayed->{scores};
			
			if( $gameplayed->{date} ne $currentDate) 
			{
				print $fh "\n; $gameplayed->{date}\n";
				$currentDate = $gameplayed->{date};
			}										
			
			for( my $i = 0; $i < scalar(@$positions); $i++ )
			{
				my $position = $positions->[$i];
				my $score = $scores->[$i];
				for( my $j = 0; $j < scalar(@$position); $j++ )
				{
					my $player = $position->[$j];
					my $playerscore = $score->[$j];
					$result .= ($player . "{" . $playerscore . "} / ");
				}

				chop $result;chop $result;chop $result;
				
				$result .= ", ";					
			}								

			chop $result; chop $result;
			
			print $fh "$result\n";		
		}
		$currentDate = "";	
		print $fh "\n";
	}
	
	close $fh;
	
	backupDatabaseOnDisk($dbfile, $filename, 100);
	backupDb();
}

sub backupDatabaseOnDisk
{
	my $dbfile = shift;
	my $newdbfile = shift;
	my $maxBackups = shift;
	
	my $backupFile;
	my $i = 1;
	do {
		$backupFile = $dbfile . ".backup.$i";
	} while( -e $backupFile && $i++ <= $maxBackups );
	
	die "Unable to create backup" if (-e $backupFile);
	
	copy($dbfile, $backupFile) or die "Copy failed: $!";
	move($newdbfile, $dbfile) or die "Move failed: $!";
}

sub processDb
{
	my $refGameData = shift;
	calculateAllGameRatings( $refGameData );
	
	print "\nDrawing game data";
	my $szBuffer = drawGameData( $refGameData, $email, $emailTitle );	
	print "\nDrawing game data complete";
    
    #
    # mail the results
    #
		
	print $szBuffer;
    if( $email )
    {
		print "\nMailing results";
		my $hashUsers = getMailList($stats_notifications_file);
        mailresults( $hashUsers, "Games Group", "Games Ranking Update", $szBuffer );
		print "\nMailing results complete";
    }	
	
	if($flatfile) 
	{
		print "\nOutputting to flat file";
		outputGameDataToFlatFile( $refGameData );	
		print "\nOutputting to flat file complete";
	}
	backupDb();
}

sub processDiff 
{
	my $diffhash = shift;
	my $dbhash = shift;
	
	foreach my $game ( keys( %$diffhash ) ) 
	{
		calculateSpecificGameRatings( $game, $dbhash );
	}
	my $bufferBefore = drawGameData( $dbhash, 0, "*** Before Update ***" );
	
	updateHash($dbhash, $diffhash);	
	
	%hashPlayerRatings = ();
	%hashAvgPosition = ();	
	
	foreach my $game ( keys( %$diffhash ) ) 
	{
		calculateSpecificGameRatings( $game, $dbhash );
	}
	my $bufferAfter = drawGameData( $dbhash, 0, "*** After Update ***" );	
	
	my $finalBuffer = 	$emailTitle .
						"\n" .
						$bufferBefore .
						"\n\n*************************************************************************************************************************\n" .
						$bufferAfter;
	print $finalBuffer;
	if( $email )
	{
		my $hashUsers = getMailList($stats_notifications_file);
		mailresults( $hashUsers, "Games Group", "Games Ranking Update", $finalBuffer );
	}
	backupDb();
}

sub updateHash
{
	my $dbhash = shift;
	my $diffhash = shift;
	
	foreach my $game (keys(%$diffhash))
	{
		my $dbgame = $dbhash->{$game};
		my $diffgame = $diffhash->{$game};
		my $dbgamesplayed = $dbgame->{gamesplayed};
		my $diffgamesplayed = $diffgame->{gamesplayed};
		foreach my $diffgameplayed (@$diffgamesplayed) 
		{
			push(@$dbgamesplayed, $diffgameplayed);
			
			my $diffscores = $diffgameplayed->{scores};
			foreach my $posscores (@$diffscores) 
			{
				foreach my $score (@$posscores) 
				{
					if( defined $score ) {
						if( $score < $dbgame->{minscore} || (!defined $dbgame->{minscore} && defined $score) ) {
							$dbgame->{minscore} = $score;
						}
						if( $score > $dbgame->{maxscore} ) {
							$dbgame->{maxscore} = $score;
						}
						$dbgame->{scorecount} += 1;
					}
				}
			}
		}
		
		if($dbgame->{scorecount}){
			$dbgame->{totalscore} += $diffgame->{totalscore};						
			$dbgame->{avgscore} = $dbgame->{totalscore} / $dbgame->{scorecount};			
		}
	}
}

sub calculateSpecificGameRatings
{
	my $szGameName = shift;
    my $refGameData = shift;	
        
	foreach my $recordedGame ( @{$refGameData->{ $szGameName }->{gamesplayed}} )
	{
		my $hashPostGameRatings = calculateSingleGameRatings( $szGameName, $recordedGame, \%hashPlayerRatings );
					   
		foreach my $szPlayerName( keys( %$hashPostGameRatings ) )
		{
			updatePlayerRating( $szPlayerName, $szGameName, $hashPostGameRatings->{ $szPlayerName }, \%hashPlayerRatings );
			updatePlayerGamesPlayed( $szPlayerName, $szGameName, \%hashPlayerRatings );
		}
	}        
}

sub getCurrentPlayerRating
{
    my $szPlayerName = shift;
    my $szGameName = shift;
    my $refHashRatings = shift;
    
    my $nRating = $refHashRatings->{ $szGameName }{ $szPlayerName }{ 'rating' };
    
    return( defined $nRating ? $nRating : $nBaseRating );
}

sub updatePlayerRating
{
    my $szPlayerName = shift;
    my $szGameName = shift;
    my $nNewRating = shift;
    my $hashRatings = shift;
	my $key = shift || "rating";
    
    $hashRatings->{ $szGameName }{ $szPlayerName }{ $key } = $nNewRating;
}

sub updatePlayerGamesPlayed
{
    my $szPlayerName = shift;
    my $szGameName = shift;
    my $hashRatings = shift;
    
    $hashRatings->{ $szGameName }{ $szPlayerName }{ 'gamesplayed' }++;
}

sub getResults
{
    my $nPlayerRating = shift;
    my $nOpponentRating = shift;
    my $szKey = shift; 
    
    my $nExpectedResult = 1 / (1 + 10 ** ( ($nOpponentRating - $nPlayerRating)/400 ) );
    
    return ( $nExpectedResult, $scoreHash{ $szKey } );    
}

sub calculateNewRating
{
    my $nPlayerRating = shift;
    my $nExpectedTotal = shift;
    my $nActualTotal = shift;
    
    return( $nPlayerRating + $nKFactor * ( $nActualTotal - $nExpectedTotal ) );   
}

sub calculatePlayerSingleGameRating
{
    my $szPlayerName = shift;
    my $szGameName = shift;
    my $resultsHash = shift;
    my $refArrayLostTo = shift;
    my $refArrayDefeated = shift;
    my $refArrayDrawn = shift;    
    
    my $nPlayerRating = getCurrentPlayerRating( $szPlayerName, $szGameName, $resultsHash );
    
    my $nExpectedTotal = 0;
    my $nActualTotal = 0;
    
    foreach my $szDrawnName ( @$refArrayDrawn )
    {
        my $nDrawnRating = getCurrentPlayerRating( $szDrawnName, $szGameName, $resultsHash  );
        my ($nExpectedResult, $nActualResult) = getResults( $nPlayerRating, $nDrawnRating, DRAW_KEY );
        
        $nExpectedTotal += $nExpectedResult;
        $nActualTotal += $nActualResult;
    }    
    
    foreach my $szLoserName ( @$refArrayDefeated )
    {
        my $nLoserRating = getCurrentPlayerRating( $szLoserName, $szGameName, $resultsHash  );
        my ($nExpectedResult, $nActualResult) = getResults( $nPlayerRating, $nLoserRating, WIN_KEY );
        
        $nExpectedTotal += $nExpectedResult;
        $nActualTotal += $nActualResult;
    }

    foreach my $szWinnerName ( @$refArrayLostTo )
    {
        my $nWinnerRating = getCurrentPlayerRating( $szWinnerName, $szGameName, $resultsHash  );
        my ($nExpectedResult, $nActualResult) = getResults( $nPlayerRating, $nWinnerRating, LOSE_KEY );
        
        $nExpectedTotal += $nExpectedResult;
        $nActualTotal -= $nActualResult;
    }
    
    my $nNewPlayerRating = calculateNewRating( $nPlayerRating, $nExpectedTotal, $nActualTotal );
    
    # print "\nPlayer[$szPlayerName] rating change from $nPlayerRating to $nNewPlayerRating";
    
    return( $nNewPlayerRating );
}

sub calculateSingleGameRatings
{
    my $szGameName = shift;
    my $recordedGame = shift;
    my $hashRatings = shift; 
    
    my %hashPostGameRatings;
    my @arrayLostTo = ();

	my $trueskillrank = 1;
	my @players;
	
    for( my $i = 0; $i <  scalar( @{$recordedGame->{ 'positions' }} ); $i++ )
    {      
        my $position = $recordedGame->{ 'positions' }[$i];    
		my $score = $recordedGame->{ 'scores' }[$i];		
						
		foreach my $pos (@$position) {
			my $szPlayerName = $pos;
			
			my $trueskill = [25.0, 25.0/3.0];			
			if( $hashAvgPosition{ $szGameName }{ $szPlayerName }{skill} ) {
				$trueskill = [$hashAvgPosition{ $szGameName }{ $szPlayerName }{skill}, $hashAvgPosition{ $szGameName }{ $szPlayerName }{sigma}];
			}
			my $player = {
				skill => $trueskill,
				rank => $trueskillrank,
				player => $szPlayerName
			};
			push(@players, $player);
		}		
		
        for( my $k = 0; $k < scalar( @$position ); $k++ )
        {
            my $szPlayerName = $position->[$k];

            my @arrayDefeated;
            for( my $j = $i + 1; $j <  scalar( @{$recordedGame->{ 'positions' }} ); $j++ )        
            {
                push( @arrayDefeated, @{$recordedGame->{ 'positions' }[$j]} );
            }                  

            my @arrayDrawn = @$position;
            splice( @arrayDrawn, $k, 1 );

            my $nNewPlayerRating = calculatePlayerSingleGameRating( $szPlayerName, $szGameName, $hashRatings, \@arrayLostTo, \@arrayDefeated, \@arrayDrawn );
            $hashPostGameRatings{ $szPlayerName } = $nNewPlayerRating;
            
            $hashAvgPosition{ $szGameName }{ $szPlayerName }{ totalpos } += ($i + 1);
            $hashAvgPosition{ $szGameName }{ $szPlayerName }{ gamesplayed } += 1;
            $hashAvgPosition{ $szGameName }{ $szPlayerName }{ avgposition } = ($hashAvgPosition{ $szGameName }{ $szPlayerName }{ totalpos } / $hashAvgPosition{ $szGameName }{ $szPlayerName }{ gamesplayed } );
            $hashAvgPosition{ $szGameName }{ $szPlayerName }{ numdefeated } += scalar(@arrayDefeated);
            $hashAvgPosition{ $szGameName }{ $szPlayerName }{ numlostto } += scalar(@arrayLostTo);
            $hashAvgPosition{ $szGameName }{ $szPlayerName }{ numdrawn } += scalar(@arrayDrawn);
			if( defined @$score[0] ) {
				$hashAvgPosition{ $szGameName }{ $szPlayerName }{ gamesplayedavg } += 1;
				$hashAvgPosition{ $szGameName }{ $szPlayerName }{ totalscore } += @$score[0];
				$hashAvgPosition{ $szGameName }{ $szPlayerName }{ avgscore } = $hashAvgPosition{ $szGameName }{ $szPlayerName }{ totalscore } / $hashAvgPosition{ $szGameName }{ $szPlayerName }{ gamesplayedavg };
			}
        }
		
		$trueskillrank++;
        
        push( @arrayLostTo, @$position );        
    } 

	TrueSkill::AdjustPlayers(@players);    
	foreach my $player (@players) {
		$hashAvgPosition{ $szGameName }{ $player->{player} }{ skill } = $player->{skill}->[0];
		$hashAvgPosition{ $szGameName }{ $player->{player} }{ sigma } = $player->{skill}->[1];
		my $trueskillrank = $player->{skill}->[0] - 3*$player->{skill}->[1];
		updatePlayerRating( $player->{player}, $szGameName, $trueskillrank, \%hashPlayerRatings, "skill" );
	}
    
    return( \%hashPostGameRatings );   
}

sub calculateAllGameRatings
{
    my $refGameData = shift;
        
    foreach my $szGameName ( keys( %$refGameData ) )
    {
        foreach my $recordedGame ( @{$refGameData->{ $szGameName }->{gamesplayed}} )
        {
            my $hashPostGameRatings = calculateSingleGameRatings( $szGameName, $recordedGame, \%hashPlayerRatings );
                           
            foreach my $szPlayerName( keys( %$hashPostGameRatings ) )
            {
                updatePlayerRating( $szPlayerName, $szGameName, $hashPostGameRatings->{ $szPlayerName }, \%hashPlayerRatings );
                updatePlayerGamesPlayed( $szPlayerName, $szGameName, \%hashPlayerRatings );
            }
        }        
    }
}

sub getSortedPlayerRankingsByGame
{
    my $szGameName = shift;   
    
    my @players;
    foreach my $szPlayerName( keys( %{$hashPlayerRatings{ $szGameName }} ) )
    {
        $hashPlayerRatings{ $szGameName }{ $szPlayerName }{ 'name' } = $szPlayerName;
        push( @players, $hashPlayerRatings{ $szGameName }{ $szPlayerName } );
    }
    
    return( sort { $b->{ 'skill' } <=> $a->{ 'skill' } } @players );
}

sub getAllKnownPlayers
{
	my $refGameData = shift;
	
	my %players;
    foreach my $szGameName ( keys( %$refGameData ) )
    {
        foreach my $recordedGame ( @{$refGameData->{ $szGameName }->{gamesplayed}} )
		{
			my @players;
			
			for( my $i = 0; $i <  scalar( @{$recordedGame->{ 'positions' }} ); $i++ )
			{      
				my $position = $recordedGame->{ 'positions' }[$i];    
								
				foreach my $pos (@$position) {
					$players{$pos} = 1;
				}
			}				
		}
	}
	return(keys(%players));
}

sub outputGameDataToFlatFile
{
    my $refGameData = shift;
    my %ratings;
        
    foreach my $szGameName ( keys( %$refGameData ) )
    {
	my $szFileName = "$szGameName\.csv";

	# remove characters forbidden by OS (Win32 in this case)
	$szFileName =~ s/[\/:*?"<>|]//;

        open FILE_OUT, "> $ENV{TEMP}\\$szFileName";
    
        my %output;    
        my $currentDate;
        foreach my $gameplayed ( @{$refGameData->{$szGameName}->{gamesplayed}} )
        {
            my $hashPostGameRatings = calculateSingleGameRatings( $szGameName, $gameplayed, \%ratings );
            
            my @players = getAllKnownPlayers( $refGameData );
            
            foreach my $szPlayerName ( @players )
            {                               
                if( $hashPlayerRatings{ $szGameName }{ $szPlayerName }->{ 'gamesplayed' } < $refGameData->{ $szGameName }->{vars}->{MINGAMESFORDISPLAY} )
                {
                    next;
                }                
                
                $output{ $szPlayerName } .= "," if length( $output{$szPlayerName} );
                
                my $szRatingToAdd = "";
                if( defined $hashPostGameRatings->{ $szPlayerName } )
                {
                    updatePlayerRating( $szPlayerName, $szGameName, $hashPostGameRatings->{ $szPlayerName }, \%ratings );    
                    $szRatingToAdd = $hashPostGameRatings->{$szPlayerName};
                }
                else
                {
                    $szRatingToAdd = getCurrentPlayerRating( $szPlayerName, $szGameName, \%ratings );
                }
                $output{$szPlayerName} .= $szRatingToAdd;
            }            
        }
        
        foreach my $szPlayerName( keys( %output ) )
        {
            # ignore output of players who've never played this game
            if( !( $output{$szPlayerName} =~ /^(?:$nBaseRating,*)+$/g ) )
            {
                print FILE_OUT "\"$szPlayerName\",$nBaseRating,$output{$szPlayerName}\n";
            }
        }
        
        close FILE_OUT;
    }
}

sub drawGameData
{
    my $refGameData = shift;
    my $bMailResults = shift;
	my $title = shift;
    my $gameresultspath = ".";
	
	if( $ENV{TEMP} ) 
	{
		$gameresultspath = $ENV{TEMP};
	}
	
    #
    # redirect output to a file
    #
    open (FILE_OUT, " > $gameresultspath/gameresults.txt");
    
    print FILE_OUT "\n$title";
    print FILE_OUT "\n";
    
    my $nGamesPlayed = 0;
    my @sortedGames = sort keys( %hashPlayerRatings );
    foreach my $szGameName ( @sortedGames )
    {
        print FILE_OUT "\n[$szGameName - Min=$refGameData->{ $szGameName }->{minscore}, Max=$refGameData->{ $szGameName }->{maxscore}, Avg=$refGameData->{ $szGameName }->{avgscore}]\n";
        print FILE_OUT "\nPlayer Name       True Skill Uncertainty ELO Rating       Games Played Avg Position Avg Score Players Defeated Players Lost To Players Drawn With Win/Loss Ratio";
        print FILE_OUT "\n----------------- ---------- ----------- ---------------- ------------ ------------ --------- ---------------- --------------- ------------------ --------------\n";
         
        my @sortedplayernames = getSortedPlayerRankingsByGame( $szGameName );
  
        foreach my $hashPlayer ( @sortedplayernames )
        {
            if( $hashPlayer->{ 'gamesplayed' } < $refGameData->{ $szGameName }->{vars}->{MINGAMESFORDISPLAY} )
            {
                next;
            }
            
			my $wins = $hashAvgPosition{ $szGameName }{ $hashPlayer->{ 'name' } }{numdefeated};
			my $losses = $hashAvgPosition{ $szGameName }{ $hashPlayer->{ 'name' } }{numlostto};
			my $trueskill = $hashAvgPosition{ $szGameName }{ $hashPlayer->{ 'name' } }{skill};
			my $sigma = $hashAvgPosition{ $szGameName }{ $hashPlayer->{ 'name' } }{sigma};
			my $winLoss = "infinity";
			if( $losses > 0 ) {
				$winLoss = $wins/$losses;
			}			
			
            format FILE_OUT = 
@<<<<<<<<<<<<<<<< @<<<<<<<<< @<<<<<<<<<< @<<<<<<<<<<<<<<< @||||||||||| @||||||||||| @|||||||| @||||||||||||||| @|||||||||||||| @||||||||||||||||| @|||||||||||||
$hashPlayer->{ 'name' },$trueskill, $sigma, $hashPlayer->{ 'rating' },$hashPlayer->{ 'gamesplayed' },$hashAvgPosition{ $szGameName }{ $hashPlayer->{ 'name' } }{avgposition},$hashAvgPosition{ $szGameName }{ $hashPlayer->{ 'name' } }{avgscore},$wins,$losses,$hashAvgPosition{ $szGameName }{ $hashPlayer->{ 'name' } }{numdrawn},$winLoss
.           
            write FILE_OUT;
        }
        
        $nGamesPlayed += scalar( @{$refGameData->{ $szGameName }->{gamesplayed}});
    }
    
    print FILE_OUT "\nTotal games known: " . scalar(@sortedGames);
    print FILE_OUT "\nTotal games played: $nGamesPlayed";
    close FILE_OUT;
    
    #
    # open the file for input and read it in
    #
    my $szBuffer = getFileBuffer( "$gameresultspath/gameresults.txt" );
    	
	return $szBuffer;
}

sub backupDb
{
	if( defined $backup_notifications_file )
	{
		my $hashUsers = getMailList($backup_notifications_file);
		my $szBuffer = getFileBuffer( $dbfile );
		mailresults_backup( $hashUsers, "Games Backup Users", "Game Database Backup", $szBuffer );
	}
}

sub getMailList
{
	my $filename = shift;
    #
    # get the users to notify
    #
    my %hashUsers;
    my $smtphost;
    open(FILE_IN, "< $filename");
    while(<FILE_IN>)
    {
		$_ =~ s/^\s+//;
		$_ =~ s/\s+$//;
        if( $_ =~ /\[(.+)\]/ )
        {
            $smtphost = $1;
            $hashUsers{ $smtphost } = [];
        }
        elsif( $_ )
        {
            push( @{$hashUsers{ $smtphost }}, $_ );
        }
    }
    close FILE_IN;

	return \%hashUsers;
}

sub getFileBuffer
{
    my $szFileName = shift;
    
    open (FILE_OUT, "< $szFileName");    
    my @lines = <FILE_OUT>;
    my $szBuffer = join('', @lines);
    close FILE_OUT;  
    
    return( $szBuffer );
}

sub mailresults_backup
{
    my $refUsers = shift;
    my $szRecipient = shift;
    my $szSubject = shift;
    my $szBufferToMail = shift;
	
	my($filename, $dirs, $suffix) = fileparse($dbfile);
	
	my %params;
	$params{gamedb} = $filename . $suffix;

	my %options;
	$options{INCLUDE_PATH} = $templatedir;

    foreach my $host ( keys(%$refUsers) )
    {
        #
        # notify the users
        #
        if( scalar( @{$refUsers->{$host}} ) )
        {
			my $szRecipients = join(",", @{$refUsers->{$host}});
			
			my $msg = MIME::Lite::TT::HTML->new(
				From        => 'script@gamerankingscript.com',
				To          => $szRecipients,
				Subject     => $szSubject,
				Encoding    => 'quoted-printable',
				Template    => {
					html => 'game_backup_template.html',
					text => 'game_backup_template.txt',
				},
				Charset     => 'utf8',
				TmplOptions => \%options,
				TmplParams  => \%params,
			);

			$msg->attr("content-type"  => "multipart/mixed");

			# Attach a PDF to the message
			$msg->attach(  
				Type        =>  'text/plain',
				Path        =>  $dbfile,
				Filename    =>  'gamedb.txt',
				Disposition =>  'attachment'
			);
			
			$msg->send();
        }
    }
}

sub mailresults
{
    my $refUsers = shift;
    my $szRecipient = shift;
    my $szSubject = shift;
    my $szBufferToMail = shift;
	
	my($filename, $dirs, $suffix) = fileparse($dbfile);
	
	my %params;
	$params{gameresults} = $szBufferToMail;

	my %options;
	$options{INCLUDE_PATH} = $templatedir;

    foreach my $host ( keys(%$refUsers) )
    {
        #
        # notify the users
        #
        if( scalar( @{$refUsers->{$host}} ) )
        {
			my $szRecipients = join(",", @{$refUsers->{$host}});
			
			my $msg = MIME::Lite::TT::HTML->new(
				From        => 'script@gamerankingscript.com',
				To          => $szRecipients,
				Subject     => $szSubject,
				Encoding    => 'quoted-printable',
				Template    => {
					html => 'game_results_template.html',
					text => 'game_results_template.txt',
				},
				Charset     => 'utf8',
				TmplOptions => \%options,
				TmplParams  => \%params,
			);

			$msg->send();
        }
    }
}

sub loadGameData
{
    my $szGameDatabaseFile = shift;
    my $refGameData = shift;
    
    my $currentDate;
    eval
    {
      	open FILE_IN, "< $szGameDatabaseFile" || die "failed to open $szGameDatabaseFile";
      	
		my %totals;

      	my $szCurrentGame;
    	while( <FILE_IN> )
    	{
    	    $_ =~ s/^\s+//;
    	    $_ =~ s/\s+$//;
    	    
			if( $_ =~ /^\s*;/ )
    	    {
				# do nothing for comments unless it has a date
						   
				if( $_ =~ /^\s*;\s*(\w+)\s+(\d+)\w*\w*,\s*(\d+)/ )
				{
					$currentDate = "$1 $2, $3";
				}
			}
    	    elsif( $_ =~ /\[(.+?)(?:,|\])/ )
    	    {
                $szCurrentGame = $1;
								
				if(!defined $refGameData->{ $szCurrentGame } ) {
					$refGameData->{ $szCurrentGame }->{gamesplayed} = [];
					$totals{$szCurrentGame}{totalscore} = 0;
					$totals{$szCurrentGame}{scorecount} = 0;
				}
                
                my @vars = $_ =~ /\s+(\w+)=(.+?)\]*/g;
                for my $i (0..scalar(@vars)-1)
                {
                    if( $i %2 == 0 )
                    {
                        $refGameData->{$szCurrentGame}->{vars}->{$vars[$i]} = $vars[$i + 1];
                    }
                }
    	    }
    	    elsif( $_ )
    	    {
				my @gameresult = split( ',', $_ );
					
				for( my $i = 0; $i < scalar(@gameresult); $i++ )
				{
					$gameresult[$i] =~ s/^\s+//;
					$gameresult[$i] =~ s/\s+$//;
				}
					
				my $nPosition = 0;
				my @arrayPositions = ();
				my @arrayScores = ();
				foreach my $szGameResult (@gameresult)
				{
					my @arrayDrawn = $szGameResult =~ /([\w|\s]+)(?:\{-*\d+\})*\s*[\\|\/]*\s*/g;
					my @playerScores = $szGameResult =~ /[\w|\s]+\{*(-*\d+)*\}*\s*[\\|\/]*\s*/g;
					foreach my $drawn (@arrayDrawn)
					{
						$drawn =~ s/^\s+//;
						$drawn =~ s/\s+$//;
					}
					$arrayPositions[ $nPosition ] = \@arrayDrawn;
					$arrayScores[ $nPosition ] = \@playerScores;
					
					foreach my $score (@playerScores) {
						if( defined $score ) {
							if( $score < $refGameData->{ $szCurrentGame }->{minscore} || (!defined $refGameData->{ $szCurrentGame }->{minscore} && defined $score) ) {
								$refGameData->{ $szCurrentGame }->{minscore} = $score;
							}
							if( $score > $refGameData->{ $szCurrentGame }->{maxscore} ) {
								$refGameData->{ $szCurrentGame }->{maxscore} = $score;
							}
							$totals{$szCurrentGame}{scorecount} += 1;
							$totals{$szCurrentGame}{totalscore} += $score;
							$refGameData->{ $szCurrentGame }->{totalscore} = $totals{$szCurrentGame}{totalscore};
							$refGameData->{ $szCurrentGame }->{scorecount} = $totals{$szCurrentGame}{scorecount};
							$refGameData->{ $szCurrentGame }->{avgscore} = $totals{$szCurrentGame}{totalscore} / $totals{$szCurrentGame}{scorecount};
						}
					}
					$nPosition++;
				}
					
				my %gameresult = ( 	positions => \@arrayPositions, 
									scores => \@arrayScores);				
						
					
				if( defined $currentDate )
				{
					$gameresult{date} = $currentDate;  
				}
					
				push( @{$refGameData->{ $szCurrentGame }->{gamesplayed}}, \%gameresult );
    	    }
    	}
    };
    
    close FILE_IN;
	
    die $@ if $@;
}

=head1 DESCRIPTION

This script it used to track player ratings for a variety of games where positions of all players can be determined at game end.  Statistics are rendered
using both elo and trueskill; however, the sorting is implemented using only trueskill

=head1 HOW TO LAUNCH THE PROGRAM

perl gamerankings.pl --dbfile=[game database file]

where [game database file] is a file containing the results of all games played that you wish to track.

=over

=item * The script can be used to mail results to users via an SMTP server.  It expects a gamesemailnotifications.txt file present in the running
directory of the script.  Emails can be sent to users with the following command line:

perl gamerankings.pl --email=1 --dbfile=[game database file]

Please refer to the NOTIFICATION FILE FORMAT section of this document for information on how to create a gamesemailnotifications.txt file

=item * The script can be used to email a database backup to specific users via an SMTP server.  It expects a text file name to be providedon the command
line.  Backups can be sent to user emails with the following command line:

perl gamerankings.pl --email=1 --dbfile=[game database file] --backupnotifications=[backup notifications email file]

Please refer to the NOTIFICATION FILE FORMAT section of this document for information on how to create a database backup notification text file

=back

=head1 GAME DATABASE FILE FORMAT

For the script to successfully process the game database file, it must satisfy the following criteria:

=over

=item * All game entries must be created with the game name in brackets( i.e. [] ).  For example, if you played Race for the Galaxy, the game would
be entered in the game database file as [Race for the Galaxy].

=item * Under each game entry, there can be 0 or more games played, each on its own line.  Each game played is a comma separated list of player positions.  Players tied for a position
are separated with a slash ( i.e. / ) instead of a comma.  For example, if Joe, Tim and Mike play 2 games of Ra, the entry under Ra might look like the following:

[Ra]

Joe, Tim, Mike

Mike, Tim / Joe

In the first game, Joe won the first with Tim coming in second and Mike third.  In the second game, Mike came in first and Tim and Joe tied for second place.

In addition, information can be stored in the file that has no bearing on the results of the games played.  If you want to just put in the game database file the 
date that the game was played, just prefix the line with a semicolon, like the following:

[Ra]

; January 18th, 2008

Mike, Tim, Joe

; March 14th, 2008

Pete, Ken, Sean

=item * There can be multiple types (as many as you want, actually) of games played in the database file.  For example, lets say Race for the Galaxy and
Ra are both your favorite games and you play them a lot with your friends.  Your game database file may look like this:

[Race for the Galaxy]

Joe, Tim, Mike

Mike, Pete, Tim, Joe

Sean, Tim, Joe

[Ra]

Joe, Tim, Mike

Mike, Pete, Joe

Tim, Sean, Joe

=item * The database can be used to store and track player scores per game.  This is totally optional and games can be mixed configuration (scores and no
scores).  Your game database file may look like the following:

[Wizard!]

; March 14th, 2008

Joe{250}, Tim{70}, Mike{-10}

; March 21st, 2008

; NOTE: there are no scores for this game because Tim didn't record them

Mike, Pete, Tim, Joe

; March 24th, 2008

Sean{100}, Tim{80}, Joe{20}

=back

=head1 NOTIFICATION FILE FORMAT

The email notification text file is format as follows:

=over

[<smtp server name>]

<email_1>

<email_2>

...

<email_N>

Here is a sample configuration:

[smtp.myhost.com]

joe@myhost.com

mike@myhost.com

=back

=head1

=cut
