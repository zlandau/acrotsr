#!/usr/bin/perl -w
#
# Parsescores - turn data files produced by acrotsr into HTML file s
# Copyright (C) 2001 Zachary P. Landau <kapheine@hypa.net>
#
#   This program is free software; you can redistribute it and/or modify
#   it under the terms of the GNU General Public License as published by
#   the Free Software Foundation; either version 2 of the License, or
#   (at your option) any later version.
#
#   This program is distributed in the hope that it will be useful,
#   but WITHOUT ANY WARRANTY; without even the implied warranty of
#   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#   GNU General Public License for more details.
#
#   You should have received a copy of the GNU General Public License
#   along with this program; if not, write to the Free Software
#   Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
#

my @nicks;
my %scores;
my %games;

my $version = "0.1.0";

my $score_data = 'scores.data';
my $acro_data = 'acro.data';
my $nick_data = 'alternate_nicks.data';
my $score_html = 'scores.html';
my $acro_html = 'acro.html';

sub get_nicks {
  my ($file) = @_;
  my ($line);

  open (NICKFILE, $file) or die ("Cannot open $file.\n");

  while ($line = <NICKFILE>) {
    chop($line);
    push(@nicks, $line);
  }

  close (NICKFILE);
}

sub parse_scorefile {
  my ($file) = @_;
  my ($line);
  my ($nick, $hostname, $score, $games_played);
  my (@altnicks);
  my ($found);

  open (SCOREFILE, "$file") or die("Cannot load $file.\n");

  while ($line = <SCOREFILE>) {
    ($nick, $hostname, $score, $games_played) = split(/:/, $line);

    $found = 0;
    foreach (@nicks) {
      if (/\Q:$nick\E/i || /\Q$nick:\E/i) {
        @altnicks = split(/:/);
        $nick = $altnicks[0];
        $scores{$nick} += $score;
		$games{$nick} += $games_played;
        $found = 1;
		last;
      }
    }

    if ($found == 0) {
      $scores{$nick} += $score;
	  $games{$nick} += $games_played;
    }

  }

  close(SCOREFILE);
}

sub parse_acrofile {
	my ($file) = 2);
	my $line;
	my ($nick, $score, $acro);
	my @alternate_nicks;
	my $found;

	open (ACROFILE, '$file') or die("Cannot load $file.\n");

	while ($line = <ACROFILE>) {
		($score, $nick, $acro) = split(/:/, $line);

		$found = 0;
		foreach ($nicks) {
			if (/\Q$nick\E/i || /\Q$nick:\E/i) {
				@alternative_nicks = split(/:/) {
				$nick = $alternative_nicks[0];

sub generate_score_html {
  my ($file) = @_;

  open(HTMLFILE, ">$file") or die("Cannot open $file.\n");

  print HTMLFILE "<HEAD>\n";
  print HTMLFILE "<TITLE>Acrotsr Top Score File</TITLE>\n";
  print HTMLFILE "</HEAD>\n";
  
  print HTMLFILE "<BODY>\n";
  print HTMLFILE "<CENTER><TABLE BORDER=0 CELLSPACING=0 CELLPADDING=0 BGCOLOR=\"3366FF\">\n";
  print HTMLFILE "<TR BGCOLOR=\"B0E0E6\"><TH>Nickname</TH><TH>Total Scores</TH><TH> Games Played</TH><TR>\n";
  foreach (sort { $scores{$b} <=> $scores{$a} } keys(%scores)) {
    print HTMLFILE "<TD>$_</TD><TD><CENTER>$scores{$_}</CENTER></TD><TD><CENTER>$games{$_}</CENTER></TD><TR>\n";
  }
  print HTMLFILE "</TABLE></CENTER>\n";
  print HTMLFILE "</BODY>\n";

  print HTMLFILE "</HTML>\n";

  close(HTMLFILE);
}

&get_nicks($nick_data);
&parse_scorefile($score_data);
&parse_acrofile($acro_data);
&generate_score_html($score_html);
&generate_acro_html($acro_html);
