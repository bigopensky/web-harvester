#!/usr/bin/perl
# ------------------------------------------------------------
# WORMS HARVESTER fuer die Abfrage mariner Arten 
# ------------------------------------------------------------
# (C) 2012 IFGDV - A. Weidauer 
# KONTAKT alex.weidauer@huckfinn.de
# ------------------------------------------------------------
#@TODO PROOF OF CONCEPT
# ------------------------------------------------------------
use SOAP::Lite;
use Pod::Usage;
use Switch;
use strict;
use Data::Dumper;

my $DEBUG = 0;

# ------------------------------------------------------------
# SOAP Client vorbereiten 
# ------------------------------------------------------------
my $endpoint = qq{http://www.marinespecies.org/aphia.php?p=soap};
my $tns = "http://aphia/v1.0" ;
my $method_urn = $tns;
my $soapaction = $tns;
my $sObj = SOAP::Lite->new(uri => $soapaction, proxy => $endpoint);

# -------------------------------------------------
# DEFINITION: Ausgabe Felder, Sortierung und Muster
# -------------------------------------------------
# Feldnamen DUMP
my @ORDER_TAB=qw (APHIA_ID NAME AUTHOR RANK STATUS VALID_APHIA_ID VALID_NAME 
         VALID_AUTHOR RNK_KINGDOM RNK_PHYLUM RNK_CLASS RNK_ORDER 
         RNK_FAMILY RNK_GENUS CITATION );

# Feldnamen bzw. Spaltennamen SQL und CSV
my @ORDER_CSV=qw (APHIA.ID NAME AUTHOR RANK STATUS VALID.APHIA.ID VALID.NAME 
         VALID_AUTHOR KINGDOM PHYLUM CLASS ORDER 
         FAMILY GENUS CITATION);

# Zuordnung der SOAP Eintraege zu den Feldnamen (INDEX)
my %ORDER_HASH = (
  "AphiaID"       =>  0, "scientificname"  =>  1, "authority"  =>  2, 
  "rank"          =>  3,  "status"        =>  4,
  "valid_AphiaID" =>  5, "valid_name" =>  6, "valid_authority" =>  7, 
  "kingdom"       =>  8, "phylum"     =>  9, "class"           => 10, 
  "order"         => 11, "family"     => 12, "genus"           => 13,
  "citation"     =>  14,);

# Datentypen der einzelnen Felder 
my @TYPE = qw (INTEGER STRING STRING  STRING STRING
INTEGER STRING STRING STRING STRING STRING 
 STRING STRING STRING STRING);

# -------------------------------------------------
# Parameter abfragen
# -------------------------------------------------
my @BOOL = qw (true, false);
my @FMT  = qw (DUMP CSV SQL);
my $do     = 0; 
my $param  = "";
my $format = "DUMP";
my $fuzzy  = "false";
@_ = @ARGV; 

# -------------------------------------------------
# Parameter auslesen
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
    else {  die "Unbekannter Parameter $mode!\n" };
  }
  $mode = shift;
}
# ------------------------------------------------------
# Konsistenz-Check der Parameter
# ------------------------------------------------------
die "Fehlender Arbeitsmode !\n" if $do==0;
die "Fehlender Parameter fuer $mode!\n" if ! $param;
die "Falsches Format $format! Die Formatschluessel ".
    join("|",@FMT)." sind erlaubt!\n"
    if ! grep{ /$format/i } @FMT;

die "Falsche Fuzzy-Option $fuzzy! Die Schluessel ".
   join("|",@BOOL)." sind erlaubt!\n"
   if ! grep{ /$fuzzy/i } @BOOL;

