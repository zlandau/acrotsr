#!/usr/bin/perl -w
#
# acrotsr - an acrobot whoo
# Copyright (c) 2001 Zachary P. Landau
#

use strict;
use Net::IRC;
use Time::HiRes qw(sleep);

my $debug = 1;

my $version = '0.9.0';

###########################
# user definable variables
my @servers = qw( irc.freenode.net );
my $bot_port = 6667;
my $bot_nick = 'acrotsr';
my $bot_ircname = 'I\'m to lame for grammar.';
my $bot_username = 'acrotsr';
my $versionreply = "acrotsr v$version";
my $password = "PAzNeZcFJV3Vk";

## game vars
my %game;
$game{'default_rounds'} = 10;
$game{'total_rounds'} = 0;
$game{'max_rounds'} = 50;
$game{'round'} = 1;
$game{'channel'} = '#acrotsr';
$game{'guess_delay'} = 45;
$game{'warning_delay'} = 10;
$game{'vote_delay'} = 25;
$game{'round_delay'} = 15;
$game{'max_acro'} = 6;
$game{'min_acro'} = 3;
$game{'min_entries'} = 2;
$game{'score_file'} = 'scores.data';
$game{'acro_file'} = 'acro.data';
$game{'html_output'} = 1;
$game{'banned_words'} = 1;
$game{'paused'} = 0;

my @banned_words = ( 'and', 'the' );

my @set_options = ( 'default_rounds', 'max_rounds', 'guess_delay', 'warning_delay',
					'vote_delay', 'round_delay', 'max_acro', 'min_acro', 'min_entries' );

###########################
# system vars
$game{'acronym'} = undef;
use constant NOGAME			=> 0;
use constant ENTRIES		=> 1;
use constant VOTE			=> 2;
use constant ROUND_DELAY	=> 3;
$game{'stage'} = NOGAME;

my $connection;
my $connected;
my $server;
my $irc = new Net::IRC;
my @names;

# instead of one struct, im using these, referenced by hostname. would a struct
# be better?
my %nickname;
my %current_score;
my %game_score;
my %total_score;
my %voted;
my %acro_entry;
my %authed;
my %games_played;
my @best_acro = (0, '', '');	# best acronym of each game, (score, nick, acro)

my @chars = (qw(A A A A A B C D E E E E E F G H H H H H I I I I I J K L M N N N N N O O O O O P Q R R R R R S S S S S T T T T T U U U V W X Y Y Y Z));

my $delay_time = 0;
my $warning_time = 0;
my $extended_time = 0;			# have we extended the time for more entries?
my $pause_start = 0;			# keep track of time of pause to add to
								# $delay_time etc
my $quit = 0;					# quit on disconnect, or reconnect
my @voting_list;				# kinda weird, but it's a list of numbers from
								# 1..num_of_entries, pos 0 holds voting
								# number of the first entry, pos 1 voting number
								# of the second entry etc :P
my @authorized_hosts;

sub rotate ( \@ ) {				# taken from perl cookbook, p120
	my $listref = shift;
	my $element = $listref->[0];
	push(@$listref, shift @$listref);
	return $element;
}

sub do_connect {
	$connected = 1;
	$server = rotate(@servers);
	print "do_connect: trying to connect to $server\n" if $debug;
	$connection = $irc->newconn( Server		=> $server,
								 Port		=> $bot_port,
								 Nick		=> $bot_nick,
								 Ircname	=> $bot_ircname,
								 Username	=> $bot_username )
		or $connected = 0;
}

sub on_connect {
	my $self = shift;

	print "on_connect: joining $game{'channel'}\n" if $debug;
	$self->join($game{'channel'});
}

sub on_init {
	my ($self, $event) = @_;
	my (@args) = ($event->args);
	shift (@args);

	print "on_init: *** @args\n" if $debug;
}

