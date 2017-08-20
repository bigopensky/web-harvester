########################################################################
# metaf2xml/src2raw.pl 1.50
#   convert data from different sources to standard format
#
# copyright (c) metaf2xml 2011-2012
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License as
# published by the Free Software Foundation; either version 2 of the
# License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful, but
# WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
# General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, 59 Temple Place, Suite 330, Boston, MA 02111-1307, USA
########################################################################

package metaf2xml::src2raw;

########################################################################
# some things strictly perl
########################################################################
use strict;
use warnings;
use 5.008_001;

########################################################################
# export the functions provided by this module
########################################################################
BEGIN {
    require Exporter;

    our @ISA       = qw(Exporter);
    our @EXPORT_OK = qw(start_file next_line);
}

sub VERSION {
    return '1.50';
}

END { }

=head1 NAME

metaf2xml::src2raw

=head1 SYNOPSIS

 use metaf2xml::src2raw;
 metaf2xml::src2raw::start_file($format,$suppressNIL,$wmo_prefix);
 while (1) {
   my $line = <>;
   @msgs = metaf2xml::src2raw::next_line($line);
   # process contents of @msgs ...
   last unless defined $line;
 }

=head1 DESCRIPTION

This Perl module contains functions to convert METAR, TAF, SYNOP or BUOY
information provided in files on various public Internet servers to messages
delimited by a newline and in the format specified by the I<WMO Manual No.
306>, without modifications due to distribution (which e.g. lists the initial
part of messages only once for several messages, or uses the "=" (equal sign)
as a delimiter).
It removes the leading keywords C<METAR>, C<SPECI>, C<TAF>, C<SYNOP> and C<BUOY>
and prepends parts of the WMO header according to the argument C<wmo_prefix>.
The output can then be used by the module C<metaf2xml::parser>.

=head1 ABBREVIATIONS

=over

=item noaa

National Oceanic and Atmospheric Administration

=item nws

the National Weather Service department of the NOAA

=item iws

the Internet Weather Source of the NWS

=item adds

the Aviation Digital Data Service of the NWS

=item addsds

the experimental data server of the Aviation Digital Data Service of the NWS

=item cod

College of DuPage

=item fsu

Florida State University

=back

=cut

########################################################################
# define some regular expressions
########################################################################
my $re_id_synop = '(?:S[IMN][A-Z]{2}\d{2})';
my $re_id_buoy = '(?:SS[A-Z]{2}\d{2})';
my $re_id_metaf = '(?:(?:S[AP]|F[CT])[A-Z]{2}\d{2})';
my $re_day  = '(?:0[1-9]|[12]\d|3[01])';
my $re_hour = '(?:[01]\d|2[0-3])';
my $re_min  = '[0-5]\d';
my $re_header_synop = '(?:AAXX {0,2}'. $re_day . $re_hour .'[0134/]|BBXX|OOXX)';
my $re_header_buoy = '(?:ZZYY \d{5})';
my $re_ICAO = '(?:[A-Z][A-Z\d]{3})';
my $re_header_metaf = "(?:(?:COR +|AMD +|METAR +|TAF +|SPECI +)*$re_ICAO )";
my $re_header_sao = "(?:[A-Z]{3,4} (NIL|(?:S[AP]|RS)(?: COR)? $re_hour$re_min (?:AUTO|AWOS|SAWR)))";

########################################################################
# variables to be preserved over function calls
########################################################################
my ($format, $suppressNIL, $wmo_prefix,
    $state, $wmo_header, $wmo_header_fix, $msg_header, $msg,
    $report_id, $dissem, $date, @return_msg);

sub _add_msg {
    my $m = $wmo_header . $_[0];

    $m =~ s/  +/ /g;
    $m =~ s/[ =]*$//;
    push @return_msg, $m;
    return;
}

