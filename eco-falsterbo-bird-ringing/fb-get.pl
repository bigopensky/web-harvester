#!/usr/bin/perl -w
# -----------------------------------------------------------------
# Harvester to get records from the Falsterbo Lighthouse Garden
# bird ringing station in sweden.
# -----------------------------------------------------------------
# Copyright (C) 2012 Alexander Weidauer
# Contact: alex.weidauer@huckfinn.de
#               weidauer@ifaoe.de
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
# -----------------------------------------------------------------
use strict;
use Getopt::Long;
use LWP::Simple;
use Pod::Usage;
use Switch;

# -----------------------------------------------------------------
# Constants
# -----------------------------------------------------------------
use constant PFX_DBG   => 'DBG: ';
use constant BASE_URL  => 'http://www.falsterbofagelstation.se';
use constant BASE_PATH => '/arkiv/ringm/ringm_eram.php';
use constant FILTER    => 'valdag=';
use constant DATE_UTIL => 'date -u -d "%s %d days" +%%Y-%%m-%%d';

# -----------------------------------------------------------------
# Parameter
# -----------------------------------------------------------------
my $DELETE  = 0;       # Delete existing datasets in SQL mode
my $TABLE   = 'falsterbo_lighthouse'; # SQL database table
my $DATE    = 'today'; # The date where the offset ist anchored
my $DEBUG   = 0;       # To debug some lines for development
my $WHEN    = '?';     # The resulting date to iterate in time
my $OFFS    = 0;       # The offset in time before/after the $DATE
my $VERB    = 0;       # Show some more Info's
my $FORMAT  = 'text';   # Outpoyformat TEXT, or SQL
my $COMMENT = '#';     # The comment sign
my $PPFX    = $COMMENT.' '; # The text prefix to $VERB somthing,
                            # but get valid SQL
my $OUTFNC  = \&outTab;     # Reference to the output function
my @HEADER  = qw(DATE DSUM SSUM SAVG SPEC);# Header fields ..see SQL

# -----------------------------------------------------------------
# Main
# -----------------------------------------------------------------
# Read parameter
GetOptions (
 'offset=i'  => \$OFFS,
 'verbose'   => \$VERB,
 'delete'    => \$DELETE,
 'date=s'    => \$DATE,
 'table=s'   => \$TABLE,
 'help'      => \&getHelp,
 'fields=s'  => \&checkFields,
 'format=s'  => \&checkFormat,
) or die "$0 ".
 ' [--date ISO8601|today'.
 ' [--offset]'.
 ' [--help]'.
 ' [--verbose|--debug]'.
 ' [--format text|sql]'.
 ' [--delete]'.
 ' [--table  sqlTable]'.
 ' [--fields sqlFieldNames]'.
 "\n";

# Control messages
if ($DEBUG) {
  print $PPFX."SETTINGS:\n";
  print $PPFX."VERBOSE: \t $VERB\n";
  print $PPFX."TIMEPOS: \t $DATE\n";
  print $PPFX."OFFSET:  \t $OFFS days\n";
  print $PPFX."FORMAT:  \t $FORMAT\n";
}

# Get the addressed date
$WHEN = &calcDate($DATE,$OFFS);

# Read and parse the web page
# $code  = -10 invalid URL
# $code  = -20 no Lighthouse Garden table (no catches)
# $code  =   0 no catches
# $code > 0 number of lines in data
# $result holds error messages or the data
my ($code, $result) = &getWebPage($WHEN);

# Handle the result
switch ($code) {
  case (-10)   { die $result; }
  case [-20,1]   { print "$PPFX $result" if $VERB; }
  else         { &{$OUTFNC}($result, $code); }
}