# what a mess
sub on_msg {
	my ($self, $event) = @_;
	my ($nick) = $event->nick;
	my ($arg) = ($event->args);
	my ($hostname) = ($event->userhost);
	my $access = 0;	 # authorized hostname?

	$nickname{$hostname} = $nick;

	print "*$nick* ", ($event->args), "\n" if $debug;
	
	foreach my $check (@authorized_hosts) {
		$access = 1 if ($check eq $hostname);
	}

	if ($arg =~ /^!access ?(\w*)/i) {
		if (!defined($1)) {
			$connection->privmsg($nick, "Usage: !access [password]");
		} else {	
			if (crypt($1, $password) eq $password) {
				print "Access granted to $nick($hostname)\n" if $debug;
				$connection->privmsg($nick, "Access granted to $nick($hostname)");
				push(@authorized_hosts, $hostname);
			} else {
				print "Access denied to $nick($hostname)\n" if $debug;
				$connection->privmsg($nick, "Access denied to $nick($hostname)");
			}
		}	
	} elsif ($arg =~ /^!set (\w+) (\d+)/i) {
		if ($access == 0) {
			$connection->privmsg($nick, "You do not have access.");
		} else {	
			if (defined($1) && defined($2)) {
				handle_set($nick, $1, $2);
			} else {
				$connection->privmsg($nick, 'Usage: !set [option] [value]');
			}	
		}	
	} elsif ($arg =~ /^!quit ?(.*)/i) {
		$quit = 1;
		if (defined($1)) {
			$connection->quit($1);
		} else {
			$connection->quit('Requested to leave.');
		}
	} elsif ($arg =~ /^!reconnect/i) {
		# auto rotates, so just quit
		$connection->quit('Changing servers');
	} elsif ($arg =~ /^!op/i) {
		$connection->mode($game{'channel'}, '+o', $event->nick);
	} elsif ($arg =~ /^!leave/i) {
		$connection->part($game{'channel'});
	} elsif ($arg =~ /^!/) {
		if ($access == 1) {
			$connection->privmsg($nick, "Invalid command.");
		} else {
			$connection->privmsg($nick, "You do not have access.");
		}	
	} elsif (!&in_channel($nick)) {
		$connection->privmsg($nick, "Cannot vote outside of channel.");
		return 1;
	} elsif ( $game{'stage'} == ENTRIES ) {
		if (&check_validity($arg)) {	# true if valid
			$acro_entry{$hostname} = $arg;
			$self->privmsg($nick, "Entry \"$arg\" has been accepted.");
			$current_score{$hostname} = 0;
			$game_score{$hostname} = 0 unless defined($game_score{"$hostname"});
		} else {
			$self->privmsg($nick, "Entry \"$arg\" has been rejected.");
		}
	} elsif ( $game{'stage'} == VOTE ) {
		&handle_vote($nick, $hostname, $arg);
	}

}	

# handles !set command
sub handle_set {
	my ($nick, $option, $value) = @_;
	
	foreach my $opt (@set_options) {
		if ($option eq $opt) {
			$game{$option} = $value;
			$connection->privmsg($nick, "$option set to $value");
			return;
		}
	}

	# if you never match, invalid option
	$connection->privmsg($nick, "Invalid set command: $option");
}	

sub on_names {
	my ($self, $event) = @_;
	my (@users, $channel) = ($event->args);
	my (@tmpnames, @name);

	($channel, @name) = splice @users, 2;

	$name[0] =~ s/[@\+]//g;
	@names = split(/ /, $name[0]);
}	

sub on_public {
	my ($self, $event) = @_;
	my @to = $event->to;
	my ($nick) = ($event->nick);
	my ($arg) = ($event->args);
	my ($hostname) = ($event->userhost);
	my (@params);

	if (($game{'stage'} == NOGAME) && ($arg =~ /^\!start ?(\d*)/)) {
		if ($1 gt 0 && $1 lt $game{'max_rounds'}) {
			$game{'total_rounds'} = $1;
		} else {
			$game{'total_rounds'} = $game{'default_rounds'};
		}	
		$connection->privmsg($game{'channel'}, "Starting new game with $game{'total_rounds'} rounds.");
		print "on_public: starting new game (requested by $nick)\n" if $debug;
		$game{'stage'} = ENTRIES;
		# we also check names on join, but this starts the list
		$connection->names($game{'channel'});
	} elsif ($arg =~ /^\!start ?(\d*)/) {
		$connection->privmsg($game{'channel'}, "A paused game is still running.\n");
	}

	if (($game{'stage'} != NOGAME) && ($arg =~ /^\!pause/)) {
		print "on_public: pausing game (requested by $nick)\n" if $debug;
		$connection->privmsg($game{'channel'}, "Game has been paused.");
		$game{'paused'} = 1;
		$pause_start = time();
	}

	if (($game{'stage'} != NOGAME) && ($arg =~ /^\!resume/)) {
		print "on_public: resuming game (requested by $nick)\n" if $debug;
		$connection->privmsg($game{'channel'}, "Game has been resumed.");
		$game{'paused'} = 0;
		$delay_time += (time() - $pause_start) if ($delay_time != 0);
		$warning_time += (time() - $pause_start) if ($warning_time != 0);
		$extended_time += (time() - $pause_start) if ($extended_time != 0);
	}

	if (($game{'stage'} != NOGAME) && ($arg =~ /^\!stop/)) {
		$connection->privmsg($game{'channel'}, "Game has been stopped.");
		print "on_public: stopping game (requested by $nick)\n" if $debug;
		$game{'stage'} = NOGAME;
		&clear_game_stats();
	}

	if ($arg =~ /^\!top_ten/) {
		&display_top_ten();
	}	
}	