# special cases:
#   TAFPA TAF PHLI 292334Z ...
#   TAFPQ TAF PGUM 292347Z ...
#   ONTAF VTSP 300330Z ...
#   TFFR 300600Z METAR VRB01KT ...
sub _add_metaf_msg {
    my $m = $_[0];

    $m =~ s/  +/ /g;
    $m =~ s/^ +//;
    $m =~ s/ +$//;
    $m =~ s/^(?:PART \d+ OF \d+ PARTS |ONTAF |TAFP[AQ] )+//;
    $m =~ s/^(METAR|SPECI|TAF(?: AMD| COR)?) \1 /$1 /;
    $m =~ s/^(TAF (?:AMD |COR )?)(?:TAF |COR |AMD )*/$1/;
    $m =~ s/^(?=[A-Z]{3} (?:NIL|(?:S[AP]|RS)(?: COR)? $re_hour$re_min (?:AUTO|AWOS|SAWR)))/C/;

    _add_msg $m
        unless $suppressNIL
           && $m =~ /^$re_header_metaf(?:$re_day$re_hour${re_min}Z (?:$re_day(?:$re_hour|24){2} )?)?(RMK )?NIL[= ]*$/;
    return;
}

# WMO header: TTAA[II] CCCC DDHHMM [BBB]
#   TT:     report type (e.g. SM: main synoptic hour reports, SA: METAR)
#   AA:     region for the stations in the report
#   II:     report number (optional)
#   CCCC:   the report dissemination location
#   DDHHMM: the report dissemination time
#   BBB:    report indicator (optional, if delayed/corrected/amendet/segmented)
#
#   $opt_H: 0 -> (empty)
#           1 -> TT
#           2 -> TTAA[II]
#           3 -> TTAA[II] CCCC
#           4 -> TTAA[II] CCCC DDHHMM
#           5 -> TTAA[II] CCCC DDHHMM [BBB]
sub _format_wmo_header {
    my $hdr = shift;

    return '' unless $wmo_prefix > 0;
    return ($hdr =~ /(((((..)[^ ]+) [^ ]+) \d+)(?: COR| (?:RR|CC|AA)[A-Z]| P[A-Z]{2})?)/)[5 - $wmo_prefix] . ' ';
}