# =====================================================
# Service procedures
# =====================================================
# Read the falsterbo page and parse the stuff
# -----------------------------------------------------
sub getWebPage($) {
  my $date = shift;
  my $url = BASE_URL.BASE_PATH.'?'.FILTER.$date;
  print $PPFX,"..read Falsterbo records $date\n" if $VERB;
  print $PPFX,"  from $url\n" if $DEBUG;
  my $content = get $url;

  return(-10, "Couldn't get data from $url!\n")
   if ! (defined $content);

  print $content,"\n --------------------------\n" if $DEBUG;

  print $PPFX,"..preparation for parsing\n" if $VERB;
  # The HTML code is heavily messed up. No xml parser here!
  $content =~ s/\n//smg;                      #  1. throw line breaks away
  $content =~ s/<(\w+)([^>]*)>/<$1>/smg;      #  2. remove all attributes
  $content =~ s/<([a-z]+)>/\n<$1>\n/smg;      #  3. line break opening tags
  $content =~ s/<\/([a-z]+)>/\n<\/$1>\n/smg;  #  4. line break closing tags
  $content =~ s/^\s+//smg;                    #  5. clear leading white spaces
  $content =~ s/\s+$//smg;                    #  6. clear trailing whitespaces
  $content =~ s:<$::smg;                      #  7. remove dangeling braces
  $content =~ s:<b>::g;                       #  8. remove bold stuff in
  $content =~ s:</b>::g;                      #     the table part
  $content =~ s:<font>::g;                    #  9. remove font stuff in
  $content =~ s:</font>::g;                   #     stuff in the table part
  $content =~ s/^\n//smg;                     # 10. remove empty lines
  $content =~ s/Lighthouse Garden/LHG:\n/smg; # 11. set the table marker
  $content =~ s/Savg\n<\/td>\n<tr>\n<td>/BOF:/smg; # 12. Set the data marker
  $content =~ s/<tr>\n<td>\nTOTAL/EOF:/smg;   # 13. set the eof marker
  $content =~ s:<td>::g;                      # 14. obsolete but nice
  $content =~ s:</td>::g;                     #     remove all tags
  $content =~ s:<tr>::g;                      #     <td></td> and
  $content =~ s:</tr>::g;                     #     <tr></tr>
  $content =~ s/^\n//smg;                     # 15. remove empty lines again

  # We have a Lighthouse table?
  if (! grep (/LHG:/, $content)) {
    return (-20, "No Ligthouse Garden table for $WHEN found!\n");
  }

  # DEBUG the results before parsing
  print $content,"\n --------------------------\n"
    if $DEBUG;

  # Handle text as array now
  my @lines = split (/\n/, $content);
  my $line = '';

  print $PPFX, "..parse ringing data\n" if $VERB;
  # Find first record
  do {
    $line  = shift(@lines);
  } while ( $line && !($line =~ /BOF:/) );
  # return empty stuff if no valid line was found
  return (0, "No ringes birds at $WHEN!\n") if ! $line;

  # Read datasets and check type
  my ($spec, $dsum, $ssum, $savg) = ('', 0, 0, 0);
  my $doNext = 0; my $num =0;
  my %result = ();
  do {
    $spec  = shift(@lines);
    $dsum  = shift(@lines);
    $ssum  = shift(@lines);
    $savg  = shift(@lines);
    if ( !($spec =~ /EOF:/) &&
	  ($dsum =~ /\d+/)  &&
	  ($ssum =~ /\d+/)  &&
	  ($savg =~ /\d+/) ) {
      $doNext = 1; $num++;
      $result{$num} = [ $dsum, $ssum, $savg, $spec ];
    } else {
      $doNext = 0;
    }
  } while ( $doNext );
  return ($num, \%result);
}

# -----------------------------------------------------
# Calculate the requested date
# -----------------------------------------------------
sub calcDate ($$) {
   # calculate the date
   my $cmd = sprintf(DATE_UTIL,@_);
   my $res = `$cmd`; chomp($res);

   # error if not iso 8601
   die "Invalid date $res!\n"
     if ! ($res =~ /\d{4}-\d{2}-\d{2}/);

   # check current date
   $cmd = sprintf(DATE_UTIL,'today',0);
   my $today = `$cmd`;

   # error if in the future
   die "Date $res is in the future!\n"
     if $res gt $today;

   # fine got a valid date
   return $res;
}

# =====================================================
# Output procedures
# =====================================================
# Generate the tabbed output
# -----------------------------------------------------
sub outTab($$) {
  my %data = %{shift(@_)};
  my $numrec = shift(@_);
  print join("\t",@HEADER)."\n";
  for my $key (sort keys %data) {
    my @row = @{$data{$key}};
    print "$WHEN\t",join("\t",@row),"\n";
  }
}

# -----------------------------------------------------
# Generate a output SQL output
# -----------------------------------------------------
sub outSql($$) {
  my %data = %{shift(@_)};
  my $numrec = shift(@_);
  print "DELETE FROM $TABLE WHERE $HEADER[0] = '$WHEN';\n" if $DELETE;
  print "INSERT INTO $TABLE (",join(", ",@HEADER),") VALUES";
  my $sep = '';
  for my $key (sort keys %data) {
    my ($dsum, $ssum, $savg, $spec) = @{$data{$key}};
    $spec =~ s/'/''/g;
    print "$sep\n('$WHEN', $dsum, $ssum, $savg, '$spec')";
    $sep =',' if $sep eq '';
  }
  print ";\n";
}

# =====================================================
# Parameter checks
# =====================================================
# Set the output type TEXT
# -----------------------------------------------------
sub checkFormat() {
  my ($key, $value) = @_;
  switch ($value) {
    case ('text') {
      $OUTFNC  = \&outTab;
      $COMMENT = '#';
    }
    case ('sql') {
      $OUTFNC  = \&outSql;
      $COMMENT = '--';
    }
  }
  $PPFX = $COMMENT.' ';
}