sub clear_round_stats {
	undef %current_score;
	undef %voted;
	undef %acro_entry;
}

sub clear_game_stats {
	&clear_round_stats();
	undef %game_score;
	undef @voting_list;
	$game{'round'} = 1;
	$game{'paused'} = 0;
	$delay_time = 0;
	$warning_time = 0;
	$pause_start = 0;
	@best_acro = (0, '', '');
}

sub write_game_stats {
	if ($game{'html_output'}) {
		open(SCORE_FILE, ">>$game{'score_file'}") || print "WARNING: Cannot open $game{'score_file'}\n";
		foreach my $person (keys(%total_score)) {
			print SCORE_FILE "$nickname{$person}:$person:$total_score{$person}:$games_played{$person}\n";
		}
		close(SCORE_FILE);

		open(ACRO_FILE, ">>$game{'acro_file'}") || print "WARNING: Cannot open $game{'acro_file'}\n";
		print ACRO_FILE "$best_acro[0]:$best_acro[1]:$best_acro[2]\n";
		close(ACRO_FILE);
	}

}	

sub add_name {
	my ($self, $event) = @_;
	
	printf "*** %s (%s) has joined\n", $event->nick, $event->userhost if $debug;
	push(@names, $event->nick);
}

# not sure how to handle this, so we'll just reconstruct the names list
sub change_name {
	my ($self, $event) = @_;

	$connection->names($game{'channel'});
}

sub remove_name {
	my ($self, $event) = @_;
	my @new_names;

	printf "*** %s (%s) has left\n", $event->nick, $event->userhost if $debug;
	
	foreach my $name (@names) {
		if ($name ne $event->nick) {
			push(@new_names, $name);
		}
	}

	@names = @new_names;
}	

# add more checks
sub on_kick {
	my ($self, $event) = @_;

	printf "*** kicked, rejoining\n";

	$connection->join($game{'channel'});
}

sub on_disconnect {
	my ($self, $event) = @_;

	die("Program complete.\n") if $quit;

	print "Attempting to reconnect.\n" if $debug;
	&do_connect;
}

sub generate_acronym {
	my $acro_length;

	$acro_length = int (rand $game{'min_acro'})+ ($game{'max_acro'} - $game{'min_acro'});
	$game{'acronym'} = join("", @chars [ map { rand @chars } (1..$acro_length) ]);
}

# this routine sucks. the way i display it in order of score is terrible
sub game_over {
	my $player;
	my %ordered_output;

	$game{'stage'} = NOGAME;

	# make a hash with the keys being the game score, for sorting
	# player_nick-total_score allows unique entries, will filter out
	# player_nick later
	foreach $player (keys(%total_score)) {
		$games_played{$player}++;
		$ordered_output{"$nickname{$player}:$total_score{$player}"} = sprintf("%-16.16s %s  %s", $nickname{"$player"}, &center($total_score{"$player"}, 11), &center($games_played{"$player"}, 12));
	}

	$connection->privmsg($game{'channel'}, "Game has ended.");
	$connection->privmsg($game{'channel'}, "Nick             Total Score  Games Played");
	foreach my $score (sort sort_ltg keys(%ordered_output)) {
		$connection->privmsg($game{'channel'}, $ordered_output{$score});
	}
	
	&write_game_stats();
	&clear_game_stats();
}

# displays top ten scores since the bot started running
sub display_top_ten {
	my $player;
	my %ordered_output;
	my $i = 0;

	return if (scalar(keys(%total_score)) == 0);

	foreach $player (keys(%total_score)) {
		$ordered_output{"$nickname{$player}:$total_score{$player}"} = sprintf("%-16.16s %s  %s", $nickname{"$player"}, &center($total_score{"$player"}, 11), &center($games_played{"$player"}, 12));
	}

	$connection->privmsg($game{'channel'}, "Nick             Total Score  Games Played");
	$i = 1;
	foreach my $score (sort sort_ltg keys(%ordered_output)) {
		if ($score == 0) {
			next;
		}	
		$connection->privmsg($game{'channel'}, $ordered_output{$score});
		$i++;
		if ($i == 10) {
			last;
		}
	}
}	