#
# parse METAR/TAF file from NOAA/NWS, College of DuPage, or Florida State Univ.
#   difference: the pattern for the SOM (apart from white space)
#
sub _process_metaf_nws_cod_fsu {
    my $re_SOM;

    local $_ = $_[0];
    $re_SOM = $_[1];

    if (defined $_) {
        s/[\n\r\cA\cC\cZ]+//g;
        s/  +/ /g;

        # check for trailing encoded(!) '=' or ' '
        s/(?<=[^ ])=3D(?:=20)?=? *$/=/;
        s/(?<=[^ ])=20 *$//;

        return
            if /^TX OPMET V1$/;

        # (STARTED: MSGEND)?, -> SOM
        if (/$re_SOM/) {
            # final '=' missing in previous block or missing new line?
            if ($state eq 'STARTED' && ($msg ne '' || $1)) {
                $msg .= $1;
                if (   $msg =~ /^$re_header_metaf *[^ ]{3,}/o
                    || ($msg ne 'TAF NIL' && $msg =~ /^$re_header_sao/o))
                {
                    _add_metaf_msg "$msg_header$msg"
                } else {
                    #print STDERR "IGNORED 1: $.: $msg\n" if $msg ne '';
                }
                $msg = '';
            }
            #print STDERR "IGNORED 2: $.: $msg\n" if $msg ne '';
            $state = 'SOM';

        # SOM -> Sx
        # SOM: KAWN uses SA(GL|EU|EW|UK|..), FT(MX), ..
        # SOM: SAST uses SAAG
        } elsif (   $state eq 'SOM'
                 && (   /^$re_id_metaf [A-Z\d]{4} \d{6}/o
                     || /^(?:S[AP]|F[CT])[A-Z]{2} (?:KAWN|SAST) \d{6}/))
        {
            $state      = 'Sx';
            $wmo_header = _format_wmo_header $_;
            $msg_header = '';

        # Sx: K*, PANC, PGUM, PHFO, TJSJ use (MTR|TAF)[A-Z\d]{3}
        # Sx: UHHH, WMKK use 'METAR DDHHMMZ'
        } elsif (   $state eq 'Sx'
                 && (/^(?:MTR|TAF)[A-Z\d]{3}$/ || /^METAR \d{6}Z$/))
        {
            # skip this line
            #print STDERR "IGNORED 3: $.: $_\n";

        # Sx, STARTED: (MSGSTART +) MSGEND -> Sx
        } elsif (($state eq 'STARTED' || $state eq 'Sx') && /= *$/) {
            if ($state eq 'STARTED' && /^(?:METAR |SPECI |TAF )?$re_ICAO (?:$re_day$re_hour${re_min}Z |NIL ?(?:= ?)?$)/)
            {
                # new message starts, previous didn't end with =
                if (   $msg =~ /^$re_header_metaf *[^ ]{3,}/o
                    || ($msg ne 'TAF NIL' && $msg =~ /^$re_header_sao/o))
                {
                    _add_metaf_msg "$msg_header$msg"
                } else {
                    #print STDERR "IGNORED 4: $.: $msg\n" if $msg ne '';
                }
                $msg = '';
            }
            /^(.*)= *$/;
            $msg = "$msg$1";
            $msg_header = '' if /^(?:METAR|SPECI|TAF) /;
            if (   $msg =~ /^$re_header_metaf *[^ ]{3,}/o
                || ($msg ne 'TAF NIL' && $msg =~ /^$re_header_sao/o))
            {
                _add_metaf_msg "$msg_header$msg"
            } else {
                #print STDERR "IGNORED 5: $.: $msg\n" if $msg ne '';
            }
            $msg = '';
            $state = 'Sx';

        # Sx, STARTED: MSGSTART -> STARTED
        } elsif (   (   ($state eq 'STARTED' || $state eq 'Sx')
                     && /^((?:METAR|SPECI|TAF)(?: AMD| COR)*(?: +([^ ].*))?)/)
                 || ($state eq 'Sx' && /^ *(([^ ].*))/)) # METAR|SPECI|TAF missing
        {
            if ($1) {
                if (defined $2) {
                    $msg = "$1 ";
                    $state = 'STARTED';
                    $msg_header = '' if /^(?:METAR|SPECI|TAF) /;
                } else {
                    $msg_header = "$1 ";
                }
            } else {
                #print STDERR "IGNORED 6: $.: $_\n";
            }

        # STARTED: MSGCONTD
        } elsif ($state eq 'STARTED' && /^ *([^ ].*)/) {
            $msg .= "$1 ";
        }
    } else {
        # end of message could be missing in last block
        _add_metaf_msg "$msg_header$msg"
            if $state eq 'STARTED' && $msg;
    }
    return;
}