# -----------------------------------------------------
# Set the output type TEXT
# -----------------------------------------------------
sub checkFields() {
  my ($key, $value) = @_;
  my @fields = split(/\s+/,$value);
  my %unique = (); my $err = 0;

  for my $field (@fields) {
    $field = uc($field);                # Case insensitive
    $err++ if ! ($field =~ /\w+/);      # Field name is not a word
    $err++ if defined($unique{$field}); # field name is not unique
    $unique{$field}=1;                  # Into the dict
  }

  if ($#fields < $#HEADER || $err != 0) {
    die "Invalid field description we need 5 unique field ".
      "names in the order \n".
      "Date DaySum SaisonSum SaisonAverage SpeciesName\n".
      "Example: --fields 'DATE DSUM SSUM SAVG SPEC'\n";
  }
  @HEADER = @fields;
}

# -----------------------------------------------------
# Generate the help message
# -----------------------------------------------------
sub getHelp() {
  pod2usage(-verbose => 2);
}

__END__

# =====================================================
# DOCUMENTATION
# =====================================================

=head1 NAME

fb-get - Read Falsterbo bird census records at a date

=head1 SYNOPSIS

fb-get  [--date ISO8601|today  [--offset] [--verbose] [--format text|sql]\
 [--delete] [--table  sqlTable] [--fields sqlFieldNames]

=head1 DESCRIPTION

fb-get is a Harvester to read and parse records from the
Falsterbo Lighthouse Garden bird ringing station in sweden.
It extracts bird ringing statistics for a special day and a
given offset (in days). SQL und plain text can be used as output.

=head1 EXAMPLES

fb-get

fb-get --date 2014-04-10 --offset 12

fb-get --date today --offset -10 --format sql --delete

=head1 OPTIONS

=over 8

=item B<--date> TEXT

The date where the record offset is anchored. Default is 'today'.
The Syntax is defined by the -d option of the UNIX date command.

=item B<--delete>

Delete existing datasets in SQL mode. This option inserts a
the SQl command DELETE FROM $TABLE WHERE DATE = $DATE + $OFFSET.

=item B<--fields> TEXT

Option to change the five SQL field names in exact this order.
Default is 'DATE DSUM SSUM SAVG SPEC'

=over 8

=item DATE

The date field has to be the first

=item DSUM

Day sum of the catched birds the second field.

=item SSUM

Saisonal sum of the cached birds the third field.

=item SAVG

Saisonal average of the cached birds the forth field.

=item SPEC

The taxon of the cached birds the last field.

=back

=item B<--format> text|sql

Output format tabbed text or SQL

=item B<--help>

Print a brief help message and exits.

=item B<--offset> INTEGER

The offset in time before/after the --date.
Negtive value means days before the $DATE
and a positive value means days after the $DATE.

=item B<--table> TEXT

Option to change the SQL table name.
Default is 'falsterbo_lighthouse'

=item B<--verbose>

Show some more info's while the script is working.

=back

=head1 OUTPUT TEXT

All fields are TAB separated.

> ./fb-get.pl --offset -1

DATE	DSUM	SSUM	SAVG	SPEC

2015-04-08	2	42	24	WINTER WREN

2015-04-08	1	13	8	EURASIAN SISKIN

2015-04-08	5	32	50	DUNNOCK

2015-04-08	3	93	209	EUROPEAN ROBIN

2015-04-08	1	13	13	SONG THRUSH

2015-04-08	1	7	6	COMMON CHIFFCHAFF

2015-04-08	1	99	119	GOLDCREST

2015-04-08	5	6	10	BLUE TIT

2015-04-08	1	1	0	WOOD NUTHATCH

2015-04-08	1	18	40	CHAFFINCH

=head1 OUTPUT SQL

> ./fb-get.pl --offset -1 --format sql --delete

DELETE FROM falsterbo_lighthouse WHERE DATE = '2015-04-08';

INSERT INTO falsterbo_lighthouse (DATE, DSUM, SSUM, SAVG, SPEC) VALUES

('2015-04-08', 2, 42, 24, 'WINTER WREN'),

('2015-04-08', 1, 13, 8, 'EURASIAN SISKIN'),

('2015-04-08', 5, 32, 50, 'DUNNOCK'),

('2015-04-08', 3, 93, 209, 'EUROPEAN ROBIN'),

('2015-04-08', 1, 13, 13, 'SONG THRUSH'),

('2015-04-08', 1, 7, 6, 'COMMON CHIFFCHAFF'),

('2015-04-08', 1, 99, 119, 'GOLDCREST'),

('2015-04-08', 5, 6, 10, 'BLUE TIT'),

('2015-04-08', 1, 1, 0, 'WOOD NUTHATCH'),

('2015-04-08', 1, 18, 40, 'CHAFFINCH');


=head1 AUTHOR

(c) - 2012 Alexander Weidauer;

weidauer@ifaoe.de alias
alex.weidauer@huckfinn.de

=cut

# =====================================================
# EOF
# =====================================================