# checks for invalid chars and makes sure it fits the acronym letters, returning
# 1 for valid, 0 for invalid
# XXX: redo this code, it sucks ass
sub check_validity {
	my ($entry) = @_;
	my @words;
	my @letters;
	my $letter;
	my $count;

	if ($entry =~ /[@\-_$%^&*()|~\\\/]/) {
		return 0;	 # invalid 
	}

	@words = split(/ /, $entry);
	@letters = split(//, $game{'acronym'});

	if ($game{'banned_words'} == 1) {
		foreach my $word (@words) {
			foreach my $banned_word (@banned_words) {
				if ($word eq $banned_word) {
					return 0;
				}
			}
		}
	}

	$count = 0;
	foreach $letter (@letters) {
		if ($letter ne uc(substr($words[$count], 0, 1))) {
			return 0;	# invalid
		}
		$count++;
	}

	return 1;	# valid
}

sub in_channel {
	my ($nick) = @_;
	my $name;

	foreach $name (@names) {
		if ($nick eq $name) {
			return 1;
		}
	}

	return 0;
}

# sees if user already voted, if they are in the channel, etc
# handles updating score etc
# handle_vote($nickname, $hostname, $vote)
sub handle_vote {
	my ($nick, $hostname, $vote) = @_;
	my $length;
	my $player;
	my $name;
	my $i;

	if (!&in_channel($nick)) {
		$connection->privmsg($nick, "Cannot vote outside of channel.");
		return 1;
	}

	# valid entry?
	$length = scalar(keys(%acro_entry));

	if ($vote < 1 || $vote > $length) {
		$connection->privmsg($nick, "Invalid entry number: $vote\n");
		return 2;
	}

	if (defined $voted{$hostname}) {
		# already voted, take away old vote
		$current_score{$voted{$hostname}}--;
		$game_score{$voted{$hostname}}--;
		$total_score{$voted{$hostname}}--;
	}

	# seems okay, updated scores
	$i = 1;
	foreach $player (keys(%acro_entry)) {
		if ($vote == $voting_list[$i-1]) {
			if ($nickname{$player} eq $nick) {
				$connection->privmsg($nick, "Cannot vote for yourself");
				return 4;
			} else {
				$connection->privmsg($nick, "Vote for $vote accepted.");
				$voted{$hostname} = $player;
			}	
			$current_score{$player}++;
			$game_score{$player}++;
			$total_score{$player}++;
			last;
		}
		$i++;
	}

}
	
sub display_choices {
	my $i = 1;
	my $entry;
	my @output;

	@voting_list = (1..scalar(keys(%acro_entry)));
	randomize_array(\@voting_list);

	$connection->privmsg($game{'channel'}, "Number Entry");
	foreach $entry (values(%acro_entry)) {
		$output[$i] = sprintf("%4.4s   %.50s", $voting_list[$i-1], $entry);
		$i++;
	}
	
	$output[0] = 'skip';				# dummy value to avoid warning, stupid kludges
	foreach $entry (sort(@output)) {
		next if ($entry eq 'skip');		# skip that dummy value
		$connection->privmsg($game{'channel'}, $entry);
	}
}

# fisher_yates_shuffle, from perl cookbook
# randomizes elements in given array
sub randomize_array {
	my $array = shift;
	my $i;

	for ($i = @$array; --$i; ) {
		my $j = int rand ($i+1);
		next if $i == $j;
		@$array[$i,$j] = @$array[$j,$i];
	}
}

sub display_results {
	my $i = 1;
	my $player;
	my %ordered_output;

	# make a hash with the keys being the game score, for sorting
	# playername-current_score to keep it unique even if they have the same score
	foreach $player (keys(%acro_entry)) {
		$ordered_output{"$nickname{$player}+$voting_list[$i-1]"} = sprintf("%-16.16s %s   %s   %s", $nickname{$player}, &center($voting_list[$i-1], 12), &center($current_score{$player}, 5), &center($game_score{$player}, 10));
		if ($current_score{$player} > $best_acro[0]) {
			$best_acro[1] = $nickname{$player};
			$best_acro[2] = $acro_entry{$player};
		}	
		$i++;
	}
	
	$connection->privmsg($game{'channel'}, "Nick             Entry Number  Score  Game Score");
	foreach my $score (sort sort_gtl keys(%ordered_output)) {
		$connection->privmsg($game{'channel'}, $ordered_output{$score});
	}	
}

# sort greatest to lowest
# format: player:score
sub sort_gtl {
	my ($score1, $score2);

	(undef, $score1) = split(/:/, $a);
	(undef, $score2) = split(/:/, $b);
	
	return $score1 <=> $score2;
}

# sort lowest to greatest
# format: player:score
sub sort_ltg {
	my ($score1, $score2);

	(undef, $score1) = split(/:/, $a);
	(undef, $score2) = split(/:/, $b);

	return $score2 <=> $score1;
}

# pad and center string
# center($text, $pad_len)
sub center {
	my ($text, $pad_len) = @_;
	my $pad;

	$pad = ' ' x ( ($pad_len - length($text))/2 );

	return ($pad . $text . $pad);
}

sub on_ping {
	my ($self, $event) = @_;
	my $nick = $event->nick;

	$self->ctcp_reply($nick, join(' ', ($event->args)));
	print "*** CTCP PING request from $nick received\n";
}

sub on_version {
	my ($self, $event) = @_;
	my $nick = $event->nick;

	$self->ctcp_reply($nick, "VERSION $version");
}	
	
sub on_nick_taken {
	my ($self) = shift;

	$self->nick($self->nick . '_');
}	

while (!$connected) {
	&do_connect();
}

print "Installing handlers.\n" if $debug;

$connection->add_handler('msg', \&on_msg);
$connection->add_handler('public', \&on_public);
$connection->add_handler('join', \&add_name);
$connection->add_handler('nick', \&change_name);
$connection->add_handler('part', \&remove_name);
$connection->add_handler('kick', \&on_kick);
$connection->add_handler('quit', \&remove_name);
$connection->add_handler('cping', \&on_ping);
$connection->add_handler('cversion', \&on_version);

$connection->add_global_handler([ 251,252,253,254,302,255 ], \&on_init);
$connection->add_global_handler('disconnect', \&on_disconnect);
$connection->add_global_handler(376, \&on_connect);
$connection->add_global_handler(433, \&on_nick_taken);
$connection->add_global_handler(353, \&on_names);

$connection->join($game{'channel'});

while (1) {
	$irc->do_one_loop;

	$bot_nick = $connection->nick;

	if ($game{'paused'} == 1) {
		next;
	}

	# XXX: check number of entries
	if ($game{'stage'} == ENTRIES) {
		if ($delay_time == 0) {
			&generate_acronym;
			$connection->privmsg($game{'channel'}, "Round $game{'round'}: Acronym is $game{'acronym'}");
			$connection->privmsg($game{'channel'}, "/msg $bot_nick [entry]");
			$connection->privmsg($game{'channel'}, "You have $game{'guess_delay'} seconds");
			$delay_time = time() + $game{'guess_delay'};
		} elsif ((time() > $delay_time) && ($warning_time == 0)) {
			$connection->privmsg($game{'channel'}, "$game{'warning_delay'} seconds left");
			$warning_time = time() + $game{'warning_delay'};
		} elsif ((time() > $warning_time) && ($warning_time != 0)) {
			if (scalar(keys(%acro_entry)) < $game{'min_entries'}) {
				if ($extended_time == 0) {
					$connection->privmsg($game{'channel'}, "Not enough entries. Extending time.");
					$warning_time = time() + ($game{'guess_delay'} / 2);
					$extended_time = 1;
				} else {
					$connection->privmsg($game{'channel'}, "Still not enough entries. Ending Game.");
					$extended_time = 0;
					&game_over();
				}	
			} else {
				$game{'stage'} = VOTE;
				$delay_time = 0;
				$warning_time = 0;
				$extended_time = 0;
			}	
		}
	} elsif ($game{'stage'} == VOTE) {
		if ($delay_time == 0) {
			&display_choices();
			$connection->privmsg($game{'channel'}, "/msg $bot_nick \#. You have $game{'vote_delay'} seconds.");
			$delay_time = time() + $game{'vote_delay'};
		} elsif (time() > $delay_time) {
			$delay_time = 0;
			&display_results();
			$delay_time = time() + $game{'round_delay'};
			if ($game{'round'} == $game{'total_rounds'}) {
				&game_over();
			} else {
				$game{'stage'} = ROUND_DELAY;
				&clear_round_stats();
				$game{'round'}++;
			}	
		}	
	} elsif ($game{'stage'} == ROUND_DELAY) {
		if (time() > $delay_time) {
			$game{'stage'} = ENTRIES;
			$delay_time = 0;
		}	
	}	

}