#
# parse SYNOP file from NOAA/NWS, College of DuPage or Florida State University
#   difference: the pattern for the SOM (apart from white space)
#
sub _process_synop_nws_cod_fsu {
    my $re_SOM;

    local $_ = $_[0];
    $re_SOM = $_[1];

    if (defined $_) {
        s/[\n\r\cA\cC\cZ]+//g;

        # check for trailing encoded(!) '=' or ' '
        s/(?<=[^ ])=3D(?:=20)?=? *$/=/;
        s/(?<=[^ ])=20 *$//;

        return
            if /^NNNN/ || ($suppressNIL && /NIL=$/);

        # (STARTED: MSGEND)? -> SOM
        if (/$re_SOM/) {
            # final '=' missing in previous block or missing new line?
            if ($state eq 'STARTED' && ($msg ne '' || $1)) {
                _add_msg "$msg_header$msg$1";
                $msg = '';
            }
            $state = 'SOM';

        # ? -> Sx
        } elsif (/^($re_id_synop) ([A-Z\d]{4}) (\d{4})/o) {
            $state      = 'Sx';
            $report_id  = $1;
            $dissem     = $2;
            $date       = $3;
            $wmo_header = _format_wmo_header $_;

        # Sx, STARTED -> STARTED
        } elsif (   ($state eq 'Sx' || $state eq 'STARTED')
                 && /$re_header_synop(?: +[^ ].*| *)$/o)
        {
            _add_msg "$msg_header$msg"
                if $msg;

            s/(?<=^AAXX) */ /;
            /($re_header_synop)(?: +([^ ].*)| *)$/o;
            $state = 'STARTED';
            if (defined $2) {
                $msg = "$1 $2 ";
                $msg_header = '';
            } else {
                $msg = '';
                $msg_header = "$1 ";
            }

        # Sx -> STARTED
        } elsif ($state eq 'Sx') {
            if ($dissem eq 'KGYX' && /^SSMMWN/) {
                # KGYX omits 'AAXX YYGGiw' (and has no '=')
                $state = 'STARTED';
                $msg = '';
                $msg_header = "AAXX ${date}4 ";
            } elsif ($dissem eq 'PTYA' && /^SSYM2 (.{5})/) {
                # PTYA sometimes uses 'SSYM2' instead of 'AAXX' (and has no '=')
                $state = 'STARTED';
                $msg = '';
                $msg_header = "AAXX ${date}4 ";
            }

        # STARTED: MSGSTART SxPF80 KWBC
        # SxPF80 KWBC does not use delimiters, check for IIiii + (NIL | iRixhVV)
        } elsif (   $state eq 'STARTED'
                 && $dissem eq 'KWBC'
                 && substr($report_id, 2) eq 'PF80'
                 && m@^919(?:2[59]|4[358]|5[48]) (?:NIL|[0-4/][1-7/][\d/]{3} )@)
        {
            _add_msg "$msg_header$msg"
                if $msg;
            $msg = "$_ ";

        # STARTED: MSGEND
        # - MDSD uses empty lines as delimiter
        # - PTKK sometimes has no delimiters, last group is (555 .* 9YYGG | NIL)
        } elsif (   $state eq 'STARTED'
                 && (   /^(.*)= *$/                         # end of message
                     || ($dissem eq 'MDSD' && /^ *()$/)     # MDSD && empty line
                     || (   $dissem eq 'PTKK'               # PTKK && ...
                         && (   /^ *(.* NIL)\s*$/           #  ... NIL
                             || (   "$msg $_" =~ / 555 /    #  ... 555 .* 9YYGG
                                 && /^ *(.* 9$date)\s*$/)))))
        {
            $msg = "$msg_header$msg$1";
            _add_msg $msg
                if $msg =~ /^$re_header_synop *[^ ]{3,}/o;
            $msg = '';

        # STARTED: MSGCONTD
        } elsif ($state eq 'STARTED' && /^ *(.+)/) {
            $msg .= $1;
            # MXBA uses fixed width format
            $msg .= ' ' unless $dissem eq 'MXBA';
        }
    } else {
        # end of message could be missing in last block
        _add_msg "$msg_header$msg"
            if $state eq 'STARTED' && $msg;
    }
    return;
}

