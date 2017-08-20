#!/usr/bin/perl
# ------------------------------------------------------------
# WORMS HARVESTER Query tool or marine taxa
# ------------------------------------------------------------
# (C) 2012 IfGDV - A. Weidauer
# -----------------------------------------------------------------
# Copyright (C) 2012 Alexander Weidauer
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
# ------------------------------------------------------------
#@TODO PROOF OF CONCEPT
# ------------------------------------------------------------
use SOAP::Lite;
use Pod::Usage;
use Switch;
use strict;
use Data::Dumper;
use utf8;

my $DEBUG = 0;
binmode STDOUT, ":utf8";
binmode STDERR, ":utf8";


# ------------------------------------------------------------
# Prepare SOAP Client
# ------------------------------------------------------------
my $endpoint = qq{http://www.marinespecies.org/aphia.php?p=soap};
my $tns = "http://aphia/v1.0" ;
my $method_urn = $tns;
my $soapaction = $tns;
my $sObj = SOAP::Lite->new(uri => $soapaction, proxy => $endpoint);

# -------------------------------------------------
# DEFINITION: IO fields, sortation and patter
# -------------------------------------------------
# Field name dump output
my @ORDER_TAB=qw (APHIA_ID NAME AUTHOR RANK STATUS VALID_APHIA_ID VALID_NAME
         VALID_AUTHOR RNK_KINGDOM RNK_PHYLUM RNK_CLASS RNK_ORDER
         RNK_FAMILY RNK_GENUS CITATION );

# Field names SQL / CSV
my @ORDER_CSV=qw (APHIA.ID NAME AUTHOR RANK STATUS VALID.APHIA.ID VALID.NAME
         VALID_AUTHOR KINGDOM PHYLUM CLASS ORDER
         FAMILY GENUS CITATION);

# SOAP entry mapping to field names
my %ORDER_HASH = (
  "AphiaID"       =>  0, "scientificname"  =>  1, "authority"  =>  2,
  "rank"          =>  3, "status"        =>  4,
  "valid_AphiaID" =>  5, "valid_name" =>  6, "valid_authority" =>  7,
  "kingdom"       =>  8, "phylum"     =>  9, "class"           => 10,
  "order"         => 11, "family"     => 12, "genus"           => 13,
  "citation"      => 14,);

# Data types of the fields
my @TYPE = qw (INTEGER STRING STRING  STRING STRING
INTEGER STRING STRING STRING STRING STRING
 STRING STRING STRING STRING);

# -------------------------------------------------
# Data/pattern for command line parameter
# -------------------------------------------------
my @BOOL = qw (true, false);
my @FMT  = qw (DUMP CSV SQL);
my $do     = 0;
my $param  = "";
my $format = "DUMP";
my $fuzzy  = "false";
my $HELP   = "Use $0 --help";

@_ = @ARGV;

# -------------------------------------------------
# Read CLI parameter
# -------------------------------------------------
my $mode = shift;
while ( !$mode eq "" ) {
  switch ($mode) {
    case "--fuzzy"         { $fuzzy = shift  };
    case "--help"          { pod2usage(-verbose => 2) ; exit;  };
    case "--format"        { $format = shift;  }
    case "--search-id"     { $do=1; $param = shift;  }
    case "--search-record" { $do=2; $param = shift;  }
    case "--get-record"    { $do=3; $param = shift;  }
    case "--get-children"  { $do=4; $param = shift;  }
    case "--search-fuzzy"  { $do=5; $param = shift;  }
    case "-h" { pod2usage(2); exit; };
    case "-f" { $format = shift;  }
    case "-i" { $do=1; $param = shift;  }
    case "-n" { $do=2; $param = shift;  }
    case "-r" { $do=3; $param = shift;  }
    case "-c" { $do=4; $param = shift;  }
    case "-s" { $do=5; $param = shift;  }
    case ""   { shift; }
    else {  die "Unkown command line option $mode!\n" };
  }
  $mode = shift;
}
# ------------------------------------------------------
# Consistency check for program settings
# ------------------------------------------------------
die "Request mode missed ! $HELP\n" if $do==0;
die "mode parameter missed $mode! $HELP\n" if ! $param;
die "Invalid format $format for output! The following keys ".
    join("|",@FMT)." are valid!\n"
    if ! grep{ /$format/i } @FMT;

die "Invalid search option $fuzzy! The keys  ".
   join("|",@BOOL)." are valid!\n"
   if ! grep{ /$fuzzy/i } @BOOL;

# ------------------------------------------------------
# Program logic
# ------------------------------------------------------
switch ($do) {

    # --search-id
    case 1 {  search_species_id($param,1); }

    # --search-record
    case 2 {
      my $id = search_species_id($param,0);
      exit if ! $id;
      my $rec = get_record_by_id($id);
      exit if ! $rec;
      print_record($rec,1,1,"");
    }

    # --get-record
    case 3 {
      my $rec = get_record_by_id($param);
      exit if ! $rec;
      print_record($rec,1,1,"");
    }
    # --get-children
    case 4 {
      get_children_by_id($param);
    }

    # --search-fuzzy experimentell
    #   offset funktioniert nicht!
    case 5 {
      search_fuzzy($param, $fuzzy);
    }
}

# ==================================================
# Service routines
# ==================================================
# Get subsequent taxa of a specific taxon
# -------------------------------------------------
sub get_children_by_id() {
    my $sid = $_[0];
    my $offs=0; my $total = 0; my $num=1;
    print "\nWORMS.CHILDREN ID $sid \n" if $format eq "DUMP";
    while ($num > 0) {
	my $recs_ref = get_block_children_by_id($sid,$ offs);
        if ($recs_ref) {
          my @recs = @$recs_ref;
          $num  = @recs;
          foreach my $rec (@recs) {
              $total++;
              print_record($rec,$total==1,0,"  ");
          }
          $offs +=$num+1;
        } else { $num=0; }
        #  print "---- $num $offs $total -----\n";
    }
    print "EOF\n" if $format eq "DUMP";
    print ";\n" if $format eq "SQL" && $total >0;
}

# -------------------------------------------------
# Request for taxa pattern search
# -------------------------------------------------
sub search_fuzzy() {
    my $name  = $_[0];
    my $fuzzy = $_[1];
    my $offs=0; my $total = 0; my $num=1;
    print "\nWORMS.SEARCH.FUZZY PATTERN '$name' \n" if $format eq "DUMP";
    while ($num > 0) {
        my $recs_ref = search_block_fuzzy($name,$offs,$fuzzy);
        if ($recs_ref) {
          my @recs = @$recs_ref; $num  = @recs;
          foreach my $rec (@recs) {
              $total++;
              print_record($rec,$total==1,0,"  ");
          }
          $offs +=$num+1;
        } else { $num=0; }
        if ( $num < 50 || $total >= 50 ) {
                $num=0;
        }
        # print "---- $num $offs $total -----\n";
    }
    print "EOF\n" if $format eq "DUMP";
    print ";\n" if $format eq "SQL" && $total > 0;
}

# ------------------------------------------------------------
# Request to WORMS for a specific taxon by name
# ------------------------------------------------------------
sub search_species_id() {
   my $name  = $_[0];
   my $print = $_[1];
   my $response = $sObj->call(
                   SOAP::Data->name("getAphiaID")->attr({ "xmlns" => $method_urn})
                => SOAP::Data->name("ScientificName" => $name)) ;

   my $aphia_id = $response->result;
   print "INTEGER APHIA.ID ", $aphia_id, "\n"  if $aphia_id && $format eq "DUMP" && $print;
   print "APHIA_ID = ", $aphia_id, "\n"  if $aphia_id && $format eq "SQL" && $print;
   print $aphia_id, "\n"  if $aphia_id && $format eq "CSV && $print";
   return $aphia_id;
}


# ------------------------------------------------------------
# Request to WORMS for a specific taxon by AphiaID
# ------------------------------------------------------------
sub get_record_by_id() {
    my $id  = $_[0];
    my $response = $sObj->call(   SOAP::Data->name("getAphiaRecordByID")->attr({ "xmlns" => $method_urn})
			       => SOAP::Data->name("AphiaID") -> value($id)) ;

    my $result = $response->result;
    print "DGB BEGIN:\n",Dumper($result),"EOF\n" if $DEBUG;

    return $result;
}

# -------------------------------------------------
# @TODO THIS REQUEST DONT WORK
# -------------------------------------------------
sub get_block_children_by_id() {
    my $id   = $_[0];
    my $offs  = $_[1];
    my $response = $sObj->call(   SOAP::Data->name("getAphiaChildrenByID")->attr({ 'xmlns' => $method_urn})
                               => SOAP::Data->name("AphiaID") -> value($id),
                               => SOAP::Data->name("offset")  -> value($offs),
                               => SOAP::Data->name("marine_only") -> value("false")
                              ) ;
    my $result = $response->result;
    print "DGB BEGIN:\n",Dumper($result),"EOF\n" if $DEBUG;

    return $result;
}

# -------------------------------------------------
# DONT WORK
# -------------------------------------------------
sub search_block_fuzzy() {
    my $name   = $_[0];
    my $offs   = $_[1];
    my $fuzzy  = $_[2];
    # print $name, $offs, $fuzzy, "\n";
    my $response = $sObj->call(   SOAP::Data->name("getAphiaRecords")->attr({ 'xmlns' => $method_urn})
                               => SOAP::Data->name("scientificname") -> value($name),
                               => SOAP::Data->name("offset") -> value($offs),
                               => SOAP::Data->name("marine_only") -> value("false"),
                               => SOAP::Data->name("like")  ->  value($fuzzy)) ;
    my $result = $response->result;
    print "DGB BEGIN:\n",Dumper($result),"EOF\n" if $DEBUG;

    return $result;
}


# -------------------------------------------------
# Output service routine record DUMP, CSV and SQL
# @TODO this is a mess rewrite
# -------------------------------------------------
sub print_record() {
    my $record = shift;
    my $first  = shift;
    my $last   = shift;
    my $spc    = shift;
    # asign header section 
    my @head = ();
    @head = @ORDER_TAB if $format eq "SQL";
    @head = @ORDER_TAB if $format eq "CSV";
    @head = @ORDER_CSV if $format eq "DUMP";

    my $num_fields = $#head;
    my @data = (); my @quote = ();
    # NULL and quotation
    for my $i (0..$num_fields) {
      # Handle empty fields  
      $data[$i] = "NULL" if $format eq "SQL";
      $data[$i] = "NA"   if $format eq "CSV" || $format eq "DUMP";
      # Apply quotation
      if ($TYPE[$i] eq "STRING") {
        $quote[$i] = "'";
      } else { $quote[$i] = ""; }
    }

    my %rechash = %$record;
    my $id = $rechash{AphiaID};

    # return if $record{status} =~ "deleted";
    # print %rechash, "\n";
    
    print "\n", $spc, "WORMS ID $id \n" if $format eq "DUMP";
    if ($first && $format eq "SQL") {
      print "INSERT INTO WORMS_TABLE\n(";
      print join(",",@head), ") VALUES\n(";
    }
    if (!$first && $format eq "SQL") {
       print ",\n(";
    }
    if ($first && $format eq "CSV") {
      print join(",",@head), "\n";
    }

    foreach my $k (keys %rechash)  {
        my $value =  $rechash{$k};
        $value =~ s/'/\\'/g; # French quotes author
        my $i = $ORDER_HASH{$k};
        if (! defined($i)) {
            print "NO MATCH ",$k,"\n" if $DEBUG;
            next;
        }
        if ($i>=0) {
          # $data[i] = sprintf("%16s %d %8s %16s %s%s%s",
          #    $k, $i, $TYPE[$i],$head[$i],$quote[$i], $value, $quote[$i])
           $data[$i] = sprintf("%s%8s %16s %s%s%s",
             $spc, $TYPE[$i],$head[$i],$quote[$i], $value, $quote[$i])
          if $format eq "DUMP";

          $data[$i] = $quote[$i].$value.$quote[$i]
          if $format eq "SQL";

          $data[$i] = $quote[$i].$value.$quote[$i]
          if $format eq "CSV";
        }
    }
    print join(",", @data), "\n" if $format eq "CSV";
    print join(",", @data), ")"  if !$last && $format eq "SQL";
    print join(",", @data), ");" if  $last && $format eq "SQL";
    print join("\n", @data)      if $format eq "DUMP";
    print "\n", $spc,"EOF\n"     if  $last && $format eq "DUMP";
}

# -------------------------------------------------
# WORMS dump Data
# -------------------------------------------------
sub print_record_def() {
    my $record = shift;
    my $spc    = shift;
    my %rechash = %$record;
    my $id = $rechash{AphiaID};
    # return if $record{status} =~ "deleted";
    # print %rechash, "\n";
    print "\n", $spc, "WORMS ID $id \n";
    foreach my $k (keys %rechash)  {
        my $value =  $rechash{$k};
        $value =~ s/'/\\'/g; # Franzoesische Authoren unerwuenscht
	print $spc, "  INTEGER APHIA.ID       ", $value, "\n"  if $k =~ m/^AphiaID/;
        print $spc, "  STRING  AUTHOR         '",$value, "'\n" if $k =~ m/^authority/;
        print $spc, "  STRING  NAME           '",$value, "'\n" if $k =~ m/^scientificname/;
        print $spc, "  STRING  RANK           '",$value, "'\n" if $k =~ m/^rank/;
        print $spc, "  STRING  STATUS         '",$value, "'\n" if $k =~ m/^status/;
        print $spc, "  STRING  CITE           '",$value, "'\n" if $k =~ m/^citation/;
	print $spc, "  INTEGER VALID.APHIA.ID ", $value, "\n"  if $k =~ m/^valid_AphiaID/;
	print $spc, "  STRING  VALID.NAME     '",$value, "'\n" if $k =~ m/^valid_name/;
	print $spc, "  STRING  VALID.AUTHOR   '",$value, "'\n" if $k =~ m/^valid_authority/;
	print $spc, "  STRING  KINGDOM        '",$value, "'\n" if $k =~ m/^kingdom/;
	print $spc, "  STRING  PHYLUM         '",$value, "'\n" if $k =~ m/^phylum/;
	print $spc, "  STRING  CLASS          '",$value, "'\n" if $k =~ m/^class/;
	print $spc, "  STRING  ORDER          '",$value, "'\n" if $k =~ m/^order/;
	print $spc, "  STRING  FAMILY         '",$value, "'\n" if $k =~ m/^family/;
        print $spc, "  STRING  GENUS          '",$value, "'\n" if $k =~ m/^genus/;
    }
    print $spc, "EOF \n";
}

# ==================================================
# Help text
# ==================================================
=pod

=head1 NAME

 web-worms - WORMS Harvester Q&D to find taxa

=head1 SYNOPSIS

worms-harvester.pl MODE PARAM [OPTIONS..]

worms-harvester.pl -i Abra

worms-harvester.pl -n Abra


==head1 DESCRIPTION

 The tool is Q&D solution to read and search datasets from the
 taxonomic database WoRMS.  WoRMS is a register for marine
 species. The aim of a World Register of Marine Species (WoRMS) is to
 provide an authoritative and comprehensive list of names of marine
 organisms, including information on synonymy. While highest priority
 goes to valid names, other names in use are included so that this
 register can serve as a guide to interpret taxonomic literature.

 http://www.marinespecies.org/

=head1 MODI

=over 4

=item -i --search-id NAME

  Find taxon name by AphiaID

=item -n --search-record NAME

  Find taxon by name

=item -r --get-record ID

   Get the record for a specific AphiaID

=item -s --search-fuzzy PATTERN
    
   Pattern search with max 50 results (EXPERIMENTAL)

=item -c --get-children ID

  Get su sequent taxa fo a specific AphiaID

=back

=head1 PARAMETER

=over 4

=item NAME

 a scientific name (lat.)

=item PATTERN

 a search pattern like Abra%

=item ID

 a numeric key in WORMS clled AphiaID

=back

=head1 OPTIONEN

=over 4

=item -f --format dump|csv|sql

  Output format

=back

=head1 Output formats

The tool gives you different output structures for each
operation mode (--get-record, --search-record, etc...).

=over 4

=item --search-id

  You get back the key of the (AphiaID)

=back

=over 8

=item FORMAT DUMP (Standardeinstellung)

 INTEGER APHIA.ID 550560

=item FORMAT SQL

 APHIA_ID = 550560

=item FORMAT CSV

550560

=back

=over 4

=item --search-record, --get-record

  Record for species datasets

=back

=over 8

=item FORMAT DUMP (DEFAULT CONFIG)

WORMS ID 550560

  INTEGER APHIA.ID       550560

  STRING  NAME           'Pontoporeia affinis'

  STRING  AUTHOR         'Ekman, 1913'

  STRING  STATUS         'unaccepted'

  STRING  CITE           'Lowry, J. (2012). Pontoporeia ..'

  INTEGER VALID.APHIA.ID 103078

  STRING  VALID.NAME     'Pontoporeia affinis'

  STRING  VALID.AUTHOR   'Lindstroem, 1855'

  STRING  KINGDOM        'Animalia'

  STRING  PHYLUM         'Arthropoda'

  STRING  ORDER          'Amphipoda'

  STRING  CLASS          'Malacostraca'

  STRING  RANK           'Species'

  STRING  FAMILY         'Pontoporeiidae'

  STRING  GENUS          'Pontoporeia'

 EOF

=item FORMAT SQL

 INSERT INTO WORMS_TABLE

  (APHIA_ID, NAME, AUTHOR, STATUS, CITE, RANK,
   VALID_APHIA_ID, VALID_NAME, VALID_AUTHOR,
   RNK_KINGDOM, RNK_PHYLUM, RNK_CLASS,
   RNK_ORDER,  RNK_FAMILY,  RNK_GENUS)

 VALUES

  (550560,'Pontoporeia affinis','Ekman, 1913',
   'unaccepted','Lowry, J. (2012). Pontoporeia ..',
   'Species',103078,'Pontoporeia affinis',
   'Lindstroem, 1855',
   'Animalia','Arthropoda','Amphipoda',
   'Malacostraca','Pontoporeiidae','Pontoporeia');

=item FORMAT CSV

LINE1:APHIA_ID,NAME,AUTHOR,STATUS,CITE RANK,VALID_APHIA_ID,VALID_NAME,VALID_AUTHOR,RNK_KINGDOM,RNK_PHYLUM,RNK_CLASS,RNK_ORDER,RNK_FAMILY RNK_GENUS
LINE2:550560,'Pontoporeia affinis','Ekman, 1913','unaccepted','Lowry, J. (2012). Pontoporeia ..','Species',103078,'Pontoporeia affinis',   'Lindstroem, 1855','Animalia','Arthropoda','Amphipoda','Malacostraca','Pontoporeiidae','Pontoporeia'

=back

=over 4

=item --search-fuzzy, --get-children ID

  A list of secord for pattern search or species groups

=back

=over 8

=item FORMAT DUMP (Default config)

WORMS.CHILDREN ID XXXXX, WORMS.SEARCH.FUZZY PATTERN XXXXX

 WORMS ID 550560
    STRING  VALID.NAME     'Pontoporeia affinis'
    STRING  STATUS         'unaccepted'
  ...
  EOF
  ...
 EOF

=item FORMAT SQL

 INSERT INTO WORMS_TABLE

  (APHIA_ID, NAME, AUTHOR, STATUS, CITE, RANK,
   VALID_APHIA_ID, VALID_NAME, VALID_AUTHOR,
   RNK_KINGDOM, RNK_PHYLUM, RNK_CLASS,
   RNK_ORDER,  RNK_FAMILY,  RNK_GENUS)

 VALUES

  (550560,'Pontoporeia affinis','Ekman, 1913',
   'unaccepted','Lowry, J. (2012). Pontoporeia ..',
   'Species',103078,'Pontoporeia affinis',
   'Lindstroem, 1855',
   'Animalia','Arthropoda','Amphipoda',
   'Malacostraca','Pontoporeiidae','Pontoporeia')

  (550561,'Pontoporeia ...'...),
  ...;

=item FORMAT CSV

 LINE1: APHIA_ID,NAME,AUTHOR,STATUS,CITE RANK,VALID_APHIA_ID,VALID_NAME,VALID_AUTHOR,RNK_KINGDOM,RNK_PHYLUM,RNK_CLASS,RNK_ORDER,RNK_FAMILY RNK_GENUS
 LINE22: 50560,'Pontoporeia affinis','Ekman, 1913','unaccepted','Lowry, J. (2012). Pontoporeia ..','Species',103078,'Pontoporeia affinis',   'Lindstroem, 1855','Animalia','Arthropoda','Amphipoda','Malacostraca','Pontoporeiidae','Pontoporeia'
 LINE3: 550560,'Pontoporeia ...',...,...
 LINE4: ...

=back

=cut

# ------------------------------------------------------------
# EOF
# ------------------------------------------------------------