# ------------------------------------------------------
# Programmlogik aufrufen
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
# Deklaration Service-Routinen
# ==================================================
# Untergordnete Taxa eines bestimmten Taxon suchen 
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
# Taxa unscharf suchen
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
# Art in WORMS suchen 
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
# Auslesen des WORMS Records bei gegebenen AphiaID
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
# DONT WORK
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
# WORMS Daten ausgeben 
# -------------------------------------------------
sub print_record() {
    my $record = shift;
    my $first  = shift;
    my $last   = shift;
    my $spc    = shift;
    my @head = ();

    @head = @ORDER_TAB if $format eq "SQL";
    @head = @ORDER_TAB if $format eq "CSV";
    @head = @ORDER_CSV if $format eq "DUMP";
    
    my $num_fields = $#head;
    my @data = (); my @quote = ();
    for ( my $i = 0; $i <= $num_fields; $i++ ) {
      $data[$i] = "NULL" if $format eq "SQL";
      $data[$i] = "NA"   if $format eq "CSV" || $format eq "DUMP";
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
        $value =~ s/'/\\'/g; # Franzoesische Authoren...
        my $i = $ORDER_HASH{$k};
        if ($i>=0) {
          # $data[i] = sprintf("%16s %d %8s %16s %s%s%s",
          #    $k, $i, $TYPE[$i],$head[$i],$quote[$i], $value, $quote[$i]);
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
# WORMS Daten ausgeben 
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
# Hilfetext
# ==================================================
=pod
=head1 NAME

 web-worms - WORMS Harvester fuer dynamische Abfragen 

=head1 SYNOPSIS

web-worms MODE PARAM [OPTIONEN..]

=head1 MODI

=over 4

=item -i --search-id NAME

  nach einer AphiaID suchen

=item -n --search-record NAME  

  nach einem WoRMS-Record suchen

=item -r --get-record ID 

   Record fuer AphiaID suchen

=item -s --search-fuzzy MUSTER

   Unschrafe Suche nach einem Namen EXPERIMENTELL
   Max. 50 Ergebnisse werden ausgegeben.

=item -c --get-children ID    

  Records unterhalb der AphiaID suchen

=back

=head1 PARAMETER

=over 4

=item NAME 

 ein wissenschaftlicher Name

=item MUSTER 

 ein Suchmuster z.B. Abra%


=item ID    

 ein Zahlenschluessel in WORMS AphiaID genannt

=back

=head1 OPTIONEN

=over 4

=item -f --format dump|csv|sql

  Ausgabeformat

=back

=head1 Ausgabeformate

Je nach Aufgabe werden unterschiedliche Ausgaben erzeugt

=over 4

=item --search-id 

  Die  Schluesselnummer der Art (AphiaID) 

=over 8

=item FORMAT DUMP (Standardeinstellung)

 INTEGER APHIA.ID 550560

=item FORMAT SQL

 APHIA_ID = 550560

=item FORMAT CSV

550560

=back

=item --search-record, --get-record 

  Der Datensatz einer Art

=over 8

=item FORMAT DUMP (Standardeinstellung) 

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

ZEILE1:APHIA_ID,NAME,AUTHOR,STATUS,CITE RANK,VALID_APHIA_ID,VALID_NAME,VALID_AUTHOR,RNK_KINGDOM,RNK_PHYLUM,RNK_CLASS,RNK_ORDER,RNK_FAMILY RNK_GENUS
ZEILE2:550560,'Pontoporeia affinis','Ekman, 1913','unaccepted','Lowry, J. (2012). Pontoporeia ..','Species',103078,'Pontoporeia affinis',   'Lindstroem, 1855','Animalia','Arthropoda','Amphipoda','Malacostraca','Pontoporeiidae','Pontoporeia' 

=back

=item --search-fuzzy, --get-children ID    

  Eine Liste von Datensaetzen mehrer Arten

=over 8

=item FORMAT DUMP (Standardeinstellung)

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

 ZEILE1: APHIA_ID,NAME,AUTHOR,STATUS,CITE RANK,VALID_APHIA_ID,VALID_NAME,VALID_AUTHOR,RNK_KINGDOM,RNK_PHYLUM,RNK_CLASS,RNK_ORDER,RNK_FAMILY RNK_GENUS
 ZEILE2: 50560,'Pontoporeia affinis','Ekman, 1913','unaccepted','Lowry, J. (2012). Pontoporeia ..','Species',103078,'Pontoporeia affinis',   'Lindstroem, 1855','Animalia','Arthropoda','Amphipoda','Malacostraca','Pontoporeiidae','Pontoporeia' 
 ZEILE3: 550560,'Pontoporeia ...',...,...
 ZEILE4: ...

=back

=cut

# ------------------------------------------------------------
# EOF
# ------------------------------------------------------------