#
# parse METAR/STAF/TAF cycle file from NOAA/IWS
#
# special cases:
#   TAF GCLP 292300Z 300606 01016KT CAVOK= TAF GCXO 292300Z ...
#   TAF HECA 300400Z 300606 VRB03KT ... CAVOK= HELX 300400Z ...
#   DRZR 300600Z 00000KT CAVOK 24/23 Q1013 METAR DNAA 300600Z ...
sub _process_metaf_cycle_iws {
    my $type;

    local $_ = $_[0];
    $type = $_[1];

    if (defined $_) {
        s/[\n\r\cC\cZ]+//g;

        # check for trailing encoded(!) '=' or ' '
        s/(?<=[^ ])=3D(?:=20)?=? *$/=/;
        s/(?<=[^ ])=20 *$//;

        if (/^ *$/) {                                     # end of message?
            _add_metaf_msg $msg;
            $msg = '';
        } elsif (   /(.*)= ?TAF (.*)/                     # TAF after '='?
                 || /(.*)= ?($re_ICAO .*)/                # ICAO code after '='?
                 || /(.*) METAR ($re_ICAO .*)/)           # METAR + ICAO code?
        {
            _add_metaf_msg "$msg $1";
            $msg = $2;
        } elsif (/^[^\d]/) {                 # start or continuation of message?
            $msg .= $_;
        } elsif (m@^\d{4}/(?:0[1-9]|1[012])/($re_day) ($re_hour):($re_min)$@) {
            # time of report dissemination is N/A, this is the observation time
            $wmo_header = _format_wmo_header "$wmo_header_fix$1$2$3";
        }
    } else {
        _add_metaf_msg $msg
            if $msg;
    }
    return;
}

#
# parse BUOY file from NOAA/NWS
#
sub _process_buoy_nws {
    my $re_SOM;

    local $_ = $_[0];
    $re_SOM = $_[1];

    if (defined $_) {
        s/[\n\r\cA\cC\cZ]+//g;

        # check for trailing encoded(!) '=' or ' '
        s/(?<=[^ ])=3D(?:=20)?=? *$/=/;
        s/(?<=[^ ])=20 *$//;

        # (STARTED: MSGEND)?, -> SOM
        if (/$re_SOM/) {
            # final '=' missing in previous block or missing new line?
            if ($state eq 'STARTED' && ($msg ne '' || $1)) {
                _add_msg "$msg$1";
                $msg = '';
            }
            $state = 'SOM';

        # ? -> Sx
        } elsif (/^($re_id_buoy) ([A-Z\d]{4}) (\d{4})/o) {
            $state      = 'Sx';
            $report_id  = $1;
            $dissem     = $2;
            $date       = $3;
            $wmo_header = _format_wmo_header $_;

        # Sx, STARTED -> STARTED
        } elsif (   ($state eq 'Sx' || $state eq 'STARTED')
                 && /^$re_header_buoy(?: +[^ ].*| *)$/o)
        {
            _add_msg $msg
                if $msg;
            $state = 'STARTED';
            $msg = "$_ ";

        # STARTED: MSGCONTD
        } elsif ($state eq 'STARTED' && /^ *([^ ].*)/) {
            $msg .= "$1 ";
        }
    } else {
        # end of message could be missing in last block
        _add_msg $msg
            if $state eq 'STARTED' && $msg;
    }
    return;
}

=head1 SUBROUTINES/METHODS

=cut

