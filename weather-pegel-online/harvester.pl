#!/usr/bin/env perl
# -----------------------------------------------------
# Q&D WSV pegel harvester for the cross evaluation of
# the IMK stations 
# -----------------------------------------------------
# Copyright (C) 2016 Alexander Weidauer
# Contact: alex.weidauer@huckfinn.de
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.
# -----------------------------------------------------
use strict;
use warnings;
use LWP::Simple;
use Data::Dumper;
use Statistics::Basic qw(:all);
use URI::Escape;
use IO::String;

# -----------------------------------------------------
# Read and parse command line args
# -----------------------------------------------------
my $STN = shift;

# Handle date token UNIX command date switch -d
my $WHEN = shift;
if ( ! defined $WHEN) {
    $WHEN = 'yesterday';
}
# Handle pegel offset WSV from data or IMK -499
my $WHAT = shift;
if ( ! defined($WHAT) ) {
    $WHAT = 'WSV'
}
my $IMK_OFF = -499; # IMK Mittelwasserstand

# Vlide pegel IMK pairs 
my @WSV_SITES=qw(KLOSTER KOSEROW SASSNITZ RUDEN WARNEMÜNDE RUDEN TIMMENDORF+POEL);
my @IMK_SITES=qw(ZI KO VA GO WA KO BO);

# -----------------------------------------------------
# Parameter tests for help station index etc.
# -----------------------------------------------------
# Handle help
if ( (! defined($STN)) or ($STN eq '-h') or ($STN eq '--help') ) {
    print "USAGE $0 station_index:[0..$#WSV_SITES] [date] [WSV|IMK] to get datasets\n";
    print "USAGE $0 -l or --list to list the station index\n";
    print "USAGE $0 -h or --help to get some help \n";
    print"Examples:
> $0 0 today
> $0 1 'yesterday-1 day'
> $0 --list
> $0 --help\n";
    exit 0;
}

# Handle list stations
if ( ($STN eq '-l') or ($STN eq '--list') ) {
    print "# Stations:\n";
    for my $stn (0..$#WSV_SITES) {
        print $stn,' - ',$WSV_SITES[$stn],"\n";
    }
    exit 0;
}

# Check station index
die "Wrong station index $STN!\n" if ($STN<0 or $STN>$#WSV_SITES);

# ------------------------------------------------------
# DATE Setup via UNIX date tool
# ------------------------------------------------------
my $DATE_DE=`date -d '$WHEN' +'%d.%m.%Y'` or die 'Invalid date coding $!\n';
chomp($DATE_DE);
my $DATE_ISO=`date -d '$WHEN' +'%Y-%m-%d'`;
chomp($DATE_ISO);

# Handle URI template
# my $DATA='Wasserstand+Rohdaten';
my $URL='https://www.pegelonline.wsv.de/webservices/files/Wasserstand+Rohdaten/OSTSEE/%s/%s/down.txt';
# Escape the strange WSV names
my ($wsv, $wsvURI) = &escWSV($WSV_SITES[$STN]);
# Get the corresponding IMK site
my $imk=$IMK_SITES[$STN];
# Build the url
my $url  = sprintf($URL,$wsvURI,$DATE_DE);
# Print commented the URL
print "# ", $url,"\n";

# Set windows chomp stuff
local $/ = "\r\n";

# Get basic data like date vendor etc
my $io = IO::String->new(get($url)) or die "Can't open: $!\n";

my $dt = $io->getline or die "Missing date in $url!\n";
my $vt = $io->getline or die "Missing vendor in $url!\n";
my $rg = $io->getline or die "Missing region in $url!\n";
chomp($rg);
die "Wrong no dataset avialable $rg!\n" if (  $rg ne 'OSTSEE' );
my $st = $io->getline or die "Missing station in $url!\n";
my $id = $io->getline or die "Missing identifier in $url!\n";
my $d1 = $io->getline or die "Missing dummy 1 in $url!\n";
my $cm = $io->getline or die "Missing centimeter in $url!\n";
my $d2 = $io->getline or die "Missing dummy 2 in $url!\n";
my $d3 = $io->getline or die "Missing dummy 3 in $url!\n";
my $d4 = $io->getline or die "Missing dummy 4 in $url!\n";
my $pt = $io->getline or die "Missing pegel zero type in $url!\n";
my $p0 = $io->getline or die "Missing pegel zero in $url!\n";

# Postprc header section
chomp($pt, $p0, $cm, $vt, $rg, $id, $st);
if ( $WHAT eq  'WSV') {
    $p0 =~ s/,//; $p0 = int($p0);
}
else {
    $p0 = $IMK_OFF;
}
# Print it
print "#PARAMS: $rg $st $pt $p0 $cm $WHAT\n";
my $ctm='00:00'; my @data=(); my $cnt = 0;

# IMK runs in 10 min intervals WSK in min 
while (my $ln = $io->getline ) {
    chomp($ln);
    # Read time and pegel
    my ($tm, $pg) = split(/#/,$ln);
    # Skip NA values
    next if $pg =~ /XX/;
    # Get hour an minute
    my ($hr, $mn) = split(/:/,$tm);
    # Create 10 min interval
    $mn = substr($mn,0,1).'0';
    $tm = $hr.':'.$mn;
    # Flush data stack
    if ( $ctm ne $tm) {
        if ( $#data > 0) {
            print "SITE: ", $wsv,' DT: ',$DATE_ISO,' TM: ',$ctm,
                " MEAN: ", mean(@data)," $cm SD: ",stddev(@data)," $cm\n";
            $cnt++;
        }

        $ctm = $tm; @data=();
    }
    # Else collect data
    else {
        push(@data,($pg+$p0));
    }
}
# Check if empty file
die "No datasets aviable!\n" if !$cnt;
# Close data handle
$io->close();

# --------------------------------------------------------
# We got a strange URI Encoding mixed between LATIN and
# URI parameter encoding for the WSV pegel names
# --------------------------------------------------------
sub escWSV() {
    my $wsv = shift;
    die "Unkown WSV site!\n" if (! $wsv) or ( $wsv eq '');
    my $wsvURI = $wsv;
    $wsvURI =~ s/Ä/%C4/g;
    $wsvURI =~ s/Ü/%DC/g;
    $wsvURI =~ s/Ö/%D6/g;
    $wsvURI =~ s/ /+/g;
    $wsv =~ s/Ä/AE/g;
    $wsv =~ s/Ü/UE/g;
    $wsv =~ s/Ö/OE/g;
    $wsv =~ s/ /_/g;
    return($wsv, $wsvURI);
}

# EOF -----------------------------------------------------
