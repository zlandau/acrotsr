#!/usr/bin/perl -w
#
# Generate - create a crypted password for use with acrotsr
# Copyright (C) 2000 Zachary P. Landau <kapheine@hypa.net>
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

use strict;
use Term::ReadKey;

my (@password, $salt);

print "Enter desired password: ";
ReadMode 'noecho';
$password[0] = ReadLine(0);
chop($password[0]);
print "\n";
print "Retype password: ";
$password[1] = ReadLine(0);
chop($password[1]);
print "\n";
print "Desired salt (two characters): ";
$salt = ReadLine(0);
chop($salt);
print "\n";
ReadMode 'normal';

if ($password[0] eq $password[1]) {
  if ($salt =~ /^[a-zA-Z]{2}$/) {
    die("Crypted password: " . crypt($password[0], $salt) . "\n");
  } else {
    die("Invalid salt.\n");
  }
} else {
  die("Passwords do not match.\n");
}  