########################################################################
# start_file
########################################################################
sub start_file {

    ($format, $suppressNIL, $wmo_prefix) = @_;

    # init global variables
    $state = '';
    $wmo_header = '';
    $msg_header = '';
    $msg = '';
    $report_id = '';
    $dissem = '';
    $date = '';

=head2 start_file($format,$suppressNIL,$wmo_prefix)

This function must be called before processing a file.
The following arguments are expected:

=over

=item format

origin of the input data: metar_cycle_iws, staf_cycle_iws, taf_cycle_iws, metaf_nws, metaf_cod, metaf_fsu, synop_nws, synop_cod, synop_fsu, buoy_nws

=cut

    if ($format !~
             /^((metar|s?taf)_cycle_iws|(metaf|synop)_(nws|cod|fsu)|buoy_nws)$/)
    {
        $format = '';
        return "ERROR: invalid input data format: '" . $_[0] . "'.";
    }
    if (defined $2) {
        $wmo_header_fix =   { metar => 'SA', staf => 'FC', taf => 'FT' }->{$2}
                          . 'XX NOAA ';
        $wmo_header = _format_wmo_header "${wmo_header_fix}010000";
    }

=item suppressNIL

if true, messages that only contain C<NIL> are not returned

=item wmo_prefix

which parts of the WMO header (C<TTAA[II] CCCC DDHHMM [BBB]>) to prepend
to each message:

=over

=item 0

(no header) (default)

=item 1

C<TT> (report type:

=over

=item SA

METAR

=item SP

SPECI

=item FT

TAF with forecast period >= 12 hours

=item FC

TAF with forecast period < 12 hours

=item SM

SYNOP at main hours (00:00, 06:00, 12:00, 18:00 UTC)

=item SI

SYNOP at intermediate (main + 3) hours

=item SN

SYNOP at non-standard (other than main and intermediate) hours

=item SS

BUOY

=back

)

=item 2

C<TTAA[II]> (like C<1> plus region for the stations and optional report number)

=item 3

C<TTAA[II] CCCC> (like C<2> plus report dissemination location)

=item 4

C<TTAA[II] CCCC DDHHMM> (like C<3> plus report dissemination time)

=item 5

C<TTAA[II] CCCC DDHHMM [BBB]> (like C<4> plus optional indicator if the report is delayed/corrected/amended/segmented)

=back

=back

The function will return 0 on success, or a string describing the error which
occurred.

=cut

    $wmo_prefix = 0
        unless defined $wmo_prefix && $wmo_prefix =~ /^[0-5]$/;

    return 0;
}

########################################################################
# next_line
########################################################################
sub next_line {
    my $line = shift;

=head2 next_line($line)

This function must be called for each line in a file and once with the
argument "undef" at the end of file.

The following arguments are expected:

=over

=item line

string that contains a line from the file, or "undef" after the last line of
the file

=back

The return value is an array of 0, 1 or 2 strings, or "undef" if
L<start_file()|start_file__format__suppressnil__wmo_prefix_> was not called
(never, or after L<next_line()|next_line__line_> was called with "undef").

=cut

    return undef unless $format;

    @return_msg = ();
    if ($format =~ /^(metar|s?taf)_cycle_iws$/) {
        _process_metaf_cycle_iws($line, $1);
    } elsif ($format =~ /^metaf_nws$/) {
        _process_metaf_nws_cod_fsu($line, '(.*)####\d{9}####$');
    } elsif ($format eq 'metaf_cod' || $format eq 'metaf_fsu') {
        _process_metaf_nws_cod_fsu($line, '^\d{3} ()$');
    } elsif ($format eq 'synop_nws') {
        _process_synop_nws_cod_fsu($line, '(.*)####\d{9}####$');
    } elsif ($format eq 'synop_cod' || $format eq 'synop_fsu') {
        _process_synop_nws_cod_fsu($line, '^\d{3} ()$');
    } elsif ($format eq 'buoy_nws') {
        _process_buoy_nws($line, '(.*)####\d{9}####$');
    }

    # after EOF, start_file is required again
    $format = '' unless defined $line;

    return @return_msg;
}

=head1 SEE ALSO

=begin html

<p>
<a href="metafsrc2raw.pl.html">metafsrc2raw(1)</a>,
<a href="metaf.pl.html">metaf(1)</a>,
<a href="parser.pm.html">metaf2xml::parser(3pm)</a>,
</p><!--

=end html

B<metafsrc2raw>(1),
B<metaf>(1),
B<metaf2xml::parser>(3pm),

=for html -->

L<http://metaf2xml.sourceforge.net/>

=head1 COPYRIGHT and LICENSE

copyright (c) 2011-2012 metaf2xml @ L<http://metaf2xml.sourceforge.net/>

This program is free software; you can redistribute it and/or
modify it under the terms of the GNU General Public License as
published by the Free Software Foundation; either version 2 of the
License, or (at your option) any later version.

This program is distributed in the hope that it will be useful, but
WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program; if not, write to the Free Software
Foundation, 59 Temple Place, Suite 330, Boston, MA 02111-1307, USA

=cut

1;
