########################################################################
# metaf2xml/parser.pm 1.50
#   parse a METAR, TAF, SYNOP or BUOY message
#
# copyright (c) metaf2xml 2006-2012
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

package metaf2xml::parser;

########################################################################
# some things strictly perl
########################################################################
use strict;
use warnings;
use 5.008_001;

use POSIX qw(floor);

########################################################################
# export the functions provided by this module
########################################################################
BEGIN {
    require Exporter;

    our @ISA       = qw(Exporter);
    our @EXPORT_OK = qw(parse_report);
}

sub VERSION {
    return '1.50';
}

END { }

=head1 NAME

metaf2xml::parser

=head1 SYNOPSIS

 use metaf2xml::parser;
 my %report = metaf2xml::parser::parse_report($msg,$default_msg_type);

=head1 DESCRIPTION

This Perl module contains functions to analyze a string (per default as a METAR
message). Its function L<parse_report()|parse_report__msg__default_msg_type_>
returns a hash with all its components.

=cut

########################################################################
# define lots of regular expressions
########################################################################
my $re_ICAO = '(?:[A-Z][A-Z\d]{3})';
my $re_day = '(?:0[1-9]|[12]\d|3[01])';
my $re_hour = '(?:[01]\d|2[0-3])';
my $re_min = '[0-5]\d';
my $re_bbb = '(?:(?:RR|CC|AA)[A-Z]|P[A-Z]{2})';
my $re_A1bw = '(?:1[1-7]|2[1-6]|3[1-4]|4[1-8]|5[1-6]|6[1-6]|7[1-4])';
# WMO-No. 306 Vol I.1, Part A, code table 0877, but only actual directions
my $re_dd = '(?:0[1-9]|[12]\d|3[0-6])';
my $re_rwy_des = "$re_dd(?:[LCR]|LL|RR)?";
my $re_rwy_des2 = '(?:[05][1-9]|[1267]\d|[38][0-6])'; # add 50 for rrR
my $re_wind_speed = 'P?[1-9]?\d\d';
my $re_wind_speed_unit = '(?: ?KTS?| ?MPS| ?KMH)';
my $re_wind_dir = "(?:$re_dd|00)";
# EXTENSION: allow wind direction not rounded to 10 degrees
my $re_wind = "(VRB|///|$re_wind_dir\\d)(//|$re_wind_speed)(?:G($re_wind_speed))?($re_wind_speed_unit)";
my $re_vis = '(?:VIS|VSBY?)';
my $re_vis_m = '(?:0[0-7]50|[0-4]\d00|\d000|9999)';
my $re_vis_km = '[1-9]\d?KM';
my $re_vis_m_km_remark = "(?:${re_vis_m}M?|[1-9]\\d{2,3}M|$re_vis_km)";
my $re_frac16 = '[135]/16';
my $re_frac8 =  '[1357]/8';
my $re_frac4 =  '[13]/4';
my $re_frac2 =  '1/2';
my $re_vis_frac_sm0 = "(?:$re_frac16|$re_frac8|$re_frac4|$re_frac2)";
# MANAIR 2.6.8: no space between whole miles and fraction
my $re_vis_frac_sm1 = "1(?: ?(?:$re_frac8|$re_frac4|$re_frac2))";
# EXTENSION: allow /8 for 2 miles
my $re_vis_frac_sm2 = "2(?: ?(?:$re_frac8|$re_frac4|$re_frac2))";
# EXTENSION: allow /2 for 3 miles
my $re_vis_frac_sm3 = "3(?: ?(?:$re_frac2))";
my $re_vis_whole_sm = '(?:[1-9]\d0|1[0-5]|[2-9][05]|\d)'; # longest match first
my $re_vis_sm =   "(?:M1/4"
                 . "|$re_vis_frac_sm0"
                 . "|$re_vis_frac_sm1"
                 . "|$re_vis_frac_sm2"
                 . "|$re_vis_frac_sm3"
                 . "|$re_vis_whole_sm)"; # last, to find fractions first
my $re_gs_size = "(?:M1/4|[1-9]\\d*(?: $re_frac4| $re_frac2)?|$re_frac4|$re_frac2)";
my $re_rwy_vis = '[PM]?\d{4}';
my $re_rwy_wind = "(?:WIND )?(?:RWY($re_rwy_des) ?|($re_rwy_des)/)((?:///|VRB|${re_wind_dir}0)(?://|$re_wind_speed(?:G$re_wind_speed)?)$re_wind_speed_unit)(?: ($re_wind_dir\\d)V($re_wind_dir\\d))?";
my $re_rwy_wind2 = "((?:///|VRB|${re_wind_dir}0)(?://|$re_wind_speed(?:G$re_wind_speed)?)$re_wind_speed_unit)/RWY($re_rwy_des)";

# format change around 03/2009: trailing 0 for wind direction
my $re_rs_rwy_wind = "(RS|$re_rwy_des)($re_wind_dir)0?($re_wind_speed(?:G$re_wind_speed)?$re_wind_speed_unit)";

my $re_compass_dir = '(?:[NS]?[EW]|[NS])';
my $re_compass_dir16 = "(?:[NE]NE|[ES]SE|[SW]SW|[NW]NW|$re_compass_dir)";

# represents exact location
my $re_loc_exact = "(?:(?:OVR|AT) AP)";

# approximate location
my $re_loc_approx = "(?:OMTNS|OVR (?:LK|RIVER|VLYS|RDG)|ALG (?:RIVER|SHRLN)|IN VLY|NR AP|VC AP)";

# inexact/all direction(s)
my $re_loc_inexact = "(?:ARND|ALQDS|V/D)";

# inexact distance
my $re_loc_dsnt_vc = "(?:DSNT|VC)";

# compass direction or quadrant, with optional exact distance
my $re_loc_compass = "(?:(?:(?:$re_loc_dsnt_vc|[1-9]\\d*(?:KM|NM)? ?))?(?:TO )?(?:GRID )?$re_compass_dir16(?: QUAD)?)";

my $re_loc_thru = "(?:(?:$re_loc_dsnt_vc )?(?:TO )?(?:(?:(?:$re_loc_compass(?: $re_loc_approx)?|(?:$re_loc_approx |OBSCG MTNS )?$re_loc_compass|OHD)(?:(?: ?- ?| THRU )(?:$re_loc_compass|OHD))*)|$re_loc_approx|$re_loc_inexact)|$re_loc_exact)";
my $re_loc_and = "(?:$re_loc_thru(?:(?:[+/, ]| AND )$re_loc_thru)*)";
my $re_loc = "(?:[ /-]$re_loc_and)";
my $re_wx_mov_d3 = "(?: (MOVD?) ($re_compass_dir16(?:-$re_compass_dir16)*|OHD|UNKN)| (STNRY))";
my $re_num_quadrant1 = '(?:1(?:ST|ER)?|2(?:ND)?|3(?:RD)?|4(?:TH)?)';
my $re_num_quadrant = "(?: $re_num_quadrant1(?:[- ]$re_num_quadrant1)*[ /]?QUAD)";

my $re_loc_quadr3 = "(?:(?: TO)?($re_loc)|(?:(?: (DSNT))?($re_num_quadrant)))";

my $re_weather_desc = '(?:MI|BC|PR|DR|BL|SH|TS|FZ)';
my $re_weather_prec = '(?:(?:DZ|RA|SN|SG|PL|GR|GS)+|IC|UP)';
my $re_weather_obsc = '(?:BR|FG|FU|VA|DU|SA|HZ)';
my $re_weather_other = '(?:PO|SQ|FC|SS|DS)';
# EXTENSION: allow SHRADZ (ENHK)
my $re_weather_ts_sh = '(?:RA|SN|PL|GR|GS|DZ)+|UP';
my $re_weather_bl_dr = '(?:SN|SA|DU)';
# WMO-No. 306 Vol I.1, Part A, Section C:
#   Intensity shall be indicated only with precipitation, precipitation
#   associated with showers and/or thunderstorms, duststorm or sandstorm.
#   Not more than one descriptor shall be included in a w´w´ group ...
# EXTENSION: allow JP (adjacent precipitation in old METAR)
# EXTENSION: allow SN, BR, PL with FZ, filter out FZSN later
# EXTENSION: allow +/- with *FG, DS, SS, BR, TS
my $re_weather_w_i = "(?:$re_weather_prec|FC|JP"
                      . "|(?:TS|SH)(?:$re_weather_ts_sh)"
                      . "|FZ(?:(?:RA|DZ|SN|BR|PL)+|UP)"
                      . "|(?:FZ|MI|BC|PR)?FG"
                      . "|DS|SS|BR|TS)";
# FMH-1 12.6.8a
#   Intensity shall be coded with precipitation types, except ice crystals
#   (IC), hail (GR or GS), and unknown precipitation (UP)
# -> if no intensity is given for IC, GR, GS, *UP: don't add isModerate
my $re_weather_wo_i = "(?:$re_weather_obsc|$re_weather_other|TS|IC|GR|GS"
                       . "|(?:FZ|SH|TS)?UP"
                       . "|(?:FZ|MI|BC|PR)FG"
                       . "|(?:BL|DR)$re_weather_bl_dr)";
my $re_weather_vc = "(?:FG|PO|FC|DS|SS|TS(?:$re_weather_ts_sh)?|SH|BL$re_weather_bl_dr|VA)";
# annex 3, form:
# FZDZ FZRA DZ   RA   SHRA SN SHSN SG SHGR SHGS BLSN SS DS
# TSRA TSSN TSPL TSGR TSGS FC VA   PL UP
# annex 3, text:
# FZDZ FZRA DZ   RA   SHRA SN SHSN SG SHGR SHGS BLSN SS DS
#                          FC VA   PL    TS
# EXTENSION: allow FZFG
my $re_weather_re = "(?:(?:FZ|SH)?$re_weather_prec"
                     . "|TS(?:$re_weather_ts_sh)"
                     . "|FZFG|BLSN|DS|SS|TS|FC|VA|UP)";
# EXTENSION: allow [+-]VC...
# EXTENSION: Canada uses +BLSN, +BLSA, +BLDU (MANOBS chapter 20)
my $re_weather = "(?:[+-]?$re_weather_w_i|[+]BL$re_weather_bl_dr|$re_weather_wo_i|[+-]?VC$re_weather_vc)";

my $re_cloud_cov = '(?:FEW|SCT|BKN|OVC)';
my $re_cloud_base = '(?:///|\d{3})';
my $re_cloud_type = '(?:AC(?:C|SL)?|AS|CB(?:MAM)?|CC(?:SL)?|CI|CS|CU(?:FRA)?|CF'
                     . '|NS|SAC|SC(?:SL)?|ST(?:FRA)?|SF|TCU)';

# EXTENSION: allow // for last 2 digits
# EXTENSION: allow tenths of hPa as .\d (FLLS, HUEN, OPRN)
# EXTENSION: allow QNH\d{4}INS, A\d{4}INS
my $re_qnh = '(?:(?:Q[01]\d|A[23]\d[./]?)(?:\d\d|//)|(?:QNH|A)[23]\d{3}INS|[AQ]////|Q[01]\d{3}\.\d)';

# prefixes for unrecognised groups, with some exceptions
my $re_unrec = '(?:(?!RMK[ /]|TEMPO|BECMG|INTER|FM|PROB)(?:([^ ]+) )??)';
my $re_unrec_cloud = '(?:(?!RMK[ /]|TEMPO|BECMG|INTER|FM|PROB|(?:M?\d\d|//)/(?:M?\d\d|//) |[AQ][\d/]{4})(?:([^ ]+) )??)';
my $re_unrec_weather = "(?:(?!RMK[ /]|TEMPO|BECMG|INTER|FM|PROB|SKC|NSC|CLR|NCD|VV|$re_cloud_cov|[AQ][\\d/]{4})(?:([^ ]+) )??)";

my $re_colour1 = 'BLU\+?|WHT|GRN|YLO[12]?|AMB|RED';
my $re_colour = "(?:(?:BL(?:AC)?K ?)?(?:$re_colour1)/?(?: ?(?:$re_colour1|FCST CANCEL)/?)?|BL(?:AC)?K)";

my $re_be_weather_be   = "(?:[BE]$re_hour?$re_min)";
my $re_be_weather = "(?:(?:$re_weather_w_i|$re_weather_wo_i) ?(?:$re_be_weather_be|[BE]MM)+)";

my $re_rsc_cond = '(?:DRY|WET|SANDED)';
my $re_rsc_deposit = '(?:LSR|SLR|PSR|IR|WR)+(?://|\d\d)?';
my $re_rsc = "(?:$re_rsc_deposit(?:P(?:[ /]$re_rsc_cond)?)?|(?:(?:P[ /])?$re_rsc_cond))";

my $re_snw_cvr_title = '(?:SNO?W? ?(?:CVR|COV(?:ER)?)?[/ ])';
my $re_snw_cvr_state =
       '(?:(?:ONE |MU?CH |TR(?:ACE)? ?)LOOSE|(?:MED(?:IUM)?|HARD) PACK(?:ED)?)';
my $re_snw_cvr = "(?:$re_snw_cvr_title?($re_snw_cvr_state)|${re_snw_cvr_title}NIL)";

my $re_temp = '(?:-?\d+\.\d)';
my $re_precip = '(?:\d{1,2}(?:\.\d)?(?: ?[MC]M)?)';

my $re_opacity_phenom =
    '(?:(?:BL)?SN|FG?|DZ|IC|AS|ACC?|CC|CF|CI|CS|CU(?:FRA)?|TCU|NS|ST|SF|SC|CB)';
my $re_trace_cloud = '(?:AC|AS|CF|CI|CS|CU(?:FRA)?|SC|SF|ST|TCU)';

my $re_phen_desc_when = '(?:OCNL|FRE?Q|INTMT|CON(?:TU)?S|CNTS|PAST HR)';
my $re_phen_desc_how  = '(?:LOW?|LWR|ALOFT|(?:VRY |V|PR )?(?:THN|THIN|THK|THICK)|ISOL|CVCTV|DSIPTD|FREEZING|PTCHY|VERT|PTL)';
my $re_phen_desc_strength  = '(?:(?:VRY |V|PR )?(?:LGT|FBL)|MDT|MOD)';
my $re_phen_desc = "(?:$re_phen_desc_when|$re_phen_desc_how|$re_phen_desc_strength)";

my $re_ltg_types = '(?:CA|CC|CG|CW|IC)';

my $re_wind_shear_lvl = "WS(\\d{3})/(${re_wind_dir}0${re_wind_speed}KT)";

my $re_phenomenon_other = "(?:LTG$re_ltg_types*|VIRGA|AURBO|AURORA|F(?:O?G)? BA?NK|FULYR|HZY|BINOVC|ICG|SH|DEW|(?:$re_vis|CIG|SC) (?:HYR|HIER|LWR|RDCD|RED(?:UCED)?)|ROTOR CLD|CLDS?(?: EMBD(?: 1ST LYR)?)?|(?:GRASS )?FIRES?|(?:SKY|MTN?S?(?: TOPS)?|RDGS)(?: P[TR]L?Y?)? OBSC(?:URED|D)?|HALO(?: VI?SBL| VSBL?)?|(?:CB|TCU) ?TOPS?)";
my $re_phenomenon4 = "(?:($re_phenomenon_other|PCPN|(?:BC )?VLY FG|HIR CLDS)|($re_cloud_type(?:[/-]$re_cloud_type)*)|($re_weather|SMOKE|HAZE|TSTMS)|($re_cloud_cov))";

my $re_estmd = '(?:EST(?:M?D)?|ESMTD|ESTIMATED)';
my $re_data_estmd = '(?:WI?NDS?(?: DATA)?|(?:CIG )?BLN|ALTM?|CIG|CEILING|SLP|ALSTG|QNH|CLD HGTS)';

my $re_synop_tt = '(?:[0-6]\d|7[0-5])';
my $re_synop_zz = '(?:[7-9]\d)';
my $re_synop_period = '(?:[0-6]\d)';
my $re_synop_w1w1 = '(?:0[46-9]|1[01379]|2[0-8]|3[09]|4[1-9]|5[0-79]|6[0-7]|[78]\d|9[0-3])';

my $re_record_temp = '(?:(?:HI|LO)(?:[EX])(?:AT|FM|SE|SL|DA))';

########################################################################
# helper functions
########################################################################

# FMH-1 2.6.3:
#   If the fractional part of a positive number to be dropped is equal to or
#   greater than one-half, the preceding digit shall be increased by one. If
#   the fractional part of a negative number to be dropped is greater than
#   one-half, the preceding digit shall be decreased by one. In all other
#   cases, the preceding digit shall remain unchanged.
#   For example, 1.5 becomes 2, -1.5 becomes -1 ...
# WMO-No. 306 Vol I.1, Part A, Section A, 15.11.1:
#   Observed values involving 0.5°C shall be rounded up to the next higher
#   Celsius degree
sub _rnd {
    my ($val, $prec) = @_;
    return $prec * floor(($val / $prec) + 0.5);
}

sub _makeErrorMsgPos {
    my $errorType = shift;

    if (/\G$/) {
        s/\G/<@/;
    } else {
        if (pos $_ == 0) {
            s/\G/@> /;
        } elsif (/\G(?=.)/) {
            s/\G/<@> /;
        }
        s/(@> +[^ ]+) .+/$1 .../;
        s/ $//;
    }
    return { errorType => $errorType, s => $_ };
}

# $cy: [ 'ABCD', 'AB', 'A' ]
sub _cyInString {
    my ($cy, $str) = @_;

    return    index($str, ' ' . $cy->[0] . ' ') > -1
           || index($str, ' ' . $cy->[1] . ' ') > -1
           || index($str, ' ' . $cy->[2] . ' ') > -1;
}

# WMO-No. 306 Vol I.1, Part A, Section A, 15.6.3:
# Visibility shall be reported using the following reporting steps:
# (a) Up to 800 metres rounded down to the nearest 50 metres;
# (b) Between 800 and 5000 metres rounded down to the nearest 100 metres;
# (c) Between 5000 metres up to 9999 metres rounded down to the nearest 1000
#     metres;
# (d) With 9999 indicating 10 km and above.
#
# WMO-No. 306 Vol I.1, Part A, Section B:
# VVVV
#   Horizontal visibility at surface, in metres,
#   in increments of 50 metres up to 500 metres,             WRONG! CORRECT: 800
#   in increments of 100 metres between 500 and 5000 metres, and      WRONG! 800
#   in increments of 1000 metres between 5000 metres up to 9999 metres,
#   with 9999 indicating visibility of 10 km and above.
sub _getVisibilityM {
    my ($visM, $less_greater) = @_;
    my $rp;

    return { v => 10, u => 'KM', q => 'isEqualGreater' } if $visM == 9999;
    return { v => $visM + 0, u => 'M', q => { P => 'isEqualGreater',
                                              M => 'isLess' }->{$less_greater} }
        if $less_greater;

    # add rp only if reported value is correctly rounded
    if ($visM =~ /0[0-7][05]0/) {
        $rp = 50;
    } elsif ($visM =~ /[0-4]\d00/) {
        $rp = 100;
    } elsif ($visM =~ /\d000/) {
        $rp = 1000;
    } else {
        $rp = 0;
    }

    return { v => $visM + 0, u => 'M', $rp ? (rp => $rp) : () };
}

# WMO-No. 306 Vol I.1, Part A, Section B:
# VRVRVRVR
#   Runway visual range shall be reported
#   in steps of 25 metres when the runway visual range is less than 400 metres;
#   in steps of 50 metres when it is between 400 metres and 800 metres; and
#   in steps of 100 metres when the runway visual range is more than 800 metres.
sub _setVisibilityMRVROffset {
    my $vis = shift;

    # add rp only if reported value is correctly rounded
    if ($vis->{v} =~ /0[0-3][0257][05]/) {
        $vis->{rp} = 25;
    } elsif ($vis->{v} =~ /0[4-7][05]0/) {
        $vis->{rp} = 50;
    } elsif ($vis->{v} =~ /\d\d00/) {
        $vis->{rp} = 100;
    }
    return;
}

# FMH-1 12.6.7c
sub _setVisibilityFTRVROffset {
    my $vis = shift;

    # add rp only if reported value is correctly rounded
    if ($vis->{v} =~ /0\d00/) {
        $vis->{rp} = 100;
    } elsif ($vis->{v} =~ /[12][02468]00/) {
        $vis->{rp} = 200;
    } elsif ($vis->{v} =~ /[3-5][05]00|6000/) {
        $vis->{rp} = 500;
    }
    return;
}

sub _parseFraction {
    my ($val, $unit) = @_;
    my $q;

    $q = 'isLess'         if $val =~ s/^M//;
    $q = 'isEqualGreater' if $val =~ s/^P//;
    if ($val =~ m@^([1357])/([1-8]+)$@) {
        $val = $1 / $2;
    } elsif ($val =~ m@^(\d)(?: ?(\d*)/(\d*))?$@) {
        $val = $1;
        $val += $2 / $3 if $2;
    }
    return { v => $val, u => $unit, $q ? (q => $q) : () };
}

# FMH-1 table 6-1
sub _setVisibilitySMOffsetUS {
    my ($visSM, $is_auto) = @_;

    return if defined $visSM->{q};
    # TODO: add rp only if reported value is correctly rounded
    if ($is_auto) {
        if ($visSM->{v} < 2) {
            $visSM->{rp} = 1/4;
        } elsif ($visSM->{v} < 3) {
            $visSM->{rp} = 1/2;
        } else {
            $visSM->{rp} = 1;
        }
    } else {
        if ($visSM->{v} < 3/8) {
            $visSM->{rp} = 1/16;
        } elsif ($visSM->{v} < 2) {
            $visSM->{rp} = 1/8;
        } elsif ($visSM->{v} < 3) {
            $visSM->{rp} = 1/4;
        } elsif ($visSM->{v} < 15) {
            $visSM->{rp} = 1;
        } else {
            $visSM->{rp} = 5;
        }
    }
    return;
}

sub _getVisibilitySM {
    my ($vis, $is_auto, $cy) = @_;
    my $r;

    $r = _parseFraction $vis, 'SM';
    if (_cyInString $cy, ' cUS ') {
        _setVisibilitySMOffsetUS $r, $is_auto;
    } elsif (_cyInString $cy, ' cCA ') {
        if (!exists $r->{q}) {
            # http://ops.8wing.ca/downloads/WX_Decode_card.doc
            if ($r->{v} < 3/4) {
                $r->{rp} = 1/8;
            } elsif ($r->{v} < 2.5) {
                $r->{rp} = 1/4;
            } elsif ($r->{v} < 3) {
                $r->{rp} = 1/2;
            } elsif ($r->{v} < 15) {
                $r->{rp} = 1;
            } else {
                $r->{rp} = 5;
            }
        }
    # TODO: what about EQ(YR,YS) MM MY TKPK TNCM TX(KF)?
    }
    return { distance => $r };
}

sub _parseWeather {
    my ($weather, $mode) = @_;           # $mode: RE = recent, NI = no intensity
    my ($w, $int, $in_vicinity, $desc, $phen, $weather_str);

    if (defined $mode && $mode eq 'RE') {
        $weather_str = 'RE' . $weather;
    } else {
        $weather_str = $weather;
    }
    return { NSW => undef, s => $weather_str } if $weather eq 'NSW';
    return { invalidFormat => $weather_str, s => $weather_str }
        if $weather eq 'FZSN';
    return { notAvailable => undef, s => $weather_str }
        if $weather eq '//';

    return { tornado => undef, s => $weather_str } if $weather eq '+FC';

    # for $re_phenomenon4, only
    $weather = 'FU' if $weather eq 'SMOKE';
    $weather = 'HZ' if $weather eq 'HAZE';
    $weather = 'TS' if $weather eq 'TSTMS';

    ($int, $in_vicinity, $desc, $phen) =
                      $weather =~ m@([+-])?(VC)?($re_weather_desc)?([A-Z/]+)@o;
    $w->{s} = $weather_str;
    if (defined $int) {
        $w->{phenomDescr} = ($int eq '-' ? 'isLight' : 'isHeavy');
    } else {
        # weather in vicinity _can_ have intensity, but it is an EXTENSION
        $w->{phenomDescr} = 'isModerate'
            unless    $in_vicinity
                   || $mode
                   || $weather =~ /^$re_weather_wo_i$/;
    }
    $w->{inVicinity}    = undef if defined $in_vicinity;
    $w->{descriptor}    = $desc if defined $desc;
    @{$w->{phenomSpec}} = $phen =~ /../g;
    return $w;
}

sub _parseOpacityPhenom {
    my ($r, $clds) = @_;

    for ($clds =~ /[A-Z]+\d/g) {
        my ($phenom, $oktas) = /(.*)(.)/;
        $phenom = 'FG' if $phenom eq 'F';
        if ($phenom =~ /$re_weather/) {
            push @{$r->{opacityPhenomArr}}, { opacityWeather => {
                oktas   => $oktas,
                weather => _parseWeather $phenom, 'NI'
            }};
        } else {
            push @{$r->{opacityPhenomArr}}, { opacityCloud => {
                oktas     => $oktas,
                cloudType => $phenom
            }};
        }
    }
    return;
}

sub _parseRwyVis {
    my $metar = shift;
    my $r;

    if (m@\G(R($re_rwy_des)/(?:////|($re_rwy_vis)(?:V($re_rwy_vis))?(FT)?)/?([UDN])?) @ogc)
    {
        my $v;

        $v->{s}        = $1;
        $v->{rwyDesig} = $2;
        $v->{visTrend} = $6 if defined $6;
        if (!defined $3) {
            $v->{RVR}{notAvailable} = undef;
        } else {
            $v->{RVR}{distance} = { v => $3, u => (defined $5 ? $5 : 'M') };
            if (defined $4) {
                $v->{RVRVariations}{distance} =
                                       { v => $4, u => $v->{RVR}{distance}{u} };
                if ($v->{RVRVariations}{distance}{v} =~ s/^M//) {
                    $v->{RVRVariations}{distance}{q} = 'isLess'
                } elsif ($v->{RVRVariations}{distance}{v} =~ s/^P//) {
                    $v->{RVRVariations}{distance}{q} = 'isEqualGreater'
                } elsif ($v->{RVRVariations}{distance}{u} eq 'M') {
                    _setVisibilityMRVROffset $v->{RVRVariations}{distance};
                } else {
                    _setVisibilityFTRVROffset $v->{RVRVariations}{distance};
                }
                $v->{RVRVariations}{distance}{v} += 0;
            }
            # corrections postponed because pattern matching changes $4
            if ($v->{RVR}{distance}{v} =~ s/^M//) {
                $v->{RVR}{distance}{q} = 'isLess';
            } elsif ($v->{RVR}{distance}{v} =~ s/^P//) {
                $v->{RVR}{distance}{q} = 'isEqualGreater';
            } elsif ($v->{RVR}{distance}{u} eq 'M') {
                _setVisibilityMRVROffset $v->{RVR}{distance};
            } else {
                _setVisibilityFTRVROffset $v->{RVR}{distance};
            }
            $v->{RVR}{distance}{v} += 0;
        }
        push @{$metar->{visRwy}}, $v;
        return 1;
    }
    return 0;
}

sub _parseRwyState {
    my $metar = shift;
    my $r;

    # SNOCLO|((RRRR|RDRDR/)((CLRD|ERCReReR)BRBR))
    # EXTENSION: allow missing /
    # EXTENSION: allow (and ignore) runway designator for SNOCLO
    # EXTENSION: allow (and mark invalid) states U, D, N
    if (m@\G(((?:R(?:88|$re_rwy_des)?/)?SNOCLO)|(88|99|$re_rwy_des2|R(?:88|99|$re_rwy_des)/?)(?:(?:(?:(CLRD)|([\d/])([\d/])(\d\d|//))(\d\d|//))|([UDN]))) @ogc)
    {
        $r->{s} = $1;
        if (defined $2) {
            $r->{SNOCLO} = undef;
        } else {
            if (defined $4) {
                $r->{cleared} = undef;
            } elsif (defined $9) {
                $r->{invalidFormat} = $9;
            } else {
                # WMO-No. 306 Vol I.1, Part A, code table 0919:
                if ($5 eq '/') {
                    $r->{depositType}{notAvailable} = undef;
                } else {
                    $r->{depositType}{depositTypeVal} = $5;
                }

                # WMO-No. 306 Vol I.1, Part A, code table 0519:
                if ($6 eq '/') {
                    $r->{depositExtent}{notAvailable} = undef;
                } elsif (   $6 eq '0' || $6 eq '1' || $6 eq '2'
                         || $6 eq '5' || $6 eq '9')
                {
                    $r->{depositExtent}{depositExtentVal} = $6;
                } else {
                    $r->{depositExtent}{invalidFormat} = $6;
                }

                # WMO-No. 306 Vol I.1, Part A, code table 1079:
                if ($7 eq '//') {
                    $r->{depositDepth}{notAvailable} = undef;
                } elsif ($7 == 0) {
                    $r->{depositDepth}{depositDepthVal} =
                        { v => 1, u => 'MM', q => 'isLess' };
                } elsif ($7 <= 90) {
                    $r->{depositDepth}{depositDepthVal} =
                        { v => $7 + 0, u => 'MM' };
                } elsif ($7 >= 92 && $7 <= 97) {
                    $r->{depositDepth}{depositDepthVal} =
                        { v => ($7 - 90) * 5, u => 'CM' };
                } elsif ($7 == 98) {
                    $r->{depositDepth}{depositDepthVal} =
                        { v => 40, u => 'CM', q => 'isEqualGreater' };
                } elsif ($7 == 99) {
                    $r->{depositDepth}{rwyNotInUse} = undef;
                } else {
                    $r->{depositDepth}{invalidFormat} = $7;
                }
            }

            if (defined $8) {
                # WMO-No. 306 Vol I.1, Part A, code table 0366:
                if ($8 eq '//') {
                    $r->{friction}{notAvailable} = undef;
                } elsif ($8 >= 1 && $8 <= 90) {
                    $r->{friction}{coefficient} = $8 + 0;
                } elsif ($8 == 99) {
                    $r->{friction}{unreliable} = undef;
                } elsif ($8 >= 91 && $8 <= 95) {
                    $r->{friction}{brakingAction} = $8;
                } else {
                    $r->{friction}{invalidFormat} = $8;
                }
            }

            if ($3 eq '88' || $3 eq 'R88' || $3 eq 'R88/') {
                $r->{rwyDesigAll} = undef;
            } elsif ($3 eq '99' || $3 eq 'R99' || $3 eq 'R99/') {
                $r->{rwyReportRepeated} = undef;
            } else {
                my $rwy_des = $3;

                if ($rwy_des =~ m@^R($re_rwy_des)/?$@) {
                    $r->{rwyDesig} = $1;
                } elsif ($rwy_des > 50) {
                    $r->{rwyDesig} = sprintf '%02dR', $rwy_des - 50;
                } else {
                    $r->{rwyDesig} = $rwy_des;
                }
            }
        }
        push @{$metar->{rwyState}}, $r;
        return 1;
    }
    return 0;
}

sub _parseWind {
    my ($wind, $dir_is_rounded, $is_grid) = @_;
    my ($w, $dir, $speed, $gustSpeed, $unitSpeed);

    return { notAvailable => undef } if $wind eq '/////';
    ($dir, $speed, $gustSpeed, $unitSpeed) = $wind =~ m@^$re_wind$@o;
    if ($dir eq '///' && $speed eq '//') {
        $w->{notAvailable} = undef;
    } elsif ($dir eq '000' && $speed eq '00' && !defined $gustSpeed) {
        $w->{isCalm} = undef;
    } else {
        my $isGreater;

        if ($dir eq '///') {
            $w->{dirNotAvailable} = undef;
        } elsif ($dir eq 'VRB') {
            $w->{dirVariable} = undef;
        } else {
            $w->{dir}{v} = $dir + 0; # true, not magnetic
            $w->{dir}{q} = 'isGrid' if $is_grid;
            if ($dir_is_rounded && $dir =~ /0$/) {
                $w->{dir}{rp} = 4;
                $w->{dir}{rn} = 5;
            }
        }
        $unitSpeed =~ s/KTS/KT/;
        $unitSpeed =~ s/ //;
        if ($speed eq '//') {
            $w->{speedNotAvailable} = undef;
        } else {
            $isGreater = $speed =~ s/^P//;
            $w->{speed} = { v => $speed + 0, u => $unitSpeed };
            $w->{speed}{q} = 'isGreater' if $isGreater;
        }
        if (defined $gustSpeed) {
            $isGreater = $gustSpeed =~ s/^P//;
            $w->{gustSpeed} = { v => $gustSpeed + 0, u => $unitSpeed };
            $w->{gustSpeed}{q} = 'isGreater' if $isGreater;
        }
    }
    return $w;
}

sub _parseWindAtLoc {
    my ($s, $location, $wind, $windVarLeft, $windVarRight) = @_;
    my $r;

    $r = _parseWind $wind;
    $r->{windVarLeft} = $windVarLeft + 0 if defined $windVarLeft;
    $r->{windVarRight} = $windVarRight + 0 if defined $windVarRight;
    return { windAtLoc => {
        s            => $s,
        windLocation => $location,
        wind         => $r
    }};
}

sub _parseLocations {
    my ($loc_str, $in_distance) = @_;
    my (@loc_thru, $obscgMtns, $in_vicinity, $is_grid);

    $obscgMtns = $loc_str =~ s/OBSCG MTNS //;

    for ($loc_str =~ m@(?:[+/, ]| AND )?($re_loc_thru|UNKN)@og) {
        my @loc;

        for ($_ =~ m@(?: ?[/-] ?| THRU )?((?:(?:$re_loc_dsnt_vc )?(?:TO )?(?:(?:(?:$re_loc_compass(?: $re_loc_approx)?|(?:$re_loc_approx )?$re_loc_compass|OHD))|$re_loc_approx|$re_loc_inexact))|$re_loc_exact|UNKN)@og)
        {
            my $l;

            m@^(?:($re_loc_dsnt_vc )?(?:TO )?(?:(?:($re_loc_compass)(?: ($re_loc_approx))?|(?:($re_loc_approx) )?($re_loc_compass)|(OHD))|($re_loc_approx|$re_loc_inexact)))|($re_loc_exact|UNKN)@;
            $in_distance = 1 if defined $1 && $1 eq 'DSNT ';
            $in_vicinity = 1 if defined $1 && $1 eq 'VC ';
            $l->{locationSpec} = $3 || $4 || $6 || $7 || $8
                if defined $3 || $4 || $6 || $7 || $8;

            if ($2 || $5) {
                ($2 || $5) =~ m@(?:($re_loc_dsnt_vc )|([1-9]\d*)(KM|NM)? ?)?(?:TO )?(GRID )?($re_compass_dir16)( QUAD)?@o;
                $in_distance = 1 if defined $1 && $1 eq 'DSNT ';
                $in_vicinity = 1 if defined $1 && $1 eq 'VC ';
                $l->{distance} = { v => $2, u => (defined $3 ? $3 : 'SM') }
                    if defined $2;
                $is_grid = 1 if defined $4;
                push @{$l->{sortedArr}}, { compassDir => {
                    v => $5,
                    $is_grid ? (q => 'isGrid') : ()
                }};
                push @{$l->{sortedArr}}, { isQuadrant => undef } if defined $6;
            }

            if (exists $l->{locationSpec}) {
                if ($l->{locationSpec} =~ $re_loc_exact) {
                    $in_distance = 0;
                    $in_vicinity = 0;
                }
                $l->{locationSpec} =~ s/ARND/isAround/;
                $l->{locationSpec} =~ tr /\/ /_/;
                $l->{locationSpec} =~ s/ /_/;
            }
            $l->{inDistance} = undef if $in_distance;
            $l->{inVicinity} = undef if $in_vicinity;

            push @loc, $l;
        }
        push @loc_thru, { location => \@loc };
    }
    return { locationThru => \@loc_thru,
             $obscgMtns ? (obscgMtns => undef) : ()
    };
}

sub _parseCloud {
    my ($cloud, $cy, $is_thin, $q_base) = @_;
    my $c;

    $c->{s} = $cloud;
    if ($cloud =~ m@^/+$@) {
        $c->{notAvailable} = undef;
    } elsif ($cloud =~ m@^(?:$re_cloud_cov|///)$re_cloud_base(?: ?(?:$re_cloud_type|///)(?:\($re_loc_and\))?)?@o)
    {
        $cloud =~ '(...)(...) ?([A-Z/]+)?(?:\(([^)]+)\))?';
        if ($1 eq '///') {
            $c->{cloudCoverNotAvailable} = undef;
        } else {
            $c->{cloudCover} = {
                v => $1,
                $is_thin ? (q => 'isThin') : ()
            };
        }
        if ($2 eq '///') {
            # can mean: not measured (autom. station) or base below station
            $c->{cloudBaseNotAvailable} = undef;
        } else {
            $c->{cloudBase} = { v => $2 * 100, u => 'FT' }; # AGL
            if (defined $q_base && $q_base eq 'E') {
                $c->{cloudBase}{q} = 'isEstimated';
            } elsif (defined $q_base && $q_base eq 'V') {
                $c->{cloudBase}{q} = 'isVariable';
            } elsif (defined $cy) {
                if (_cyInString $cy, ' cUS ') {
                    # FMH-1 9.5.4, 9.5.5
                    if ($2 == 0) {
                        $c->{cloudBase}{rp} = 50;
                    } elsif ($2 < 50) {
                        @{$c->{cloudBase}}{qw(rn rp)} = (50, 50);
                    } elsif ($2 == 50) {
                        @{$c->{cloudBase}}{qw(rn rp)} = (50, 250);
                    } elsif ($2 < 100 && $2 % 5 == 0) {
                        @{$c->{cloudBase}}{qw(rn rp)} = (250, 250);
                    } elsif ($2 == 100) {
                        @{$c->{cloudBase}}{qw(rn rp)} = (250, 500);
                    } elsif ($2 > 100 && $2 % 10 == 0) {
                        @{$c->{cloudBase}}{qw(rn rp)} = (500, 500);
                    }
                    $c->{cloudBase}{q} = 'exclLower'
                        if exists $c->{cloudBase}{rp};
                } else {
                    # WMO-No. 306 Vol I.1, Part A, Section A, 15.9.1.5
                    $c->{cloudBase}{rp} = 100;
                }
            }
        }
        if (defined $3) {
            if ($3 eq '///') {
                $c->{cloudTypeNotAvailable} = undef;
            } else {
                $c->{cloudType} = $3;
            }
            $c->{locationAnd} = _parseLocations $4
                if defined $4;
        }
    } else {
        $cloud =~ '(...)(.+)?';
        $c->{cloudCover}{v} = $1;
        $c->{cloudType}  = $2 if defined $2;
    }
    return $c;
}

sub _parseQNH {
    my $qnh = shift;
    my ($q, $descr, $dig12, $dig34);

    $q->{s} = $qnh;
    ($descr, $dig12, $dig34) = $qnh =~ '([AQNH]*)(..)[./]?(//|\d\d(?:\.\d)?)';
    if ("$dig12$dig34" eq '////') {
        $q->{notAvailable} = undef;
    } else {
        if ($descr eq 'Q') { # not QNHxxxx (it is always QNHxxxxINS) or Axxxx
            $dig34 = '00' if $dig34 eq '//';
            $q->{pressure}{v} = ($dig12 + 0) . $dig34;
            $q->{pressure}{u} = 'hPa'
        } else {
            $q->{pressure}{v} = $dig12;
            $q->{pressure}{v} .= ".$dig34" unless $dig34 eq '//';
            $q->{pressure}{u} = 'inHg';
        }
    }
    return $q;
}

sub _parseColourCode {
    my $colour = shift;
    my $c;

    $colour =~ m@^(BL(?:AC)?K ?)?($re_colour1)?/? ?([^/]+)?@o;
    $c->{s} = $colour;
    $c->{BLACK} = undef if defined $1;
    $c->{currentColour} =
            $2 eq 'BLU+' ? 'BLUplus' : ($2 eq 'FCST CANCEL' ? 'FCSTCANCEL' : $2)
        if defined $2;
    $c->{predictedColour} =
            $3 eq 'BLU+' ? 'BLUplus' : ($3 eq 'FCST CANCEL' ? 'FCSTCANCEL' : $3)
        if defined $3;
    return $c;
}

sub _determineCeiling {
    my $cloud = shift;
    my ($ceil, $idx, $ii);

    $ceil = 20000; # max. ceiling (FT AGL)
    $idx = -1;
    $ii = -1;
    for (@$cloud) {
        $ii++;
        if (   exists $_->{cloudBase} && exists $_->{cloudCover}
            && $_->{cloudBase}{u} eq 'FT'
            && $_->{cloudBase}{v} < $ceil
            && ($_->{cloudCover}{v} eq 'BKN' || $_->{cloudCover}{v} eq 'OVC'))
        {
            $ceil = $_->{cloudBase}{v};
            $idx = $ii;
        }
    }
    $cloud->[$idx]{isCeiling}{q} = 'M2Xderived' if $idx > -1;
    return;
}

sub _parseQuadrants {
    my ($q, $in_distance) = @_;

    return { locationThru => { location => {
        $in_distance ? (inDistance => undef) : (),
        quadrant => [ $q =~ /([1-4])/g ]
    }}};
}

sub _parseTemp {
    my $temp = shift;

    $temp =~ /(.)(..)(.)/;
    return { v => $2 * ($1 == 1 ? -1 : 1) + 0, u => 'C' }
        if $3 eq '/';
    return { v => sprintf('%.1f', "$2.$3" * ($1 == 1 ? -1 : 1) + 0), u => 'C' };
}

sub _parsePhenomDescr {
    my ($r, $tag, $phen_descr) = @_;

    for ($phen_descr =~ /$re_phen_desc|BBLO/og) {
        s/CONTUS/CONS/;
        s/CNTS/CONS/;
        s/V(LGT|THN|THIN|FBL|THK|THICK)/VRY $1/;
        s/THIN/THN/;
        s/FREQ/FRQ/;
        s/THICK/THK/;
        s/^LOW?/LOW/;
        s/^MOD/MDT/;

        push @{$r->{$tag}}, {
            FRQ      => 'isFrequent',
            OCNL     => 'isOccasional',
            INTMT    => 'isIntermittent',
            CONS     => 'isContinuous',
            THK      => 'isThick',
           'PR THK'  => 'isPrettyThick',
           'VRY THK' => 'isVeryThick',
            THN      => 'isThin',
           'PR THN'  => 'isPrettyThin',
           'VRY THN' => 'isVeryThin',
            LGT      => 'isLight',
           'PR LGT'  => 'isPrettyLight',
           'VRY LGT' => 'isVeryLight',
            FBL      => 'isFeeble',
           'PR FBL'  => 'isPrettyFeeble',
           'VRY FBL' => 'isVeryFeeble',
            MDT      => 'isModerate',
            LOW      => 'isLow',
            LWR      => 'isLower',
            ISOL     => 'isIsolated',
            CVCTV    => 'isConvective',
            DSIPTD   => 'isDissipated',
           'PAST HR' => 'inPastHour',
            BBLO     => 'baseBelowStation',
            ALOFT    => 'isAloft',
            FREEZING => 'isFreezing',
            PTCHY    => 'isPatchy',
            VERT     => 'isVertical',
            PTL      => 'isPartial',
        }->{$_};
    }
    return;
}

sub _parsePhenom {
    my ($r, $phenom) = @_;

    if ($phenom =~ /LTG$re_ltg_types/o) {
        $$r->{lightningType} = ();
        for ($phenom =~ /$re_ltg_types/og) {
            push @{$$r->{lightningType}}, $_;
        }
    } else {
        ($$r->{otherPhenom} = $phenom) =~ tr/ /_/;
        $$r->{otherPhenom} =~ s/_HIER/_HYR/;
        $$r->{otherPhenom} =~ s/_RED(?:UCED)?/_RDCD/;
        $$r->{otherPhenom} =~ s/AURORA/AURBO/;
        $$r->{otherPhenom} =~ s/$re_vis/VIS/o;
        $$r->{otherPhenom} =~ s/_VI?SBL?//;
        $$r->{otherPhenom} =~ s/OBSC(?:URE)?D/OBSC/;
        $$r->{otherPhenom} =~ s/_P[TR]L?Y?_/_PRLY_/;
        $$r->{otherPhenom} =~ s/(?<=MT)N?S?(?=_[OP])/NS/;
        $$r->{otherPhenom} =~ s/(?<=MT)N?S?(?=_T)/N/;
        $$r->{otherPhenom} =~ s/F(?:O?G)?_BA?NK/FG_BNK/;
        $$r->{otherPhenom} =~ s/(?<=[^_])(?=TOP)/_/;
        $$r->{otherPhenom} =~ s/(?<=_TOP$)/S/;
    }
    return;
}

# hBhBhB height of lowest level of turbulence
# hihihi height of lowest level of icing
sub _codeTable1690 {
    my $level = shift;

    return { v => 30, u => 'M', q => 'isLess' } if $level eq '000';
    return { v => $level * 30,
             u => 'M',
             $level eq '999' ? (q => 'isEqualGreater') : () };
}

# "supplementary" section of TAFs and additional TAF info
sub _parseTAFsuppl {
    my ($metar, $base_metar, $cy) = @_;
    my $r;

    # "supplementary" section of TAFs

    # groups 5BhBhBhBtL, 6IchihihitL
    # WMO-No. 306 Vol I.1, Part A, Section A, 53.1.9.2 (FM-53 ARFOR):
    # if group is repeated and only level differs: level is layer top
    if (/\G(([56])(\d)(\d{3})(\d)(?: \2\3(\d{3})\5)?) /gc) {
        my $type;

        $type = $2 eq '5' ? 'turbulence' : 'icing';

        $r = {
            s               => $1,
            $type . 'Descr' => $3,
            layerBase       => _codeTable1690 $4
        };
        if (defined $6) {
            $r->{layerTop} = _codeTable1690 $6;
        } else {
            # WMO-No. 306 Vol I.1, Part A, coding table 4013
            if ($5 eq '0') {
                $r->{layerTopOfCloud} = undef;
            } else {
                $r->{layerThickness} = { v => $5 * 300, u => 'M' };
            }
        }
        push @{$metar->{TAFsupplArr}}, { $type => $r };
        return 1;
    }

    if (m@\G($re_wind_shear_lvl) @ogc) {
        push @{$metar->{TAFsupplArr}}, { windShearLvl => {
            s     => $1,
            level => $2 + 0,
            wind  => _parseWind $3
        }};
        return 1;
    }

    if (m@\G($re_qnh) @ogc) {
        push @{$metar->{TAFsupplArr}}, { QNH => _parseQNH $1 };
        return 1;
    }

    if (   _cyInString($cy, ' cUS NZ RK ')
        && /\G((FU|(?:FZ)?FG|BR|SN|PWR PLNT(?: PLUME)?) ($re_cloud_cov$re_cloud_base)) /ogc)
    {
        my ($cl, $phen);

        $r->{s} = $1;
        $r->{cloud} = _parseCloud $3;
        $phen = $2;
        if ($phen =~ m@^$re_weather$@o) {
            $r->{weather} = _parseWeather $phen, 'NI';
        } else {
            ($r->{cloudPhenom} = $phen) =~ s/ /_/g;
        }
        push @{$metar->{TAFsupplArr}}, { obscuration => $r };
        return 1;
    }

    # additional TAF info

    if (/\G((COR|AMD) ($re_hour)($re_min)Z?) /ogc) {
        push @{$base_metar->{TAFinfoArr}},
            { $2 eq 'COR' ? 'correctedAt' : 'amendedAt' => {
                s      => $1,
                timeAt => { hour => $3, minute => $4 }
        }};
        return 1;
    }

    if (/\G(LIMITED METWATCH ($re_day)($re_hour) TIL ($re_day)($re_hour)) /ogc){
        push @{$base_metar->{TAFinfoArr}}, { limMetwatch => {
            s         => $1,
            timeFrom => { day => $2, hour => $3 },
            timeTill => { day => $4, hour => $5 },
        }};
        return 1;
    }

    if (/\G(AUTOMATED SENSOR(?:ED)? METWATCH(?: ($re_day)($re_hour) TIL ($re_day)($re_hour))?) /ogc)
    {
        $r->{s} = $1;
        if (defined $2) {
            $r->{timeFrom} = { day => $2, hour => $3 };
            $r->{timeTill} = { day => $4, hour => $5 };
        }
        push @{$base_metar->{TAFinfoArr}}, { autoMetwatch => $r };
        return 1;
    }

    if (/\G(AMD (?:LTD TO CLD VIS AND WIND(?: (?:TIL ($re_hour|24)Z|(${re_hour})Z-($re_hour|24)Z))?|(NOT SKED))) /ogc)
    {
        $r->{s} = $1;
        if (defined $5) {
            $r->{isNotScheduled} = undef;
        } else {
            $r->{isLtdToCldVisWind} = undef;
            $r->{timeTill}{hour} = $2 if defined $2;
            $r->{timeFrom}{hour} = $3 if defined $3;
            $r->{timeTill}{hour} = $4 if defined $4;
        }
        push @{$base_metar->{TAFinfoArr}}, { amendment => $r };
        return 1;
    }

    if (/\G(BY ($re_ICAO)) /ogc) {
        push @{$base_metar->{TAFinfoArr}},
                                         { providedBy => { s => $1, id => $2 }};
        return 1;
    }

    return 0;
}

sub _turbulenceTxt {
    my $r;

    m@\G((?:F(?:RO)?M ?(?:($re_day)($re_hour)($re_min)|($re_hour)($re_min)?) )?(SEV|MOD(?:/SEV)?) TURB (?:BLW|BELOW) ([1-9]\d+)FT(?: TILL ?(?:($re_day)($re_hour|24)($re_min)|($re_hour|24)($re_min)?))?) @gc || return undef;

    $r->{s} = $1;
    if (defined $2) {
        $r->{timeFrom} = { day => $2, hour => $3, minute => $4 };
    } elsif (defined $5) {
        $r->{timeFrom}{hour} = $5;
        $r->{timeFrom}{minute} = $6 if defined $6;
    }
    $r->{turbulenceDescr} = $7;
    $r->{layerTop} = { v => $8, u => 'FT' };
    if (defined $9) {
        $r->{timeTill} = { day => $9, hour => $10, minute => $11 };
    } elsif (defined $12) {
        $r->{timeTill}{hour} = $12;
        $r->{timeTill}{minute} = $13 if defined $13;
    }
    $r->{turbulenceDescr} =~ s@/@_@;
    return $r;
}

sub _setHumidity {
    my $r = shift;
    my ($t, $d);

    $t = $r->{air}{temp}{v};
    $d = $r->{dewpoint}{temp}{v};

    # FGFS metar
    $r->{relHumid1}{v}
      = _rnd(100 * 10 ** (7.5 * ($d / ($d + 237.7) - $t / ($t + 237.7))), 0.01);
    $r->{relHumid1}{q} = 'M2Xderived';

    # http://www.bragg.army.mil/www-wx/wxcalc.htm
    # http://www.srh.noaa.gov/bmx/tables/rh.html
    $r->{relHumid2}{v}
        = _rnd(100 * ((112 - (0.1 * $t) + $d) / (112 + (0.9 * $t))) ** 8, 0.01);
    $r->{relHumid2}{q} = 'M2Xderived';

    # http://www.mattsscripts.co.uk/mweather.htm
    # http://ingrid.ldeo.columbia.edu/dochelp/QA/Basic/dewpoint.html
    $r->{relHumid3}{v}
       = _rnd(
           100 * (6.11 * exp(5417.118093 * (1 / 273.15 - (1 / ($d + 273.15)))))
               / (6.11 * exp(5417.118093 * (1 / 273.15 - (1 / ($t + 273.15))))),
           0.01);
    $r->{relHumid3}{q} = 'M2Xderived';

    # http://de.wikipedia.org/wiki/Taupunkt
    $r->{relHumid4}{v}
               = _rnd(100 * (6.11213 * exp(17.5043 * $d / (241.2 + $d)))
                          / (6.11213 * exp(17.5043 * $t / (241.2 + $t))), 0.01);
    $r->{relHumid4}{q} = 'M2Xderived';
}

# WMO-No. 306 Vol I.1, Part A, Section D.a:
sub _IIiii2region {
    my $IIiii = shift;

    my %IIiii_region = (
         I        => [ [ 60001, 69998 ] ],
         II       => [ [ 20001, 20099 ], [ 20200, 21998 ], [ 23001, 25998 ],
                       [ 28001, 32998 ], [ 35001, 36998 ], [ 38001, 39998 ],
                       [ 40350, 48599 ], [ 48800, 49998 ], [ 50001, 59998 ] ],
         III      => [ [ 80001, 88998 ] ],
         IV       => [ [ 70001, 79998 ] ],
         V        => [ [ 48600, 48799 ], [ 90001, 98998 ] ],
         VI       => [ [     1, 19998 ], [ 20100, 20199 ], [ 22001, 22998 ],
                       [ 26001, 27998 ], [ 33001, 34998 ], [ 37001, 37998 ],
                       [ 40001, 40349 ] ],
        Antarctic => [ [ 89001, 89998 ] ],
    );
    for my $region (keys %IIiii_region) {
        for (@{$IIiii_region{$region}}) {
            return $region if $IIiii >= $_->[0] && $IIiii <= $_->[1];
        }
    }
    return '';
}

# determine the country that operates a station to select correct decoding rules
sub _IIiii2country {
    my $IIiii = shift;

    # ISO-3166 coded
    my %IIiii_country2 = (
        AR => [ [ 87007, 87999 ] ],                  # Argentina
        AT => [ [ 11001, 11399 ] ],                  # Austria
        BD => [ [ 41850, 41999 ] ],                  # Bangladesh
        BE => [ [  6400,  6499 ] ],                  # Belgium
        CA => [ [ 71001, 71998 ] ],                  # Canada
        CH => [ [  6600,  6989 ] ],                  # Switzerland
        CN => [ [ 50001, 59998 ] ],                  # China
        CZ => [ [ 11400, 11799 ] ],                  # Czech Republic
        DE => [ [ 10000, 10999 ] ],                  # Germany
        FR => [ [  7000,  7999 ] ],                  # France
        IN => [ [ 42001, 42998 ],                    # India
                [ 43001, 43399 ] ],
        LK => [ [ 43400, 43499 ] ],                  # Sri Lanka
        MG => [ [ 67000, 67199 ] ],                  # Madagascar
        MZ => [ [ 67200, 67399 ] ],                  # Mozambique
        NL => [ [  6200,  6399 ] ],                  # Netherlands
        NO => [ [  1000,  1499 ] ],                  # Norway
        RO => [ [ 15000, 15499 ] ],                  # Romania
        RU => [ [ 20000, 39999 ] ],                  # ex-USSR minus 14 states
        SA => [ [ 40350, 40549 ],                    # Saudi Arabia
                [ 41001, 41149 ] ],
        SE => [ [  2000,  2699 ] ],                  # Sweden
        US => [ [ 70001, 70998 ],                    # USA (US-AK)
                [ 72001, 72998 ],
                [ 74001, 74998 ],
                [ 91066, 91066 ],                    # (UM-71)
                [ 91101, 91199 ], [ 91280, 91299 ],  # (US-HI)
                [ 91210, 91219 ],                    # (GU)
                [ 91220, 91239 ],                    # (MP)
                [ 91250, 91259 ], [ 91365, 91379 ],  # (MH)
                [ 91764, 91768 ],                    # (AS)
                [ 91901, 91901 ],                    # (UM-86)
                [ 91902, 91903 ],                    # (KI-L)
              ],
    );
    my %IIiii_country = (
        AM => [ 37609, 37618, 37626, 37627, 37682, 37686, 37689, 37690, 37693,
                37694, 37698, 37699, 37704, 37706, 37708, 37711, 37717, 37719,
                37770, 37772, 37781, 37782, 37783, 37785, 37786, 37787, 37788,
                37789, 37789, 37791, 37792, 37801, 37802, 37808, 37815, 37871,
                37872, 37873, 37874, 37875, 37878, 37880, 37882, 37897, 37950,
                37953, 37958, 37959, ],                             # Armenia
        AR => [ 88963, 88968, 89034, 89053, 89055, 89066, ],
        AZ => [ 37575, 37579, 37590, 37636, 37639, 37642, 37661, 37668, 37670,
                37673, 37674, 37675, 37676, 37677, 37729, 37734, 37735, 37736,
                37740, 37744, 37746, 37747, 37749, 37750, 37753, 37756, 37759,
                37769, 37813, 37816, 37825, 37831, 37832, 37835, 37843, 37844,
                37849, 37851, 37852, 37853, 37860, 37861, 37864, 37866, 37869,
                37877, 37883, 37893, 37895, 37896, 37898, 37899, 37901, 37905,
                37907, 37912, 37913, 37914, 37923, 37925, 37936, 37941, 37946,
                37947, 37952, 37957, 37968, 37972, 37978, 37981, 37984, 37985,
                37989, ],                                           # Azerbaijan
        BY => [ 26554, 26643, 26645, 26653, 26657, 26659, 26666, 26668, 26759,
                26763, 26774, 26825, 26832, 26850, 26853, 26855, 26863, 26864,
                26878, 26887, 26941, 26951, 26961, 26966, 33008, 33019, 33027,
                33036, 33038, 33041, 33124, ],                      # Belarus
        EE => [ 26029, 26038, 26045, 26046, 26058, 26115, 26120, 26124, 26128,
                26134, 26135, 26141, 26144, 26145, 26214, 26215, 26218, 26226,
                26227, 26231, 26233, 26242, 26247, 26249, ],        # Estonia
        GE => [ 37279, 37308, 37379, 37395, 37409, 37432, 37481, 37484, 37492,
                37514, 37531, 37545, 37553, 37621, ],               # Georgia
        KG => [ 36911, 36944, 36974, 36982, 38345, 38353, 38613, 38616,
              ],                                                    # Kyrgyzstan
        KZ => [ 28676, 28766, 28867, 28879, 28951, 28952, 28966, 28978, 28984,
                29802, 29807, 35067, 35078, 35085, 35108, 35173, 35188, 35217,
                35229, 35302, 35357, 35358, 35376, 35394, 35406, 35416, 35426,
                35497, 35532, 35576, 35671, 35699, 35700, 35746, 35796, 35849,
                35925, 35953, 35969, 36003, 36152, 36177, 36208, 36397, 36428,
                36535, 36639, 36686, 36821, 36859, 36864, 36870, 36872, 38001,
                38062, 38064, 38069, 38196, 38198, 38222, 38232, 38328, 38334,
                38341, 38343, 38439, ],                             # Kazakhstan
        LT => [ 26502, 26509, 26515, 26518, 26524, 26529, 26531, 26547, 26600,
                26603, 26620, 26621, 26629, 26633, 26634, 26713, 26728, 26730,
                26732, 26737, ],                                    # Lithuania
        LV => [ 26229, 26238, 26313, 26314, 26318, 26324, 26326, 26335, 26339,
                26346, 26348, 26403, 26406, 26416, 26422, 26424, 26425, 26429,
                26435, 26436, 26446, 26447, 26503, 26544, ],        # Latvia
        MD => [ 33664, 33678, 33679, 33744, 33745, 33748, 33749, 33754, 33810,
                33815, 33821, 33824, 33829, 33881, 33883, 33885, 33886, 33892,
              ],                                                    # Moldova
        TJ => [ 38598, 38599, 38609, 38705, 38713, 38715, 38718, 38719, 38725,
                38734, 38744, 38836, 38838, 38844, 38846, 38847, 38851, 38856,
                38869, 38875, 38878, 38932, 38933, 38937, 38943, 38944, 38947,
                38951, 38954, 38957, ],                             # Tajikistan
        TM => [ 38261, 38267, 38367, 38383, 38388, 38392, 38507, 38511, 38527,
                38529, 38545, 38634, 38637, 38641, 38647, 38656, 38665, 38684,
                38687, 38750, 38755, 38756, 38759, 38763, 38767, 38773, 38774,
                38791, 38799, 38804, 38806, 38880, 38885, 38886, 38895, 38899,
                38911, 38915, 38974, 38987, 38989, 38998, ],      # Turkmenistan
        TV => [ 91643, ],                    # Tuvalu
        UA => [ 33049, 33058, 33088, 33135, 33173, 33177, 33187, 33213, 33228,
                33231, 33246, 33261, 33268, 33275, 33287, 33297, 33301, 33312,
                33317, 33325, 33345, 33347, 33356, 33362, 33376, 33377, 33393,
                33398, 33409, 33415, 33429, 33446, 33464, 33466, 33484, 33487,
                33495, 33506, 33526, 33536, 33548, 33557, 33562, 33577, 33586,
                33587, 33605, 33609, 33614, 33621, 33631, 33651, 33657, 33658,
                33663, 33699, 33705, 33711, 33717, 33723, 33761, 33777, 33791,
                33805, 33833, 33834, 33837, 33846, 33862, 33869, 33877, 33889,
                33896, 33902, 33907, 33910, 33915, 33924, 33929, 33939, 33945,
                33946, 33959, 33962, 33966, 33976, 33983, 33990, 33998, 34300,
                34302, 34312, 34319, 34401, 34407, 34409, 34415, 34421, 34434,
                34504, 34509, 34510, 34519, 34523, 34524, 34537, 34601, 34607,
                34609, 34615, 34622, 34704, 34708, 34712, 89063, ], # Ukraine
        US => [ 61902,                       # USA (SH-AC)
                61967,                       # (IO)
                78367,                       # (CU-14)
                91245,                       # (UM-79)
                91275,                       # (UM-67)
                91334, 91348, 91356, 91413,  # (FM)
                91442,                       # (MH)
                89009, 89049, 89061,
                89083, 89175, 89528, 89598, 89627, 89628, 89637, 89664, 89674,
                89108, 89208, 89257, 89261, 89262, 89264, 89266, 89269, 89272,
                89314, 89324, 89327, 89332, 89345, 89371, 89376, 89377, 89643,
                89667, 89734, 89744, 89768, 89769, 89799, 89828, 89832, 89834,
                89847, 89864, 89865, 89866, 89867, 89868, 89869, 89872, 89873,
                89879,
              ],
        UZ => [ 38023, 38141, 38146, 38149, 38178, 38262, 38264, 38339, 38396,
                38403, 38413, 38427, 38457, 38462, 38475, 38551, 38553, 38565,
                38567, 38579, 38583, 38589, 38606, 38611, 38618, 38683, 38685,
                38696, 38812, 38815, 38816, 38818, 38829, 38921, 38927,
              ],                                                    # Uzbekistan
    );
    # check single entries before ranges
    for my $country (keys %IIiii_country) {
        for (@{$IIiii_country{$country}}) {
            return $country if $IIiii == $_;
        }
    }
    for my $country (keys %IIiii_country2) {
        for (@{$IIiii_country2{$country}}) {
            return $country if $IIiii >= $_->[0] && $IIiii <= $_->[1];
        }
    }
    return '';
}

# WMO-No. 306 Vol I.1, Part A, code table 0161:
sub _A1bw2region {
    my $A1bw = shift;

    return qw(I II III IV V VI Antarctic)[substr($A1bw, 0, 1) - 1];
}

# determine the country that operates a station to select correct decoding rules
sub _A1bw2country {
    my $A1bw = shift;

    # ISO-3166 coded
    my %A1bw_country = (
        CA => [ qw(44137 44138 44139 44140 44141 44142 44150 44235 44251 44255
                   44258 45132 45135 45136 45137 45138 45139 45140 45141 45142
                   45143 45144 45145 45147 45148 45149 45150 45151 45152 45154
                   45159 45160 46004 46036 46131 46132 46134 46145 46146 46147
                   46181 46183 46184 46185 46204 46205 46206 46207 46208 46531
                   46532 46534 46537 46538 46559 46560 46561 46562 46563 46564
                   46565 46632 46633 46634 46635 46636 46637 46638 46639 46640
                   46641 46642 46643 46651 46652 46657 46660 46661 46692 46695
                   46698 46700 46701 46702 46705 46707 46710 47559 47560)
              ],
        US => [ qw(21413 21414 21415 21416 21417 21418 21419 32012 32301 32302
                   32411 32412 32745 32746 41001 41002 41003 41004 41005 41006
                   41007 41008 41009 41010 41011 41012 41013 41015 41016 41017
                   41018 41021 41022 41023 41025 41035 41036 41040 41041 41043
                   41044 41046 41047 41048 41049 41420 41421 41424 41X01 42001
                   42002 42003 42004 42005 42006 42007 42008 42009 42010 42011
                   42012 42015 42016 42017 42018 42019 42020 42025 42035 42036
                   42037 42038 42039 42040 42041 42042 42053 42054 42055 42056
                   42057 42058 42059 42060 42080 42407 42408 42409 42534 43412
                   43413 44001 44003 44004 44005 44006 44007 44008 44009 44010
                   44011 44012 44013 44014 44015 44017 44018 44019 44020 44022
                   44023 44025 44026 44027 44028 44039 44040 44052 44053 44056
                   44060 44065 44066 44070 44098 44401 44402 44585 44X11 45001
                   45002 45003 45004 45005 45006 45007 45008 45009 45010 45011
                   45012 45020 45021 45022 45023 46001 46002 46003 46005 46006
                   46007 46008 46009 46010 46011 46012 46013 46014 46015 46016
                   46017 46018 46019 46020 46021 46022 46023 46024 46025 46026
                   46027 46028 46029 46030 46031 46032 46033 46034 46035 46037
                   46038 46039 46040 46041 46042 46043 46045 46047 46048 46050
                   46051 46053 46054 46059 46060 46061 46062 46063 46066 46069
                   46070 46071 46072 46073 46075 46076 46077 46078 46079 46080
                   46081 46082 46083 46084 46085 46086 46087 46088 46089 46094
                   46105 46106 46107 46270 46401 46402 46403 46404 46405 46406
                   46407 46408 46409 46410 46411 46412 46413 46419 46490 46499
                   46551 46553 46779 46780 46781 46782 46785 46X84 48011 51000
                   51001 51002 51003 51004 51005 51026 51027 51028 51100 51101
                   51406 51407 51425 51426 51542 51X04 52009 52401 52402 52403
                   52404 52405 52406 54401 62027 91204 91222 91251 91328 91338
                   91343 91352 91355 91356 91365 91374 91377 91411 91442 ABAN6
                   ACQS1 ACXS1 AGMW3 ALRF1 ALSN6 AMAA2 ANMN6 ANRN6 APQF1 APXF1
                   AUGA2 BDVF1 BGXN3 BHRI3 BIGM4 BLIA2 BLTA2 BNKF1 BOBF1 BRIM2
                   BSBM4 BSLM2 BURL1 BUSL1 BUZM3 BWSF1 CANF1 CARO3 CBLO1 CBRW3
                   CDEA2 CDRF1 CHDS1 CHLV2 CHNO3 CLKN7 CLSM4 CNBF1 CPXC1 CSBF1
                   CSPA2 CVQV2 CWQO3 CYGM4 DBLN6 DEQD1 DESW1 DISW3 DKKF1 DMBC1
                   DPIA1 DRFA2 DRSD1 DRYF1 DSLN7 DUCN7 EB01 EB10 EB31 EB32 EB33
                   EB35 EB36 EB43 EB52 EB53 EB61 EB62 EB70 EB90 EB91 EB92 ELQC1
                   ELXC1 ERKC1 EROA2 FARP2 FBIS1 FBPS1 FFIA2 FILA2 FPSN7 FPTM4
                   FWYF1 GBCL1 GBIF1 GBLW3 GBQN3 GBTF1 GDIL1 GDIV2 GDQM6 GDWV2
                   GDXM6 GELO1 GLLN6 GRMM4 GSLM4 GTBM4 GTLM4 GTQF1 GTRM4 GTXF1
                   HCEF1 HHLO1 HMRA2 HPLM2 HUQN6 IOSN3 JCQN4 JCRN4 JCTN4 JKYF1
                   JOQP4 JOXP4 KCHA2 KNOH1 KNSW3 KTNF1 LBRF1 LBSF1 LCNA2 LDLC3
                   LMDF1 LMFS1 LMRF1 LMSS1 LNEL1 LONF1 LPOI1 LRKF1 LSCM4 LSNF1
                   LTQM2 MAQT2 MAXT2 MDRM1 MEEM4 MISM1 MLRF1 MPCL1 MRKA2 MUKF1
                   NABM4 NAQR1 NAXR1 NIQS1 NIWS1 NLEC1 NOQN7 NOXN7 NPDW3 NWPO3
                   OLCN6 OTNM4 OWQO1 OWXO1 PBFW1 PBLW1 PBPA2 PCLM4 PILA2 PILM4
                   PKYF1 PLSF1 PNGW3 POTA2 PRIM4 PRTA2 PSCM4 PTAC1 PTAT2 PTGC1
                   PWAW3 RKQF1 RKXF1 ROAM4 RPRN6 SANF1 SAQG1 SAUF1 SAXG1 SBIO1
                   SBLM4 SCLD1 SCQC1 SDIA2 SEQA2 SFXC1 SGNW3 SGOF1 SISA2 SISW1
                   SJLF1 SJOM4 SLVM5 SMBS1 SMKF1 SOQO3 SPGF1 SPTM4 SRST2 STDM4
                   SUPN6 SVLS1 SXHW3 SYWW3 TAWM4 TCVF1 TDPC1 TESTQ THIN6 TIBC1
                   TIQC1 TIXC1 TPEF1 TPLM2 TRRF1 TTIW1 VENF1 VMSV2 WAQM3 WATS1
                   WAXM3 WEQM1 WEXM1 WFPM4 WHRI2 WIWF1 WKQA1 WKXA1 WPLF1 WPOW1
                   WRBF1 YGNN6 YRSV2)
              ],
    );
    for my $country (keys %A1bw_country) {
        for (@{$A1bw_country{$country}}) {
            return $country if $A1bw eq $_;
        }
    }
    return '';
}

# determine the country that operates a station to select correct decoding rules
sub _A1A22country {
    my $A1A2 = shift;

    # WMO-No. 306 Vol I Part I.1, Section B recommends to use
    #   WMO-No. 386 Vol I Att. II-5 Table C1 but actually ISO-3166 is used,
    #   e.g. ARP03,CAP16,CKP23,KIP39,MNP45,PAP50,ISP34,MRP43,PAP50,RUP59
    return substr $A1A2, 0, 2;
}

# a3 standard isobaric surface for which the geopotential is reported
sub _codeTable0264 {
    my $idx = shift;

    return {
        1 => '1000',
        2 =>  '925',
        5 =>  '500',
        7 =>  '700',
        8 =>  '850'
    }->{$idx};
}

# C  genus of cloud
# C  genus of cloud predominating in the layer
# C' genus of cloud whose base is below the level of the station
sub _codeTable0500 {
    my ($r, $idx) = @_;

    if ($idx eq '/') {
        $r->{cloudTypeNotAvailable} = undef;
    } else {
        $r->{cloudType} = qw(CI CC CS AC AS NS SC ST CU CB)[$idx];
    }
    return;
}

# WMO-No. 306 Vol I.1, Part A, code table 0700:
# D  true direction from which surface wind is blowing
# D  true direction towards which ice has drifted in the past 12 hours
# DH true direction from which CH clouds are moving
# DK true direction from which swell is moving
# DL true direction from which CL clouds are moving
# DM true direction from which CM clouds are moving
# Da true direction in which orographic clouds or clouds with vertical development are seen
# Da true direction in which the phenomenon indicated is observed or in which conditions specified in the same group are reported
# De true direction towards which an echo pattern is moving
# Dp true direction from which the phenomenon indicated is coming
# Ds true direction of resultant displacement of the ship during the three hours preceding the time of observation
# D1 true direction of the point position from the station
sub _codeTable0700 {
    my ($r, $type, $idx, $parameter) = @_;

    if ($idx eq '/') {
        $r->{"${type}NA"} = undef;
    } elsif ($idx == 0) {
        if (defined $parameter && $parameter eq 'Da') {
            $r->{locationSpec} = 'atStation';
        } else {
            $r->{"${type}None"} = undef;
        }
    } elsif ($idx == 9) {
        if (defined $parameter && $parameter eq 'Da') {
            $r->{locationSpec} = 'allDirections';
        } else {
            $r->{"${type}Invisible"} = undef;
        }
    } else {
        $r->{"${type}Dir"} = {
            1 => 'NE',
            2 => 'E',
            3 => 'SE',
            4 => 'S',
            5 => 'SW',
            6 => 'W',
            7 => 'NW',
            8 => 'N',
        }->{$idx};
    }
    return;
}

# dc duration and character of precipitation given by RRR
sub _codeTable0833 {
    my $idx = shift;

    return { hours => { v => 1, q => 'isLess' }} if $idx == 0 || $idx == 4;
    return { hoursFrom => 1, hoursTill => 3 }    if $idx == 1 || $idx == 5;
    return { hoursFrom => 3, hoursTill => 6 }    if $idx == 2 || $idx == 6;
    return { hours => { v => 6, q => 'isGreater' }};
}

# eC elevation angle of the top of the cloud indicated by C
# e' elevation angle of the top of the phenomenon above horizon
sub _codeTable1004 {
    my ($r, $idx) = @_;

    if ($idx == 0) {
        $r->{topsInvisible} = undef;
    } elsif ($idx == 1) {
        $r->{elevationAngle}{v} = 45;
        $r->{elevationAngle}{q} = 'isEqualGreater';
    } elsif ($idx == 9) {
        $r->{elevationAngle}{v} = 5;
        $r->{elevationAngle}{q} = 'isLess';
    } else {
        $r->{elevationAngle} = {
            2 => 30,
            3 => 20,
            4 => 15,
            5 => 12,
            6 => 9,
            7 => 7,
            8 => 6,
        }->{$idx};
    }
    return;
}

# h height above surface of the base of the lowest cloud seen
sub _codeTable1600 {
    my $idx = shift;
    my @v;

    return { notAvailable => undef } if $idx eq '/';
    return { from => { v => 2500, u => 'M', q => 'isEqualGreater' }}
        if $idx == 9;
    @v = (0, 50, 100, 200, 300, 600, 1000, 1500, 2000, 2500)[$idx, $idx + 1];
    return { from => { v => $v[0], u => 'M' },
             to   => { v => $v[1], u => 'M' }};
}

# FMH-2 table 4-3
sub _codeTable1600US {
    my $idx = shift;
    my $v;

    return { notAvailable => undef } if $idx eq '/';
    return { from => { v => 8500, u => 'FT', q => 'isEqualGreater' }}
        if $idx == 9;
    $v = ([    0,  100 ],
          [  200,  300 ],
          [  400,  600 ],
          [  700,  900 ],
          [ 1000, 1900 ],
          [ 2000, 3200 ],
          [ 3300, 4900 ],
          [ 5000, 6500 ],
          [ 7000, 8000 ])[$idx];

    return { from => { v => $v->[0], u => 'FT' },
             to   => { v => $v->[1], u => 'FT' }};
}

# hshs height of base of cloud layer or mass whose genus is indicated by C
# htht height of the tops of the lowest clouds or height of the lowest cloud layer or fog
sub _codeTable1677 {
    my $idx = shift;

    return { v => 30,    q => 'isLess'         } if $idx == 0;
    return { v => 30 * $idx                    } if $idx <= 50;
    return { v => 300 * ($idx - 50)            } if $idx <= 80;
    return { v => 1500 * ($idx - 74)           } if $idx <= 88;
    return { v => 21000, q => 'isGreater'      } if $idx == 89;
    return { v => 50,    q => 'isLess'         } if $idx == 90;
    return { v => 2500,  q => 'isEqualGreater' } if $idx == 99;
    return [(50, 100, 200, 300, 600, 1000, 1500, 2000, 2500)
                                                        [$idx - 91, $idx - 90]];
}

# N  total cloud cover
# Nh amount of all the CL cloud present or, if no CL cloud is present, the amount of all the CM cloud present
# Ns amount of individual cloud layer or mass whose genus is indicated by C
# N' amount of cloud whose base is below the level of the station
sub _codeTable2700 {
    my $idx = shift;

    return { oktasNotAvailable => undef } if $idx eq '/';
    return { skyObscured       => undef } if $idx eq '9';
    return { oktas             => $idx  };
}

# QA location quality class (range of radius of 66% confidence)
sub _codeTable3302 {
    my $idx = shift;

    return $idx eq '/' ? { notAvailable => undef }
                       : ($idx > 3 ? { invalidFormat => $idx }
                                   : {
         0 => { distance     => { v => 1500, u => 'M', q => 'isEqualGreater' }},
         1 => { distanceFrom => { v => 500,  u => 'M', q => 'isEqualGreater' },
                distanceTo   => { v => 1500, u => 'M', q => 'isLess'         }},
         2 => { distanceFrom => { v => 250,  u => 'M', q => 'isEqualGreater' },
                distanceTo   => { v => 500,  u => 'M', q => 'isLess'         }},
         3 => { distance     => { v => 250,  u => 'M', q => 'isLess'         }}
    }->{$idx});
}

# Rt time at which precipitation given by RRR began or ended
sub _codeTable3552 {
    my $idx = shift;

    return { hours => { v => 1, q => 'isLess' }}        if $idx == 1;
    return { hoursFrom => $idx - 1, hoursTill => $idx } if $idx <= 6;
    return { hoursFrom => 6, hoursTill => 12 }          if $idx == 7;
    return { hours => { v => 12, q => 'isGreater' }}    if $idx == 8;
    return { notAvailable => undef };
}

# RR amount of precipitation or water equivalent of solid precipitation, or diameter of solid deposit
sub _codeTable3570 {
    my ($r, $idx, $tag) = @_;

    if ($idx <= 55) {
        $$r->{$tag} = { v => $idx + 0, u => 'MM' };
    } elsif ($idx <= 90) {
        $$r->{$tag} = { v => ($idx - 50) * 10, u => 'MM' };
    } elsif ($idx <= 96) {
        $$r->{$tag} = { v => ($idx - 90) / 10, u => 'MM' };
    } elsif ($idx == 97) {
        $$r->{precipTraces} = undef;
    } elsif ($idx == 98) {
        $$r->{$tag} = { v => 400, u => 'MM', q => 'isGreater' };
    } else {
        $$r->{notAvailable} = undef;
    }
    return;
}

# RRR amount of precipitation which has fallen during the period preceding the time of observation, as indicated by tR
sub _codeTable3590 {
    my $idx = shift;

    return { notAvailable => undef }                       if $idx eq '///';

    return { precipAmount => { v => $idx + 0, u => 'MM' }} if $idx <= 988;
    return { precipAmount => { v => 989,      u => 'MM',
                               q => 'isEqualGreater' }}    if $idx == 989;
    return { precipTraces => undef }                       if $idx == 990;
    return { precipAmount => { v => ($idx - 990) / 10, u => 'MM' }};
}

# ss depth of newly fallen snow
sub _codeTable3870 {
    my ($r, $idx) = @_;

    if ($idx <= 55) {
        $$r->{precipAmount} = { v => $idx * 10, u => 'MM' };
    } elsif ($idx <= 90) {
        $$r->{precipAmount} = { v => ($idx - 50) * 100, u => 'MM' };
    } elsif ($idx <= 96) {
        $$r->{precipAmount} = { v => $idx + 0, u => 'MM' };
    } elsif ($idx == 97) {
        $$r->{precipAmount} = { v => 1, q => 'isLess', u => 'MM' };
    } elsif ($idx == 98) {
        $$r->{precipAmount} = { v => 4000, q => 'isGreater', u => 'MM' };
    } else {
        $$r->{noMeasurement} = undef;
    }
    return;
}

# tR duration of period of reference for amount of precipitation, ending at the time of the report
sub _codeTable4019 {
    my $idx = shift;
    return { notAvailable => undef } if $idx == 0;
    return { hours => (6, 12, 18, 24, 1, 2, 3, 9, 15)[$idx - 1] };
}

# tt time before observation or duration of phenomena (00-69)
# zz variation, location or intensity of phenomena (76-99)
# for both: 70-75
sub _codeTable4077 {
    my ($idx, $occurred) = @_; # 'Since' is default for occurred

    return { timeBeforeObs => { hours => sprintf('%.1f', $idx / 10),
                                $occurred ? (occurred => $occurred) : () }}
        if $idx <= 60;
    return { timeBeforeObs => { hoursFrom => $idx - 55, hoursTill => $idx - 54,
                                $occurred ? (occurred => $occurred) : () }}
        if $idx <= 66;
    return { timeBeforeObs => { hoursFrom => 12, hoursTill => 18,
                                $occurred ? (occurred => $occurred) : () }}
        if $idx == 67;
    return { timeBeforeObs => { hours => { v => 18, q => 'isGreater' },
                                $occurred ? (occurred  => $occurred) : () }}
        if $idx == 68;
    return { timeBeforeObs => { notAvailable => undef,
                                $occurred ? (occurred  => $occurred) : () }}
        if $idx == 69;
    return { phenomVariation =>
             qw(beganDuringObs      endedDuringObs
                beganEndedDuringObs changedDuringObs
                beganAfterObs       endedAfterObs)[$idx - 70]
    } if $idx <= 75;
    return { location => { locationSpec =>
        (qw(atStation                atStationNotInDistance
            allDirections            allDirectionsNotAtStation
            approchingStation        recedingFromStation
            passingStationInDistance)[$idx - 76])}
    } if $idx <= 82;
    return { location => { inDistance => undef }} if $idx == 83;
    return { location => { inVicinity => undef }} if $idx == 84;
    return { phenomDescr =>
        qw(aloftNotNearGround
           nearGroundNotAloft       isOccasional
           isIntermittent           isFrequent
           isSteady                 isIncreasing
           isDecreasing             isVariable
           isContinuous             isVeryLight
           isLight                  isModerate
           isHeavy                  isVeryHeavy)[$idx - 85]
    };
}

# VV   horizontal visibility at surface
# VsVs visibility towards the sea
# WMO-No. 306 Vol I.1, Part A, Section A, 12.2.1.3.2:
#   In reporting visibility at sea, the decile 90-99 shall be used for VV.
# WMO-No. 488:
#   3.2.2.3 Observations at sea stations
#   3.2.2.3.4 Visibility
#   The requirements ... are ... low, ... decade 90-99 of code table 4377 ...
sub _codeTable4377 {
    my ($r, $idx, $station_type) = @_;
    my (%vis, $vis_type);

    if ($idx eq '//') {
        $r->{visPrev}{s} = $idx;
        $r->{visPrev}{notAvailable} = undef;
        return;
    }
    if ($idx >= 51 && $idx <= 55) {
        $r->{visPrev}{s} = $idx;
        $r->{visPrev}{invalidFormat} = $idx;
        return;
    }

    $vis_type = 'visPrev';
    $vis{distance}{u} = 'KM';
    if ($idx == 0) {
        $vis{distance}{v} = 100;
        $vis{distance}{u} = 'M';
        $vis{distance}{q} = 'isLess';
    } elsif ($idx <= 50) {
        $vis{distance}{v} = $idx * 100;
        $vis{distance}{rp} = 100;
        $vis{distance}{u} = 'M';
    } elsif ($idx <= 80) {
        $vis{distance}{v} = $idx - 50;
        $vis{distance}{rp} = 1;
    } elsif ($idx <= 88) {
        $vis{distance}{v} = 5 * ($idx - 74);
        $vis{distance}{rp} = 4;
    } elsif ($idx == 89) {
        $vis{distance}{v} = 70;
        $vis{distance}{q} = 'isGreater';
    } elsif ($idx == 90) {
        $vis_type = 'visibilityAtLoc';
        $vis{distance}{v} = 50;
        $vis{distance}{u} = 'M';
        $vis{distance}{q} = 'isLess';
    } elsif ($idx == 99) {
        $vis_type = 'visibilityAtLoc';
        $vis{distance}{v} = 50;
        $vis{distance}{q} = 'isEqualGreater';
    } else {
        $vis_type = 'visibilityAtLoc';
        @{$vis{distance}}{qw(v rp u)} = @{(
            [   50, 150,  'M' ],   # 91
            [  200, 300,  'M' ],   # 92
            [  500, 500,  'M' ],   # 93
            [    1,   1, 'KM' ],   # 94
            [    2,   2, 'KM' ],   # 95
            [    4,   6, 'KM' ],   # 96
            [   10,  10, 'KM' ],   # 97
            [   20,  30, 'KM' ],   # 98
        )[$idx - 91]};
    }
    if ($vis_type eq 'visPrev' || $station_type =~ /^[AO]/) {
        $r->{visPrev} = \%vis;
        $r->{visPrev}{s} = $idx;
    } else {
        $r->{visibilityAtLoc}{visibility} = \%vis;
        $r->{visibilityAtLoc}{locationAt} = 'MAR';
        $r->{visibilityAtLoc}{s} = $idx;
    }
    return;
}

sub _codeTable4377US {
    my ($r, $idx, $station_type, $is_auto) = @_;
    my (%vis, $vis_type);

    if ($idx eq '//') {
        $r->{visPrev}{s} = $idx;
        $r->{visPrev}{notAvailable} = undef;
        return;
    }

    $vis_type = 'visPrev';
    $vis{distance}{u} = 'SM';
    if ($idx == 0) {
        $vis{distance}{v} = 1/16;
        $vis{distance}{q} = 'isLess';
    } elsif ($idx =~ /^(?:0[1-68]|[12][02468]|3[026]|4[048])$/) {
        $vis{distance}{v} = $idx / 16;
    } elsif ($idx =~ /^(?:5[68]|6[0134689]|7[134]|8[02457])$/) {
        $vis{distance}{v} = {
            56 =>  4, 58 =>  5,
            60 =>  6, 61 =>  7, 63 =>  8, 64 => 9, 66 => 10, 68 => 11, 69 => 12,
            71 => 13, 73 => 14, 74 => 15,
            80 => 20, 82 => 25, 84 => 30, 85 => 35, 87 => 40,
        }->{$idx};
    } elsif ($idx == 89) {
        $vis{distance}{v} = 45;
        $vis{distance}{q} = 'isEqualGreater';
    } elsif ($idx == 90) {
        $vis_type = 'visibilityAtLoc';
        $vis{distance}{v} = 1/16;
        $vis{distance}{q} = 'isLess';
        $vis{distance}{u} = 'NM';
    } elsif ($idx == 99) {
        $vis_type = 'visibilityAtLoc';
        $vis{distance}{v} = 10;
        $vis{distance}{q} = 'isGreater';
        $vis{distance}{u} = 'NM';
    } elsif ($idx > 90) {
        $vis_type = 'visibilityAtLoc';
        # FMH-2 table 4-5
        @{$vis{distance}}{qw(v rp)} = @{(
           [ 1/16, 1/16 ],   # 91
           [ 1/8,  1/8  ],   # 92
           [ 1/4,  1/4  ],   # 93
           [ 1/2,  1/2  ],   # 94
           [ 1,    1    ],   # 95
           [ 2,    5    ],   # 96
           [ 5,    9    ],   # 97
           [ 9,    11   ],   # 98
        )[$idx - 91]};
        $vis{distance}{u} = 'NM';
    } else {
        $r->{visPrev}{s} = $idx;
        $r->{visPrev}{invalidFormat} = $idx;
        return;
    }
    _setVisibilitySMOffsetUS $vis{distance}, $is_auto
        if $vis{distance}{u} eq 'SM';
    if ($vis_type eq 'visPrev' || $station_type =~ /^[AO]/) {
        $r->{visPrev} = \%vis;
        $r->{visPrev}{s} = $idx;
    } else {
        $r->{visibilityAtLoc}{visibility} = \%vis;
        $r->{visibilityAtLoc}{locationAt} = 'MAR';
        $r->{visibilityAtLoc}{s} = $idx;
    }
    return;
}

# MANOBS 12.3.1.4
sub _codeTable4377CA {
    my ($r, $idx) = @_;
    my (%vis, $vis_type);

    if ($idx eq '//') {
        $r->{visPrev}{s} = $idx;
        $r->{visPrev}{notAvailable} = undef;
        return;
    }

    $vis_type = 'visPrev';
    $vis{distance}{u} = 'SM';
    if ($idx =~ /^(?:0[02468]|1[026]|2[048]|3[26]|4[08])$/) {
        $vis{distance}{v} = $idx / 16;
    } elsif ($idx =~ /^(?:5[689]|6[124679]|7[024]|8[0-8])$/) {
        $vis{distance}{v} = {
            56 =>  4, 58 =>  5, 59 =>  6,
            61 =>  7, 62 =>  8, 64 =>  9, 66 => 10, 67 => 11, 69 => 12,
            70 => 13, 72 => 14, 74 => 15,
            80 => 19, 81 => 22, 82 => 25, 83 => 28, 84 => 32, 85 => 35,
                      86 => 38, 87 => 41, 88 => 44,
        }->{$idx};
    } elsif ($idx == 89) {
        $vis{distance}{v} = 44;
        $vis{distance}{q} = 'isGreater';
    } else {
        $r->{visPrev}{s} = $idx;
        $r->{visPrev}{invalidFormat} = $idx;
        return;
    }

    if (!exists $vis{distance}{q}) {
        if ($vis{distance}{v} < 3/4) {
            $vis{distance}{rp} = 1/8;
        } elsif ($vis{distance}{v} < 2.5) {
            $vis{distance}{rp} = 1/4;
        } elsif ($vis{distance}{v} < 3) {
            $vis{distance}{rp} = 1/2;
        } elsif ($vis{distance}{v} < 15) {
            $vis{distance}{rp} = 1;
        } elsif ($vis{distance}{v} == 15 || $vis{distance}{v} == 28) {
            $vis{distance}{rp} = 4;
        } elsif ($vis{distance}{v} != 44) {
            $vis{distance}{rp} = 3;
        }
    }

    $r->{visPrev} = \%vis;
    $r->{visPrev}{s} = $idx;
    return;
}

# w1w1 Present weather phenomenon not specified in Code table 4677, or
#      specification of present weather phenomenon in addition to group 7wwW1W2
sub _codeTable4687 {
    my $idx = shift;
    my $r;

    return { weatherPresent1 => $idx }
        unless (   ($idx >= 47 && $idx <= 57)
                || ($idx >= 60 && $idx <= 67)
                || ($idx >= 70 && $idx <= 77));

    $r = ( { weatherSynopFG => { # 47
             visVertFrom => { distance => { v => 60, u => 'M' }},
             visVertTo   => { distance => { v => 90, u => 'M' }}}},
         { weatherSynopFG => { # 48
             visVertFrom => { distance => { v => 30, u => 'M' }},
             visVertTo   => { distance => { v => 60, u => 'M' }}}},
         { weatherSynopFG => { # 49
             visVert     => { distance => { v => 30, u => 'M',
                                            q => 'isLess' }}}},
         { weatherSynopPrecip => { # 50
             rateOfFall     => { v => '0.10', u => 'MMH', q => 'isLess' }}},
         { weatherSynopPrecip => { # 51
             rateOfFallFrom => { v => '0.10', u => 'MMH' },
             rateOfFallTo   => { v => 0.19, u => 'MMH' }}},
         { weatherSynopPrecip => { # 52
             rateOfFallFrom => { v => '0.20', u => 'MMH' },
             rateOfFallTo   => { v => 0.39, u => 'MMH' }}},
         { weatherSynopPrecip => { # 53
             rateOfFallFrom => { v => '0.40', u => 'MMH' },
             rateOfFallTo   => { v => 0.79, u => 'MMH' }}},
         { weatherSynopPrecip => { # 54
             rateOfFallFrom => { v => '0.80', u => 'MMH' },
             rateOfFallTo   => { v => 1.59, u => 'MMH' }}},
         { weatherSynopPrecip => { # 55
             rateOfFallFrom => { v => '1.60', u => 'MMH' },
             rateOfFallTo   => { v => 3.19, u => 'MMH' }}},
         { weatherSynopPrecip => { # 56
             rateOfFallFrom => { v => '3.20', u => 'MMH' },
             rateOfFallTo   => { v => 6.39, u => 'MMH' }}},
         { weatherSynopPrecip => { # 57
             rateOfFall     => { v => 6.4, u => 'MMH',
                                 q => 'isEqualGreater' }}},
         { }, # 58
         { }, # 59
         { weatherSynopPrecip => { # 60
             rateOfFall     => { v => '1.0', u => 'MMH', q => 'isLess' }}},
         { weatherSynopPrecip => { # 61
             rateOfFallFrom => { v => '1.0', u => 'MMH' },
             rateOfFallTo   => { v => 1.9, u => 'MMH' }}},
         { weatherSynopPrecip => { # 62
             rateOfFallFrom => { v => '2.0', u => 'MMH' },
             rateOfFallTo   => { v => 3.9, u => 'MMH' }}},
         { weatherSynopPrecip => { # 63
             rateOfFallFrom => { v => '4.0', u => 'MMH' },
             rateOfFallTo   => { v => 7.9, u => 'MMH' }}},
         { weatherSynopPrecip => { # 64
             rateOfFallFrom => { v => '8.0', u => 'MMH' },
             rateOfFallTo   => { v => 15.9, u => 'MMH' }}},
         { weatherSynopPrecip => { # 65
             rateOfFallFrom => { v => '16.0', u => 'MMH' },
             rateOfFallTo   => { v => 31.9, u => 'MMH' }}},
         { weatherSynopPrecip => { # 66
             rateOfFallFrom => { v => '32.0', u => 'MMH' },
             rateOfFallTo   => { v => 63.9, u => 'MMH' }}},
         { weatherSynopPrecip => { # 67
             rateOfFall     => { v => '64.0', u => 'MMH',
                                 q => 'isEqualGreater' }}},
         { }, # 68
         { }, # 69
         { weatherSynopPrecip => { # 70
             rateOfFall     => { v => '1.0', u => 'CMH', q => 'isLess' }}},
         { weatherSynopPrecip => { # 71
             rateOfFallFrom => { v => '1.0', u => 'CMH' },
             rateOfFallTo   => { v => 1.9, u => 'CMH' }}},
         { weatherSynopPrecip => { # 72
             rateOfFallFrom => { v => '2.0', u => 'CMH' },
             rateOfFallTo   => { v => 3.9, u => 'CMH' }}},
         { weatherSynopPrecip => { # 73
             rateOfFallFrom => { v => '4.0', u => 'CMH' },
             rateOfFallTo   => { v => 7.9, u => 'CMH' }}},
         { weatherSynopPrecip => { # 74
             rateOfFallFrom => { v => '8.0', u => 'CMH' },
             rateOfFallTo   => { v => 15.9, u => 'CMH' }}},
         { weatherSynopPrecip => { # 75
             rateOfFallFrom => { v => '16.0', u => 'CMH' },
             rateOfFallTo   => { v => 31.9, u => 'CMH' }}},
         { weatherSynopPrecip => { # 76
             rateOfFallFrom => { v => '32.0', u => 'CMH' },
             rateOfFallTo   => { v => 63.9, u => 'CMH' }}},
         { weatherSynopPrecip => { # 77
             rateOfFall     => { v => '64.0', u => 'CMH',
                                 q => 'isEqualGreater' }}}
       )[$idx - 47];

    $r->{weatherSynopPrecip}{phenomSpec} = 'DZ' if $idx >= 50 && $idx <= 57;
    $r->{weatherSynopPrecip}{phenomSpec} = 'RA' if $idx >= 60 && $idx <= 67;
    $r->{weatherSynopPrecip}{phenomSpec} = 'SN' if $idx >= 70;

    return $r;
}

# WMO-No. 306 Vol I.1, Part A, Section B:
# HwHw     height of wind waves, in units of 0.5 m
# HwaHwa   height of waves, obtained by instrumental methods, in units of 0.5 m
# Hw1Hw1   height of swell waves, in units of 0.5 m
# Hw2Hw2   height of swell waves, in units of 0.5 m
sub _waveHeight {
    my $height = shift;

    return { v => 0, rp => 0.25, u => 'M' } if $height == 0;
    return { v => $height * 0.5 - 0.25, rp => 0.5, u => 'M' };
}

sub _radiationType {
    my $idx = shift;

    return {
        0 => 'rad0PosNet',
        1 => 'rad1NegNet',
        2 => 'rad2GlobalSolar',
        3 => 'rad3DiffusedSolar',
        4 => 'rad4DownwardLongWave',
        5 => 'rad5UpwardLongWave',
        6 => 'rad6ShortWave',
    }->{$idx};
}

sub _getTempCity {
    my ($prefix, $sn, $temp, $tempAirF) = @_;
    my $r;

    $r->{s} = "$prefix$sn$temp";
    $r->{temp}{v} = $temp + 0;
    if ($sn == 1) {
        $r->{temp}{v} *= -1;
    } elsif (defined $tempAirF && $r->{temp}{v} + 50 < $tempAirF) {
        $r->{temp}{v} += 100;
    }
    $r->{temp}{u} = 'F';
    return $r;
}

sub _getRecordTemp {
    my $record = shift;

    $record =~ /(..)(.)(..)/;
    return {
        s            => "$1$2$3",
        recordPeriod => $3,
        recordType   => {
            v => $1,
            $2 eq 'X' ? (q => $1 eq 'LO' ? 'isLess' : 'isGreater') : ()
        }
    };
}

sub _check_915dd {
    my ($r, $winds_est) = @_;

    if (/\G915($re_dd) /ogc) {
        $r->{s} .= " 915$1";
        if ($winds_est) {
            $r->{wind}{isEstimated} = undef;
        } else {
            $r->{wind}{dir} = { rp => 4, rn => 5 };
        }
        $r->{wind}{dir}{v} = ($1 % 36) * 10;
    }
}

sub _check_958EhDa {
    my $r = shift;

    while (m@\G958([137/])(\d) @gc) {
        my $e;

        $r->{s} .= " 958$1$2";

        if ($1 eq '/') {
            $e->{elevNotAvailable} = undef;
        } else {
            # Eh: WMO-No. 306 Vol I.1, Part A, code table 0938:
            $e->{elevAboveHorizon} = $1;
        }

        $e->{location} = {};
        _codeTable0700 $e->{location}, 'compass', $2, 'Da';
        push @{$r->{maxConcentration}}, $e;
    }
}

# get temperature with tenths from rounded temperature and tenths digit
# for rounded temperature == 0: tenths are -4 .. 4
# otherwise tenths are 0..9
sub _mkTempTenths {
    my ($temp_rounded, $tenths) = @_;

    $tenths = $tenths - 10
        if $tenths >= 5;
    $tenths = -$tenths
        if $temp_rounded < 0;
    return sprintf '%.1f', $temp_rounded + $tenths / 10;
}

# get position from QcLaLaLaLaLa LoLoLoLoLoLo
sub _latLon1000 {
    my $r;

    m@\G(([1357])(\d\d)(\d)(?:(\d\d)|(\d)/|//) (\d\d\d)(\d)(?:(\d\d)|(\d)/|//)) @gc
        or return undef;

    $r->{lat} =   ($3 + 0) . ".$4"
                . (defined $5 ? $5 : '') . (defined $6  ? $6  : '');
    $r->{lon} =   ($7 + 0) . ".$8"
                . (defined $9 ? $9 : '') . (defined $10 ? $10 : '');
    if ($r->{lat} > 90 || $r->{lon} > 180) {
        pos $_ -= 14;
        return undef;
    }

    $r->{s} = $1;
    $r->{lat} = '-' . $r->{lat} if ($2 == 3 || $2 == 5);
    $r->{lon} = '-' . $r->{lon} if ($2 == 5 || $2 == 7);
    return $r;
}

sub _msgModified {
    my $report = shift;
    my $warning;

    $warning = \(grep { $_->{warningType} eq 'msgModified' }
                      ($report->{warning} ? @{$report->{warning}} : ()));
    if ($$warning) {
        $$warning->{s} = substr $_, 0, -1;
    } else {
        unshift @{$report->{warning}}, { warningType => 'msgModified',
                                         s           => substr $_, 0, -1 }
    }
}

# since 00:00Z, 06:00Z, 12:00Z, 18:00Z
sub _timeSinceSynopticMain {
    my ($obs_hour, $obs_minute) = @_;
    my ($hour_min, $since_hour);

    if (defined $obs_hour) {
        $hour_min = $obs_hour * 60 + $obs_minute;
    } else {
        $hour_min = 0;
    }

    if ($hour_min % 360 == 0) {
        $since_hour = sprintf "%02d", $obs_hour - 6;
        $since_hour = 18 if $since_hour == -6;
    } else {
        $since_hour = sprintf "%02d", ($hour_min - ($hour_min % 360)) / 60;
    }
    return { hour => $since_hour };
}

########################################################################
# _parseBuoy
########################################################################
sub _parseBuoy {
    my (%report, $windUnit, $winds_est, $country, $region);

    $report{msg} = $_;
    $report{isBuoy} = undef;
    $report{version} = VERSION();

    if (/^ERROR -/) {
        pos $_ = 0;
        $report{ERROR} = _makeErrorMsgPos 'other';
        return %report;
    }

=head2 Parsing of BUOY messages

=cut

    # EXTENSION: preprocessing
    # remove trailing =
    s/ ?=$//;

    $_ .= ' '; # this makes parsing much easier

    pos $_ = 0;

    # warn about modification
    push @{$report{warning}}, { warningType => 'msgModified',
                                s           => substr $_, 0, -1 }
        if $report{msg} . ' ' ne $_;

########################################################################

=head3 Section 0: information about the identification, time and position data

 MiMiMjMj A1bwnbnbnb YYMMJ GGggiw QcLaLaLaLaLa LoLoLoLoLoLo (6QlQtQA/)

=for html <!--

=over

=item B<MiMiMjMj>

=for html --><dl><dt><strong>M<sub>i</sub>M<sub>i</sub>M<sub>j</sub>M<sub>j</sub></strong></dt>

station type

=back

=cut

    # group MiMiMjMj
    if (!/\G(ZZYY) /gc) {
        $report{ERROR} = _makeErrorMsgPos 'obsStationType';
        return %report;
    }
    $report{obsStationType} = { s => $1, stationType => $1 };

    $region = '';
    $country = '';

=for html <!--

=over

=item B<A1bwnbnbnb>

=for html --><dl><dt><strong>A<sub>1</sub>b<sub>w</sub>n<sub>b</sub>n<sub>b</sub>n<sub>b</sub></strong></dt>

station id

=back

=cut

    # group A1bwnbnbnb
    # A1bw: maritime zone, nnn: 001..499, 500 added if drifting buoy
    if (/\G(${re_A1bw}\d{3}) /ogc) {
        $country = _A1bw2country $1;
        $region  = _A1bw2region $1;
        $report{buoyId} = { s => $1, id => $1, region => $region };
    } else {
        $report{ERROR} = _makeErrorMsgPos 'buoyId';
        return %report;
    }

=for html <!--

=over

=item B<YYMMJ GGggiw>

=for html --><dl><dt><strong>YYMMJ GGggi<sub>w</sub></strong></dt>

day, month, units digit of year, hour, minute of observation, indicator for wind speed (unit)

=back

=cut

    # groups YYMMJ GGggiw
    if (!m@\G($re_day)(0[1-9]|1[0-2])(\d) ($re_hour)($re_min)([0134/]) @ogc) {
        $report{ERROR} = _makeErrorMsgPos 'obsTimeWindInd';
        return %report;
    }
    $report{obsTime} = {
        s      => "$1$2$3 $4$5",
        timeAt => { day => $1, month => $2, yearUnitsDigit => $3,
                    hour => $4, minute => $5 }
    };

    # WMO-No. 306 Vol I.1, Part A, code table 1855:
    $report{windIndicator}{s} = $6;
    if ($6 ne '/') {
        $windUnit = $6 < 2 ? 'MPS' : 'KT';
        $winds_est = $6 == 0 || $6 == 3;
        $report{windIndicator}{windUnit} = $windUnit;
        $report{windIndicator}{isEstimated} = undef if $winds_est;
    } else {
        $report{windIndicator}{notAvailable} = undef;
    }

=for html <!--

=over

=item B<QcLaLaLaLaLa LoLoLoLoLoLo>

=for html --><dl><dt><strong>Q<sub>c</sub>L<sub>a</sub>L<sub>a</sub>L<sub>a</sub>L<sub>a</sub>L<sub>a</sub> L<sub>o</sub>L<sub>o</sub>L<sub>o</sub>L<sub>o</sub>L<sub>o</sub></strong></dt>

position of the buoy

=back

=cut

    # group QcLaLaLaLaLa LoLoLoLoLoLo
    if (m@\G(////// //////) @gc) {
        $report{stationPosition} = { s => $1, notAvailable => undef };
    } else {
        my $r;

        $r = _latLon1000;
        if (!defined $r) {
            $report{ERROR} = _makeErrorMsgPos 'stationPosition';
            return %report;
        }
        $report{stationPosition} = $r;
    }

=for html <!--

=over

=item B<C<6>QlQtQAC</>>

=for html --><dl><dt><strong><code>6</code>Q<sub>l</sub>Q<sub>t</sub>Q<sub>A</sub><code>/</code></strong></dt>

quality control indicators for position and time

=back

=cut

    # group 6QlQtQA/
    if (m@\G6([\d/])([\d/])([\d/])/ @gc) {
        $report{qualityPositionTime} = {
            s => "6$1$2$3/",
            # WMO-No. 306 Vol I.1, Part A, code table 3334:
            qualityControlPosition => {
                $1 eq '/' ? (notAvailable => undef)
                          : ($1 > 5 ? (invalidFormat => $1)
                                    : (qualityControlInd => $1))
            },
            # WMO-No. 306 Vol I.1, Part A, code table 3334:
            qualityControlTime => {
                $2 eq '/' ? (notAvailable => undef)
                          : ($2 > 5 ? (invalidFormat => $2)
                                    : (qualityControlInd => $2))
            },
            qualityLocClass => _codeTable3302 $3
        };
    }

########################################################################

=head3 Section 1: meteorological and other non-marine data (optional)

 111QdQx 0ddff 1snTTT {2snTdTdTd|29UUU} 3P0P0P0P0 4PPPP 5appp

=for html <!--

=over

=item B<C<111>QdQx>

=for html --><dl><dt><strong><code>111</code>Q<sub>d</sub>Q<sub>x</sub></strong></dt>

quality control indicators for section 1

=back

=cut

    # group 111QdQx
    if (m@\G111(//|([01])9|([2-5])([1-69])|([\d/][\d/])) @gc) {
        my (@s1, %temp);

        @s1  = ();

        # WMO-No. 306 Vol I.1, Part A, Section A, 18.3.3,
        # WMO-No. 306 Vol I.1, Part A, code table 3334:
        push @s1, { qualitySection => {
            s => $1,
            defined $2
                ? (qualityControlInd => $2)
                : (defined $3
                    ? (qualityControlInd => $3,
                       $4 != 9 ? (worstQualityGroup => $4) : ())
                    : (defined $5 ? (invalidFormat => $5)
                                  : (notAvailable => undef)))
        }};

=over

=item B<C<0>ddff>

wind direction and speed

=back

=cut

        # group 0ddff
        if (m@\G0($re_dd|00|99|//)(\d\d|//) @ogc) {
            my $r;

            $r->{s} = "0$1$2";
            if ("$1$2" eq '////') {
                $r->{wind}{notAvailable} = undef;
            # WMO-No. 306 Vol I.1, Part A, code table 0877:
            } elsif ($1 eq '00') {
                $r->{wind}{isCalm} = undef;
                $r->{wind}{isEstimated} = undef if $winds_est;
            } else {
                if ($1 eq '//') {
                    $r->{wind}{dirNotAvailable} = undef;
                } elsif ($1 eq '99') {
                    $r->{wind}{dirVarAllUnk} = undef;
                } else {
                    if ($winds_est) {
                        $r->{wind}{isEstimated} = undef;
                    } else {
                        $r->{wind}{dir} = { rp => 4, rn => 5 };
                    }
                    $r->{wind}{dir}{v} = $1 * 10;
                }
                if ($2 eq '//' || !$windUnit) {
                    $r->{wind}{speedNotAvailable} = undef;
                } else {
                    $r->{wind}{speed} = { v => $2 + 0, u => $windUnit };
                    $r->{wind}{isEstimated} = undef if $winds_est;
                }
            }
            push @s1, { sfcWind => $r };
        }

=for html <!--

=over

=item B<C<1>snTTT>

=for html --><dl><dt><strong><code>1</code>s<sub>n</sub>TTT</strong></dt>

temperature

=back

=cut

        # group 1snTTT
        if (m@\G(1(?:[01/]///|([01]\d\d[\d/]))) @gc) {
            $temp{s} = $1;
            if (defined $2) {
                $temp{air}{temp} = _parseTemp $2;
            } else {
                $temp{air}{notAvailable} = undef;
            }
        }

=for html <!--

=over

=item B<C<2>snTdTdTd> | B<C<29>UUU>

=for html --><dl><dt><strong><code>2</code>s<sub>n</sub>T<sub>d</sub>T<sub>d</sub>T<sub>d</sub></strong> | <strong><code>29</code>UUU</strong></dt>

dewpoint or relative humidity

=back

=cut

        # group 2snTdTdTd|29UUU
        if (m@\G(2(?:[109/]///|([01]\d\d[\d/])|9(100|0\d\d))) @gc) {
            if (exists $temp{s}) {
                $temp{s} .= ' ';
            } else {
                $temp{s} = '';
            }
            $temp{s} .= $1;
            if (defined $2) {
                $temp{dewpoint}{temp} = _parseTemp $2;
                _setHumidity \%temp
                    if exists $temp{air} && exists $temp{air}{temp};
            } elsif (defined $3) {
                $temp{relHumid1} = $3 + 0;
            } else {
                $temp{dewpoint}{notAvailable} = undef;
            }
        }

        push @s1, { temperature => \%temp } if exists $temp{s};

=for html <!--

=over

=item B<C<3>P0P0P0P0>

=for html --><dl><dt><strong><code>3</code>P<sub>0</sub>P<sub>0</sub>P<sub>0</sub>P<sub>0</sub></strong></dt>

station level pressure

=back

=cut

        # group 3P0P0P0P0
        # don't confuse with start of section 3
        if (!/\G333/ && m@\G(3(?:(\d{4})|[\d/]///)) @gc) {
            push @s1, { stationPressure => {
                s => $1,
                defined $2
                    ? (pressure => {
                        v => sprintf('%.1f', $2 / 10 + ($2 < 5000 ? 1000 : 0)),
                        u => 'hPa'
                      })
                    : (notAvailable => undef)
            }};
        }

=over

=item B<C<4>PPPP>

sea level pressure

=back

=cut

        # group 4PPPP
        if (m@\G(4[09/]///) @gc) {
            push @s1, { SLP => { s => $1, notAvailable => undef }};
        } elsif (m@\G(4([09]\d\d)([\d/])) @gc) {
            my $hPa;

            $hPa = $2;
            $hPa += 1000 if $2 < 500;
            $hPa .= ".$3" unless $3 eq '/';
            push @s1, {
                SLP => { s => $1, pressure => { v => $hPa, u => 'hPa' }}
            };
        } elsif (m@\G(4[\d/]{4}) @gc) {
            push @s1, { SLP => { s => $1, invalidFormat => $1 }};
        }

=over

=item B<C<5>appp>

three-hourly pressure tendency (for station level pressure if provided)

=back

=cut

        # group 5appp
        if (/\G(5([0-8])(\d{3})) /gc) {
            push @s1, { pressureChange => {
                s                 => $1,
                timeBeforeObs     => { hours => 3 },
                pressureTendency  => $2,
                pressureChangeVal => {
                    v => sprintf('%.1f', $3 / ($2 >= 5 ? -10 : 10) + 0),
                    u => 'hPa'
            }}};
        } elsif (m@\G(5////) @gc) {
            push @s1, { pressureChange => {
                s             => $1,
                timeBeforeObs => { hours => 3 },
                notAvailable  => undef
            }};
        } elsif (m@\G(5[\d/]{4}) @gc) {
            push @s1, { pressureChange => {
                s             => $1,
                timeBeforeObs => { hours => 3 },
                invalidFormat => $1
            }};
        }

        $report{section1} = \@s1;
    }

########################################################################

=head3 Section 2: surface marine data (optional)

 222QdQx 0snTwTwTw 1PwaPwaHwaHwa 20PwaPwaPwa 21HwaHwaHwa

=for html <!--

=over

=item B<C<222>QdQx>

=for html --><dl><dt><strong><code>222</code>Q<sub>d</sub>Q<sub>x</sub></strong></dt>

quality control indicators for section 2

=back

=cut

    # group 222QdQx
    if (m@\G222(//|([01])9|([2-5])([1-49])|([\d/][\d/])) @gc) {
        my @s2;

        @s2  = ();

        # WMO-No. 306 Vol I.1, Part A, Section A, 18.4.3,
        # WMO-No. 306 Vol I.1, Part A, code table 3334:
        push @s2, { qualitySection => {
            s => $1,
            defined $2
                ? (qualityControlInd => $2)
                : (defined $3
                    ? (qualityControlInd => $3,
                       $4 != 9 ? (worstQualityGroup => $4) : ())
                    : (defined $5 ? (invalidFormat => $5)
                                  : (notAvailable => undef)))
        }};

=for html <!--

=over

=item B<C<0>snTwTwTw>

=for html --><dl><dt><strong><code>0</code>s<sub>n</sub>T<sub>w</sub>T<sub>w</sub>T<sub>w</sub></strong></dt>

sea-surface temperature

=back

=cut

        # group 0snTwTwTw
        if (m@\G(0(?:([01]\d{3})|[01/]///)) @gc) {
            push @s2, { seaSurfaceTemp => {
                s    => $1,
                defined $2 ? (temp => _parseTemp $2)
                           : (notAvailable => undef)
            }};
        }

=for html <!--

=over

=item B<C<1>PwaPwaHwaHwa>

=for html --><dl><dt><strong><code>1</code>P<sub>wa</sub>P<sub>wa</sub>H<sub>wa</sub>H<sub>wa</sub></strong></dt>

period and height of waves (instrumental data)

=back

=cut

        # group 1PwaPwaHwaHwa
        if (m@\G(1(?://|(\d\d))(?://|(\d\d))) @gc) {
            my $r;

            $r->{s} = $1;
            if ($1 eq '10000') {
                $r->{isCalm} = undef;
            } else {
                $r->{wavePeriod} = $2 + 0         if defined $2;
                $r->{height}     = _waveHeight $3 if defined $3;
                $r->{notAvailable} = undef
                    unless defined $2 || defined $3;
            }
            push @s2, { waveDataInstrumental => $r };
        }

=for html <!--

=over

=item B<C<20>PwaPwaPwa C<21>HwaHwaHwa>

=for html --><dl><dt><strong><code>20</code>P<sub>wa</sub>P<sub>wa</sub>P<sub>wa</sub> <code>21</code>H<sub>wa</sub>H<sub>wa</sub>H<sub>wa</sub></strong></dt>

period and height of waves (instrumental data) with tenths

=back

=cut

        # groups 20PwaPwaPwa 21HwaHwaHwa
        if (m@\G(20(?:///|(\d\d\d)) 21(?:///|(\d\d\d))) @gc) {
            my $r;

            $r->{s} = $1;
            $r->{wavePeriod} = sprintf('%.1f', $2 / 10) if defined $2;
            $r->{height} = { v => sprintf('%.1f', $3 / 10), u => 'M' }
                if defined $3;
            $r->{notAvailable} = undef unless defined $2 || defined $3;
            push @s2, { waveDataInstrumental => $r };
        }

        $report{section2} = \@s2;
    }

########################################################################

=head3 Section 3: temperatures, salinity and current at selected depths (optional)

 333Qd1Qd2 (8887k2  2z0z0z0z0 3T0T0T0T0 4S0S0S0S0
                    ...
                    2znznznzn 3TnTnTnTn 4SnSnSnSn)
           (66k69k3 2z0z0z0z0 d0d0c0c0c0
                    ...
                    2znznznzn dndncncncn)

=for html <!--

=over

=item B<C<333>Qd1Qd2>

=for html --><dl><dt><strong><code>333</code>Q<sub>d1</sub>Q<sub>d2</sub></strong></dt>

quality of the temperature and salinity profile, quality of the current speed
and direction profile

=back

=cut

    # group 333Qd1Qd2
    if (m@\G333(([0-5])|[\d/])(([0-5])|[\d/]) @gc) {
        my @s3;

        @s3  = ();

        # WMO-No. 306 Vol I.1, Part A, Section A, 18.5.3,
        # WMO-No. 306 Vol I.1, Part A, code table 3334:
        push @s3, { qualityTempSalProfile => {
            s => $1,
            defined $2
                ? (qualityControlInd => $2)
                : ($1 eq '/' ? (notAvailable => undef) : (invalidFormat => $1))
        }};
        push @s3, { qualityCurrentProfile => {
            s => $3,
            defined $4
                ? (qualityControlInd => $4)
                : ($3 eq '/' ? (notAvailable => undef) : (invalidFormat => $3))
        }};

=for html <!--

=over

=item B<C<8887>k2 C<2>z0z0z0z0 C<3>T0T0T0T0 C<4>S0S0S0S0> ...

=for html --><dl><dt><strong><code>8887</code>k<sub>2</sub> <code>2</code>z<sub>0</sub>z<sub>0</sub>z<sub>0</sub>z<sub>0</sub> <code>3</code>T<sub>0</sub>T<sub>0</sub>T<sub>0</sub>T<sub>0</sub> <code>4</code>S<sub>0</sub>S<sub>0</sub>S<sub>0</sub>S<sub>0</sub></strong> ...</dt>

method of salinity measurement, selected depth, temperature, salinity

=back

=cut

        # groups 8887k2 2z0z0z0z0 3T0T0T0T0 4S0S0S0S0 ...
        if (m@\G8887(/|([0-3])|\d) @gc) {
            push @s3, { salinityMeasurement => {
                s => "8887$1",
                defined $2
                    ? (salinityMeasurementInd => $2)
                    : ($1 eq '/' ? (notAvailable => undef)
                                 : (invalidFormat => $1))
            }};

            while (m@\G2((\d{4})(?: 3(\d\d)(\d)([\d/])| 3////)?(?: 4(\d)(\d{3})| 4////)?) @gc)
            {
                my $temp;

                if (defined $3) {
                    $temp = ($3 > 50 ? $3 : -$3 + 50) . ".$4";
                    $temp .= $5 unless $5 eq '/';
                }
                push @s3, { waterTempSalDepth => {
                    s => $1,
                    depth => { v => $2 + 0, u => 'M' },
                    defined $temp ? (temp  => { v => $temp, u => 'C' }) : (),
                    defined $6 ? (salinity => "$6.$7") : ()
                }};
            }
        }

=for html <!--

=over

=item B<C<66>k6C<9>k3 C<2>z0z0z0z0 d0d0c0c0c0> ...

=for html --><dl><dt><strong><code>66</code>k<sub>6</sub><code>9</code>k<sub>3</sub> <code>2</code>z<sub>0</sub>z<sub>0</sub>z<sub>0</sub>z<sub>0</sub> c<sub>0</sub>c<sub>0</sub>d<sub>0</sub>d<sub>0</sub>d<sub>0</sub></strong> ...</dt>

method of removing the velocity and motion of the buoy from current measurement,
duration and time of current measurement, selected depth, direction and speed of
the current

=back

=cut

        # groups 66k69k3 2z0z0z0z0 d0d0c0c0c0 ...
        # WMO-No. 306 Vol I.1, Part A, code tables:
        #   k6: 2267. k3: 2264
        if (m@\G66(/|([0-6])|\d)9(/|([1-9])|\d) @gc) {
            push @s3, { measurementCorrection => {
                s => "66$1",
                defined $2
                    ? (measurementCorrectionInd => $2)
                    : ($1 eq '/' ? (notAvailable => undef)
                                 : (invalidFormat => $1))
            }};
            push @s3, { measurementDurTime => {
                s => "9$3",
                defined $4
                    ? (measurementDurTimeInd => $4)
                    : ($3 eq '/' ? (notAvailable => undef)
                                 : (invalidFormat => $3))
            }};

            # WMO-No. 306 Vol I.1, Part A, code tables:
            #   d0d0: 0877
            while (m@\G(2(\d{4}) (?://///|($re_dd|99)(?:///|(\d\d\d)))) @gc) {
                my $r;

                if (defined $3) {
                    if ($3 eq '99') {
                        $r->{dirVarAllUnk} = undef;
                    } else {
                        $r->{dir} = { v => $3 * 10, rp => 4, rn => 5 };
                    }
                    if (defined $4) {
                        $r->{speed} = { v => $4 + 0, u => 'CMSEC' };
                    } else {
                        $r->{speedNotAvailable} = undef;
                    }
                }
                push @s3, { waterCurrent => {
                    s     => $1,
                    depth => { v => $2 + 0, u => 'M' },
                    defined $r ? (current => $r) : ()
                }};
            }
        }

        $report{section3} = \@s3;
    }

    # skip groups until next section
    push @{$report{warning}}, { warningType => 'notProcessed', s => $1 }
        if /\G(.*?) ?(?=\b444 )/gc && $1 ne '';

########################################################################

=head3 Section 4: information on engineering and technical parameters (optional)

 444 1QPQ2QTWQ4 2QNQLQAQz {QcLaLaLaLaLa LoLoLoLoLoLo|YYMMJ GGgg/} (3ZhZhZhZh 4ZcZcZcZc) 5BtBtXtXt 6AhAhAhAN 7VBVBdBdB 8ViViViVi 9/ZdZdZd

=cut

    if (/\G444 /gc) {
        my (@s4, $QL);

        @s4  = ();

=for html <!--

=over

=item B<C<1>QPQ2QTWQ4>

=for html --><dl><dt><strong><code>1</code>Q<sub>P</sub>Q<sub>2</sub>Q<sub>TW</sub>Q<sub>4</sub></strong></dt>

quality of: pressure measurement, houskeeping parameter, measurement of
water-surface temperature, measurement of air temperature

=back

=cut

        # group 1QPQ2QTWQ4
        # WMO-No. 306 Vol I.1, Part A, code tables:
        #   QP: 3315. QTW: 3319. Q2, Q4: 3363
        if (m@\G(1([01])([01])([01])([01])) @gc) {
            push @s4, { qualityGroup1 => {
                s => $1,
                "$2$3$4$5" eq '0000' ? (invalidFormat => $1)
                                     : (qualityPressure     => $2,
                                        qualityHousekeeping => $3,
                                        qualityWaterTemp    => $4,
                                        qualityAirTemp      => $5)
            }};
        }

=for html <!--

=over

=item B<C<2>QNQLQAQz>

=for html --><dl><dt><strong><code>2</code>Q<sub>N</sub>Q<sub>L</sub>Q<sub>A</sub>Q<sub>z</sub></strong></dt>

quality of buoy satellite transmission, quality of location, location quality
class, indicator of depth correction

=back

=cut

        # group 2QNQLQAQz
        # WMO-No. 306 Vol I.1, Part A, code tables:
        #   QN: 3313. QL: 3311. QA: 3302. Qz: 3318
        if (m@\G(2([01])([0-2])([0-3/])([01/])) @gc) {
            push @s4, { qualityGroup2 => {
                s                   => $1,
                qualityTransmission => $2,
                qualityLocation     => $3,
                qualityLocClass     => _codeTable3302($4),
                $5 eq '/' ? () : (depthCorrectionInd => $5)
            }};
            $QL = $3;
        }

=for html <!--

=over

=item B<QcLaLaLaLaLa LoLoLoLoLoLo>

=for html --><dl><dt><strong>Q<sub>c</sub>L<sub>a</sub>L<sub>a</sub>L<sub>a</sub>L<sub>a</sub>L<sub>a</sub> L<sub>o</sub>L<sub>o</sub>L<sub>o</sub>L<sub>o</sub>L<sub>o</sub></strong></dt>

second possible solution for the position of the buoy

=back

=cut

        if (defined $QL && $QL == 2) {
            # groups QcLaLaLaLaLa LoLoLoLoLoLo
            my $r;

            $r = _latLon1000;
            if (!defined $r) {
                $report{ERROR} = _makeErrorMsgPos 'stationPosition';
                $report{section4} = \@s4;
                return %report;
            }
            push @s4, { stationPosition => $r };
        }

=over

=item B<YYMMJ GGggC</>>

day, month, units digit of year, hour, minute of the time of the last known
position

=back

=cut

        if (defined $QL && $QL == 1) {
            # groups YYMMJ GGgg/
            if (!m@\G($re_day)(0[1-9]|1[0-2])(\d) ($re_hour)($re_min)/ @ogc) {
                $report{ERROR} = _makeErrorMsgPos 'obsTime';
                $report{section4} = \@s4;
                return %report;
            }
            push @s4, { lastKnownPosTime => {
                s      => "$1$2$3 $4$5/",
                timeAt => { day => $1, month => $2, yearUnitsDigit => $3,
                            hour => $4, minute => $5 }
            }};
        }

=for html <!--

=over

=item B<C<3>ZhZhZhZh C<4>ZcZcZcZc>

=for html --><dl><dt><strong><code>3</code>Z<sub>h</sub>Z<sub>h</sub>Z<sub>h</sub>Z<sub>h</sub> <code>4</code>Z<sub>c</sub>Z<sub>c</sub>Z<sub>c</sub>Z<sub>c</sub></strong></dt>

hydrostatic pressure of lower end of cable, length of cable in metres
(thermistor strings)

=back

=cut

        # groups 3ZhZhZhZh 4ZcZcZcZc
        if (m@\G3(\d{4}) 4(\d{4}) @gc) {
            push @s4, { pressureCableEnd => {
                s        => "3$1",
                pressure => { v => $1 + 0, u => 'kPa' }
            }};
            push @s4, { cableLengthThermistor => {
                s      => "4$2",
                length => { v => $2 + 0, u => 'M' }
            }};
        }

=for html <!--

=over

=item B<C<5>BtBtXtXt>

=for html --><dl><dt><strong><code>5</code>B<sub>t</sub>B<sub>t</sub>X<sub>t</sub>X<sub>t</sub></strong></dt>

type of buoy, type of drogue

=back

=cut

        # group 5BtBtXtXt
        # WMO-No. 306 Vol I.1, Part A, code tables:
        #   BtBt: 0370. XtXt: 4780
        if (m@\G5(//|(0[0-489]|1[0-26-9]|2[0-24-6])|[\d/]{2})(//|(0[1-5])|[\d/]{2}) @gc)
        {
            push @s4, { buoyType => {
                s => "5$1",
                defined $2 ? (buoyTypeInd => $2 + 0)
                           : ($1 eq '//' ? (notAvailable => undef)
                                         : (invalidFormat => $1))
            }};
            push @s4, { drogueType => {
                s => $3,
                defined $4 ? (drogueTypeInd => $4 + 0)
                           : ($3 eq '//' ? (notAvailable => undef)
                                         : (invalidFormat => $3))
            }};
        }

=for html <!--

=over

=item B<C<6>AhAhAhAN>

=for html --><dl><dt><strong><code>6</code>A<sub>h</sub>A<sub>h</sub>A<sub>h</sub>A<sub>N</sub></strong></dt>

anemometer height, type of anemometer

=back

=cut

        # group 6AhAhAhAN
        # WMO-No. 306 Vol I.1, Part A, code tables 0114
        if (m@\G(6(\d{3})(/|([0-2])|\d)) @gc) {
            push @s4, { anemometer => {
                s => $1,
                height => { v => $2 + 0, u => 'DM' },
                anemometerType => {
                    defined $4 ? (anemometerTypeInd => $4)
                               : ($3 eq '/' ? (notAvailable => undef)
                                            : (invalidFormat => $3))
                }
            }};
        }

=for html <!--

=over

=item B<C<7>VBVBdBdB>

=for html --><dl><dt><strong><code>7</code>V<sub>B</sub>V<sub>B</sub>d<sub>B</sub>d<sub>B</sub></strong></dt>

drifting speed and drift direction of the buoy at the last known position

=back

=cut

        if (defined $QL && $QL == 1) {
            # group 7VBVBdBdB
            if (m@\G(7(\d\d)($re_dd|99)) @gc) {
                my $r;

                if ($3 eq '99') {
                    $r->{dirVarAllUnk} = undef;
                } else {
                    $r->{dir} = { v => $3 * 10, rp => 4, rn => 5 };
                }
                $r->{speed} = { v => $2 + 0, u => 'CMSEC' };
                push @s4, { buoyDrift => {
                    s     => $1,
                    drift => $r
                }};
            }
        }

=for html <!--

=over

=item B<C<8>ViViViVi> ...

=for html --><dl><dt><strong><code>8</code>V<sub>i</sub>V<sub>i</sub>V<sub>i</sub>V<sub>i</sub></strong></dt>

engineering status of the buoy

=back

=cut

        # groups 8ViViViVi ...
        if (m@\G(8(?:////|\d{4})(?: 8(?:////|\d{4}))*) @gc) {
            push @s4, { engineeringStatus => { s => $1 } };
        }

=for html <!--

=over

=item B<C<9/>ZdZdZd> ...

=for html --><dl><dt><strong><code>9/</code>Z<sub>d</sub>Z<sub>d</sub>Z<sub>d</sub></strong></dt>

length of the cable at which the drogue is attached

=back

=cut

        # group 9/ZdZdZd
        if (m@\G9/(///|\d{3}) @gc) {
            push @s4, { cableLengthDrogue => {
                s      => "9/$1",
                $1 eq '///' ? (notAvailable => undef)
                            : (length => { v => $1 + 0, u => 'M' })
            }};
        }

        $report{section4} = \@s4;
    }

    push @{$report{warning}}, { warningType => 'notProcessed', s => $1 }
        if /\G(.+) $/;

    return %report;
}

########################################################################
# _parseSynop
########################################################################
sub _parseSynop {
    my (%report, $period, $windUnit, $winds_est, $region, $country,
        $is_auto, $obs_hour, $have_precip333, $matched);

    my $re_D____D = '[A-Z\d]{3,}';
    my $re_MMM    = '(?:\d{3})'; # 001..623, 901..936
    my $re_ULaULo = '(?:\d\d)';
    my $re_IIiii  = '(?:\d{5})';

    $report{msg} = $_;
    $report{isSynop} = undef;
    $report{version} = VERSION();

    if (/^ERROR -/) {
        pos $_ = 0;
        $report{ERROR} = _makeErrorMsgPos 'other';
        return %report;
    }

=head2 Parsing of SYNOP messages

=cut

    $_ .= ' '; # this makes parsing much easier

    pos $_ = 0;

    # warn about modification
    push @{$report{warning}}, { warningType => 'msgModified',
                                s           => substr $_, 0, -1 }
        if $report{msg} . ' ' ne $_;

########################################################################

=head3 Section 0: information about the observation and the observing station

 MiMiMjMj
 FM12 (fixed land):  AAXX                     YYGGiw IIiii
 FM13 (sea):         BBXX {D....D|A1bwnbnbnb} YYGGiw 99LaLaLa QcLoLoLoLo
 FM14 (mobile land): OOXX D....D              YYGGiw 99LaLaLa QcLoLoLoLo MMMULaULo h0h0h0h0im

=for html <!--

=over

=item B<MiMiMjMj>

=for html --><dl><dt><strong>M<sub>i</sub>M<sub>i</sub>M<sub>j</sub>M<sub>j</sub></strong></dt>

station type

=back

=cut

    # group MiMiMjMj
    if (!/\G((?:AA|BB|OO)XX) /gc) {
        $report{ERROR} = _makeErrorMsgPos 'obsStationType';
        return %report;
    }
    $report{obsStationType} = { s => $1, stationType => $1 };

    $region = '';
    $country = '';

=for html <!--

=over

=item BBXX: B<D....D> | B<A1bwnbnbnb>

=for html --><dl><dt>BBXX: <strong>D....D</strong> | <strong>A<sub>1</sub>b<sub>w</sub>n<sub>b</sub>n<sub>b</sub>n<sub>b</sub></strong></dt>

call sign or station id

=back

=cut

    # BBXX: group (D....D|A1bwnbnbnb)
    #   D....D: ship's call sign, A1bwnbnbnb: call sign of stations at sea
    if ($report{obsStationType}{stationType} eq 'BBXX') {
        if (m@\G(${re_A1bw}\d{3}) @ogc) {
            $country = _A1bw2country $1;
            $region  = _A1bw2region $1;
            $report{callSign} = { s => $1, id => $1, region => $region };
        } elsif (m@\G($re_D____D) @ogc) {
            $region  = 'SHIP';
            $report{callSign} = { s => $1, id => $1 };
        } else {
            $report{ERROR} = _makeErrorMsgPos 'stationId';
            return %report;
        }
    }

=over

=item OOXX: B<D....D>

call sign

=back

=cut

    # OOXX: group D....D
    if ($report{obsStationType}{stationType} eq 'OOXX') {
        if (!m@\G($re_D____D) @ogc) {
            $report{ERROR} = _makeErrorMsgPos 'callSign';
            return %report;
        }
        $report{callSign} = { s => $1, id => $1 };
        $country = _A1A22country $1;
    }

=for html <!--

=over

=item B<YYGGiw>

=for html --><dl><dt><strong>YYGGi<sub>w</sub></strong></dt>

day and hour of observation, indicator for wind speed (unit)

=back

=cut

    # group YYGGiw
    if (!m@\G($re_day)($re_hour)([0134/]) @ogc) {
        $report{ERROR} = _makeErrorMsgPos 'obsTimeWindInd';
        return %report;
    }
    $report{obsTime} = {
        s      => "$1$2",
        timeAt => { day => $1, hour => $2 }
    };
    $obs_hour = $2;

    # WMO-No. 306 Vol I.1, Part A, code table 1855:
    $report{windIndicator}{s} = $3;
    if ($3 ne '/') {
        $windUnit = $3 < 2 ? 'MPS' : 'KT';
        $winds_est = $3 == 0 || $3 == 3;
        $report{windIndicator}{windUnit} = $windUnit;
        $report{windIndicator}{isEstimated} = undef if $winds_est;
    } else {
        $report{windIndicator}{notAvailable} = undef;
    }

    if ($obs_hour =~ /00|06|12|18/) {
        $period = 6;
    } elsif ($obs_hour =~ /03|09|15|21/) {
        $period = 3;
    } else {
        $period = 1;
    }

    if ($report{obsStationType}{stationType} eq 'AAXX') {

=over

=item AAXX: B<IIiii>

station identification

=back

=cut

        # AAXX: group IIiii
        $matched = m@\G($re_IIiii) @ogc;
        if (!$matched || !($region = _IIiii2region $1)) {
            pos $_ -= $matched ? 6 : 0;
            $report{ERROR} = _makeErrorMsgPos 'stationId';
            return %report;
        }
        $report{obsStationId} = { s => $1, id => $1, region => $region };
        $country = _IIiii2country $1;
    } else {

=for html <!--

=over

=item BBXX, OOXX: B<C<99>LaLaLa QcLoLoLoLo>

=for html --><dl><dt>BBXX, OOXX: <strong><code>99</code>L<sub>a</sub>L<sub>a</sub>L<sub>a</sub> Q<sub>c</sub>L<sub>o</sub>L<sub>o</sub>L<sub>o</sub>L<sub>o</sub></strong></dt>

position of the station

=back

=cut

        my $lat_lon_unit_digits;

        # BBXX, OOXX: group 99LaLaLa QcLoLoLoLo
        if (m@\G(99/// /////) @gc) {
            $report{stationPosition}{s} = $1;
            $report{stationPosition}{notAvailable} = undef;
            $lat_lon_unit_digits = '';
        } else {
            $matched = m@\G(99(\d(\d)\d) ([1357])(\d\d(\d)\d)) @gc;
            if ($matched && $2 <= 900 && $5 <= 1800) {
                $report{stationPosition}{s} = $1;
                $report{stationPosition}{lat} =
                       sprintf '%.1f', $2 / ($4 == 3 || $4 == 5 ? -10 : 10) + 0;
                $report{stationPosition}{lon} =
                       sprintf '%.1f', $5 / ($4 == 5 || $4 == 7 ? -10 : 10) + 0;
                $lat_lon_unit_digits = "$3$6";
            } else {
                pos $_ -= $matched ? 12 : 0;
                $report{ERROR} = _makeErrorMsgPos 'stationPosition';
                return %report;
            }
        }

=for html <!--

=over

=item OOXX: B<MMMULaULo h0h0h0h0im>

=for html --><dl><dt>OOXX: <strong>MMMU<sub>La</sub>U<sub>Lo</sub> h<sub>0</sub>h<sub>0</sub>h<sub>0</sub>h<sub>0</sub>i<sub>m</sub></strong></dt>

position of the station (Marsden square, height)

=back

=cut

        if ($report{obsStationType}{stationType} eq 'OOXX') {
            # OOXX: group MMMULaULo h0h0h0h0im
            $matched = m@\G((?:///|($re_MMM))(?://|($re_ULaULo)) (?:////[/1-8]|(\d{4})([1-8]))) @ogc;
            if (   !$matched
                || (   defined $2
                    && !(($2 >= 1 && $2 <= 623) || ($2 >= 901 && $2 <= 936)))
                || (defined $3 && $3 ne $lat_lon_unit_digits))
            {
                pos $_ -= $matched ? 12 : 0;
                $report{ERROR} = _makeErrorMsgPos 'stationPosition';
                return %report;
            }
            $report{stationPosition}{s} .= " $1";
            $report{stationPosition}{marsdenSquare} = $2 + 0 if defined $2;
            if (defined $4) {
                $report{stationPosition}{elevation} = {
                    v => $4 + 0,
                    # WMO-No. 306 Vol I.1, Part A, code table 1845:
                    u => ($5 <= 4 ? 'M' : 'FT'),
                    q => 'confidenceIs' .
                         { 1 => 'Excellent', 2 => 'Good',
                           3 => 'Fair',      0 => 'Poor' }->{$5 % 4}
                };
            }
        }
    }

=over

=item optional: B<C<NIL>>

message contains no observation data, end of message

=back

=cut

    if (/\GNIL $/) {
        $report{reportModifier}{s} =
            $report{reportModifier}{modifierType} = 'NIL';
        return %report;
    }

########################################################################

=head3 Section 1: land observations (data for global exchange common for all code forms)

 iRixhVV Nddff (00fff) 1snTTT {2snTdTdTd|29UUU} 3P0P0P0P0 {4PPPP|4a3hhh} 5appp 6RRRtR {7wwW1W2|7wawaWa1Wa2} 8NhCLCMCH 9GGgg

=for html <!--

=over

=item B<iRixhVV>

=for html --><dl><dt><strong>i<sub>R</sub>i<sub>x</sub>hVV</strong></dt>

precipitation indicator, weather indicator, base of lowest cloud

=back

=cut

    # group iRixhVV
    # EXTENSION: iR can be '/': notAvailable
    # EXTENSION: ix can be '/': notAvailable
    $matched = m@\G(([0-46-8/])([1-7/])([\d/])(\d\d|//)) @gc;
    if (   !$matched
        || (($2 eq '6' || $2 eq '7' || $2 eq '8') && $country ne 'RU'))
    {
        pos $_ -= 6 if $matched;
        $report{ERROR} = _makeErrorMsgPos 'indicatorCloudVis';
        return %report;
    }

    # WMO-No. 306 Vol I.1, Part A, code table 1819:
    $report{precipInd}{s} = $2;
    if ($2 eq '/') {
        $report{precipInd}{notAvailable} = undef;
    } elsif ($2 <= 4) {
        # ( 1 + 3, 1, 3, omitted (amount=0), omitted (NA) )[$2];
        $report{precipInd}{precipIndVal} = $2;
    } else {
        # RU: 6 (=1), 7 (=2), 8 (=4) for stations with autom. precip. sensors
        $report{precipInd}{precipIndVal} = (1, 2, 4)[$2 - 6];
    }

    # WMO-No. 306 Vol I.1, Part A, code table 1860:
    # 1 Manned Included
    # 2 Manned Omitted (no significant phenomenon to report)
    # 3 Manned Omitted (no observation, data not available)
    # 4 Automatic Included using Code tables 4677 and 4561 (US: FMH-2 4-12/4-14)
    # 5 Automatic Omitted (no significant phenomenon to report)
    # 6 Automatic Omitted (no observation, data not available)
    # 7 Automatic Included using Code tables 4680 and 4531 (US: FMH-2 4-13/4-15)
    $report{wxInd}{s} = $3;
    if ($3 eq '/') {
        $report{wxInd}{notAvailable} = undef;
    } else {
        $report{wxInd}{wxIndVal} = $3;
        if ($report{wxInd}{wxIndVal} >= 4) {
            $report{reportModifier}{s} =
                                 $report{reportModifier}{modifierType} = 'AUTO';
            $is_auto = 1;
        }
    }

    if ($country eq 'US') {
        $report{baseLowestCloud} = _codeTable1600US $4;
    } else {
        $report{baseLowestCloud} = _codeTable1600 $4;
    }
    $report{baseLowestCloud}{s} = $4;

    if ($country eq 'US') {
        _codeTable4377US \%report, $5, $report{obsStationType}{stationType},
                         $is_auto;
    } elsif ($country eq 'CA') {
        _codeTable4377CA \%report, $5;
    } else {
        _codeTable4377 \%report, $5, $report{obsStationType}{stationType};
    }

=over

=item B<Nddff> (B<C<00>fff>)

total cloud cover, wind direction and speed

=back

=cut

    # group Nddff (00fff)
    if (!m@\G([\d/])($re_dd|00|99|//)(\d\d|//) @ogc) {
        $report{ERROR} = _makeErrorMsgPos 'cloudWind';
        return %report;
    }
    if ($1 eq '/') {
        $report{totalCloudCover}{notAvailable} = undef;
    } else {
        $report{totalCloudCover} = _codeTable2700 $1;
    }
    $report{totalCloudCover}{s} = $1;
    $report{sfcWind}{s} = "$2$3";
    if ("$2$3" eq '////') {
        $report{sfcWind}{wind}{notAvailable} = undef;
    # WMO-No. 306 Vol I.1, Part A, code table 0877:
    } elsif ($2 eq '00') {
        $report{sfcWind}{wind}{isCalm} = undef;
        $report{sfcWind}{wind}{isEstimated} = undef if $winds_est;
    } else {
        if ($2 eq '//') {
            $report{sfcWind}{wind}{dirNotAvailable} = undef;
        } elsif ($2 eq '99') {
            $report{sfcWind}{wind}{dirVarAllUnk} = undef;
        } else {
            if ($winds_est) {
                $report{sfcWind}{wind}{isEstimated} = undef;
            } else {
                $report{sfcWind}{wind}{dir} = { rp => 4, rn => 5 };
            }
            $report{sfcWind}{wind}{dir}{v} = $2 * 10;
        }
        if ($3 eq '//' || !$windUnit) {
            $report{sfcWind}{wind}{speedNotAvailable} = undef;
        } else {
            $report{sfcWind}{wind}{speed} = { v => $3 + 0, u => $windUnit };
            $report{sfcWind}{wind}{isEstimated} = undef if $winds_est;
            # US: FMH-2 4.2.2.2, CA: MANOBS 12.3.2.3
            # default: WMO-No. 306 Vol I.1, Part A, Section A, 12.2.2.3.1
            $report{sfcWind}{measurePeriod} = { v => 10, u => 'MIN' };
        }
    }

    if ($3 eq '99') {
        if (!m@\G(00([1-9]\d\d)) @gc) {
            $report{ERROR} = _makeErrorMsgPos 'wind';
            return %report;
        }
        $report{sfcWind}{s} .= " $1";
        $report{sfcWind}{wind}{speed}{v} = $2 + 0 if $windUnit;
    }

    # EXTENSION: allow 00///
    if (m@\G(00///) @gc) {
        $report{sfcWind}{s} .= " $1";
    }

=for html <!--

=over

=item B<C<1>snTTT>

=for html --><dl><dt><strong><code>1</code>s<sub>n</sub>TTT</strong></dt>

temperature

=back

=cut

    # group 1snTTT
    if (m@\G(1(?:[01/]///|([01]\d\d[\d/]))) @gc) {
        $report{temperature}{s} = $1;
        if (defined $2) {
            $report{temperature}{air}{temp} = _parseTemp $2;
        } else {
            $report{temperature}{air}{notAvailable} = undef;
        }
    }

=for html <!--

=over

=item B<C<2>snTdTdTd> | B<C<29>UUU>

=for html --><dl><dt><strong><code>2</code>s<sub>n</sub>T<sub>d</sub>T<sub>d</sub>T<sub>d</sub></strong> | <strong><code>29</code>UUU</strong></dt>

dewpoint or relative humidity

=back

=cut

    # group 2snTdTdTd|29UUU
    if (m@\G(2(?:[109/]///|([01]\d\d[\d/])|9(100|0\d\d))) @gc) {
        $report{temperature}{s} .= ' ' if exists $report{temperature};
        $report{temperature}{s} .= $1;
        if (defined $2) {
            $report{temperature}{dewpoint}{temp} = _parseTemp $2;
            _setHumidity $report{temperature}
                if    exists $report{temperature}{air}
                   && exists $report{temperature}{air}{temp};
        } elsif (defined $3) {
            $report{temperature}{relHumid1} = $3 + 0;
        } else {
            $report{temperature}{dewpoint}{notAvailable} = undef;
        }
    }

    # EXTENSION: 29UUU after 2snTdTdTd
    push @{$report{warning}}, { warningType => 'notProcessed', s => $1 }
        if m@\G(29[\d/]{3}) @gc;

=for html <!--

=over

=item B<C<3>P0P0P0P0>

=for html --><dl><dt><strong><code>3</code>P<sub>0</sub>P<sub>0</sub>P<sub>0</sub>P<sub>0</sub></strong></dt>

station level pressure

=back

=cut

    # group 3P0P0P0P0
    if (m@\G(3(?:(\d{3})([\d/])|[\d/]///)) @gc) {
        $report{stationPressure} = {
            s => $1,
            defined $2
                ? (pressure => {
                   v => ($2 + ($2 < 500 ? 1000 : 0)) . ($3 eq '/' ? '' : ".$3"),
                   u => 'hPa'
                  })
                : (notAvailable => undef)
        };
    }
    if (   !exists $report{stationPressure}
        && $report{obsStationType}{stationType} eq 'AAXX')
    {
        push @{$report{warning}}, { warningType => 'pressureMissing' };
    }

=for html <!--

=over

=item B<C<4>PPPP> | B<C<4>a3hhh>

=for html --><dl><dt><strong><code>4</code>PPPP</strong> | <strong><code>4</code>a<sub>3</sub>hhh</strong></dt>

sea level pressure or geopotential height of an agreed standard isobaric surface

=back

=cut

    # group 4PPPP|4a3hhh
    if (m@\G(4[09/]///) @gc) {
        $report{SLP}{s} = $1;
        $report{SLP}{notAvailable} = undef;
    } elsif (m@\G(4([09]\d\d)([\d/])) @gc) {
        $report{SLP}{s} = $1;
        $report{SLP}{pressure}{v} = $2;
        $report{SLP}{pressure}{v} += 1000 if $2 < 500;
        $report{SLP}{pressure}{v} .= ".$3" unless $3 eq '/';
        $report{SLP}{pressure}{u} = 'hPa';
    } elsif (m@\G(4([1-8])(\d{3}|///)) @gc) {
        my ($surface, $height) = ($2, $3);

        $report{gpSurface}{s} = $1;
        if ($3 eq '///') {
            $report{gpSurface}{notAvailable} = undef;
        } elsif ($surface =~ /[1278]/) {
            $report{gpSurface}{surface} = _codeTable0264 $surface;
            # hhh geopotential of an agreed standard isobaric surface given by a3, in standard geopotential metres, omitting the thousands digit.
            #    1 (1000):           100 gpm ->    0 ...  999
            #    2  (925):           800 gpm ->  300 ... 1299
            #    5  (500): 5000 ... 5500 gpm -> 4500 ... 5999 !
            #    7  (700):          3000 gpm -> 2500 ... 3499
            #    8  (850):          1500 gpm -> 1000 ... 1999
            if ($surface == 2) {
                $height += 1000 if $height < 300;
            } elsif ($surface == 7) {
                $height += ($height < 500 ? 3000 : 2000);
            } elsif ($surface == 8) {
                $height += 1000;
            }
            $report{gpSurface}{geopotential} = $height;
#       } elsif (   $surface == 6
#           && exists $report{obsStationId}
#           && $report{obsStationId}{id} == 84735)
#       {
#           $height += ($height < 500 ? 4000 : 3000);
#           $report{gpSurface}{geopotential} = $height;
        } else {
            $report{gpSurface}{invalidFormat} = $surface;
        }
    }

=over

=item B<C<5>appp>

three-hourly pressure tendency (for station level pressure if provided)

=back

=cut

    # group 5appp
    if (/\G(5([0-8])(\d{3})) /gc) {
        $report{pressureChange} = {
            s                 => $1,
            timeBeforeObs     => { hours => 3 },
            pressureTendency  => $2,
            pressureChangeVal => {
                v => sprintf('%.1f', $3 / ($2 >= 5 ? -10 : 10) + 0),
                u => 'hPa'
        }};
    } elsif (m@\G(5////) @gc) {
        $report{pressureChange} = {
            s             => $1,
            timeBeforeObs => { hours => 3 },
            notAvailable  => undef
        };
    } elsif (m@\G(5[\d/]{4}) @gc) {
        $report{pressureChange} = {
            s             => $1,
            timeBeforeObs => { hours => 3 },
            invalidFormat => $1
        };
    }

=for html <!--

=over

=item B<C<6>RRRtR>

=for html --><dl><dt><strong><code>6</code>RRRt<sub>R</sub></strong></dt>

amount of precipitation for given period

=back

=cut

    # group 6RRRtR
    if (m@\G(6(\d{3}|///)([\d/])) @gc) {
        if (   exists $report{precipInd}{precipIndVal}
            && $report{precipInd}{precipIndVal} != 0
            && $report{precipInd}{precipIndVal} != 1)
        {
            push @{$report{warning}}, { warningType => 'precipNotOmitted1' };
        }

        $report{precipitation} = _codeTable3590 $2;
        $report{precipitation}{s} = $1;
        if (!exists $report{precipitation}{notAvailable}) {
            if ($3 eq '/') {
                if ($country eq 'SA') {
                    $report{precipitation}{timeBeforeObs} = { hours => 12 };
                } else {
                    $report{precipitation}{timeBeforeObs} =
                                                       { notAvailable => undef};
                }
            } else {
                if ($country eq 'KZ' && $3 eq '0' && $period > 1) {
                    $report{precipitation}{timeBeforeObs} = { hours => $period};
                } else {
                    $report{precipitation}{timeBeforeObs} = _codeTable4019 $3;
                }
            }
        }
    } elsif (   exists $report{precipInd}{precipIndVal}
             && (   $report{precipInd}{precipIndVal} == 0
                 || $report{precipInd}{precipIndVal} == 1))
    {
        push @{$report{warning}}, { warningType => 'precipOmitted1' };
    }

=for html <!--

=over

=item B<C<7>wwW1W2> | B<C<7>wawaWa1Wa2>

=for html --><dl><dt><strong><code>7</code>wwW<sub>1</sub>W<sub>2</sub></strong> | <strong><code>7</code>w<sub>a</sub>w<sub>a</sub>W<sub>a1</sub>W<sub>a2</sub></strong></dt>

present and past weather

=back

=cut

    # group (7wwW1W2|7wawaWa1Wa2)
    if (m@\G(7(\d\d|//)([\d/])([\d/])) @gc) {
        my $simple;

        if (   exists $report{wxInd}{wxIndVal}
            && $report{wxInd}{wxIndVal} != 1
            && $report{wxInd}{wxIndVal} != 4
            && $report{wxInd}{wxIndVal} != 7)
        {
            push @{$report{warning}}, { warningType => 'weatherNotOmitted' };
        }

        $simple =      exists $report{wxInd}{wxIndVal}
                    && $report{wxInd}{wxIndVal} == 7
                  ? "Simple" : "";
        $report{weatherSynop}{s} = $1;
        if ($2 eq '//') {
            $report{weatherSynop}{weatherPresentNotAvailable} = undef;
        } else {
            $report{weatherSynop}{"weatherPresent$simple"} = $2;
        }
        # http://www.wmo.int/pages/prog/www/WMOCodes/Updates_Sweden.pdf
        # TODO: effective from?
        if ($country eq 'SE') {
            my $period_SE;

            $period_SE = $obs_hour % 6;
            $period_SE = 6 if $period_SE == 0;
            $report{weatherSynop}{timeBeforeObs} = { hours => $period_SE };
        } else {
            $report{weatherSynop}{timeBeforeObs} = { hours => $period };
        }
        if ($3 eq '/') {
            $report{weatherSynop}{weatherPast1NotAvailable} = undef;
        } else {
            $report{weatherSynop}{"weatherPast1$simple"} = $3;
        }
        if ($4 eq '/') {
            $report{weatherSynop}{weatherPast2NotAvailable} = undef;
        } else {
            $report{weatherSynop}{"weatherPast2$simple"} = $4;
        }
    } elsif (   exists $report{wxInd}{wxIndVal}
             && (   $report{wxInd}{wxIndVal} == 1
                 || $report{wxInd}{wxIndVal} == 4
                 || $report{wxInd}{wxIndVal} == 7))
    {
        push @{$report{warning}}, { warningType => 'weatherOmitted' };
    }

=for html <!--

=over

=item B<C<8>NhCLCMCH>

=for html --><dl><dt><strong><code>8</code>N<sub>h</sub>C<sub>L</sub>C<sub>M</sub>C<sub>H</sub></strong></dt>

cloud type for each level and cloud cover of lowest reported cloud type

=back

=cut

    # group 8NhCLCMCH
    # WMO-No. 306 Vol I.1, Part A, Section A, 12.2.7
    # "This group shall be omitted ... [for] N=0 ... N=9 ... N=/."
    # but: "All cloud observations at sea ... shall be reported ..."
    # EXTENSION: allow 8000[1-8], 8/[\d/]{3}
    if (m@\G(8([\d/])([\d/])([\d/])([\d/])) @gc) {
        if (   $report{obsStationType}{stationType} ne 'BBXX'
            && (   $1 eq '8////'
                || ($2 eq '0' && ("$3$4" ne '00' || $5 eq '/' || $5 eq '0'))
                || $2 eq '9'))
        {
            $report{cloudTypes}{invalidFormat} = $1;
        } elsif (($2 eq '/' || $2 == 9) && "$3$4$5" eq '///') {
            $report{cloudTypes}{ $2 eq '/' ? 'notAvailable' : 'skyObscured' }
                                                                        = undef;
        } elsif ($2 ne '9') {
            $report{cloudTypes} = {
               $3 eq '/' ? (cloudTypeLowNA    => undef):(cloudTypeLow    => $3),
               $4 eq '/' ? (cloudTypeMiddleNA => undef):(cloudTypeMiddle => $4),
               $5 eq '/' ? (cloudTypeHighNA   => undef):(cloudTypeHigh   => $5),
            };
            if ($2 ne '/') {
                if ($3 ne '/' && $3 != 0) {
                    # low has clouds (1..9)
                    $report{cloudTypes}{oktasLow} = $2;
                } elsif ($3 ne '/' && $4 ne '/' && $4 != 0) {
                    # low has no clouds (0) and middle has clouds (1..9)
                    $report{cloudTypes}{oktasMiddle} = $2;
                } else {
                    # low and middle are N/A or have no clouds
                    # if low and middle have no clouds: oktas should be 0
                    # EXTENSION: tolerate and store oktas,
                    #            but for which layer is it?
                    $report{cloudTypes}{oktas} = $2;
                }
            }
        } else {
            $report{cloudTypes}{invalidFormat} = $1;
        }
        $report{cloudTypes}{s} = $1;
    }

    # EXTENSION: tolerate multiple 8NhCLCMCH groups
    while (m@\G(8[\d/]{4}) @gc) {
        push @{$report{warning}}, { warningType => 'multCloudTypes', s => $1 };
    }

=over

=item B<C<9>GGgg>

exact observation time

=back

=cut

    # group 9GGgg
    if (/\G(9($re_hour)($re_min)) /ogc) {
        $report{exactObsTime} = {
            s      => $1,
            timeAt => { hour => $2, minute => $3 }
        };
    }

########################################################################

=head3 Section 2: sea surface observations (maritime data for global exchange, optional)

 222Dsvs 0ssTwTwTw 1PwaPwaHwaHwa 2PwPwHwHw 3dw1dw1dw2dw2 4Pw1Pw1Hw1Hw1 5Pw2Pw2Hw2Hw2 {6IsEsEsRs|ICING plain language} 70HwaHwaHwa 8swTbTbTb ICE {ciSibiDizi|plain language}

=for html <!--

=over

=item B<C<222>Dsvs>

=for html --><dl><dt><strong><code>222</code>D<sub>s</sub>v<sub>s</sub></strong></dt>

direction and speed of displacement of the ship since 3 hours

=back

=cut

    # group 222Dsvs
    if (m@\G222(?://|00|([\d/])([\d/])) @gc) {
        my @s2;

        @s2  = ();

        if (defined $1) {
            my $r;

            $r->{s} = "$1$2";
            $r->{timeBeforeObs} = { hours => 3 };
            if ($1 eq '/' || $1 == 9) {
            } elsif ($1 == 0) {
                $r->{isStationary} = undef;
            } else {
                _codeTable0700 $r, 'compass', $1;
            }

            # WMO-No. 306 Vol I.1, Part A, code table 4451:
            if ($2 eq '/') {
                $r->{speedNotAvailable} = undef;
            } elsif ($2 == 0) {
                $r->{speed} = [ { v => 0, u => 'KT' }, { v => 0, u => 'KMH' }];
            } elsif ($2 == 9) {
                $r->{speed} = [ { v => 40, u => 'KT',  q => 'isGreater' },
                                { v => 75, u => 'KMH', q => 'isGreater' }];
            } else {
                my @speed_KMH = (1,11,20,29,38,48,57,66,76);
                $r->{speed} = [ { v => $2 * 5 - 4, u => 'KT', rp => 5 },
                                { v => $speed_KMH[$2 - 1],
                                  u => 'KMH',
                                  rp => $speed_KMH[$2] - $speed_KMH[$2 - 1]}
                              ];
            }

            push @s2, { displacement => $r };
        }

=for html <!--

=over

=item B<C<0>ssTwTwTw>

=for html --><dl><dt><strong><code>0</code>s<sub>s</sub>T<sub>w</sub>T<sub>w</sub>T<sub>w</sub></strong></dt>

sea-surface temperature and its type of measurement

=back

=cut

        # group 0ssTwTwTw
        # ss: WMO-No. 306 Vol I.1, Part A, code table 3850
        if (m@\G(0([0-7])(\d\d[\d/])) @gc) {
            push @s2, { seaSurfaceTemp => {
                s                    => $1,
                waterTempMeasurement =>
                             qw(intake bucket hullContactSensor other)[$2 >> 1],
                temp                 => _parseTemp(($2 % 2) . $3)
            }};
        } elsif (m@\G(0[0-7/]///) @gc) {
            push @s2, { seaSurfaceTemp => {
                s            => $1,
                notAvailable => undef
            }};
        }

=for html <!--

=over

=item B<C<1>PwaPwaHwaHwa>

=for html --><dl><dt><strong><code>1</code>P<sub>wa</sub>P<sub>wa</sub>H<sub>wa</sub>H<sub>wa</sub></strong></dt>

period and height of waves (instrumental data)

=back

=cut

        # group 1PwaPwaHwaHwa
        if (m@\G(1(?://|(\d\d))(?://|(\d\d))) @gc) {
            my $r;

            $r->{s} = $1;
            if ($1 eq '10000') {
                $r->{isCalm} = undef;
            } else {
                $r->{wavePeriod} = $2 + 0         if defined $2;
                $r->{height}     = _waveHeight $3 if defined $3;
                $r->{notAvailable} = undef
                    unless defined $2 || defined $3;
            }
            push @s2, { waveDataInstrumental => $r };
        }

=for html <!--

=over

=item B<C<2>PwPwHwHw>

=for html --><dl><dt><strong><code>2</code>P<sub>w</sub>P<sub>w</sub>H<sub>w</sub>H<sub>w</sub></strong></dt>

period and height of wind waves

=back

=cut

        # group 2PwPwHwHw
        if (m@\G(2(?://|(\d\d))(?://|(\d\d))) @gc) {
            my $r;

            $r->{s} = $1;
            if ($1 eq '20000') {
                $r->{isCalm} = undef;
            } else {
                if (defined $2) {
                    if ($2 == 99) {
                        $r->{seaConfused} = undef;
                    } else {
                        $r->{wavePeriod} = $2 + 0;
                    }
                }
                $r->{height} = _waveHeight $3 if defined $3;
                $r->{notAvailable} = undef
                    unless defined $2 || defined $3;
            }
            push @s2, { waveData => $r };
        }

=for html <!--

=over

=item B<C<3>dw1dw1dw2dw2 C<4>Pw1Pw1Hw1Hw1 C<5>Pw2Pw2Hw2Hw2>

=for html --><dl><dt><strong><code>3</code>d<sub>w1</sub>d<sub>w1</sub>d<sub>w2</sub>d<sub>w2</sub> <code>4</code>P<sub>w1</sub>P<sub>w1</sub>H<sub>w1</sub>H<sub>w1</sub> <code>5</code>P<sub>w2</sub>P<sub>w2</sub>H<sub>w2</sub>H<sub>w2</sub></strong></dt>

swell data

=back

=cut

        # groups 3dw1dw1dw2dw2 4Pw1Pw1Hw1Hw1 5Pw2Pw2Hw2Hw2
        # EXTENSION: missing 4Pw1Pw1Hw1Hw1
        # EXTENSION: allow 99 for dw1dw1/dw2dw2. Pw1Pw1/Pw2Pw2=99: seaConfused
        if (m@\G(3($re_dd|00|99|//)($re_dd|00|99|//)(?: 4(\d\d|//)(\d\d|//))?(?: 5(\d\d|//)(\d\d|//))?) @ogc)
        {
            my ($r, $s1, $s2);

            $r->{s} = $1;
            $s1->{dir} = { v => $2 * 10, rp => 4, rn => 5 }
                if $2 ne '00' && $2 ne '99' && $2 ne '//';
            if (defined $4 && $4 ne '//') {
                if ($4 eq '99') {
                    $s1->{seaConfused} = undef;
                } else {
                    $s1->{wavePeriod} = $4 + 0;
                }
            }
            $s1->{height} = _waveHeight $5
                if defined $5 && $5 ne '//';
            $s1->{notAvailable} = undef
                unless $s1;
            push @{$r->{swellData}}, $s1;

            if (defined $6 && ($3 ne '//' || $6 ne '//' || $7 ne '//')) {
                $s2->{dir} = { v => $3 * 10, rp => 4, rn => 5 }
                    if $3 ne '00' && $3 ne '99' && $3 ne '//';
                if ($6 ne '//') {
                    if ($6 eq '99') {
                        $s2->{seaConfused} = undef;
                    } else {
                        $s2->{wavePeriod} = $6 + 0;
                    }
                }
                $s2->{height} = _waveHeight $7
                    if $7 ne '//';
                $s2->{notAvailable} = undef
                    unless $s2;
                push @{$r->{swellData}}, $s2;
            }
            push @s2, { swell => $r };
        }

=for html <!--

=over

=item B<C<6>IsEsEsRs> | B<C<ICING>> I<plain language>

=for html --><dl><dt><strong><code>6</code>I<sub>s</sub>E<sub>s</sub>E<sub>s</sub>R<sub>s</sub></strong> | <strong><code>ICING</code></strong> <em>plain language</em></dt>

ice accretion on ships

=back

=cut

        # group 6IsEsEsRs or ICING plain language
        if (m@\G(6(?:////|([1-5])(\d\d)([0-4]))) @gc) {
            push @s2, { iceAccretion => {
                s => $1,
                defined $2
                    ? ( iceAccretionSource => $2,
                        thickness          => { v => $3 + 0, u => 'CM' },
                        iceAccretionRate   => $4
                      )
                    : ( notAvailable => undef )
            }};
        } elsif (   m@\GICING (.*?) ?(?=\b(?:([3-9])\2\2|[\d/]{5}|ICE) )@gc
                 || /\GICING (.*?) ?$/gc)
        {
            push @s2, { iceAccretion => {
                s => "ICING" . ($1 ne '' ? " $1" : ""),
                text => $1
            }};
        }

=for html <!--

=over

=item B<C<70>HwaHwaHwa>

=for html --><dl><dt><strong><code>70</code>H<sub>wa</sub>H<sub>wa</sub>H<sub>wa</sub></strong></dt>

height of waves in units of 0.1 metre

=back

=cut

        # group 70HwaHwaHwa
        # EXTENSION: use group even if 1PwaPwaHwaHwa was 10000 or HwaHwa was //
        if (m@\G(70(\d\d\d|///)) @gc) {
            push @s2, { waveDataInstrumental => {
                s => $1,
                $2 eq '///'
                 ? (notAvailable => undef)
                 : (height       => { v => sprintf('%.1f', $2 / 10), u => 'M' })
            }};
        }

=for html <!--

=over

=item B<C<8>swTbTbTb>

=for html --><dl><dt><strong><code>8</code>s<sub>w</sub>T<sub>b</sub>T<sub>b</sub>T<sub>b</sub></strong></dt>

data from wet-bulb temperature measurement

=back

=cut

        # group 8swTbTbTb
        # sw: WMO-No. 306 Vol I.1, Part A, code table 3855
        if (/\G(8([0-25-7])(\d\d\d)) /gc) {
            push @s2, { wetbulbTemperature => {
                s                      => $1,
                wetbulbTempMeasurement => qw(measured measured icedMeasured . .
                                            computed computed icedComputed)[$2],
                temp                   => _parseTemp(($2 % 5 ? 1 : 0) . $3)
            }};
        } elsif (m@\G(8////) @gc) {
            push @s2, { wetbulbTemperature => {
                s            => $1,
                notAvailable => undef
            }};
        }

=for html <!--

=over

=item B<C<ICE>> {B<ciSibiDizi> | I<plain language>}

=for html --><dl><dt><strong><code>ICE</code></strong> {<strong>c<sub>i</sub>S<sub>i</sub>b<sub>i</sub>D<sub>i</sub>z<sub>i</sub></strong> | <em>plain language</em>}</dt>

sea ice and ice of land origin

=back

=cut

        # group ICE (ciSibiDizi|plain language)
        # ci + Si reported only if ship is within 0.5 NM of ice
        # ci=1, Di=0: ship is in an open lead more than 1.0 NM wide
        # ci=1, Di=9: ship is in fast ice with ice boundary beyond visibility
        # ci=zi=0, Si=Di=/: bi icebergs in sight, but no sea ice
        if (m@\G(ICE (?://///|([\d/])([\d/])([\d/])([\d/])([\d/]))) @gc)
        {
            push @s2, { seaLandIce => {
                s => $1,
                defined $2
                    ? (sortedArr => [
                       $2 ne '/' ? { seaIceConcentration => $2 } : (),
                       $3 ne '/' ? { iceDevelopmentStage => $3 } : (),
                       $4 ne '/' ? { iceOfLandOrigin     => $4 } : (),
                       $5 ne '/' ? { iceEdgeBearing      => $5 } : (),
                       $6 ne '/' ? { iceConditionTrend   => $6 } : ()
                      ])
                    : ( notAvailable => undef )
            }};
        } elsif (   m@\GICE (.*?) ?(?=\b([3-9])\2\2 |\b[\d/]{5} )@gc
                 || /\GICE (.*?) ?$/gc)
        {
            push @s2, { seaLandIce => {
                s => "ICE" . ($1 ne '' ? " $1" : ""),
                text => $1
            }};
        }

        $report{section2} = \@s2;
    }

    # skip groups until next section
    push @{$report{warning}}, { warningType => 'notProcessed', s => $1 }
        if /\G(.*?) ?(?=\b333 )/gc && $1 ne '';

########################################################################

=head3 Section 3: climatological data (data for regional exchange, optional)

(partially implemented)

The WMO regions are:

=over

=item *

I (Africa)

=item *

II (Asia)

=item *

III (South America)

=item *

IV (North and Central Amerika)

=item *

V (South-West Pacific)

=item *

VI (Europe)

=item *

Antarctic

=back

 region I: 0TgTgRcRt 1snTxTxTx 2snTnTnTn 4E'sss 5j1j2j3j4 (j5j6j7j8j9) 6RRRtR 7R24R24R24R24 8NsChshs 9SPSPspsp 80000 0LnLcLdLg (1sLdLDLve)

 region II: 0EsnT'gT'g 1snTxTxTx 2snTnTnTn 3EsnTgTg 4E'sss 5j1j2j3j4 (j5j6j7j8j9) 6RRRtR 7R24R24R24R24 8NsChshs 9SPSPspsp

 region III: 1snTxTxTx 2snTnTnTn 3EsnTgTg 4E'sss 5j1j2j3j4 (j5j6j7j8j9) 6RRRtR 7R24R24R24R24 8NsChshs 9SPSPspsp

 region IV: 0CsDLDMDH 1snTxTxTx 2snTnTnTn 3E/// 4E'sss 5j1j2j3j4 (j5j6j7j8j9) 6RRRtR 7R24R24R24R24 8NsChshs 9SPSPspsp TORNADO/ONE-MINUTE MAXIMUM x KNOTS AT x UTC

 region V: 1snTxTxTx 2snTnTnTn 4E'sss 5j1j2j3j4 (j5j6j7j8j9) 6RRRtR 7R24R24R24R24 8NsChshs 9SPSPspsp

 region VI: 1snTxTxTx 2snTnTnTn 3EsnTgTg 4E'sss 5j1j2j3j4 (j5j6j7j8j9) 6RRRtR 7R24R24R24R24 8NsChshs 9SPSPspsp

 Antarctic: 0dmdmfmfm (00200) 1snTxTxTx 2snTnTnTn 4E'sss 5j1j2j3j4 (j5j6j7j8j9) 6RRRtR 7DmDLDMDH 8NsChshs 9SPSPspsp

=cut

    if (/\G333 /gc) {
        my @s3;

        @s3  = ();

=for html <!--

=over

=item region I: B<C<0>TgTgRcRt>

=for html --><dl><dt>region I: <strong><code>0</code>T<sub>g</sub>T<sub>g</sub>R<sub>c</sub>R<sub>t</sub></strong></dt>

minumum ground temperature last night, character and start/end of precipitation

=back

=cut

        # region I: group 0TgTgRcRt
        if ($region eq 'I' && m@\G0(//|\d\d)([\d/])([\d/]) @gc) {
            my ($tag, $r);

            $r->{s} = "0$1";
            if ($1 eq '//') {
                $r->{notAvailable} = undef;
            } else {
                $r->{timePeriod} = 'n';
                $r->{temp}{v} = $1 > 50 ? -($1 - 50) : $1 + 0;
                $r->{temp}{u} = 'C';
            }
            push @s3, { tempMinGround => $r };
            $r = undef;

            # WMO-No. 306 Vol II, Chapter I, code table 167:
            $r->{s} = $2;
            if ($2 eq '/') {
                $r->{notAvailable} = undef
            } else {
                if ($2 == 1 || $2 == 5) {
                    $r->{phenomDescr} = 'isLight';
                } elsif ($2 == 2 || $2 == 6) {
                    $r->{phenomDescr} = 'isModerate';
                } elsif ($2 == 3 || $2 == 7) {
                    $r->{phenomDescr} = 'isHeavy';
                } elsif ($2 == 4 || $2 == 8) {
                    $r->{phenomDescr} = 'isVeryHeavy';
                } elsif ($2 == 9) {
                    $r->{phenomDescr} = 'isVariable';
                }
                if ($2 == 0) {
                    $r->{noPrecip} = undef;
                } elsif ($2 < 5) {
                    $r->{phenomDescr2} = 'isIntermittent';
                } elsif ($2 < 9) {
                    $r->{phenomDescr2} = 'isContinuous';
                }
            }
            push @s3, { precipCharacter => $r };
            $r = undef;

            # WMO-No. 306 Vol II, Chapter I, code table 168:
            # Rt time of beginning or end of precipitation
            $r->{s} = $3;
            if ($3 eq '/') {
                $r->{notAvailable} = undef
            } else {
                if ($3 == 0) {
                    $r->{noPrecip} = undef;
                } elsif ($3 == 1) {
                    $r->{hours} = { v => 1, q => 'isLess' };
                } elsif ($3 < 7) {
                    $r->{hoursFrom} = $3 - 1;
                    $r->{hoursTill} = $3;
                } elsif ($3 < 9) {
                    $r->{hoursFrom} = ($3 - 7) * 2 + 6;
                    $r->{hoursTill} = ($3 - 7) * 2 + 8;
                } else {
                    $r->{hours} = { v => 10, q => 'isGreater' };
                }
            }
            # WMO-No. 306 Vol I.1, Part A, code table 4677:
            #   00..49 is not precipitation
            $tag =      exists $report{weatherSynop}
                     && exists $report{weatherSynop}{weatherPresent}
                     && $report{weatherSynop}{weatherPresent} >= 50
                   ? 'beginPrecip' : 'endPrecip';
            push @s3, { $tag => $r };
        }

=for html <!--

=over

=item region II: B<C<0>EsnT'gT'g>

=for html --><dl><dt>region II: <strong><code>0</code>Es<sub>n</sub>T'<sub>g</sub>T'<sub>g</sub></strong></dt>

state of the ground without snow or measurable ice cover, ground temperature

=back

=cut

        # region II: group 0EsnT'gT'g
        # EXTENSION: allow 'E' for state of the ground
        # TODO: enable CN if the documentation matches the data:
        #       e.g. 2009-12: AAXX 14001 54527 ... 333 00151 -> -51 °C ?!?
        if ($country eq 'CN' && m@\G(0[\d/E][\d/]{3}) @gc) {
            push @{$report{warning}},
                                     { warningType => 'notProcessed', s => $1 };
        } elsif ($region eq 'II' && m@\G(0([\d/E]))(///|[01]\d\d) @gc) {
            my $r;

            $r->{s} = $1;
            if ($2 eq '/' || $2 eq 'E') {
                $r->{notAvailable} = undef;
            } else {
                $r->{stateOfGroundVal} = $2;
            }
            push @s3, { stateOfGround => $r };
            $r = undef;

            $r->{s} = $3;
            if ($3 eq '///') {
                $r->{notAvailable} = undef;
            } else {
                $r->{temp} = _parseTemp "${3}0";
                $r->{temp}{v} += 0;
            }
            push @s3, { tempGround => $r };
        }

=for html <!--

=over

=item region IV: B<C<0>CsDLDMDH>

=for html --><dl><dt>region IV: <strong><code>0</code>C<sub>s</sub>D<sub>L</sub>D<sub>M</sub>D<sub>H</sub></strong></dt>

state of sky in tropics

=back

=cut

        # region IV: group 0CsDLDMDH
        if ($region eq 'IV' && m@\G0([\d/])([\d/])([\d/])([\d/]) @gc) {
            my $r;

            # WMO-No. 306 Vol II, Chapter IV, code table 430
            $r->{s} = "0$1";
            if ($1 eq '/') {
                $r->{notAvailable} = undef;
            } else {
                $r->{stateOfSkyVal} = $1;
            }
            push @s3, { stateOfSky => $r };
            $r = undef;

            $r->{s} = "$2$3$4";
            _codeTable0700 $r, 'cloudTypeLow', $2;
            _codeTable0700 $r, 'cloudTypeMiddle', $3;
            _codeTable0700 $r, 'cloudTypeHigh', $4;
            push @s3, { cloudTypesDrift => $r };
        }

=for html <!--

=over

=item Antarctic: B<C<0>dmdmfmfm> (B<C<00200>>)

=for html --><dl><dt>Antarctic: <strong><code>0</code>d<sub>m</sub>d<sub>m</sub>f<sub>m</sub>f<sub>m</sub></strong> (<strong><code>00200</code></strong>)</dt>

maximum wind during the preceding six hours

=back

=cut

        # Antarctic: group 0dmdmfmfm (00200)
        if (   $region eq 'Antarctic'
            && m@\G(0($re_dd|5[1-9]|[67]\d|8[0-6]|//)(\d\d)( 00200)?) @ogc)
        {
            my $r;

            $r->{s} = $1;
            $r->{wind} = { speed => { v => $3, u => 'KT' }};
            $r->{wind}{isEstimated} = undef if $winds_est;
            $r->{wind}{speed}{v} += 200 if defined $4;

            if ($2 eq '//') {
                $r->{wind}{dirNotAvailable} = undef;
            } else {
                # WMO-No. 306 Vol I.1, Part A, code table 0877:
                $r->{wind}{dir} = { rp => 4, rn => 5 } unless $winds_est;
                $r->{wind}{dir} = $2 * 10;
                if ($r->{wind}{dir} > 500) {
                    $r->{wind}{dir} -= 500;
                    $r->{wind}{speed}{v} += 100;
                }
            }
            $r->{measurePeriod} = { v => 1, u => 'MIN' };
            $r->{timeBeforeObs} = { hours => 6 };
            push @s3, { highestMeanSpeed => $r };
        }

=for html <!--

=over

=item B<C<1>snTxTxTx>

=for html --><dl><dt><strong><code>1</code>s<sub>n</sub>T<sub>x</sub>T<sub>x</sub>T<sub>x</sub></strong></dt>

maximum temperature
(regions I, II except CN, MG: last 12 hours day-time;
MG: 24 hours before 14:00,
region III: day-time;
region IV: at 00:00 and 18:00 last 12 hours,
           at 06:00 last 24 hours,
           at 12:00 previous day;
region V, CN: last 24 hours,
region VI: last 12 hours, DE at 09:00 UTC: 15 hours,
Antarctic: last 12 hours)

=back

=cut

        # group 1snTxTxTx
        if ($region && m@\G(1(?:([01]\d{3})|[01/]///)) @gc) {
            my $r;

            $r->{s} = $1;
            if (defined $2) {
                $r->{temp} = _parseTemp $2;
            } else {
                $r->{notAvailable} = undef;
            }
            if ($region eq 'V' || $country eq 'CN') {
                $r->{timeBeforeObs} = { hours => 24 } if exists $r->{temp};
                push @s3, { tempMax => $r };
            } elsif ($country eq 'RU') {
                $r->{timeBeforeObs} = { hours => 12 } if exists $r->{temp};
                push @s3, { tempMax => $r };
            } elsif ($region eq 'IV') {
                if (exists $r->{temp}) {
                    if ($obs_hour =~ /00|18/) {
                        $r->{timeBeforeObs} = { hours => 12 };
                    } elsif ($obs_hour == 6) {
                        $r->{timeBeforeObs} = { hours => 24 };
                    } elsif ($obs_hour == 12) {
                        $r->{timePeriod} = 'p';
                    } else {
                        $r->{timeBeforeObs} = { notAvailable => undef };
                    }
                }
                push @s3, { tempMax => $r };
            } elsif ($region eq 'Antarctic') {
                $r->{timeBeforeObs} = { hours => 12 } if exists $r->{temp};
                push @s3, { tempMax => $r };
            } elsif ($region eq 'VI') {
                if (exists $r->{temp}) {
                    if ($obs_hour =~ /06|18/) {
                        $r->{timeBeforeObs} = { hours => 12 };
                    } elsif ($country eq 'DE' && $obs_hour == 9) {
                        $r->{timeBeforeObs} = { hours => 15 };
                    } else {
                        # TODO: period for BG, EE, ...?
                        $r->{timeBeforeObs} = { notAvailable => undef };
                    }
                }
                push @s3, { tempMax => $r };
            } elsif ($country eq 'MG') {
                $r->{timePeriod} = '24h14' if exists $r->{temp};
                push @s3, { tempMax => $r };
            } else { # I, II, III except CN, MG
                $r->{timeBeforeObs} = { hours => 12 }
                    if exists $r->{temp} && $region ne 'III';
                push @s3, { tempMaxDaytime => $r };
            }
        }

=for html <!--

=over

=item B<C<2>snTnTnTn>

=for html --><dl><dt><strong><code>2</code>s<sub>n</sub>T<sub>n</sub>T<sub>n</sub>T<sub>n</sub></strong></dt>

minimum temperature
(regions I, II except CN, MG: night-time last 12 hours;
MG: 24 hours before 04:00,
region III: last night;
region IV: at 00:00 last 18 hours,
           at 06:00 and 18:00 last 24 hours,
           at 12:00 last 12 hours;
region V, CN: last 24 hours,
region VI: last 12 hours, DE at 09:00 UTC: 15 hours,
Antarctic: last 12 hours)

=back

=cut

        # group 2snTnTnTn
        if ($region && m@\G(2(?:([01]\d{3})|[01/]///)) @gc) {
            my $r;

            $r->{s} = $1;
            if (defined $2) {
                $r->{temp} = _parseTemp $2;
            } else {
                $r->{notAvailable} = undef;
            }
            if ($region eq 'V' || $country eq 'CN') {
                $r->{timeBeforeObs} = { hours => 24 } if exists $r->{temp};
                push @s3, { tempMin => $r };
            } elsif ($country eq 'RU') {
                $r->{timeBeforeObs} = { hours => 12 } if exists $r->{temp};
                push @s3, { tempMin => $r };
            } elsif ($region eq 'IV') {
                if (exists $r->{temp}) {
                    if ($obs_hour =~ /06|18/) {
                        $r->{timeBeforeObs} = { hours => 24 };
                    } elsif ($obs_hour == 0) {
                        $r->{timeBeforeObs} = { hours => 18 };
                    } elsif ($obs_hour == 12) {
                        $r->{timeBeforeObs} = { hours => 12 };
                    } else {
                        $r->{timeBeforeObs} = { notAvailable => undef };
                    }
                }
                push @s3, { tempMin => $r };
            } elsif ($region eq 'Antarctic') {
                $r->{timeBeforeObs} = { hours => 12 } if exists $r->{temp};
                push @s3, { tempMin => $r };
            } elsif ($region eq 'VI') {
                if (exists $r->{temp}) {
                    if ($obs_hour =~ /06|18/) {
                        $r->{timeBeforeObs} = { hours => 12 };
                    } elsif ($country eq 'DE' && $obs_hour == 9) {
                        $r->{timeBeforeObs} = { hours => 15 };
                    } else {
                        # TODO: period for BG, EE, ...?
                        $r->{timeBeforeObs} = { notAvailable => undef };
                    }
                }
                push @s3, { tempMin => $r };
            } elsif ($country eq 'MG') {
                $r->{timePeriod} = '24h04' if exists $r->{temp};
                push @s3, { tempMin => $r };
            } else { # I, II, III except CN, MG
                $r->{timeBeforeObs} = { hours => 12 }
                    if exists $r->{temp} && $region ne 'III';
                push @s3, { tempMinNighttime => $r };
            }
        } elsif (m@\G(29(?:///|100|0\d\d)) @gc) {
            push @{$report{warning}},
                                     { warningType => 'notProcessed', s => $1 };
        }

=for html <!--

=over

=item regions II, III, VI: B<C<3>EsnTgTg>

=for html --><dl><dt>regions II, III, VI: <strong><code>3</code>Es<sub>n</sub>T<sub>g</sub>T<sub>g</sub></strong></dt>

state of the ground without snow or measurable ice cover, minimum ground temperature last night (DE: 12/15 hours)

=item region IV: B<C<3>EC<///>>

state of the ground without snow or measurable ice cover

=back

=cut

        # regions II, III, VI: group 3EsnTgTg
        # region IV: group 3E///
        # TODO: enable CN if the documentation matches the data:
        #       e.g. 2007-07: AAXX 17001 52908 ... 333 ... 30030 -> 30 °C ?!?
        # TODO: enable RO if the documentation matches the data:
        #       e.g. 2012-09: AAXX 19181 15015 ... 333 ... 30038 -> 38 °C ?!?
        if (   $country eq 'CN' && m@\G(3[\d/]{4}) @gc
            || $country eq 'RO' && $obs_hour == 18 && m@\G(3[\d/]{4}) @gc)
        {
            push @{$report{warning}},
                                     { warningType => 'notProcessed', s => $1 };
        } elsif (   (   $region =~ /^(?:II|III|VI)$/
                     && m@\G3([\d/])(///|[01]\d\d) @gc)
                 || ($region eq 'IV' && m@\G3([\d/])(///) @gc))
        {
            my $r;

            $r->{s} = "3$1";
            $r->{s} .= $2 if $region eq 'IV';
            if ($1 eq '/') {
                $r->{notAvailable} = undef;
            } else {
                $r->{stateOfGroundVal} = $1;
            }
            push @s3, { stateOfGround => $r };
            $r = undef;

            if ($region ne 'IV') {
                $r->{s} = $2;
                if ($2 eq '///') {
                    $r->{notAvailable} = undef;
                } else {
                    if ($country eq 'DE' && $obs_hour == 9) {
                        $r->{timeBeforeObs} = { hours => 15 };
                    } elsif ($country eq 'DE') {
                        $r->{timeBeforeObs} = { hours => 12 };
                    } else {
                        $r->{timePeriod} = 'n';
                    }
                    $r->{temp} = _parseTemp "${2}0";
                    $r->{temp}{v} += 0;
                }
                push @s3, { tempMinGround => $r };
            }
        # region I: 3Ejjj is not used
        # regions V, Antarctic: use of 3Ejjj not specified
        } elsif ($region && m@\G(3[\d/]{4}) @gc) {
            push @{$report{warning}},
                                     { warningType => 'notProcessed', s => $1 };
        }

=over

=item B<C<4>E'sss>

state of the ground if covered with snow or ice, snow depth

=back

=cut

        # group 4E'sss
        if (m@\G4([\d/])(///|\d{3}) @gc) {
            my $r;

            $r->{s} = "4$1";
            if ($1 eq '/') {
                $r->{notAvailable} = undef;
            } else {
                $r->{stateOfGroundSnowVal} = $1;
            }
            push @s3, { stateOfGroundSnow => $r };
            $r = undef;

            # WMO-No. 306 Vol I.1, Part A, code table 3889:
            $r->{s} = $2;
            if ($2 eq '///') {
                $r->{notAvailable} = undef;
            } elsif ($2 eq '000') {
                $r->{invalidFormat} = $2;
            } elsif ($2 eq '997') {
                $r->{precipAmount} = { v => 0.5, u => 'CM', q => 'isLess' };
            } elsif ($2 eq '998') {
                $r->{coverNotCont} = undef;
            } elsif ($2 eq '999') {
                $r->{noMeasurement} = undef;
            } else {
                $r->{precipAmount} = { v => $2 + 0, u => 'CM' };
            }
            push @s3, { snowDepth => $r };
        }

=for html <!--

=over

=item B<C<5>j1j2j3j4> (B<j5j6j7j8j9>)

=for html --><dl><dt><strong><code>5</code>j<sub>1</sub>j<sub>2</sub>j<sub>3</sub>j<sub>4</sub></strong> (<strong>j<sub>5</sub>j<sub>6</sub>j<sub>7</sub>j<sub>8</sub>j<sub>9</sub></strong>)</dt>

evaporation, temperature change, duration of sunshine,
radiation type and amount, direction of cloud drift,
direction and elevation of cloud, pressure change

=back

=cut

        {
            my ($msg5, $had_pChg, $had_sun_1d, $had_sun_1h,
                %had_rad, $had_drift);

            # WMO-No. 306 Vol I.1, Part A, code table 2061:
            # group 5j1j2j3j4 (j5j6j7j8j9)

            # use $msg5 for group(s) 5j1j2j3j4
            # determine all 5xxxx groups with 0xxxx .. 6xxxx suppl. groups:
            # 1. use only consecutive groups 0xxxx .. 6xxxx
            ($msg5) = /\G(5[\d\/]{4} (?:[0-6][\d\/]{4} )*)/gc;
            $msg5 = '' unless defined $msg5;
            # 2. remove trailing 6xxxx if precipitation indicator is 0 or 2
            if (   exists $report{precipInd}{precipIndVal}
                && (   $report{precipInd}{precipIndVal} == 0
                    || $report{precipInd}{precipIndVal} == 2))
            {
                pos $_ -= 6 if $msg5 =~ s/6[\d\/]{4} $//
            }

            pos $msg5 = 0;

            # allow any order, but check for duplicates/impossible combinations
            while ($msg5 =~ /\G./) {
                my $match_found;

                $match_found = 0;

                # group 5EEEiE
                if ($msg5 =~ /\G(5([0-3]\d\d)(\d)) /gc) {
                    push @s3, { evapo => {
                        s              => $1,
                        evapoAmount    => sprintf('%.1f', $2 / 10),
                        evapoIndicator => $3,
                        # http://www.wmo.int/pages/prog/www/WMOCodes/Updates_NewZealand_3.pdf
                        $country eq 'TV' ? (timePeriod => '24h21')
                                         : (
                        # WMO-No. 306 Vol II, Chapter I, Section D:
                          $country eq 'MZ' ? (timePeriod    => '24h07p')
                                           : (timeBeforeObs => { hours => 24 }))
                    }};
                    $match_found = 1;
                } elsif ($msg5 =~ m@\G(5[0-3/][\d/]{3}) @gc) {
                    push @s3, { group5xxxxNA => { s => $1 }};
                    $match_found = 1;
                }

                # group 54g0sndT
                if ($msg5 =~ /\G(54([0-5])([01])(\d)) /gc) {
                    my $r;

                    $r->{s} = $1;
                    $r->{hoursFrom} = $2;
                    $r->{hoursTill} = $2 + 1;

                    # WMO-No. 306 Vol I.1, Part A, code table 0822:
                    $r->{temp}{v} = $4 < 5 ? $4 + 10 : $4 + 0;
                    $r->{temp}{v} *= -1 if $3 == 1;
                    $r->{temp}{u} = 'C';
                    push @s3, { tempChange => $r };
                    $match_found = 1;
                } elsif ($msg5 =~ m@\G(54[0-5/]//) @gc) {
                    push @s3, { group5xxxxNA => { s => $1 }};
                    $match_found = 1;
                }

                # group 55SSS (j5j6j7j8j9)*, SSS = 000..240
                if (   !$had_sun_1d
                    && $msg5 =~ m@\G(55(?:///|(${re_hour}\d|240))) @ogc)
                {
                    my $r;

                    $r->{s} = $1;
                    $r->{sunshinePeriod} = 'p';
                    if (defined $2) {
                        $r->{sunshine} =
                                    { v => sprintf('%.1f', $2 / 10), u => 'H' };
                    } else {
                        $r->{sunshineNotAvailable} = undef;
                    }
                    for ($msg5 =~ m@\G(0(?:////|\d{4}) )?(1(?:////|\d{4}) )?(2(?:////|\d{4}) )?(3(?:////|\d{4}) )?(4(?:////|\d{4}) )?(5(?:////|[0-4]\d{3}) )?(6(?:////|\d{4}) )?@gc)
                    {
                        next unless defined $_;

                        /(.)(....)/;
                        $r->{s} .= " $1$2";
                        if ($2 ne '////') {
                            $r->{radiationPeriod} = { v => 24, u => 'H' };
                            $r->{_radiationType $1}{radiationValue} =
                                                      { v => $2 + 0, u => 'Jcm2' };
                        }
                    }
                    push @s3, { radiationSun => $r };
                    $match_found = 1;
                    $had_sun_1d = 1;
                }

                # group 553SS (j5j6j7j8j9)*, SS = 00..10
                if (!$had_sun_1h && $msg5 =~ m@\G(553(?://|(0\d|10))) @gc) {
                    my $r;

                    $r->{s} = $1;
                    $r->{sunshinePeriod} = { v => 1, u => 'H' };
                    if (defined $2) {
                        $r->{sunshine} =
                                    { v => sprintf('%.1f', $2 / 10), u => 'H' };
                    } else {
                        $r->{sunshineNotAvailable} = undef;
                    }
                    for ($msg5 =~ m@\G(0(?:[\d/]///|\d{4}) )?(1(?:[\d/]///|\d{4}) )?(2(?:[\d/]///|\d{4}) )?(3(?:[\d/]///|\d{4}) )?(4(?:[\d/]///|\d{4}) )?(5(?:////|[0-4]\d{3}) )?(6(?:[\d/]///|\d{4}) )?@gc)
                    {
                        next unless defined $_;

                        /(.)(....)/;
                        $r->{s} .= " $1$2";
                        if (substr($2, 1, 3) ne '///') {
                            $r->{radiationPeriod} = { v => 1, u => 'H' };
                            $r->{_radiationType $1}{radiationValue} =
                                                   { v => $2 + 0, u => 'kJm2' };
                        }
                    }
                    push @s3, { radiationSun => $r };
                    $match_found = 1;
                    $had_sun_1h = 1;
                }

                # groups 5540[78] 4FFFF or 5550[78] 5F24F24F24F24
                if (   $msg5 =~ m@\G(55([45])0([78])) \2(\d{4}|////) @
                    && !exists $had_rad{"$2$3"})
                {
                    my $r;

                    pos $msg5 += 12;
                    $r->{s} = "$1 $2$4";
                    if ($4 eq '////') {
                        $r->{notAvailable} = undef;
                    } else {
                        $r->{radiationPeriod} = { v => ($2 eq '4' ? 1 : 24),
                                                  u => 'H' };
                        $r->{radiationValue} =
                              { v => $4 + 0, u => $2 eq '4' ? 'kJm2' : 'Jcm2' };
                    }
                    push @s3,
                        { ($3 eq '7' ? 'radShortWave' : 'radDirectSolar'), $r };
                    $match_found = 1;
                    $had_rad{"$2$3"} = undef;
                } elsif ($msg5 =~ m@\G(55[45]//) @gc) {
                    push @s3, { group5xxxxNA => { s => $1 }};
                    $match_found = 1;
                }

                # group 56DLDMDH, direction of cloud drift
                if (!$had_drift && $msg5 =~ m@\G(56([\d/])([\d/])([\d/])) @gc) {
                    my $r;

                    $r->{s} = $1;
                    _codeTable0700 $r, 'cloudTypeLow', $2;
                    _codeTable0700 $r, 'cloudTypeMiddle', $3;
                    _codeTable0700 $r, 'cloudTypeHigh', $4;
                    push @s3, { cloudTypesDrift => $r };
                    $match_found = 1;
                    $had_drift = 1;
                }

                # group 57CDaeC, direction and elevation of cloud
                if ($msg5 =~ m@\G(57([\d/])(\d)(\d)) @gc) {
                    my $r;

                    $r->{s} = $1;
                    _codeTable0500 $r, $2;
                    _codeTable0700 $r, 'cloud', $3;
                    _codeTable1004 $r, $4;
                    push @s3, { cloudLocation => $r };
                    $match_found = 1;
                } elsif ($msg5 =~ m@\G(57///) @gc) {
                    push @s3, { group5xxxxNA => { s => $1 }};
                    $match_found = 1;
                }

                # group 58p24p24p24
                if (!$had_pChg && $msg5 =~ m@\G(58(?:(\d{3})|///)) @gc) {
                    push @s3, { pressureChange => {
                        s             => $1,
                        timeBeforeObs => { hours => 24 },
                        defined $2
                           ? (pressureChangeVal =>
                                   { v => sprintf('%.1f', $2 / 10), u => 'hPa' }
                             )
                           : (notAvailable      => undef)
                    }};
                    $match_found = 1;
                    $had_pChg = 1;
                }

                # group 59p24p24p24
                if (!$had_pChg && $msg5 =~ m@\G(59(?:(\d{3})|///)) @gc) {
                    push @s3, { pressureChange => {
                        s             => $1,
                        timeBeforeObs => { hours => 24 },
                        defined $2
                          ? (pressureChangeVal =>
                              { v => sprintf('%.1f', $2 / -10 + 0), u => 'hPa' }
                            )
                          : (notAvailable => undef)
                    }};
                    $match_found = 1;
                    $had_pChg = 1;
                }

                last unless $match_found; # no match but $msg5 was not "empty"
            }

            # EXTENSION: allow un-announced 6xxxx group
            if ($msg5 =~ m@\G6(?:\d{3}|///)[\d/] $@gc) {
                pos $_ -= 6;
            }
            if ($msg5 =~ /\G./) {
                pos $_ -= length(substr $msg5, pos $msg5);
                $report{ERROR} = _makeErrorMsgPos 'invalid333-5xxxx';
                $report{section3} = \@s3;
                return %report;
            }
        }

=for html <!--

=over

=item B<C<6>RRRtR>

=for html --><dl><dt><strong><code>6</code>RRRt<sub>R</sub></strong></dt>

amount of precipitation for given period

=back

=cut

        # group 6RRRtR
        if (m@\G(6(\d{3}|///)([\d/])) @gc) {
            my $r;

            if (   exists $report{precipInd}{precipIndVal}
                && $report{precipInd}{precipIndVal} != 0
                && $report{precipInd}{precipIndVal} != 2)
            {
                push @{$report{warning}},
                                     { warningType => 'precipNotOmitted3' };
            }

            $r = _codeTable3590 $2;
            $r->{s} = $1;
            if (!exists $r->{notAvailable}) {
                if ($3 eq '/') {
                    # WMO-No. 306 Vol II, Chapter II, Section D:
                    if ($country eq 'BD') {
                        $r->{timeBeforeObs} = { hours => 3 };
                    } elsif ($country eq 'IN' || $country eq 'LK') {
                        $r->{timeSince}{hour} = '03';
                    } else {
                        $r->{timeBeforeObs} = { notAvailable => undef };
                    }
                } else {
                    $r->{timeBeforeObs} = _codeTable4019 $3;
                }
            }
            push @s3, { precipitation => $r };
            $have_precip333 = 1;
        }

=for html <!--

=over

=item regions I..VI: B<C<7>R24R24R24R24>

=for html --><dl><dt>regions I..VI: <strong><code>7</code>R<sub>24</sub>R<sub>24</sub>R<sub>24</sub>R<sub>24</sub></strong></dt>

amount of precipitation in the last 24 hours

=back

=cut

        # WMO-No. 306 Vol I.1, Part A, 12.4.1:
        # regions I..VI: group 7R24R24R24R24
        # EXTENSION: allow 7////
        # EXTENSION: allow 7xxx/
        if ($region =~ /^(?:I|II|III|IV|V|VI)$/) {
            if (m@\G(7(\d{3})([\d/])) @gc) {
                my $r;

                $r->{s} = $1;
                $r->{timeBeforeObs} = { hours => 24 };
                if ("$2$3" eq '9999') {
                    $r->{precipTraces} = undef;
                } elsif ("$2$3" eq '9998') {
                    $r->{precipAmount} = { v => 999.8, u => 'MM',
                                           q => 'isEqualGreater' };
                } else {
                    $r->{precipAmount}{v} = $2 + 0;
                    $r->{precipAmount}{v} .= ".$3" unless $3 eq '/';
                    $r->{precipAmount}{u} = 'MM';
                }
                push @s3, { precipitation => $r };
            } elsif (m@\G(7////) @gc) {
                push @s3, { precipitation => {
                    s            => $1,
                    notAvailable => undef
                }};
            }
        }

=for html <!--

=over

=item Antarctic: B<C<7>DmDLDMDH>

=for html --><dl><dt>Antarctic: <strong><code>7</code>D<sub>m</sub>D<sub>L</sub>D<sub>M</sub>D<sub>H</sub></strong></dt>

maximum wind during the preceding six hours

=back

=cut

        # Antarctic: group 7DmDLDMDH
        if (   $region eq 'Antarctic'
            && m@\G7([1-8])([\d/])([\d/])([\d/]) @gc)
        {
            my $r;

            $r->{s} = "7$1";
            $r->{timeBeforeObs} = { hours => 6 };
            _codeTable0700 $r, 'compass', $1;
            push @s3, { windDir => $r };
            $r = undef;

            $r->{s} = "$2$3$4";
            _codeTable0700 $r, 'cloudTypeLow', $2;
            _codeTable0700 $r, 'cloudTypeMiddle', $3;
            _codeTable0700 $r, 'cloudTypeHigh', $4;
            push @s3, { cloudTypesDrift => $r };
        }

=for html <!--

=over

=item B<C<8>NsChshs>

=for html --><dl><dt><strong><code>8</code>N<sub>s</sub>Ch<sub>s</sub>h<sub>s</sub></strong></dt>

cloud cover and height for cloud layers

=back

=cut

        # group 8NsChshs (but not 80000!)
        # EXTENSION: allow Ns = 0
        while (m@\G(8([\d/])([\d/])([0-46-9]\d|5[06-9]|//)) @gc) {
            my ($tag, $dist, $r, $r2);

            if ($1 eq '80000') {
                pos $_ -= 6;
                last;
            }

            $r->{s} = $1;

            $r2->{dummy} = undef;
            _codeTable0500 $r2, $3;
            delete $r2->{dummy};
            $tag = $2 eq '9' && $3 eq '/' ? 'visVert' : 'cloudBase';
            if ($4 eq '//') {
                push @{$r->{sortedArr}}, { cloudBaseNotAvailable => undef };
            } else {
                $dist = _codeTable1677 $4;
                if (ref $dist eq 'HASH') {
                    if ($tag eq 'visVert') {
                        push @{$r->{sortedArr}}, { visVert => {
                            s => $4,
                            distance => { %$dist, u => 'M' }
                        }};
                    } else {
                        push @{$r->{sortedArr}}, { cloudBase => {
                            %$dist, u => 'M'
                        }};
                    }
                } else {
                    if ($tag eq 'visVert') {
                        push @{$r->{sortedArr}},
                            { visVertFrom => {
                                     distance => { v => $dist->[0], u => 'M' }
                            }},
                            { visVertTo => {
                                     distance => { v => $dist->[1], u => 'M' }
                            }};
                    } else {
                        push @{$r->{sortedArr}},
                            { cloudBaseFrom => { v => $dist->[0], u => 'M' }},
                            { cloudBaseTo   => { v => $dist->[1], u => 'M' }};
                    }
                }
            }
            push @{$r->{sortedArr}}, $r2;
            push @{$r->{sortedArr}}, { cloudOktas => _codeTable2700 $2 };
            push @s3, { cloudInfo => $r };
        }

=for html <!--

=over

=item B<C<9>SPSPspsp>

=for html --><dl><dt><strong><code>9</code>S<sub>P</sub>S<sub>P</sub>s<sub>p</sub>s<sub>p</sub></strong></dt>

supplementary information (partially implemented)

=back

=cut

        # WMO-No. 306 Vol I.1, Part A, code table 3778:
        # group 9SPSPspsp
        while (m@\G9[\d/]{4} @) {
            my ($r, @time_var, $no_match);

            $no_match = 0;

            # collect time and variability groups for weather phenomenon
            # reported in the following group 9SPSPspsp
            @time_var = ();
            while (   /\G(90([2467])($re_synop_tt)) /ogc
                   || /\G(90(2)($re_synop_zz)) /ogc)
            {
                push @time_var, { s => $1,
                                  t => $2,
                                  v => $3,
                                  r => _codeTable4077 $3,
                                          ({ 2 => 'Begin',
                                             4 => 'At',
                                             6 => '',
                                             7 => '' }->{$2})
                };
            }

            # group 90(0(tt|zz)|[15]tt)
            if (m@\G(90(?:0\d\d|[15]$re_synop_tt)) @ogc) {
                my $s;

                $s = $1;
                $s =~ /..(.)(..)/;
                $r = _codeTable4077 $2, (
                    { 0 => 'Begin',
                      1 => 'End',
                      5 => '' }->{$1});
                $r->{s} = $s;
                push @s3, { weatherSynopInfo => $r };
            # group 909Rtdc
            } elsif (/\G909([1-9])([0-79]) /gc) {
                my $tag;

                $r = _codeTable3552 $1;
                $r->{s} = "909$1";
                # WMO-No. 306 Vol I.1, Part A, code table 4677:
                #   00..49 is not precipitation
                $tag =      exists $report{weatherSynop}
                         && exists $report{weatherSynop}{weatherPresent}
                         && $report{weatherSynop}{weatherPresent} >= 50
                       ? 'beginPrecip' : 'endPrecip';
                push @s3, { $tag => $r };
                $r = undef;

                $r = _codeTable0833 $2;
                $r->{s} = $2;
                if ($2 <= 3) {
                    $r->{onePeriod} = undef;
                } elsif ($2 <= 7) {
                    $r->{morePeriods} = undef;
                } else {
                    $r->{periodsNA} = undef;
                }
                push @s3, { precipPeriods => $r };
            # group (902zz) 910ff (00fff) (915dd)
            } elsif (/\G(910(\d\d)) /gc) {
                $r->{s} = '';
                for (@time_var) {
                    if ($_->{v} >= 76) {
                        $r->{s} .= $_->{s} . ' ';
                        $_->{s} = '';
                        push @{$r->{time_var_Arr}}, $_->{r};
                    }
                }
                $r->{s} .= $1;
                $r->{measurePeriod} = { v => 10, u => 'MIN' };
                if ($windUnit) {
                    $r->{wind}{speed}{u} = $windUnit;
                    $r->{wind}{speed}{v} = $2 + 0;
                    $r->{wind}{isEstimated} = undef if $winds_est;
                } else {
                    $r->{wind}{speedNotAvailable} = undef;
                }
                if ($2 == 99) {
                    if (!/\G(00([1-9]\d\d)) /gc) {
                        $report{ERROR} = _makeErrorMsgPos 'wind';
                        $report{section3} = \@s3;
                        return %report;
                    }
                    $r->{s} .= " $1";
                    $r->{wind}{speed}{v} = $2 + 0 if $windUnit;
                }
                _check_915dd $r, $winds_est;
                push @s3, { highestGust => $r };
            # group (90[2467]tt|902zz) 91[1-4]ff (00fff) (915dd) (903tt)
            } elsif (m@\G(91([1-4])(\d\d|//)) @gc) {
                my ($type, $have_time_var);

                $r->{s} = '';
                for (@time_var) {
                    $r->{s} .= $_->{s} . ' ';
                    $_->{s} = '';
                    push @{$r->{time_var_Arr}}, $_->{r};
                    if ($_->{t} == 7) {
                        $have_time_var = 1;
                    }
                    if ($_->{t} == 4) {
                        $have_time_var = 1;
                        $r->{measurePeriod} = { v => 10, u => 'MIN' };
                    }
                }
                $r->{timeBeforeObs} = { hours => $period }
                    unless $have_time_var;
                $r->{s} .= $1;
                $type = { 1 => 'highestGust',
                          2 => 'highestMeanSpeed',
                          3 => 'meanSpeed',
                          4 => 'lowestMeanSpeed' }->{$2};
                if ($windUnit && $3 ne '//') {
                    $r->{wind}{speed}{u} = $windUnit;
                    $r->{wind}{speed}{v} = $3 + 0;
                    $r->{wind}{isEstimated} = undef if $winds_est;
                } else {
                    $r->{wind}{speedNotAvailable} = undef;
                }
                if ($3 ne '//' && $3 == 99) {
                    if (!/\G(00([1-9]\d\d)) /gc) {
                        $report{ERROR} = _makeErrorMsgPos 'wind';
                        $report{section3} = \@s3;
                        return %report;
                    }
                    $r->{s} .= " $1";
                    $r->{wind}{speed}{v} = $2 + 0 if exists $r->{wind}{speed};
                }
                _check_915dd $r, $winds_est;
                if (/\G903($re_synop_period) /ogc) {
                    $r->{s} .= " 903$1";
                    push @{$r->{time_var_Arr}}, _codeTable4077($1, 'End');
                }
                push @s3, { $type => $r };
            # group 92[01]SFx - state of the sea and maximum wind force
            } elsif (m@\G92([01])([\d/])([\d/]) @gc) {
              push @s3, { seaCondition => {
                  s  => "92.$2.",
                  $2 ne '/' ? (seaCondVal => $2) : (notAvailable => undef)
              }};
              push @s3, { maxWindForce => {
                  s => "92$1.$3",
                  ($3 ne '/') ? (timeBeforeObs => { hours => $period },
                                 windForce => { v => $1 * 10 + $3 })
                              : (notAvailable => undef)
              }};
            # group 923S'S
            } elsif (m@\G923([\d/])([\d/]) @gc) {
              push @s3, { alightingAreaCondition => {
                  s => "923$1",
                  $1 ne '/' ? (seaCondVal => $1) : (notAvailable => undef)
              }};
              push @s3, { seaCondition => {
                  s => $2,
                  $2 ne '/' ? (seaCondVal => $2) : (notAvailable => undef)
              }};
            # group 924SVs - state of the sea and visibility seawards
            } elsif (m@\G924([\d/])([\d/]) @gc) {
              push @s3, { seaCondition => {
                  s => "924$1",
                  $1 ne '/' ? (seaCondVal => $1) : (notAvailable => undef)
              }};
              if ($2 ne '/') {
                  my %distance;

                  if ($2 == 0) {
                      @distance{qw(v u q)} = qw(50 M isLess);
                  } elsif ($2 == 9) {
                      @distance{qw(v u q)} = qw(50 KM isEqualGreater);
                  } else {
                      @distance{qw(v rp u)} = @{(
                            [  50, 150, 'M'  ],
                            [ 200, 300, 'M'  ],
                            [ 500, 500, 'M'  ],
                            [   1,   1, 'KM' ],
                            [   2,   2, 'KM' ],
                            [   4,   6, 'KM' ],
                            [  10,  10, 'KM' ],
                            [  20,  30, 'KM' ],
                        )[$2 - 1]};
                  }

                  push @s3, { visibilityAtLoc => {
                      s          => $2,
                      locationAt => 'MAR',
                      visibility => { distance => \%distance }
                  }};
              } else {
                  push @s3, { visibilityAtLoc => {
                      s            => '/',
                      locationAt   => 'MAR',
                      notAvailable => undef
                  }};
              }
            # group 925TwTw
            } elsif (m@\G(925(\d\d|//)) @gc) {
              push @s3, { waterTemp => {
                  s  => $1,
                  $2 ne '//' ? (temp => { v => $2 + 0, u => 'C' })
                             : (notAvailable => undef)
              }};
            # group 926S0i0 - hoar frost
            } elsif (/\G(926([01])([0-2])) /gc) {
                push @s3, { hoarFrost => {
                    s            => $1,
                    hoarFrostVal => qw(horizSurface horizVertSurface)[$2],
                    phenomDescr  => qw(isSlight isModerate isHeavy)[$3]
                }};
            # group 926S0i0 - coloured precipitation
            } elsif (/\G(926([23])([0-2])) /gc) {
                push @s3, { colouredPrecip => {
                    s                 => $1,
                    colouredPrecipVal => qw(sand volcanicAsh)[$2 - 2],
                    phenomDescr       => qw(isSlight isModerate isHeavy)[$3]
                }};
            # group 927S6Tw - frozen deposit
            } elsif (m@\G(927([0-7/])([\d/])) @gc) {
                push @s3, { frozenDeposit => {
                    s             => $1,
                    timeBeforeObs => { hours => $period },
                    ($2 ne '/')           ? (frozenDepositType => $2) : (),
                    ($3 ne '/' && $3 < 7) ? (tempVariation     => $3) : ()
                }};
            # group 928S7S'7
            } elsif (/\G(928([0-8])([0-8])) /gc) {
                push @s3, { snowCoverCharReg => {
                    s                   => $1,
                    snowCoverCharacter  => $2,
                    snowCoverRegularity => $3
                }};
            # group 929S8S'8
            } elsif (/\G(929(\d)([0-7])) /gc) {
                push @s3, { driftSnow => {
                    s                  => $1,
                    driftSnowData      => $2,
                    driftSnowEvolution => $3
                }};
            # group (907tt) 930RR
            } elsif (/\G(930(\d\d)) /gc) {
                $r->{s} = '';
                _codeTable3570 \$r, $2, 'precipAmount';
                for (@time_var) {
                    if ($_->{t} == 7) {
                        $r->{s} .= $_->{s} . ' ';
                        $_->{s} = '';
                        push @{$r->{time_var_Arr}}, $_->{r}
                            unless exists $r->{notAvailable};
                        last;
                    }
                }
                $r->{timeBeforeObs} = { hours => $period }
                    unless    exists $r->{notAvailable}
                           || exists $r->{time_var_Arr};
                $r->{s} .= $1;
                push @s3, { precipitation => $r };
            # group (90[2467]tt|902zz) 931ss or 931s's'
            } elsif (/\G(931(\d\d)) /gc) {
                $r->{s} = '';
                if ($country eq 'AT' && $obs_hour == 6) {
                    $r->{timeBeforeObs} = { hours => 24 };
                } else {
                    $r->{timeBeforeObs} = { hours => $period };
                }
                for (@time_var) {
                    # WMO-No. 306 Vol II, Chapter VI, Section D:
                    if (   $country eq 'CH'
                        && $_->{t} == 7
                        && (   ($_->{v} == 68 && $obs_hour ==  6)
                            || ($_->{v} == 66 && $obs_hour == 18)))
                    {
                        $_->{r} = { timeBeforeObs =>
                                          { hours => $_->{v} == 68 ? 24 : 12 }};
                    }
                    $r->{s} .= $_->{s} . ' ';
                    $_->{s} = '';
                    push @{$r->{time_var_Arr}}, $_->{r};
                    if ($_->{t} == 7) {
                        delete $r->{timeBeforeObs};
                    }
                }
                $r->{s} .= $1;
                # WMO-No. 306 Vol II, Chapter VI, Section D:
                if ($country eq 'FR') { # 931s's'
                    $r->{precipAmount} = { v => $2 + 0, u => 'CM' };
                    $r->{precipAmount}{q} = 'isEqualGreater' if $2 == 99;
                } elsif ($country eq 'AT') {
                    _codeTable3870 \$r, $2;
                    $r->{precipAmount}{v} = 5 if $2 == 97;
                } else {
                    _codeTable3870 \$r, $2;
                }
                push @s3, { snowFall => $r };
            # groups 93[2-7]RR
            } elsif (/\G(93([2-7])(\d\d)) /gc) {
                $r->{s} = $1;
                _codeTable3570 \$r, $3,
                            qw(diameter precipAmount diameter
                               diameter diameter     diameter
                              )[$2 - 2];
                push @s3, { qw(hailStones  waterEquivOfSnow glazeDeposit
                               rimeDeposit compoundDeposit  wetsnowDeposit
                              )[$2 - 2] => $r };
            # group (902zz) 96[024]ww
            # group (90[2467]tt) 96[04]ww
            } elsif (/\G(96([024])(\d\d)) /gc) {
                $r->{s} = '';
                if ($2 == 2) {
                    $r->{timeBeforeObs} = { hours => 1 };
                } elsif ($2 == 4) {
                    $r->{timeBeforeObs} = { hours => $period };
                }
                for (@time_var) {
                    if ($2 != 2 || $_->{v} > 76) {
                        $r->{s} .= $_->{s} . ' ';
                        $_->{s} = '';
                        push @{$r->{time_var_Arr}}, $_->{r};
                        if ($_->{t} != 6 && $_->{v} < 76) {
                            delete $r->{timeBeforeObs};
                        }
                    }
                }
                $r->{s} .= $1;
                $r->{weatherPresent} = $3;
                push @s3, { { 0 => 'weatherSynopAdd',
                              2 => 'weatherSynopAmplPast',
                              4 => 'weatherSynopAmpl' }->{$2} => $r };
            # groups (90[2467]tt) (966ww|967w1w1) (903tt)
            } elsif (/\G(966(\d\d)|967($re_synop_w1w1)) /ogc) {
                my $have_period;

                if (defined $2) {
                    $r->{weatherPresent} = $2;
                } else {
                    $r = _codeTable4687 $3;
                }
                $r->{s} = '';
                for (@time_var) {
                    if ($_->{v} < 70) {
                        $r->{s} .= $_->{s} . ' ';
                        $_->{s} = '';
                        push @{$r->{time_var_Arr}}, $_->{r};
                    }
                }
                $r->{s} .= $1;
                if (/\G903($re_synop_period) /ogc) {
                    $r->{s} .= " 903$1";
                    push @{$r->{time_var_Arr}}, _codeTable4077($1, 'End');
                }
                $have_period = 0;
                for (@{$r->{time_var_Arr}}) {
                    $have_period |= 1
                        if    exists $_->{timeBeforeObs}{occurred}
                           && $_->{timeBeforeObs}{occurred} eq 'Begin';
                    $have_period |= 2
                        if    exists $_->{timeBeforeObs}{occurred}
                           && $_->{timeBeforeObs}{occurred} eq 'End';
                    $have_period |= 3
                        if    !exists $_->{timeBeforeObs}{occurred}
                           || $_->{timeBeforeObs}{occurred} eq 'At';
                }
                if ($have_period == 3) {
                    push @s3, { weatherSynopPast => $r };
                } else {
                    push @{$report{warning}},
                                { warningType => 'notProcessed', s => $r->{s} };
                }
            # group 940Cn3 (958EhDa)
            } elsif (/\G(940(\d)(\d)) /gc) {
                $r->{s} = $1;
                _codeTable0500 $r, $2;
                $r->{cloudEvol} = $3;
                _check_958EhDa $r;
                push @s3, { cloudEvolution => $r };
            # groups 941CDp, 943CLDp
            } elsif (/\G(94([13])(\d)([1-8])) /gc) {
                $r->{s} = $1;
                if ($2 == 1) {
                    _codeTable0500 $r, $3;
                } else {
                    $r->{cloudTypeLow} = $3;
                }

                $r->{location} = {};
                _codeTable0700 $r->{location}, 'compass', $4;
                push @s3, { { 1 => 'cloudFrom',
                              3 => 'lowCloudFrom' }->{$2} => $r };
            } elsif (m@\G(94([13])//) @gc) {
                push @s3, { { 1 => 'cloudFrom',
                              3 => 'lowCloudFrom' }->{$2} => {
                            s            => $1,
                            notAvailable => undef }};
            } elsif (m@\G(94([13])..) @gc) {
                push @s3, { { 1 => 'cloudFrom',
                              3 => 'lowCloudFrom' }->{$2} => {
                            s            => $1,
                            invalidFormat => $1 }};
            # groups 942CDa, 944CLDa
            } elsif (/\G(94([24])(\d)(\d)) /gc) {
                $r->{s} = $1;
                if ($2 == 2) {
                    _codeTable0500 $r, $3;
                } else {
                    $r->{cloudTypeLow} = $3;
                }

                $r->{location} = {};
                _codeTable0700 $r->{location}, 'compass', $4, 'Da';
                push @s3, { { 2 => 'maxCloudLocation',
                              4 => 'maxLowCloudLocation' }->{$2} => $r };
            # group 945htht (958EhDa)
            } elsif (m@\G(945([0-46-9]\d|5[06-9]|//)) @gc) {
                $r->{s} = $1;
                if ($2 eq '//') {
                    $r->{notAvailable} = undef;
                } else {
                    my $dist = _codeTable1677 $2;
                    if (ref $dist eq 'HASH') {
                        $r->{cloudTops} = $dist;
                        $r->{cloudTops}{u} = 'M';
                    } else {
                        $r->{cloudTopsFrom}{v} = $dist->[0];
                        $r->{cloudTopsFrom}{u} = 'M';
                        $r->{cloudTopsTo}{v} = $dist->[1];
                        $r->{cloudTopsTo}{u} = 'M';
                    }
                }
                _check_958EhDa $r;
                push @s3, { cloudTopsHeight => $r };
            # group 948C0Da (958EhDa)
            } elsif (/\G(948([1-9])(\d)) /gc) {
                $r->{s} = $1;

                $r->{cloudTypeOrographic} = $2;

                $r->{location} = {};
                _codeTable0700 $r->{location}, 'compass', $3, 'Da';

                _check_958EhDa $r;
                push @s3, { orographicClouds => $r };
            # group 949CaDa (958EhDa)
            } elsif (/\G(949([0-7])(\d)) /gc) {
                $r->{s} = $1;

                # WMO-No. 306 Vol I.1, Part A, code table 0531:
                $r->{cloudTypeVertical} = {
                        0 => 'Cuhum',
                        1 => 'Cucon',
                        2 => 'Cb',
                        3 => 'CuCb' }->{$2 >> 1};
                $r->{phenomDescr} = {
                        0 => 'isIsolated',
                        1 => 'isNumerous' }->{$2 % 2};

                $r->{location} = {};
                _codeTable0700 $r->{location}, 'compass', $3, 'Da';

                _check_958EhDa $r;
                push @s3, { verticalClouds => $r };
            # group 950Nmn3 (958EhDa)
            } elsif (m@\G(950(\d)([\d/])) @gc) {
                $r = { s               => $1,
                       condMountainLoc => {
                           cloudMountain => $2,
                           $3 ne '/' ? (cloudEvol => $3) : ()
                }};
                _check_958EhDa $r;
                push @s3, { conditionMountain => $r };
            # group 951Nvn4 (958EhDa)
            } elsif (m@\G(951(\d)([\d/])) @gc) {
                $r = { s             => $1,
                       condValleyLoc => {
                           cloudValley => $2,
                           $3 ne '/' ? (cloudBelowEvol => $3) : ()
                }};
                _check_958EhDa $r;
                push @s3, { conditionValley => $r };
            # group 96[135]w1w1
            } elsif (/\G(96([135])($re_synop_w1w1)) /ogc) {
                push @s3, { { 1 => 'weatherSynopAdd',
                              3 => 'weatherSynopAmplPast',
                              5 => 'weatherSynopAmpl' }->{$2} => {
                                s => $1,
                                $2 == 3 ? (timeBeforeObs => { hours => 1 })
                                        : (),
                                $2 == 5 ? (timeBeforeObs => { hours => $period})
                                        : (),
                                %{ _codeTable4687 $3 }
                }};
            # group 97[0-4]EhDa
            } elsif (/\G(97([0-4])([137])(\d)) /gc) {
                $r->{s} = $1;
                $r->{weatherType} = {
                    0 => 'present',
                    1 => 'addPresent',
                    2 => 'addPresent1',
                    3 => 'past1',
                    4 => 'past2' }->{$2};

                # Eh: WMO-No. 306 Vol I.1, Part A, code table 0938:
                $r->{elevAboveHorizon} = $3;

                $r->{location} = {};
                _codeTable0700 $r->{location}, 'compass', $4, 'Da';
                push @s3, { maxWeatherLocation => $r };
            # group 98[0-8]VV
            } elsif (/\G(98([0-8])(\d\d)) /gc) {
                $r = {};
                if ($country eq 'US') {
                    _codeTable4377US $r, $3, $report{obsStationType}{stationType},
                                     $is_auto;
                } elsif ($country eq 'CA') {
                    _codeTable4377CA $r, $3;
                } else {
                    _codeTable4377 $r, $3, $report{obsStationType}{stationType};
                }
                if (exists $r->{visPrev}) {
                    $r->{visPrev}{s} = $1;
                    _codeTable0700 $r->{visPrev}, 'compass', $2
                        if $2 != 0 && exists $r->{visPrev}{distance};
                } else {
                    $r->{visibilityAtLoc}{s} = $1;
                    _codeTable0700 $r->{visibilityAtLoc}, 'compass', $2
                        if $2 != 0;
                }
                push @s3, $r;
            # group 989VbDa
            } elsif (/\G(989([0-8])(\d)) /gc) {
                $r->{s} = $1;
                $r->{timeBeforeObs} = { hours => 1 };
                $r->{visibilityVariationVal} = $2;
                # WMO-No. 306 Vol I.1, Part A, code table 4332:
                # Vb=7,8,9: without regard to direction
                if ($2 < 7) {
                    $r->{location} = {};
                    _codeTable0700 $r->{location}, 'compass', $3, 'Da';
                }
                push @s3, { visibilityVariation => $r };
            # group 990Z0i0
            } elsif (/\G(990(\d)([0-2])) /gc) {
                push @s3, { opticalPhenom => {
                    s => $1,
                    opticalPhenomenon => $2,
                    phenomDescr => { 0 => 'isLight',
                                     1 => 'isModerate',
                                     2 => 'isHeavy' }->{$3}
                }};
            # group 991ADa - mirage
            } elsif (/\G(991([0-8])(\d)) /gc) {
                $r->{s} = $1;
                $r->{mirageType} = $2;
                $r->{location} = {};
                _codeTable0700 $r->{location}, 'compass', $3, 'Da';
                push @s3, { mirage => $r };
            # group 993CSDa (958EhDa)
            } elsif (/\G(993([1-5])(\d)) /gc) {
                $r->{s} = $1;
                $r->{cloudTypeSpecial} = $2;

                $r->{location} = {};
                _codeTable0700 $r->{location}, 'compass', $3, 'Da';

                _check_958EhDa $r;
                push @s3, { specialClouds => $r };
            # TODO: more 9xxxx stuff
            # } elsif () {
            } else {
                $no_match = 1;
            }

            for (@time_var) {
                push @{$report{warning}},
                                 { warningType => 'notProcessed', s => $_->{s} }
                    if $_->{s} ne '';
            }

            last if $no_match;
        }

        # region I: group 80000 0LnLcLdLg (1sLdLDLve)
        if ($region eq 'I' && /\G80000 /) {
           # TODO
           #while (/\G(?:0(\d{4}))(?: 1(\d{4}))? /gc) {
           #}
        }

=over

=item region IV: B<C<TORNADO/ONE-MINUTE MAXIMUM>> I<x> B<C<KNOTS AT>> I<x> B<C<UTC>>

wind speed for tornado or maximum wind

=back

=cut

        # region IV: group TORNADO/ONE-MINUTE MAXIMUM x KNOTS AT x UTC
        if ($region eq 'IV') {
            # region IV: group TORNADO
            if (m@\G(TORNADO)[ /]@gc) {
                push @s3, { weather => { s => $1, tornado => undef }};
            }

            # region IV: group ONE-MINUTE MAXIMUM x KNOTS AT x UTC
            if (/\G(ONE-MINUTE MAXIMUM ([1-9]\d+) KNOTS AT ($re_hour):($re_min) UTC) /ogc)
            {
                push @s3, { highestMeanSpeed => {
                    s             => $1,
                    timeAt        => { hour => $3, minute => $4 },
                    measurePeriod => { v => 1, u => 'MIN' },
                    wind          => { speed => { v => $2, u => 'KT' }}}};
            }
        }

        $report{section3} = \@s3;
    }

    if (   exists $report{precipInd}{precipIndVal}
        && (   $report{precipInd}{precipIndVal} == 0
            || $report{precipInd}{precipIndVal} == 2)
        && !$have_precip333)
    {
        push @{$report{warning}}, { warningType => 'precipOmitted3' };
    }

    # skip groups until next section
    push @{$report{warning}}, { warningType => 'notProcessed', s => $1 }
        if /\G(.*?) ?(?=\b444 )/gc && $1 ne '';

########################################################################

=head3 Section 4: clouds with base below station level (data for national use, optional)

 N'C'H'H'Ct

=for html <!--

=over

=item B<N'C'H'H'Ct>

=for html --><dl><dt><strong>N'C'H'H'C<sub>t</sub></strong></dt>

data for clouds with base below station level

=back

=cut

    if (/\G444 /gc) {
        my @s4;

        @s4  = ();

        # group N'C'H'H'Ct
        while (m@\G(([\d/])([\d/])(\d\d)(\d)) @gc) {
            my $r;

            $r->{s} = $1;
            $r->{cloudOktas} = _codeTable2700 $2;
            _codeTable0500 $r, $3;

            # WMO-No. 306 Vol I.1, Part A, Section B:
            # H'H' altitude of the upper surface of clouds reported by C', in hundreds of metres
            $r->{cloudTops} = { v => $4 * 100, u => 'M' };
            $r->{cloudTops}{q} = 'isEqualGreater' if $4 == 99;

            # WMO-No. 306 Vol I.1, Part A, Section B:
            # Ct description of the top of cloud whose base is below the level of the station. (code table 0552)
            $r->{cloudTopDescr} = $5;

            push @s4, { cloudBelowStation => $r };
        }

        $report{section4} = \@s4;
    }

    # skip groups until next section
    push @{$report{warning}}, { warningType => 'notProcessed', s => $1 }
        if /\G(.*?) ?(?=\b555 )/gc && $1 ne '';

########################################################################

=head3 Section 5: data for national use (optional)

(partially implemented)

 AT:      1snTxTxTx 6RRR/
 BE:      1snTxTxTx 2snTnTnTn
 CA:      1ssss 2swswswsw 3dmdmfmfm 4fhftftfi
 US land: RECORD* 0ittDtDtD 1snTT snTxTxsnTnTn RECORD* 2R24R24R24R24 44snTwTw 9YYGG
 US sea:  11fff 22fff 3GGgg 4ddfmfm 6GGgg dddfff dddfff dddfff dddfff dddfff dddfff 8ddfmfm 9GGgg
 CZ:      1dsdsfsfs 2fsmfsmfsxfsx 3UU// 5snT5T5T5 6snT10T10T10 7snT20T20T20 8snT50T50T50 9snT100T100T100
 LT:      1EsnT'gT'g (2SnTnTnTn|2snTwTwTw) 3EsnT'gT'g 4E'sss 52snT2T2 530f12f12 6RRRtR 7R24R24R24/ 88R24R24R24
 RU:      1EsnT'gT'g 2snTnTnTn 3EsnTgTg 4E'sss (5snT24T24T24) (52snT2T2) (530f12f12) 7R24R24R24/ 88R24R24R24

=cut

# TODO:
    # WMO-No. 306 Vol II, Chapter VI, Section D:
    #   AR: 1P´HP´HP´HP´H 2CVCVCVCV 3FRFRFRFR 4EVEVEVEV 5dxdxfxfx 55fxfxfx 6HeHeHeIv 64HhHhHh 65HhHhHh 66TsTsTs 67TsTsTs 68Dvhvhv 7dmdmfmfm 74HhHhHh 77fmfmfm 8HmHmHnHn 9RsRsRsRs
    #   NL: 2snTnTnTn 4snTgTgTg 511ff 512ff 51722 518wawa 53QhQhQh 5975Vm
    #   NO: 0Stzfxfx 1snT'xT'xT'x 2snT'nT'nT'n 3snTgTgTg 4RTWdWdWd
    # other sources:
    #   DE excl. 10320: 0snTBTBTB 1R1R1R1r 2snTmTmTm 22fff 23SS24WRtR 25wzwz26fff 3LGLGLsLs 4RwRwwzwz 5s's's'tR 7h'h'ZD' 8Ns/hshs 910ff 911ff 921ff PIC INp BOT hesnTTT 80000 1RRRRWR 2SSSS 3fkfkfk 4fxkfxkfxk 5RwRw 6VAVAVBVBVCVC 7snTxkTxkTxk 8snTnkTnkTnk 9snTgTgTgsTg
    #   UK and 10320: 7/VQN
    #   CH: 1V'f'/V'f''f'' 2snTwTwTw iiirrr
    #   MD: 8xxxx

    # WMO-No. 306 Vol II, Chapter VI, Section D:
    if ($country eq 'AR' && /\G555 /gc) {
        my @s5;

        @s5  = ();

        # TODO

        $report{section5} = \@s5;
    }

    # WMO-No. 306 Vol II, Chapter VI, Section D:
    if ($country eq 'AT' && /\G555 /gc) {
        my @s5;

        @s5  = ();

=for html <!--

=over

=item AT: B<C<1>snTxTxTx>

=for html --><dl><dt>AT: <strong><code>1</code>s<sub>n</sub>T<sub>x</sub>T<sub>x</sub>T<sub>x</sub></strong></dt>

maximum temperature on the previous day from 06:00 to 18:00 UTC

=back

=cut

        # AT: group 1snTxTxTx
        if (m@\G(1(?:([01]\d{3})|////)) @gc) {
            my $r;

            $r->{s} = $1;
            if (defined $2) {
                $r->{temp} = _parseTemp $2;
                $r->{timePeriod} = '12h18p';
            } else {
                $r->{notAvailable} = undef;
            }
            push @s5, { tempMax => $r };
        }

=over

=item AT: B<C<6>RRRC</>>

amount of precipitation on the previous day from 06:00 to 18:00 UTC

=back

=cut

        # AT: group 6RRR/
        if (m@\G(6(\d{3}|///)/)@gc) {
            my $r;

            $r = _codeTable3590 $2;
            $r->{s} = $1;
            $r->{timePeriod} = '12h18p' unless exists $r->{notAvailable};
            push @s5, { precipitation => $r };
        }

        $report{section5} = \@s5;
    }

    if ($country eq 'BE' && /\G555 /gc) {
        my @s5;

        @s5  = ();

=for html <!--

=over

=item BE: B<C<1>snTxTxTx>

=for html --><dl><dt>BE: <strong><code>1</code>s<sub>n</sub>T<sub>x</sub>T<sub>x</sub>T<sub>x</sub></strong></dt>

maximum temperature on the next day from 00:00 to 24:00 UTC

=back

=cut

        # BE: group 1snTxTxTx
        if (m@\G(1(?:([01]\d{3})|////)) @gc) {
            my $r;

            $r->{s} = $1;
            if (defined $2) {
                $r->{temp} = _parseTemp $2;
                $r->{timePeriod} = 'p';
            } else {
                $r->{notAvailable} = undef;
            }
            push @s5, { tempMax => $r };
        }

=for html <!--

=over

=item BE: B<C<2>snTnTnTn>

=for html --><dl><dt>BE: <strong><code>2</code>s<sub>n</sub>T<sub>n</sub>T<sub>n</sub>T<sub>n</sub></strong></dt>

minimum temperature on the next day from 00:00 to 24:00 UTC

=back

=cut

        # BE: group 2snTnTnTn
        if (m@\G(2(?:([01]\d{3})|////)) @gc) {
            my $r;

            $r->{s} = $1;
            if (defined $2) {
                $r->{temp} = _parseTemp $2;
                $r->{timePeriod} = 'p';
            } else {
                $r->{notAvailable} = undef;
            }
            push @s5, { tempMin => $r };
        }
        $report{section5} = \@s5;
    }

    if ($country eq 'CA' && /\G555 /gc) {         # MANOBS 12.5
        my @s5;

        @s5  = ();

=over

=item CA: B<C<1>ssss>

amount of snowfall, in tenths of a centimeter,
for the 24-hour period ending at 06:00 UTC

=back

=cut

        # CA: group 1ssss
        if (m@\G(1(?:(\d{4})|////)) @gc) {
            my $r;

            $r->{s} = $1;
            $r->{timePeriod} = '24h06';
            if (!defined $2) {
                $r->{noMeasurement} = undef;
            } elsif ($2 == 9999) {
                $r->{precipTraces} = undef;
            } else {
                $r->{precipAmount} =
                                   { v => sprintf('%.1f', $2 / 10), u => 'CM' };
            }
            push @s5, { snowFall => $r };
        }

=for html <!--

=over

=item CA: B<C<2>swswswsw>

=for html --><dl><dt>CA: <strong><code>2</code>s<sub>w</sub>s<sub>w</sub>s<sub>w</sub>s<sub>w</sub></strong></dt>

amount of water equivalent, in tenths of a millimeter,
for the 24-hour snowfall ending at 06:00 UTC

=back

=cut

        # CA: group 2swswswsw
        if (m@\G(2(?:(\d{4})|////)) @gc) {
            my $r;

            $r->{s} = $1;
            $r->{timePeriod} = '24h06';
            if (!defined $2) {
                $r->{noMeasurement} = undef;
            } elsif ($2 == 9999) {
                $r->{precipTraces} = undef;
            } else {
                $r->{precipAmount} =
                                   { v => sprintf('%.1f', $2 / 10), u => 'MM' };
            }
            push @s5, { waterEquivOfSnow => $r };
        }

=for html <!--

=over

=item CA: B<C<3>dmdmfmfm>

=for html --><dl><dt>CA: <strong><code>3</code>d<sub>m</sub>d<sub>m</sub>f<sub>m</sub>f<sub>m</sub></strong></dt>

maximum (mean or gust) wind speed, in knots,
for the 24-hour period ending at 06:00 UTC and its direction

=back

=cut

        # CA: group 3dmdmfmfm
        if (m@\G(3(?:(\d\d|//)(\d\d)|////)) @gc) {
            my $r;

            $r->{s} = $1;
            $r->{timePeriod} = '24h06';
            if (!defined $2) {
                $r->{wind}{notAvailable} = undef;
            } else {
                if ($2 eq '//') {
                    $r->{wind}{dirNotAvailable} = undef;
                } else {
                    $r->{wind}{dir} = { rp => 4, rn => 5 } unless $winds_est;
                    $r->{wind}{dir} = $2 * 10;
                }
                $r->{wind}{speed} = { v => $3, u => 'KT' };
                $r->{wind}{isEstimated} = undef if $winds_est;
            }
            push @s5, { highestWind => $r };
            $r = undef;

=for html <!--

=over

=item CA: B<C<4>fhftftfi>

=for html --><dl><dt>CA: <strong><code>4</code>f<sub>h</sub>f<sub>t</sub>f<sub>t</sub>f<sub>i</sub></strong></dt>

together with the previous group, the hundreds digit of the maximum wind speed
(in knots), the time of occurrence of the maximum wind speed, and the speed
range of the maximum two-minute mean wind speed,
for the 24-hour period ending at 06:00 UTC and its direction

=back

=cut

            # CA: group 4fhftftfi
            if (m@\G4([01/])($re_hour|//)([0-3/]) @ogc) {
                if ($1 eq '/') {
                    $r->{notAvailable} = undef;
                } else {
                    $r->{speed} = {
                        v => 100,
                        u => 'KT',
                        $1 == 0 ? (q => 'isLess') : (q => 'isEqualGreater')
                    };
                }
                push @s5, { highestWind => {
                    s          => "4$1$2",
                    wind       => $r,
                    timePeriod => '24h06',
                    $2 ne '//' ? (timeAt => { hour => $2 }) : ()
                }};
                $r = undef;

                if ($3 eq '/') {
                    $r->{notAvailable} = undef;
                } elsif ($3 == 0) {
                    $r->{speed} = { v => 17, u => 'KT', q => 'isLess' };
                } elsif ($3 == 1) {
                    $r->{speed} = { v => 17, rp => 11, u => 'KT' };
                } elsif ($3 == 2) {
                    $r->{speed} = { v => 28, rp => 6, u => 'KT' };
                } else {
                    $r->{speed} = { v => 34, u => 'KT',
                                    q => 'isEqualGreater' };
                }
                push @s5, { highestMeanSpeed => {
                    s             => $3,
                    timePeriod    => '24h06',
                    measurePeriod => { v => 2, u => 'MIN' },
                    wind          => $r,
                }};
            }
        }
        $report{section5} = \@s5;
    }

    # WMO-No. 306 Vol II, Chapter VI, Section D:
    if ($country eq 'NL' && /\G555 /gc) {
        my @s5;

        @s5  = ();

        # TODO

        $report{section5} = \@s5;
    }

    # WMO-No. 306 Vol II, Chapter VI, Section D:
    if ($country eq 'NO' && /\G555 /gc) {
        my @s5;

        @s5  = ();

        # TODO

        $report{section5} = \@s5;
    }

    if ($country eq 'US' && /\G555 /gc) {         # FMH-2 7.
        my @s5;

        @s5  = ();

        if ($report{obsStationType}{stationType} eq 'AAXX') {

=over

=item US land: B<RECORD>

indicator for temperature record(s)

=back

=cut

            # US land: group RECORD
            while (/\G($re_record_temp) /ogc) {
                push @s5, { recordTemp => _getRecordTemp $1 };
            }

=for html <!--

=over

=item US land: B<C<0>ittDtDtD>

=for html --><dl><dt>US land: <strong><code>0</code>i<sub>t</sub>t<sub>D</sub>t<sub>D</sub>t<sub>D</sub></strong></dt>

tide data

=back

=cut

            # US land: group 0ittDtDtD
            if (m@\G(0(?:([134679])(\d{3})|([258])000|0///)) @gc) {
                my $r;

                $r->{s} = $1;
                if (!defined $2 && !defined $4) {
                    $r->{notAvailable} = undef;
                } else {
                    my $type = ((defined $2 ? $2 : $4) - 1) / 3;
                    $r->{tideType} = qw(low neither high)[$type];
                    if (defined $2) {
                        $r->{tideDeviation} = { v => $3 + 0, u => 'FT' };
                        if ($2 % 3 == 1) {
                            $r->{tideDeviation}{v} *= -1;
                            $r->{tideLevel} = 'below';
                        } else {
                            $r->{tideLevel} = 'above';
                        }
                    } else {
                        $r->{tideDeviation} = { v => 0, u => 'FT' };
                        $r->{tideLevel} = 'equal';
                    }
                }
                push @s5, { tideData => $r };
            }

=for html <!--

=over

=item US land: B<C<1>snTT snTxTxsnTnTn RECORD* C<2>R24R24R24R24>

=for html --><dl><dt>US land: <strong><code>1</code>s<sub>n</sub>TT s<sub>n</sub>T<sub>x</sub>T<sub>x</sub>s<sub>n</sub>T<sub>n</sub>T<sub>n</sub> RECORD* <code>2</code>R<sub>24</sub>R<sub>24</sub>R<sub>24</sub>R<sub>24</sub></strong></dt>

city data: temperature, maximum and minimum temperature, indicator for
temperature record(s), precipitation last 24 hours

=back

=cut

            # US land: groups: 1snTT snTxTxsnTnTn RECORD* 2R24R24R24R24
            if (m@\G1([01])(\d\d) ([01])(\d\d)([01])(\d\d)((?: $re_record_temp)*) 2(\d{4}) @ogc)
            {
                my ($tempAirF, $r);

                $tempAirF = $report{temperature}{air}{temp}{v} * 1.8 + 32
                    if    exists $report{temperature}
                       && exists $report{temperature}{air}
                       && exists $report{temperature}{air}{temp};

                # ... group 1snTT
                push @s5, { tempCity => _getTempCity("1", $1, $2, $tempAirF) };

                # ... group snTxTx
                $r = _getTempCity "", $3, $4, $tempAirF;
                if ($obs_hour == 0) {
                    $r->{timeBeforeObs} = { hours => 12 };
                } elsif ($obs_hour == 12) {
                    $r->{timePeriod} = 'p';
                } else {
                    $r->{timeBeforeObs} = { notAvailable => undef };
                }
                push @s5, { tempCityMax => $r };

                # ... group snTnTn
                $r = _getTempCity "", $5, $6, $tempAirF;
                if ($obs_hour == 0) {
                    $r->{timeBeforeObs} = { hours => 18 };
                } elsif ($obs_hour == 12) {
                    $r->{timeBeforeObs} = { hours => 12 };
                } else {
                    $r->{timeBeforeObs} = { notAvailable => undef };
                }
                push @s5, { tempCityMin => $r };

                # ... group 2R24R24R24R24
                $r = { precipCity => {
                    s             => "2$8",
                    timeBeforeObs => { hours => 24 },
                    precipAmount  => { v => sprintf('%.2f', $8 / 100), u =>'IN'}
                }};

                # ... group RECORD
                for ($7 =~ /$re_record_temp/og) {
                    push @s5, { recordTempCity => _getRecordTemp $_ };
                }

                push @s5, $r;
            }

=for html <!--

=over

=item US land: B<C<44>snTwTw>

=for html --><dl><dt>US land: <strong><code>44</code>s<sub>n</sub>T<sub>w</sub>T<sub>w</sub></strong></dt>

water temperature

=back

=cut

            # US land: group 44snTwTw
            if (/\G(44([01]\d\d)) /gc) {
                push @s5, { waterTemp => {
                    s    => $1,
                    temp => _parseTemp "$2/"
                }};
            }

=over

=item US land: B<C<9>YYGG>

additional day and hour of observation (repeated from Section 0)

=back

=cut

            # US land: group 9YYGG
            if (/\G(9($re_day)($re_hour)) /ogc) {
                push @s5, { obsTime => {
                    s      => $1,
                    timeAt => { day => $2, hour => $3 }
                }};
            }
        } elsif ($report{obsStationType}{stationType} eq 'BBXX') {

=over

=item US sea: B<C<11>fff C<22>fff>

equivalent wind speeds at 10 and 20 meters

=back

=cut

            # US sea: groups 11fff 22fff
            if (/\G11(\d\d)(\d) 22(\d\d)(\d) /gc) {
                push @s5, { equivWindSpeed => {
                    s      => "11$1$2",
                    wind   => { speed => { v => ($1+0).".$2", u => 'MPS' }},
                    height => { v => 10, u => 'M'}
                }};
                push @s5, { equivWindSpeed => {
                    s      => "22$3$4",
                    wind   => { speed => { v => ($3+0).".$4", u => 'MPS' }},
                    height => { v => 20, u => 'M'}
                }};
            }

=for html <!--

=over

=item US sea: B<C<3>GGgg C<4>ddfmfm>

=for html --><dl><dt>US sea: <strong><code>3</code>GGgg <code>4</code>ddf<sub>m</sub>f<sub>m</sub></strong></dt>

maximum wind speed since the last observation and the time when it occurred

=back

=cut

            # US sea: groups 3GGgg 4ddfmfm
            if (/\G(?:3($re_hour)($re_min) )?4($re_dd)(\d\d) /ogc) {
                push @s5, { peakWind => {
                    s      => (defined $1 ? "3$1$2 " : "") . "4$3$4",
                    wind   => { dir   => $3 * 10,
                                speed => { v => $4 + 0, u => 'MPS' }},
                    defined $1 ? (timeAt => { hour => $1, minute => $2 })
                               : ()
                }};
            }

=over

=item US sea: B<C<6>GGgg>

end time of the latest 10-minute continuous wind measurements

=back

=cut

            # US sea: group 6GGgg
            if (/\G(6($re_hour)($re_min)) /ogc) {
                push @s5, { endOfContWinds => {
                    s      => $1,
                    timeAt => { hour => $2, minute => $3 }
                }};
            }

=over

=item US sea: 6 x B<dddfff>

6 10-minute continuous wind measurements

=back

=cut

            # US sea: 6 x group dddfff
            if (m@\G((?:$re_wind_dir\d\d\d\d |////// ){6})@ogc) {
                for (split ' ', $1) {
                    /(...)(..)(.)/;
                    push @s5, { continuousWind => {
                        s    => $_,
                        wind => $_ eq '//////'
                                    ? { notAvailable => undef }
                                    : { dir   => $1 + 0,
                                        speed => { v => ($2 + 0) . ".$3",
                                                   u => 'MPS' }
                                    }
                    }};
                }
            }

=for html <!--

=over

=item US sea: B<C<8>ddfmfm C<9>GGgg>

=for html --><dl><dt>US sea: <strong><code>8</code>ddf<sub>m</sub>f<sub>m</sub> <code>9</code>GGgg</strong></dt>

highest 1-minute wind speed and the time when it occurred

=back

=cut

            # US sea: groups 8ddfmfm 9GGgg
            if (m@\G(8($re_dd|//)(\d\d) 9($re_hour)($re_min)) @ogc) {
                push @s5, { highestMeanSpeed => {
                    s             => $1,
                    measurePeriod => { v => 1, u => 'MIN' },
                    timeAt        => { hour => $4, minute => $5 },
                    wind          => { speed => { v => $3 + 0, u => 'MPS' },
                                       $2 eq '//' ? (dirNotAvailable => undef)
                                                  : (dir             => $2 * 10)
                }}};
            }
        }

        $report{section5} = \@s5;
    }

    # http://www.wmo.int/pages/prog/www/ISS/Meetings/CT-MTDCF_Geneva2005/Doc5-1(3).doc
    if ($country eq 'CZ' && /\G555 /gc) {
        my @s5;

        @s5  = ();

=for html <!--

=over

=item CZ: B<C<1>dsdsfsfs>

=for html --><dl><dt>CZ: <strong><code>1</code>d<sub>s</sub>d<sub>s</sub>f<sub>s</sub>f<sub>s</sub></strong></dt>

wind direction and speed from tower measurement

=back

=cut

        # CZ: group 1dsdsfsfs
        if (/\G(1($re_dd|00|99)(\d\d)) /ogc) {
            my $r;

            if ($2 == 0) {
                $r->{isCalm} = undef;
            } else {
                if ($2 == 99) {
                    $r->{dirVarAllUnk} = undef;
                } else {
                    $r->{dir} = { v => ($2 % 36) * 10, rp => 4, rn => 5 };
                }
                if ($windUnit) {
                    $r->{speed} = { v => $3 + 0, u => $windUnit };
                } else {
                    $r->{speedNotAvailable} = undef;
                }
            }
            push @s5, { windAtLoc => {
                s            => $1,
                windLocation => 'TWR',
                wind         => $r
            }};
        }

=for html <!--

=over

=item CZ: B<C<2>fsmfsmfsxfsx>

=for html --><dl><dt>CZ: <strong><code>2</code>f<sub>sm</sub>f<sub>sm</sub>f<sub>sx</sub>f<sub>sx</sub></strong></dt>

maximum wind gust speed over 10 minute period and the period W1W2

=back

=cut

        # CZ: group 2fsmfsmfsxfsx
        if (/\G2(\d\d)(\d\d) /gc) {
            push @s5, { highestGust => {
                s      => "2$1",
                wind   => {
                          $windUnit ? (speed => { v => $1 + 0, u => $windUnit })
                                    : (speedNotAvailable => undef)
                },
                measurePeriod => { v => 10, u => 'MIN' }
            }};
            push @s5, { highestGust => {
                s      => $2,
                wind   => {
                          $windUnit ? (speed => { v => $2 + 0, u => $windUnit })
                                    : (speedNotAvailable => undef)
                },
                timeBeforeObs => { hours => $period }
            }};
        }

=over

=item CZ: B<C<3>UUC<//>>

relative humidity

=back

=cut

        # CZ: group 3UU//
        if (m@\G3(\d\d)// @gc) {
            push @s5, { RH => {
                s        => "3$1//",
                relHumid => $1 + 0
            }};
        }

=for html <!--

=over

=item CZ: B<C<5>snT5T5T5 C<6>snT10T10T10 C<7>snT20T20T20 C<8>snT50T50T50 C<9>snT100T100T100>

=for html --><dl><dt>CZ: <strong><code>5</code>s<sub>n</sub>T<sub>5</sub>T<sub>5</sub>T<sub>5</sub> <code>6</code>s<sub>n</sub>T<sub>10</sub>T<sub>10</sub>T<sub>10</sub> <code>7</code>s<sub>n</sub>T<sub>20</sub>T<sub>20</sub>T<sub>20</sub> <code>8</code>s<sub>n</sub>T<sub>50</sub>T<sub>50</sub>T<sub>50</sub> <code>9</code>s<sub>n</sub>T<sub>100</sub>T<sub>100</sub>T<sub>100</sub></strong></dt>

soil temperature at the depths of 5, 10, 20, 50, and 100 cm

=back

=cut

        # CZ: groups 5snT5T5T5 6snT10T10T10 7snT20T20T20 8snT50T50T50 9snT100T100T100
        for my $i (5, 6, 7, 8, 9) {
            if (/\G$i([01]\d\d\d) /gc) {
                push @s5, { soilTemp => {
                    s     => "$i$1",
                    depth => { v => ( 5, 10, 20, 50, 100 )[$i - 5], u => 'CM' },
                    temp  => _parseTemp $1
                }};
            }
        }

        $report{section5} = \@s5;
    }

    # TODO: MD: 8xxxx (ionising radiation [mSv/h])
    # http://meteoclub.ru/index.php?action=vthread&forum=7&topic=3990&page=1#2
    if ($country eq 'MD' && /\G555 /gc) {
        my @s5;

        @s5  = ();

        $report{section5} = \@s5;
    }

    # RU: http://www.meteoinfo.ru/images/misc/kn-01-synop.pdf (2012)
    #     http://www.meteo.parma.ru/doc/serv/kn01.shtml
    # LT: http://www.hkk.gf.vu.lt/nauja/apie_mus/publikacijos/Praktikos_darbai_stanku.pdf (2011)
    if ($country =~ /KZ|LT|RU/ && /\G555 /gc) {
        my @s5;

        @s5  = ();

=for html <!--

=over

=item LT, RU: B<C<1>EsnT'gT'g>

=for html --><dl><dt>LT, RU: <strong><code>1</code>Es<sub>n</sub>T'<sub>g</sub>T'<sub>g</sub></strong></dt>

state of the ground without snow or measurable ice cover, temperature of the
ground surface

=back

=cut

        # LT, RU: group 1EsnT'gT'g
        if (m@\G(1([\d/]))([01]\d\d) @gc) {
            my $r;

            $r->{s} = $1;
            if ($2 eq '/') {
                $r->{notAvailable} = undef;
            } else {
                $r->{stateOfGroundVal} = $2;
            }
            push @s5, { stateOfGround => $r };
            $r = undef;

            $r->{s} = $3;
            $r->{depth} = { v => 0, u => 'CM' };
            $r->{temp} = _parseTemp "${3}0";
            $r->{temp}{v} += 0;
            push @s5, { soilTemp => $r };
        }

=for html <!--

=over

=item LT, RU: B<C<2>snTnTnTn>

=for html --><dl><dt>LT, RU: <strong><code>2</code>s<sub>n</sub>T<sub>n</sub>T<sub>n</sub>T<sub>n</sub></strong></dt>

minimum temperature last night

=back

=cut

        # LT, RU: group 2snTnTnTn
        if (m@\G(2(?:([01]\d{3})|[01/]///)) @gc) {
            my $r;

            $r->{s} = $1;
            if (defined $2) {
                $r->{temp} = _parseTemp $2;
            } else {
                $r->{notAvailable} = undef;
            }
            push @s5, { tempMinNighttime => $r };
        }

=for html <!--

=over

=item LT, RU: B<C<3>EsnTgTg>

=for html --><dl><dt>LT, RU: <strong><code>3</code>Es<sub>n</sub>T<sub>g</sub>T<sub>g</sub></strong></dt>

state of the ground without snow or measurable ice cover, minimum temperature
of the ground surface last night

=back

=cut

        # LT, RU: group 3EsnTgTg
        if (m@\G3([\d/])([01]\d\d) @gc) {
            my $r;

            $r->{s} = "3$1";
            if ($1 eq '/') {
                $r->{notAvailable} = undef;
            } else {
                $r->{stateOfGroundVal} = $1;
            }
            push @s5, { stateOfGround => $r };
            $r = undef;

            $r->{s} = $2;
            $r->{depth} = { v => 0, u => 'CM' };
            $r->{temp} = _parseTemp "${2}0";
            $r->{temp}{v} += 0;
            $r->{timePeriod} = 'n';
            push @s5, { soilTempMin => $r };
        }

=over

=item LT, RU: B<C<4>E'sss>

state of the ground if covered with snow or ice, snow depth

=back

=cut

        # LT, RU: group 4E'sss
        if (m@\G4([\d/])(///|\d{3}) @gc) {
            my $r;

            $r->{s} = "4$1";
            if ($1 eq '/') {
                $r->{notAvailable} = undef;
            } else {
                $r->{stateOfGroundSnowVal} = $1;
            }
            push @s5, { stateOfGroundSnow => $r };
            $r = undef;

            # WMO-No. 306 Vol I.1, Part A, code table 3889:
            $r->{s} = $2;
            if ($2 eq '///') {
                $r->{notAvailable} = undef;
            } elsif ($2 eq '000') {
                $r->{invalidFormat} = $2;
            } elsif ($2 eq '997') {
                $r->{precipAmount} = { v => 0.5, u => 'CM', q => 'isLess' };
            } elsif ($2 eq '998') {
                $r->{coverNotCont} = undef;
            } elsif ($2 eq '999') {
                $r->{noMeasurement} = undef;
            } else {
                $r->{precipAmount} = { v => $2 + 0, u => 'CM' };
            }
            push @s5, { snowDepth => $r };
        }

        # TODO: RU: 5snT24T24T24 (average air temperature previous day)
        if (m@\G(5[01][\d/]{3}) @gc) {
            push @{$report{warning}},
                                     { warningType => 'notProcessed', s => $1 };
        }

=for html <!--

=over

=item LT, RU: B<C<52>snT2T2>

=for html --><dl><dt>LT, RU: <strong><code>52</code>s<sub>n</sub>T<sub>2</sub>T<sub>2</sub></strong></dt>

minimum air temperature at 2 cm last 12 hours (last night)

=back

=cut

        # LT, RU: 52snT2T2
        if (m@\G(52([01]\d\d)) @gc) {
            my $r;

            $r->{s} = $1;
            $r->{height} = { v => 2, u => 'CM' };
            $r->{temp} = _parseTemp "${2}0";
            $r->{temp}{v} += 0;
            $r->{timeBeforeObs} = { hours => 12 };
            push @s5, { tempMinGround => $r };
        }

=for html <!--

=over

=item LT, RU: B<C<530>f12f12>

=for html --><dl><dt>LT, RU: <strong><code>530</code>f<sub>12</sub>f<sub>12</sub></strong></dt>

maximum wind gust speed im the last 12 hours

=back

=cut

        # LT, RU: 530f12f12
        if (m@\G(530(\d\d)) @gc) {
            push @s5, { highestGust => {
                s      => $1,
                wind   => {
                          $windUnit ? (speed => { v => $2 + 0, u => $windUnit })
                                    : (speedNotAvailable => undef)
                },
                timeBeforeObs => { hours => 12 }
            }};
        }

=for html <!--

=over

=item LT, RU: B<C<6>RRRtR>

=for html --><dl><dt>LT, RU: <strong><code>6</code>RRRt<sub>R</sub></strong></dt>

amount of precipitation for given period

=back

=cut

        # LT, RU: group 6RRRtR
        if (m@\G(6(\d{3})(\d)) @gc) {
            my $r;

            $r = _codeTable3590 $2;
            $r->{s} = $1;
            $r->{timeBeforeObs} = _codeTable4019 $3;
            push @s5, { precipitation => $r };
        }

=for html <!--

=over

=item LT, RU: B<C<7>R24R24R24C</>>

=for html --><dl><dt>LT, RU: <strong><code>7</code>R<sub>24</sub>R<sub>24</sub>R<sub>24</sub><code>/</code></strong></dt>

amount of precipitation in the last 24 hours

=back

=cut

        # LT, RU: group 7R24R24R24/
        if (m@\G(7(\d{3})/) @gc) {
            my $r;

            $r = _codeTable3590 $2;
            $r->{s} = $1;
            $r->{timeBeforeObs} = { hours => 24 };
            push @s5, { precipitation => $r };
        }

=for html <!--

=over

=item LT, RU: B<C<88>R24R24R24>

=for html --><dl><dt>LT, RU: <strong><code>88</code>R<sub>24</sub>R<sub>24</sub>R<sub>24</sub></strong></dt>

amount of precipitation in the last 24 hours if >=30 mm (to confirm the values
in 7R24R24R24/)

=back

=cut

        # LT, RU: group 88R24R24R24
        if (m@\G(88(\d{3})) @gc) {
            push @s5, { precipitation => {
                s             => $1,
                timeBeforeObs => { hours => 24 },
                precipAmount  => { v => $2 + 0, u => 'MM' }
            }};
        }

# TODO: 912ff (maximum wind speed since 12 hours (or previous day?, but reported
# at 00 and 12)
# http://meteoclub.ru/index.php?action=vthread&forum=7&topic=3990#20

        $report{section5} = \@s5;
    }

    # TODO: section 6 DE: 666 1snTxTxTx 2snTnTnTn 3snTnTnTn 6VMxVMxVMxVMx 7VMVMVMVM 80000 0RRRrx 1RRRrx 2RRRrx 3RRRrx 4RRRrx 5RRRrx
    # TODO: section 9 DE: 999 0dxdxfxfx 2snTgTgTg 3E/// 4E'/// 7RRRzR

    push @{$report{warning}}, { warningType => 'notProcessed', s => $1 }
        if /\G(.+) $/;

    return %report;
}

########################################################################
# _parseSao
########################################################################
sub _parseSao {
    my $default_msg_type = shift;
    my (%report, $msg_hdr, @cy, $is_auto, $has_lt);

    $report{msg} = $_;
    $report{isSpeci} = undef if $default_msg_type eq 'SPECI';
    $report{version} = VERSION();

    if (/^ERROR -/) {
        pos $_ = 0;
        $report{ERROR} = _makeErrorMsgPos 'other';
        return %report;
    }

=head2 Parsing of SAO messages

SAO (Surface Aviation Observation) was the official format of aviation weather
reports until 1996-06-03. However, it is still (as of 2012) used by some
automatic stations in Canada (more than 600) and in the US (PACZ, PAEH, PAIM,
PALU, PATC, PATL), being phased out).

=head3 Observational data for aviation requirements

 CA: III (SA|SP|RS) GGgg AUTOi <sky> V.VI PPI PPP/TT/TdTd/ddff(+fmfm)/AAA/RRRR (remarks) appp TTdOA
 US: CCCC (SA|SP|RS) GGgg AWOS <sky> V PPI TT/TdTd/ddff(Gfmfm)/AAA (remarks)

If the delimiter is a 'C<E<lt>>' (less than) instead of a 'C</>' (slash), the
parameter exceeds certain quality control soft limits.

=cut

    # temporarily remove and store keyword for message type
    $msg_hdr = '';
    $msg_hdr = $1
        if s/^(METAR |SPECI )//;

    # EXTENSION: preprocessing
    # remove trailing =
    s/ ?=$//;

    $_ .= ' '; # this makes parsing much easier

    # restore keyword for message type
    $_ = $msg_hdr . $_;
    pos $_ = length $msg_hdr;

    # warn about modification
    push @{$report{warning}}, { warningType => 'msgModified',
                                s           => $_ }
        if $report{msg} . ' ' ne $_;

=over

=item CA: B<III>

reporting station (ICAO location indicator without leading C<C>)

=item US: B<CCCC>

reporting station (ICAO location indicator)

=back

=cut

    if (!/\G($re_ICAO) /ogc) {
        $report{ERROR} = _makeErrorMsgPos 'obsStation';
        return %report;
    }
    $report{obsStationId}{id} = $1;
    $report{obsStationId}{s} = $1;

    @cy = $report{obsStationId}{id} =~ /(((.).)..)/;
    $cy[2] = 'cCA' if _cyInString \@cy, ' C ';
    $cy[2] = 'cUS' if _cyInString \@cy, ' K P ';

=over

=item optional: B<C<NIL>>

message contains no observation data, end of message

=back

=cut

    if (/\GNIL $/) {
        $report{reportModifier}{s} =
            $report{reportModifier}{modifierType} = 'NIL';
        return %report;
    }

=over

=item B<C<SA>> |  B<C<RS>> |  B<C<SP>>

report type:

=over

=item C<SA>

Record Observation, scheduled

=item C<RS>

(Record Special) on significant change in weather

=item C<SP>

(Special), observation taken between Record Observations on significant change
in weather

=back

=item B<GGgg>

hour, minute of observation

=back

=cut

    if (!/\G(S[AP]|RS)(?: (COR))? ($re_hour)($re_min) /ogc) {
        $report{ERROR} = _makeErrorMsgPos 'obsTime';
        return %report;
    }
    $report{isSpeci} = undef unless $1 eq 'SA';
    push @{$report{reportModifier}}, { s => $2, modifierType => $2 }
        if defined $2;
    $report{obsTime} = {
        s      => "$3$4",
        timeAt => { hour => $3, minute => $4 }
    };

=over

=item CA: B<C<AUTO>i>

station type:

=over

=item C<AUTO1>

MARS I

=item C<AUTO2>

MARS II

=item C<AUTO3>

MAPS I

=item C<AUTO4>

MAPS II

=item C<AUTO7>

non-AES automatic station

=item C<AUTO8>

other AES automatic station

=back

=item US: B<C<AWOS>>

=back

=cut

    if (/\G(AUTO\d?|AWOS) /gc) {
        push @{$report{reportModifier}}, { s => $1, modifierType => 'AUTO' };
        $is_auto = 1;
    }

=over

=item sky

can be C<M> or C<MM> (missing), C<CLR> or C<CLR BLO ...>, C<W...> (vertical
visibility), or optionally C<X> or C<-X> (sky (partially) obstructed) and one or
more cloud groups. If the height is prefixed by C<E> or C<M>, this is the
estimated or measured ceiling. If the height is suffixed by C<V> it is variable.
If the cloud cover is prefixed by C<->, the cover is thin.

=back

=cut

    if (/\G(MM?) /gc) {
        $report{cloud} = { s => $1, notAvailable => undef };
    } elsif (/\G(CLR BLO \d+) /gc) {
        $report{cloud} = {
            s        => $1,
            noClouds => 'NCD'
        };
    } elsif (/\G(CLR) /gc) {
        $report{cloud} = {
            s        => $1,
            noClouds => $1
        };
    } else {
        while (   /\G([MABE]?)(\d+)(V?) (-?)($re_cloud_cov) /ogc
               || /\G(?:([APW]?)(\d+) )?(-?X) /gc)
        {
            if (defined $5) {
                my $r;
                $r = _parseCloud $5 . sprintf("%03d", $2), \@cy, $4 eq '-',
                                 $1 eq 'E' ? $1 : $3;
                $r->{s} = "$1$2$3 $4$5";
                $r->{isCeiling} = undef if $1;
                push @{$report{cloud}}, $r;
            } else {
                $report{visVert} = {
                    s        => "$1$2",
                    # CA: MANOBS 10.2.8.6: actually multiples of 30 m
                    distance => { v => $2 * 100, (rp => 100), u => 'FT' }
                }
                    if defined $2;
                $report{skyObstructed} = {
                    s => $3,
                    $3 eq '-X' ? (q => 'isPartial') : ()
                };
            }
        }
    }

=for html <!--

=over

=item CA: B<V.VI>

=for html --><dl><dt>CA: <strong>V.V<sub>I</sub></strong></dt>

prevailing visibility (in SM), optionally with tenths. Optionally, B<I> can be
C<V> (variable) or C<+> (greater than).

=item US: B<V>

prevailing visibility (in SM), optionally with fractions of SM

=back

=cut

    if (/\GM /gc) {
        $report{visPrev} = { s => 'M', notAvailable => undef };
    } else {
        if (/\G(\d+\.\d?)([V+]?) ?/ogc) {
            $report{visPrev} = {
                s        => "$1$2",
                distance => {
                    v => $1,
                    u => 'SM',
                    $2 eq 'V' ? (q => 'isVariable') : (),
                    $2 eq '+' ? (q => 'isGreater') : ()
                }
            };
            $report{visPrev}{distance}{v} =~ s/\.$//;
        } elsif (/\G($re_vis_sm)(V?) ?/ogc) {
            $report{visPrev} = _getVisibilitySM $1, $is_auto, \@cy;
            if ($2) {
                delete $report{visPrev}{distance}{rp}
                    if exists $report{visPrev}{distance}{rp};
                # TODO?: if reported together with M1/4 this overwrites @q
                $report{visPrev}{distance}{q} = 'isVariable';
            }
            $report{visPrev}{s} = "$1$2";
        }
    }

=for html <!--

=over

=item PPI

=for html --><dl><dt><strong>PP<sub>I</sub></strong></dt>

groups to describe the present weather: precipitation (C<L>, C<R>, C<S>, C<SG>,
C<IP>, C<A>, C<S>C<P>, C<IN>, C<U>), obscuration (C<F>, C<K>, C<BD>, C<BN>,
C<H>) or other (C<PO>, C<Q>, C<T>).
Certain precipitation and duststorm can have the intentsity (C<+>, C<-> or
C<-->) appended.

=back

=cut

    if (/\GM /gc) {
        $report{weather} = { s => 'M', notAvailable => undef };
    } else {
        #   R R- R+ ZR ZR- ZR+ RW RW- RW+
        #   L L- L+ ZL ZL- ZL+
        #   S S- S+            SW SW- SW+
        #   A A- A+
        #   T
        #   IP IP- IP+         IPW IPW- IPW+
        #   SG SG- SG+
        #   SP SP- SP+         SPW
        #   BN BN+
        #   BS BS+
        #   BD BD+
        #   IC IC- IC+
        #   H K D F Q V
        #   IF IN AP PO UP GF BY

        # from www.nco.ncep.noaa.gov/pmb/.../gemlib/pt/ptwcod.f (nawips.tar)
        while (   /\G((TORNA|FUNNE|WATER|BD\+?|IF|IN|AP|PO|U?P|GF|BY|[THKDFQ])()()()) ?/gc
               || /\G((B[SN]()())(\+?)) ?/gc
               || /\G((S[GP]|IC|[LA]|(?:R|S|IP)(W?)|(Z)[RL])((?:\+|--?)?)) ?/gc)
        {
            push @{$report{weather}}, {
                s => $1,
                # from www.nco.ncep.noaa.gov/pmb/.../prmcnvlib/pt/ptwsym.f
                # numbers: WMO-No. 306 Vol I.1, Part A, code table 4677
                $2 eq 'TORNA' || $2 eq 'FUNNE' || $2 eq 'WATER' # all 19
                  ? (tornado => {
                      TORNA => 'tornado',
                      FUNNE => 'funnel_cloud',
                      WATER => 'waterspout'
                    }->{$2})
                  : (phenomSpec => {
                      K     => 'FU',     # 4
                      H     => 'HZ',     # 5
                      D     => 'DU',     # 6
                      N     => 'SA', BD => 'DU', BN => 'SA', # 7
                      PO    => 'PO',     # 8
                      F     => 'FG',     # 10
                      GF    => 'FG',     # 12
                      T     => 'TS',     # 17
                      Q     => 'SQ',     # 18
                      'BD+' => 'DS',     # 34
                      BS    => 'SN',     # 38
                      IF    => 'FG',     # 48
                      L     => 'DZ',     # 53
                      ZL    => 'DZ',     # 57
                      R     => 'RA',     # 63
                      ZR    => 'RA',     # 67
                      S     => 'SN',     # 73
                      IN    => 'IC',     # 76
                      SG    => 'SG',     # 77
                      IC    => 'IC',     # 78
                      IP    => 'PL',     # 79
                      RW    => 'RA',     # 81
                      SW    => 'SN',     # 86
                      AP    => 'GS', SPW => 'GS', SP => 'GS', IPW => 'PL', # 88
                      A     => 'GR',     # 90
                    # V     => '??',     # 201 variable visibility
                      BY    => 'PY',     # 202
                      UP    => 'UP', P => 'UP', # 203
                    }->{$2}),
                $3 || $2 eq 'AP' ? (descriptor => 'SH') : (),
                $4 || $2 eq 'IF' ? (descriptor => 'FZ') : (),
                $2 eq 'N' || $2 eq 'BD' || $2 eq 'BN' || $2 eq 'BS' || $2 eq 'BY'
                    ? (descriptor => 'BL') : (),
                $2 eq 'GF' ? (descriptor => 'MI') : (),
                ($5 eq '+' || $2 eq 'BD+') ? (phenomDescr => 'isHeavy') : (),
                $5 eq '-' ? (phenomDescr => 'isLight') : (),
                $5 eq '--' ? (phenomDescr => 'isVeryLight') : ()
            };
        }
    }

=over

=item CA: B<PPP>

mean sea level pressure (in hPa, last 3 digits)

=back

=cut

    ($has_lt) = /\G([^ ]+)/;
    if (!defined $has_lt) {
        $report{ERROR} = _makeErrorMsgPos 'other';
        return %report;
    }
    push @{$report{warning}}, { warningType => 'qualityLimit', s => '' }
        if $has_lt =~ /</;

    if (m@\G(M|(\d\d)(\d))[</](?=(?:(?:M|-?\d+)[</]){2}(?:E?[M\d]{4}))@gc) {
        if (defined $2) {
            if ($2 > 65 || $2 < 45) { # only if within sensible range
                my $slp;

                $slp = "$2.$3";
                # threshold 55 taken from mdsplib
                $slp += $slp < 55 ? 1000 : 900;
                push @{$report{remark}}, { SLP => {
                    s        => $1,
                    pressure =>
                              { v => sprintf('%.1f', $slp), u => 'hPa' }
                }};
            } else {
                push @{$report{remark}}, { SLP => {
                    s => $1,
                    invalidFormat => "no QNH, x$2.$3 hPa"
                }};
            }
        } else {
            push @{$report{remark}}, { SLP => {
                s            => $1,
                notAvailable => undef
            }};
        }
    }

=for html <!--

=over

=item B<TT>C</>B<TdTd>

=for html --><dl><dt><strong>TT</strong><code>/</code><strong>T<sub>d</sub>T<sub>d</sub></strong></dt>

air temperature and dew point temperature (CA: in °C, US: in F). Both or either
can be C<MM> (missing).

=back

=cut

    # temperature in F may have 3 digits (100 F = 37.8 °C)
    if (m@\G((?:M|(-?\d+))[</](?:M|(-?\d+)))[</](?=E?[M\d]{4})@gc) {
        my $temp_unit;

        $temp_unit = _cyInString(\@cy, ' cCA ') ? 'C' : 'F';
        $report{temperature}{s} = $1;
        if (!defined $2) {
            $report{temperature}{air}{notAvailable} = undef;
        } else {
            $report{temperature}{air}{temp} = { v => $2 + 0, u => $temp_unit };
        }

        if (!defined $3) {
            $report{temperature}{dewpoint}{notAvailable} = undef;
        } else {
            $report{temperature}{dewpoint}{temp} =
                                               { v => $3 + 0, u => $temp_unit };
        }

        if (   exists $report{temperature}{air}{temp}
            && exists $report{temperature}{dewpoint}
            && exists $report{temperature}{dewpoint}{temp})
        {
            _setHumidity $report{temperature};
        }
    }

=for html <!--

=over

=item CA: B<ddff>(B<+fmfm>), US: B<ddff>(B<Gfmfm>)

=for html --><dl><dt>CA: <strong>ddff</strong>(<strong><code>+</code>f<sub>m</sub>f<sub>m</sub></strong>), US: <strong>ddff</strong>(<strong><code>G</code>f<sub>m</sub>f<sub>m</sub></strong>)</dt>

wind direction and speed (in KT), optionally gust speed, or C<MMMM> (missing).
If the direction is greater than 50, 100 must be added to the speed(s) and 50
subtracted from the direction.

=back

=cut

    if (!m@\G((E)?(MM|$re_wind_dir|5[1-9]|[67]\d|8[0-6])(MM|\d\d)(?:[+G](\d\d))?)(?=[</])@ogc) {
        $report{ERROR} = _makeErrorMsgPos 'other';
        return %report;
    }
    $report{sfcWind}{s} = $1;
    if ($3 eq 'MM' && $4 eq 'MM') {
        $report{sfcWind}{wind}{notAvailable} = undef;
    } elsif ($3 eq '00' && $4 eq '00' && !defined $5) {
        $report{sfcWind}{wind}{isCalm} = undef;
        $report{sfcWind}{wind}{isEstimated} = undef
            if defined $2;
    } else {
        my $plus_100 = 0;

        if ($3 eq 'MM') {
            $report{sfcWind}{wind}{dirNotAvailable} = undef;
        } else {
            $report{sfcWind}{wind}{dir} = { rp => 4, rn => 5 }
                unless defined $2;
            if ($3 > 50) {
                $plus_100 = 100;
                $report{sfcWind}{wind}{dir}{v} = ($3 - 50) * 10;
            } else {
                $report{sfcWind}{wind}{dir}{v} = $3 * 10;
            }
        }
        if ($4 eq 'MM') {
            $report{sfcWind}{wind}{speedNotAvailable} = undef;
        } else {
            $report{sfcWind}{wind}{speed} = { v => $4 + $plus_100, u => 'KT' };
        }
        $report{sfcWind}{wind}{gustSpeed} = { v => $5 + $plus_100, u => 'KT' }
            if defined $5;
        # US: FMH-1 5.4.3, CA: MANOBS 10.2.15
        $report{sfcWind}{measurePeriod} = { v => 2, u => 'MIN' };
        $report{sfcWind}{wind}{isEstimated} = undef
            if defined $2;
    }

=over

=item B<AAA>

altimeter setting (in hundredths of inHg, last 3 digits), or C<M> (missing)

=back

=cut

    if (m@\G[</] ?(M|([0189])(\d\d))(?=[ </])@gc) {
        if ($1 eq 'M') {
            $report{QNH} = { s => $1, notAvailable => undef };
        } else {
            $report{QNH} = { s => $1, pressure => {
                v => ($2 > 1 ? "2$2" : "3$2") . ".$3",
                u => 'inHg'
            }};
        }
        /\G /gc;
    }

=over

=item CA: B<RRRR>

precipitation since previous main synoptic hour (tenths of mm)

=back

=cut

    if (   _cyInString(\@cy, ' cCA ')
        && (   m@\G[</](M|\d{4}) @gc
            || m@\G[</] (M|\d{4}) (?=(?:.+ )?(?:M|[M0-8]\d{3}) (?:M|-?\d)(?:M|-?\d)[XM0-8]M $)@gc))
    {
        if (defined $1 && $1 eq 'M') {
            push @{$report{remark}},
                { precipitation => { s => $1, notAvailable => undef }};
        } elsif (defined $1) {
            push @{$report{remark}}, { precipitation => {
                s            => $1,
                timeSince    => _timeSinceSynopticMain(
                                  @{$report{obsTime}{timeAt}}{qw(hour minute)}),
                precipAmount => { v => sprintf('%.1f', $1 / 10), u => 'MM' }
            }};
        }
    }

    # end of group with slashes, delete optional trailing slash
    m@\G[</] ?@gc;

=head3 Remarks

There may be remarks, similar to the ones in METAR.

=cut

    if (/\G(PCPN (\d+.\d)MM PAST HR) /gc) {
        push @{$report{remark}}, { precipitation => {
            s             => $1,
            timeBeforeObs => { hours => 1 },
            precipAmount  => { v => sprintf('%.1f', $2), u => 'MM' }
        }};
    }

    if (/\G(PK WND (MM|$re_wind_dir)($re_wind_speed) ($re_hour)($re_min)Z) /ogc)
    {
        push @{$report{remark}}, { peakWind => {
            s      => $1,
            wind   => _parseWind(($2 eq 'MM' ? '///' : "${2}0") . "${3}KT", 1),
            timeAt => { hour => $4, minute => $5 }
        }};
    }

    if (/\G(SOG (\d+)) /gc) {
        push @{$report{remark}}, { snowDepth => {
            s            => $1,
            precipAmount => { v => $2 + 0, u => 'CM' }
        }};
    }

    if (/\G((PRES[FR]R)( PAST HR)?) /gc) {
        my $r;

        $r->{s} = $1;
        $r->{otherPhenom} = $2;
        _parsePhenomDescr $r, 'phenomDescrPost', $3 if defined $3;
        push @{$report{remark}}, { phenomenon => $r };
    }

    if (/\G(VSBY VRBL (\d+(?:\.\d?)?)V(\d+(?:\.\d?)?)(\+?)) /gc) {
        my $r;

        $r = { visVar1 => { s => $1, distance => { v => $2, u => 'SM' }},
               visVar2 => { distance => { v => $3, u => 'SM' }}
        };
        $r->{visVar2}{distance}{q} = 'isGreater'
            if $4;
        $r->{visVar1}{distance}{v} =~ s/\.$//;
        $r->{visVar2}{distance}{v} =~ s/\.$//;
        push @{$report{remark}}, $r;
    }
    push @{$report{remark}}, { notRecognised => { s => $1 }}
        if /\G(VSBY) /gc;

=head3 CA: Additional groups

=over

=item B<appp>

three-hourly pressure tendency for station level pressure

=back

=cut

    if (   _cyInString(\@cy, ' cCA ')
        && /\G(?:(?:([^ ]+) )??)(M|([M0-8])(\d{3})) /gc)
    {
        push @{$report{remark}}, { notRecognised => { s => $1 }}
            if defined $1;
        push @{$report{remark}}, { pressureChange => {
            s             => $2,
            timeBeforeObs => { hours => 3 },
            defined $3 && $3 ne 'M'
              ? (pressureTendency  => $3,
                 pressureChangeVal => {
                    v => sprintf('%.1f', $4 / ($3 >= 5 ? -10 : 10) + 0),
                    u => 'hPa'
                 })
              : (notAvailable => undef)
        }};
    }

=for html <!--

=over

=item TTdOA

=for html --><dl><dt><strong>TT<sub>d</sub>OA</strong></dt>

temperature tenths value, dew point tenths value, total opacity (in oktas),
tenths value of precipitation amount

=back

=cut

    if (_cyInString(\@cy, ' cCA ') && /\G(M|-?\d)(M|-?\d)([XM0-8])M /gc) {
        if (   $1 ne 'M'
            && exists $report{temperature}
            && exists $report{temperature}{air}
            && exists $report{temperature}{air}{temp})
        {
            my $r;

            $r->{s} = "$1$2";
            $r->{air}{temp} = {
                v => _mkTempTenths($report{temperature}{air}{temp}{v}, $1),
                u => 'C'
            };
            if (   $2 ne 'M'
                && exists $report{temperature}
                && exists $report{temperature}{dewpoint}
                && exists $report{temperature}{dewpoint}{temp})
            {
                $r->{dewpoint}{temp} = {
                    v => _mkTempTenths($report{temperature}{dewpoint}{temp}{v},
                                       $2),
                    u => 'C'
                };
                _setHumidity $r;
            }
            push @{$report{remark}}, { temperature => $r };
        }
        if ($3 ne 'M') {
            push @{$report{remark}}, { totalCloudCover => {
                s => $3,
                $3 eq 'X' ? (skyObscured => undef) : (oktas => $3)
            }};
        }
    }

    push @{$report{remark}}, { notRecognised => { s => $1 }}
        if /\G(.+) /gc;
    return %report;
}

########################################################################
# _parseMetarTaf
########################################################################
sub _parseMetarTaf {
    my $default_msg_type = shift;
    my (%metar, $is_taf, $msg_hdr, $is_auto, $is_taf_Aug2007, $s_preAug2007);
    my (@cy, $obs_hour, $old_pos, $winds_est, $winds_grid, $qnhInHg, $qnhHPa);

    $metar{msg} = $_;
    $metar{isSpeci} = undef if $default_msg_type eq 'SPECI';
    $metar{isTaf}   = undef if $default_msg_type eq 'TAF';
    $metar{version} = VERSION();

    if (/^ERROR -/) {
        pos $_ = 0;
        $metar{ERROR} = _makeErrorMsgPos 'other';
        return %metar;
    }

=head2 Parsing of METAR/SPECI and TAF messages

First, the message is checked for typical errors and corrected. Errors for
METARs could be:

=over

=item *

QNH with spaces

=item *

temperature or dew point with spaces

=item *

misspelled keywords, or with missing or additional spaces

=item *

missing keywords

=item *

removal of slashes before and after some components

=back

If the message is modified there will be a C<warning>.

=cut

    $is_taf = exists $metar{isTaf};

    # temporarily remove and store keyword for message type
    $msg_hdr = '';
    $msg_hdr = $1
        if s/^((?:METAR )?LWIS |METAR |SPECI |TAF )//;

    # EXTENSION: preprocessing
    # remove trailing =
    s/ ?=$//;

    $_ .= ' '; # this makes parsing much easier

    # QNH with spaces, brackets, dots
    s/(?<= A) (?=[23]\d{3} )//;
    s/(?<= Q) (?=[01]\d{3} )//;
    s/(?<= (?:A[23]|Q[01])) (?=\d{3} )//;
    s/(?<= (?:A[23]|Q[01])\d) (?=\d\d )//;
    s/(?<= (?:A[23]|Q[01])\d\d) (?=\d )//;
    s/ \((A[23]\d)\.?(\d\d)\) / $1$2 /;

    # misspelled keywords, or with missing or additional spaces
    s/ (?:CAMOK|CC?VOK|CAVOC) / CAVOK /;
    s/ (?:NO(?: S)?IG|NOSI(?: G)?|N[L ]OSIG|NSI?G|(?:MO|N0)SIG|NOS I ?G) / NOSIG /;
    s/(?<! )(?=(?:TEMPO|BECMG) )/ /; # BLU+BLU+(TEMPO|BECMG)
    s/ (?:R MK|RMKS|RRMK)[:.]? / RMK /;
    s@(?<= RMK)(?=[^ /])@ @;
    s@ 0VC(?=$re_cloud_base$re_cloud_type?|$re_cloud_type )@ OVC@og;
    s@ BNK(?=$re_cloud_base$re_cloud_type?|$re_cloud_type )@ BKN@og;
    s@(?<= $re_cloud_cov)O(?=\d\d )@0@og;
    s@(?<= $re_cloud_cov\d)O(?=\d )@0@og;
    s@(?<= $re_cloud_cov\d\d)O(?= )@0@og;
    s@(?<= VR) (?=B$re_wind_speed$re_wind_speed_unit )@@og;
    s@(?<= WND (?:$re_dd|00)0)MM(?=KT )@//@og;
    s@(?<= R) (?=WY)@@g;
    s@(?<= RW) (?=Y)@@g;
    s@(?<= RWY$re_dd) (?=[LCR] )@@og;
    s@(?<= RWY$re_dd) (?=(?:LL|RR) )@@og;
    s@ RNW @ RWY @g;
    s@ ?/(?=AURBO )@ @;
    s@(?<= A)0(?=[12]A? )@O@;
    s@(?<=[/ ]ALQ)(?=S )@D@g;
    s@(?<=[/ ]AL)L(?=QDS )@@g;
    s@(?<=[/ ]ALQ)UAD(?= )@DS@g;
    s@(?<=[/ ]A)Q(?= )@LQDS@g;
    s@(?<=[/ ]AR)OU(?=ND )@@g;
    s@(?<= OCNL)Y(?= )@@g;
    s@(?<= F)QT(?= )@RQ@g;
    s@ LIGHTNING @ LTG @g;
    s@ LTNG @ LTG @g;
    s@( $re_phen_desc L)GT(?=$re_ltg_types+)@$1TG@og;
    s@(?<= LTG) (?=$re_ltg_types{2,})@@og;
    s@(?<= LTG) (?=(?:C[ACGW])+)@@g; # IC could be weather
    s@(?<= I)N(?=OVC )@@g;
    s@(?<= SP)O(?=TS )@@g;
    s@(?<= W) (?=IND )@@g;
    s@(?<= WIND RWY) (?=$re_rwy_des )@@og;
    s@(?<= (?:RWY|THR))($re_rwy_des ${re_wind_dir}0$re_wind_speed) (?=$re_wind_speed_unit )@$1@og;
    s@(?<= D)ISTA(?=NT )@S@g;
    s@(?<=[ -]N)ORTH(?=[ -])@@g;
    s@(?<=[ -]S)OUTH(?=[ -])@@g;
    s@(?<=[ -]E)AST(?=[ -])@@g;
    s@(?<=[ -]W)EST(?=[ -])@@g;
    s@( [+-]?)(RA|SN)SH(?= )@$1SH$2@g;
    s@(?<= SH)(?:S|WR|OWERS?)(?= )@@g;
    s@(?<= CB)S(?= )@@g;
    s@(?<= TCU)S(?= )@@g;
    s@(?<= LTG)[S.](?= )@@g;
    s@(?<= OV)E(?=R )@@g;
    s@(?<= O)VR MT(?:N?S)?(?= )@MTNS@g;
    s@(?<= OMT)(?=S )@N@g;
    s@(?<= A)(?:R?PT|D)(?= )@P@g;
    s@(?<=[ -]O)V?HD?(?=[ -])@HD@g;
    s@(?<= UNK)(?= )@N@g;
    s@(?<= AL)N(?=G )@@g;
    s@(?<= ISOL)D(?= )@@g;
    s@(?<= H)A(?=ZY )@@g;
    s@(?<= DS)(?=T )@N@g;
    s@(?<= D)IS(?=T )@SN@g;
    s@(?<= DS)TN(?= )@NT@g;
    s@(?<= PL)(?=ME )@U@g;
    s@(?<= INVIS)T(?= )@@g;
    s@(?<= FROIN)/ ?@ @g;
    s@(?<= AS)(?=CTD )@O@g;
    s@(?<= EMBD)D(?= )@@g;
    s@(?<= M)(?=VD )@O@g;
    s@(?<= MOV)(?:(?:IN)?G )@ @g;
    s@(?<=^$re_ICAO $re_day$re_hour$re_min)(?= )@Z@o
        unless $is_taf;
    s@(?<=^$re_ICAO $re_day$re_hour$re_min)(?= $re_day$re_hour/$re_day(?:$re_hour|24))@Z@o
        if $is_taf;
    s@(?<=^$re_ICAO $re_day$re_hour$re_min)KT(?= )@Z@o;
    s@(?<=^$re_ICAO $re_day$re_hour${re_min}Z )(${re_wind_dir}0)/(?=${re_wind_speed}$re_wind_speed_unit )@$1@o;
    s@(?<= [0-2]) (?=\d0${re_wind_speed}$re_wind_speed_unit )@@og;
    s@(?<= 3) (?=[0-6]0${re_wind_speed}$re_wind_speed_unit )@@og;
    s@(?<=[+]) (?=$re_weather_w_i )@@og;
    s@(?<=M)/(?=S )@P@g;
    s@(?<=$re_cloud_base )(M?\d\d/)/(?=M?\d\d )@$1@o;
    s@ TMPO @ TEMPO @g;
    s@ TEMP0 @ TEMPO @g;
    s@ BEC @ BECMG @g;
    s@(?<= PR)0(?=B[34]0 )@O@g;
    s@(?<= BECMG| TEMPO)(?=$re_hour(?:$re_hour|24) )@ @og;
    s@(?<= (?:BECMG|TEMPO|INTER) $re_day$re_hour)(?: /|/ )(?=$re_day(?:$re_hour|24) )@/@og
        if $is_taf;
    s@ PRECIP @ PCPN @g;
    s@( T[XN]M?\d\d/(?:24|$re_day?$re_hour)Z)(?=T[XN]M?\d\d/(?:24|$re_day?$re_hour)Z )@$1 @o;
    s@ ?/(?=$re_snw_cvr_title)@ @og;
    s@(?<= RWY0) (?=[1-9] )@@g;
    s@(?<= RWY[12]) (?=\d )@@g;
    s@(?<= RWY3) (?=[0-6] )@@g;
    s@ DRFTG SNW @ DRSN @g;
    s@(?<= T)O(?=\d{3}[01]\d{3} )@0@g;
    s@ ?/(?=BLN VISBL )@ @g;
    s@ FG PATCHES @ BCFG @g;
    s@(?<=[/ ]AL)TS(?=G[/ ])@ST@g;

    # "TAF" after icao code?
    s/(?<=^$re_ICAO) TAF(?= )//
        if $is_taf;

    # missing keywords
    s@ (?:TEMPO|INTER) ($re_hour$re_min)/($re_hour$re_min|2400)(?= )@ TEMPO FM$1 TL$2@og
        unless $is_taf;

    # komma got lost somwhere during transmission from originator to provider
    s@^((?:U|ZM).*? RMK.*?QFE\d{3}) (?=\d )@$1,@;
    s@^(FQ.*? RMK.*?TX/\d\d) (?=\d )@$1,@;

    # restore keyword for message type
    $_ = $msg_hdr . $_;
    pos $_ = length $msg_hdr;

    # warn about modification
    push @{$metar{warning}}, { warningType => 'msgModified',
                               s           => substr $_, 0, -1 }
        if $metar{msg} . ' ' ne $_;

=head3 Observational data for aviation requirements

METAR, SPECI:

 (COR|AMD) CCCC YYGGggZ (NIL|AUTO|COR|RTD|BBB) dddff(f)(Gfmfm(fm)){KMH|KT|MPS} (dndndnVdxdxdx)
   {CAVOK|{VVVV (VNVNVNVNDv)|VVVVNDV} (RDRDR/VRVRVRVR(VVRVRVRVR)(i)) (w'w')
          ({NsNsNs|VVV}hshshs|CLR|SKC|NSC|NCD)}
   T'T'/T'dT'd {Q|A}PHPHPHPH
   (REw'w') (WS {RDRDR|ALL RWY}) (WTwTw/SS) (RDRDR/ERCReReRBRBR)

TAF:

 (COR|AMD) CCCC YYGGggZ (NIL|COR|AMD) {Y1Y1G1G1G2G2|Y1Y1G1G1/Y2Y2G2G2} (CNL) (NIL) dddff(f)(Gfmfm(fm)){KMH|KT|MPS} (dndndnVdxdxdx)
  {CAVOK|VVVV (w’w’) ({NsNsNs|VVV}hshshs|NSC) (TXTFTF/YFYFGFGFZ TNTFTF/YFYFGFGFZ)}

=over

=item optional: B<C<COR>> and/or B<C<AMD>>

keywords to indicate a corrected and/or amended message.

=back

=cut

    while (/\G(COR|AMD) /gc) {
        push @{$metar{reportModifier}}, { s => $1, modifierType => $1 };
    }

=over

=item B<CCCC>

reporting station (ICAO location indicator)

=back

=cut

    if (!/\G($re_ICAO) /ogc) {
        $metar{ERROR} = _makeErrorMsgPos 'obsStation';
        return %metar;
    }
    $metar{obsStationId}{id} = $1;
    $metar{obsStationId}{s} = $1;

    @cy = $metar{obsStationId}{id} =~ /(((.).)..)/;
    $cy[2] = 'cCA' if _cyInString \@cy, ' C ';
    $cy[2] = 'cJP' if _cyInString \@cy, ' RJ RO ';
    $cy[2] = 'cUS' if _cyInString \@cy, ' FHAW FJDG K MUGM MHSC NSTU P TJ TI ';

    # EXTENSION: allow NIL
    if (/\G(?:RMK )?NIL $/) {
        $metar{reportModifier}{s} =
            $metar{reportModifier}{modifierType} = 'NIL';
        return %metar;
    }

=over

=item B<YYGGggC<Z>>

METAR: day, hour, minute of observation;
SPECI: day, hour, minute of occurence of change;
TAF: day, hour, minute of origin of forecast

=back

=cut

    if (m@\G$re_unrec($re_day)($re_hour)($re_min)Z @ogc) {
        push @{$metar{warning}}, { warningType => 'notProcessed', s => $1 }
            if defined $1;
        $metar{$is_taf ? 'issueTime' : 'obsTime'} = {
            s      => "$2$3$4Z",
            timeAt => { day => $2, hour => $3, minute => $4 }
        };
        $obs_hour = $3 unless $is_taf;
    } elsif (/\G(\d+Z) /gc) {
        $metar{$is_taf ? 'issueTime' : 'obsTime'} =
                                               { s => $1, invalidFormat => $1 };
    } elsif ($is_taf && m@\G(?:$re_day$re_hour(?:$re_hour|24)|$re_day$re_hour/$re_day(?:$re_hour|24)) @o)
    {
        $metar{issueTime} = { s => '', invalidFormat => '' };
    } elsif (/\G(NIL) $/) {
        # EXTENSION: NIL instead of issueTime
        push @{$metar{reportModifier}}, { s => $1, modifierType => $1 };
        return %metar;
    } else {
        $metar{ERROR} = _makeErrorMsgPos 'obsTime';
        return %metar;
    }

=over

=item METAR, SPECI: optional: B<C<NIL>> | B<C<AUTO>> | B<C<COR>> | B<C<RTD>> | B<BBB>

report modifier(s)
C<NIL>: message contains no observation data, end of message;
C<AUTO>: message created by an automated station;
C<COR>: corrected message;
C<RTD>: retarded message.

CA: B<BBB>: report has been retarded (C<RR>?), corrected (C<CC>?), amended
(C<AA>?), or segmented (C<P>??)

=back

=cut

    # EXTENSION: BBB (for Canada)
    while (!$is_taf && /\G(NIL|AUTO|COR|RTD|$re_bbb) /ogc) {
        my $r;

        $r->{s} = $1;
        if ($r->{s} =~ 'NIL|AUTO|COR|RTD') {
            $r->{modifierType} = $r->{s};
            $is_auto = $r->{modifierType} eq 'AUTO';
        } else {
            $r->{s} =~ '(.)(.)(.)';
            if ($1 eq 'P') {
                $r->{modifierType} = $1;
                $r->{sortedArr} = [
                    $2 eq 'Z' ? { isLastSegment => undef } : (),
                    { segment => "$2$3" }
                ];
            } else {
                $r->{modifierType} = "$1$2";
                if ($3 eq 'Z') {
                    $r->{sortedArr} = [{ over24hLate => undef }];
                } elsif ($3 eq 'Y') {
                    $r->{sortedArr} = [{ sequenceLost => undef }];
                } else {
                    $r->{sortedArr} = [{ bulletinSeq => $3 }];
                }
            }
        }
        push @{$metar{reportModifier}}, $r;
        return %metar if $r->{modifierType} eq 'NIL';
    }


    if ($is_taf) {

=over

=item TAF: optional: B<C<NIL>> | B<C<COR>> | B<C<AMD>>

report modifier(s).
C<NIL>: message contains no forecast data, end of message;
C<COR>: message corrected;
C<AMD>: message amended

=back

=cut

        if (/\G(NIL|COR|AMD) /gc) {
            push @{$metar{reportModifier}}, { s => $1, modifierType => $1 };
            return %metar if $1 eq 'NIL';
        }

=for html <!--

=over

=item TAF: B<Y1Y1G1G1G2G2> | B<Y1Y1G1G1C</>Y2Y2G2G2>

=for html --><dl><dt>TAF: <strong>Y<sub>1</sub>Y<sub>1</sub>G<sub>1</sub>G<sub>1</sub>G<sub>2</sub>G<sub>2</sub></strong> |  <strong>Y<sub>1</sub>Y<sub>1</sub>G<sub>1</sub>G<sub>1</sub><code>/</code>Y<sub>2</sub>Y<sub>2</sub>G<sub>2</sub>G<sub>2</sub></strong></dt>

forecast period with format before or after August, 2007

=back

=cut

        # TODO: new TAF format _proposed_ by AMOFSG.8.SN.13:
        # YUDO 071140Z 071140/081200 FM071140 12008KT 6SM RA BKN200 FM071900 ...

        if (m@\G$re_unrec($re_day)($re_hour)($re_hour|24) @ogc) {
            push @{$metar{warning}}, { warningType => 'notProcessed', s => $1 }
                if defined $1;
            $metar{fcstPeriod} = {
                s        => "$2$3$4",
                timeFrom => { day => $2, hour => $3 },
                timeTill => {            hour => $4 }
            };
            $s_preAug2007 = "TAF $2$3$4";
        } elsif (m@\G$re_unrec($re_day)($re_hour)/($re_day)($re_hour|24) @ogc) {
            push @{$metar{warning}}, { warningType => 'notProcessed', s => $1 }
                if defined $1;
            $metar{fcstPeriod} = {
                s        => "$2$3/$4$5",
                timeFrom => { day => $2, hour => $3 },
                timeTill => { day => $4, hour => $5 }
            };
            $is_taf_Aug2007 = 1;
            $s_preAug2007 = '';
        } else {
            $metar{ERROR} = _makeErrorMsgPos 'fcstPeriod';
            return %metar;
        }

=over

=item TAF: optional: B<C<CNL>>

cancelled forecast

=cut

        if (m@\G$re_unrec(CNL) @o) {
            push @{$metar{warning}}, { warningType => 'notProcessed', s => $1 }
                if defined $1;
            $metar{fcstCancelled}{s} = $2;
            return %metar;
        }

=item TAF: optional: B<C<NIL>>

message contains no forecast data, end of message

=cut

        # EXTENSION: NIL after fcstPeriod
        if (m@\G$re_unrec(NIL) @o) {
            push @{$metar{warning}}, { warningType => 'notProcessed', s => $1 }
                if defined $1;
            push @{$metar{reportModifier}}, { s => $2, modifierType => $2 };
            return %metar;
        }

=item TAF: optional: B<C<FCST NOT AVBL DUE>> {B<C<NO>> | B<C<INSUFFICIENT>>} B<C<OBS>>

message contains no forecast data

=back

=cut

        # EXTENSION: NOT AVBL after fcstPeriod. Remarks may follow
        $metar{fcstNotAvbl} = { s => $1, fcstNotAvblReason => "${2}OBS" }
            if /\G(FCST NOT AVBL DUE (NO|INSUFFICIENT) OBS) /gc;
    }

=for html <!--

=over

=item B<dddff>(B<f>)(B<C<G>fmfm>(B<fm>)){B<C<KMH>> | B<C<KT>> | B<C<MPS>>}

=for html --><dl><dt><strong>dddff</strong>(<strong>f</strong>)(<strong><code>G</code>f<sub>m</sub>f<sub>m</sub></strong>(<strong>f<sub>m</sub></strong>)){<strong><code>KMH</code></strong> | <strong><code>KT</code></strong> | <strong><code>MPS</code></strong>}</dt>

surface wind with optional gust (if it exceeds the wind speed by 10 knots or
more)

METAR, SPECI: mean true direction in degrees rounded off to the nearest 10
degrees from which the wind is blowing and mean speed of the wind over the
10-minute period immediately preceding the observation;
TAF: mean direction and speed of forecast wind

wind direction may be C<VRB> for variable if the speed is <3 (US: <=6) knots or
if the variation of wind direction is 180° or more or cannot be determined (not
US);
wind direction and speed may be C<00000> for calm wind

=back

=cut

    # EXTENSION: allow ///// (wind not available)
    # EXTENSION: allow /// for wind direction (not available)
    # EXTENSION: allow // for wind speed (not available)
    # EXTENSION: allow missing wind
    if (m@\G$re_unrec(/////|(?:$re_wind)) @ogc) {
        push @{$metar{warning}}, { warningType => 'notProcessed', s => $1 }
            if defined $1;
        $metar{sfcWind} = { s => $2, wind => _parseWind $2, 1 };
        # US: FMH-1 5.4.3, CA: MANOBS 10.2.15
        # default: WMO-No. 306 Vol I.1, Part A, Section A, 15.5.1
        $metar{sfcWind}{measurePeriod} = {
            v => (_cyInString(\@cy, ' cUS cCA ') ? 2 : 10),
            u => 'MIN'
        } if !$is_taf && exists $metar{sfcWind}{wind}{speed};
    # EXTENSION: allow invalid formats
    } elsif (   !$is_taf && $cy[0] eq 'OPPS'
             && /\G(($re_compass_dir)--?($re_wind_speed)KTS?) /ogc)
    {
        $metar{sfcWind} = {
            s => $1,
            wind => {
                dir => { 'NE' => 1, 'E' => 2, 'SE' => 3, 'S' => 4,
                         'SW' => 5, 'W' => 6, 'NW' => 7, 'N' => 8,
                       }->{$2} * 45,
                speed => { v => $3 + 0, u => 'KT' }
        }};
    } elsif (/\G(${re_wind_dir}0$re_wind_speed|\d{4,}(?:K?T|K)) /ogc) {
        $metar{sfcWind} = { s => $1, wind => { invalidFormat => $1 }};
    }

=for html <!--

=over

=item optional: B<dndndnC<V>dxdxdx>

=for html --><dl><dt>optional: <strong>d<sub>n</sub>d<sub>n</sub>d<sub>n</sub><code>V</code>d<sub>x</sub>d<sub>x</sub>d<sub>x</sub></strong></dt>

variable wind direction if the speed is >=3 (US: >6) knots

=back

=cut

    # EXTENSION:
    # Annex 3 Appendix 3 4.1.4.2.b.1 requires wind speed >=3 kt and
    #   variation 60-180 for this group: not checked
    if (m@\G$re_unrec($re_wind_dir\d)V($re_wind_dir\d) @ogc) {
        push @{$metar{warning}}, { warningType => 'notProcessed', s => $1 }
            if defined $1;
        if (exists $metar{sfcWind}) {
            $metar{sfcWind}{s} .= ' ';
        } else {
            # TODO?: actually not "not available" but missing
            $metar{sfcWind} = {
                s    => '',
                wind => { dirNotAvailable => undef, speedNotAvailable => undef }
            };
        }
        $metar{sfcWind}{s} .= "$2V$3";
        @{$metar{sfcWind}{wind}}{qw(windVarLeft windVarRight)} =
                                                               ($2 + 0, $3 + 0);
    }

    while ($is_taf && m@\G($re_wind_shear_lvl) @ogc) {
        push @{$metar{TAFsupplArr}}, { windShearLvl => {
            s     => $1,
            level => $2 + 0,
            wind  => _parseWind $3
        }};
    }

=over

=item B<C<CAVOK>>

If the weather conditions allow (visibility 10 km or more, no significant
weather, no clouds below 5000 ft (or minimum sector altitude, whichever is
greater) and no CB or TCU) this may be indicated by the keyword C<CAVOK>. The
next component after that should be the temperature (see below).

=back

=cut

    if (m@\G${re_unrec}CAVOK @ogc) {
        push @{$metar{warning}}, { warningType => 'notProcessed', s => $1 }
            if defined $1;
        $metar{CAVOK} = undef; # cancels visibility, weather and cloud
    }

    if (!exists $metar{CAVOK}) {

=for html <!--

=over

=item B<VVVV (VNVNVNVNDv)> | B<VVVVC<NDV>>

=for html --><dl><dt><strong>VVVV</strong> (<strong>V<sub>N</sub>V<sub>N</sub>V<sub>N</sub>D<sub>v</sub></strong>) | <strong>VVVV<code>NDV</code></strong></dt>

prevailing visibility. It can have a compass direction attached or C<NDV> if no
directional variations can be given. There may be an additional group for the
minimum visibility.

=back

=cut

        # EXTENSION: allow 16 compass directions
        # EXTENSION: allow 'M' (meter) after re_vis_m
        # EXTENSION: allow xxx0 for visPrev in METAR
        # EXTENSION: allow P6000/M0050
        # EXTENSION: allow missing visibility even without CAVOK
        if (   !$is_taf
            && m@\G$re_unrec((?:([PM])?(\d{3}0|9999)M?( ?NDV)?|($re_vis_km))($re_compass_dir16)?)(?: ($re_vis_m)($re_compass_dir))? @o
            && !(defined $3 && $4 == 9999))
        {
            push @{$metar{warning}}, { warningType => 'notProcessed', s => $1 }
                if defined $1;
            pos $_ += (defined $1 ? length($1) + 1 : 0) + length($2) + 1;
            $metar{visPrev}{s} = $2;
            $metar{visPrev}{compassDir} = $7 if defined $7;
            if ($8) {
                $metar{visMin}{s} = $8 . $9;
                pos $_ += length($metar{visMin}{s}) + 1;
                $metar{visMin}{distance} = _getVisibilityM $8;
                $metar{visMin}{compassDir} = $9;
            }
            if (defined $4) {
                $metar{visPrev}{distance} = _getVisibilityM $4, $3;
                $metar{visPrev}{NDV}      = undef if defined $5;
            } else {
                $metar{visPrev}{distance} = { v => $6, rp => 1, u => 'KM' };
                $metar{visPrev}{distance}{v} =~ s/KM//;
            }
        } elsif (m@\G$re_unrec((?:($re_vis_m)M?|($re_vis_km))) @ogc) {
            push @{$metar{warning}}, { warningType => 'notProcessed', s => $1 }
                if defined $1;
            $metar{visPrev}{s} = $2;
            if (defined $3) {
                $metar{visPrev}{distance} = _getVisibilityM $3;
            } else {
                $metar{visPrev}{distance} = { v => $4, rp => 1, u => 'KM' };
                $metar{visPrev}{distance}{v} =~ s/KM//;
            }
        } elsif (m@\G$re_unrec(($re_vis_sm) ?SM) @ogc) {
            push @{$metar{warning}}, { warningType => 'notProcessed', s => $1 }
                if defined $1;
            $metar{visPrev} = _getVisibilitySM $3, $is_auto, \@cy;
            $metar{visPrev}{s} = $2;
        } elsif ($is_taf && m@\G$re_unrec(P?[1-9]\d*)SM @ogc) {
            push @{$metar{warning}}, { warningType => 'notProcessed', s => $1 }
                if defined $1;
            $metar{visPrev} = _getVisibilitySM $2, $is_auto, \@cy;
            $metar{visPrev}{s} = "$2SM";
        # EXTENSION: allow //// and misformatted entry
        } elsif (m@\G${re_unrec}//// @ogc) {
            push @{$metar{warning}}, { warningType => 'notProcessed', s => $1 }
                if defined $1;
            $metar{visPrev} = { s => '////', notAvailable => undef };
        } elsif (/\G(\d{3,4}M?$re_compass_dir16?(?: $re_vis_m$re_compass_dir)?|$re_vis_sm) /ogc) {
            $metar{visPrev} = { s => $1, invalidFormat => $1 };
        }
    }

=for html <!--

=over

=item METAR: optional: B<C<R>DRDRC</>VRVRVRVR>(B<C<V>VRVRVRVR>)(B<i>)

=for html --><dl><dt>METAR: optional: <strong><code>R</code>D<sub>R</sub>D<sub>R</sub><code>/</code>V<sub>R</sub>V<sub>R</sub>V<sub>R</sub>V<sub>R</sub></strong>(<strong><code>V</code>V<sub>R</sub>V<sub>R</sub>V<sub>R</sub>V<sub>R</sub></strong>)(<strong>i</strong>)</dt>

runway visibility range(s) with optional trend, or C<RVRNO> if they are not
available

=back

=cut

    while (!$is_taf && _parseRwyVis \%metar) {};

    # EXTENSION: allow RVRNO (not available) (KADW, RKSG, PAED)
    if (!$is_taf && /\GRVRNO /gc) {
        $metar{RVRNO} = undef;
    }

    if (!exists $metar{CAVOK}) {

=over

=item optional: B<w'w'>

up to 3 groups to describe the present weather: precipitation (C<DZ>, C<RA>,
C<SN>, C<SG>, C<PL>, C<GR>, C<GS>, C<IC>, C<UP>, C<JP>), obscuration (C<BR>,
C<FG>, C<FU>, C<VA>, C<DU>, C<S>C<A>, C<HZ>), or other (C<PO>, C<SQ>, C<FC>,
C<SS>, C<DS>).
Mixed precipitation is indicated by concatenating, e.g. C<RASN>.
Certain precipitation, duststorm and sandstorm can have the intentsity (C<+> or
C<->) prepended.
Prepended C<VC> means in the vicinity (within 5 SM / 8 km to 10 SM / 16 km) but
not at the station.
Certain phenomena can also be combined with an appropriate descriptor (C<MI>,
C<BC>, C<PR>, C<DR>, C<BL>, C<SH>, C<TS>, C<FZ>), e.g. C<TSRA>, C<FZFG>,
C<BLSN>.

=back

=cut

        # EXTENSION: allow // (not available) and other deviations
        # NSW should not be in initial section, only in trends
        # store recent weather as invalidFormat for now, check if valid later
        while (m@\G$re_unrec_weather(?:(//) |($re_weather)(?:/? |/(?=$re_weather[ /]))|(NSW|[+-]?(?:RE|VC|$re_weather_desc|$re_weather_prec|$re_weather_obsc|$re_weather_other)+) )@ogc)
        {
            push @{$metar{warning}}, { warningType => 'notProcessed', s => $1 }
                if defined $1;
            if (defined $4) {
                push @{$metar{weather}}, {
                    s             => $4,
                    invalidFormat => $4
                };
            } else {
                push @{$metar{weather}}, _parseWeather defined $2 ? $2 : $3;
            }
        }

=for html <!--

=over

=item optional: {B<NsNsNs> | B<VVV>}B<hshshs>(B<C<TCU>> | B<C<CB>>) | B<C<CLR>> | B<C<SKC>> | B<C<NSC>> | B<C<NCD>>

=for html --><dl><dt>optional: {<strong>N<sub>s</sub>N<sub>s</sub>N<sub>s</sub></strong> | <strong>VVV</strong>}<strong>h<sub>s</sub>h<sub>s</sub>h<sub>s</sub></strong>(<strong><code>TCU</code></strong> | <strong><code>CB</code></strong>) | <strong><code>CLR</code></strong> | <strong><code>SKC</code></strong> | <strong><code>NSC</code></strong> | <strong><code>NCD</code></strong></dt>

up to 3 (US: 6) groups to describe the sky condition (cloud cover and base or
vertical visibility) optionally with cloud type. The keywords C<CLR>, C<SKC>,
C<NSC>, or C<NCD> may indicate different sky conditions if no cloud cover is
given. Height values (given in hundreds of feet) are rounded to the nearest
reportable amount (<=5000 ft: 100 ft, <=10000 ft: 500 ft, otherwise 1000 ft)
(for US), or rounded down to the nearest 100 ft (WMO).

=back

=cut

        # EXTENSION: allow ////// (not available) without CB, TCU
        # WMO-No. 306 Vol I.1, Part A, Section A, 15.9.1.1:
        #   CLR: no clouds below 10000 (FMH-1: 12000) ft detected by autom. st.
        #   SKC: no clouds + VV not restricted but not CAVOK
        #   NSC: no significant clouds + no CB + VV not restr. but not CAVOK,SKC
        #   NCD: no clouds + CB, TCU detected by automatic observation system
        while (m@\G$re_unrec_cloud((SKC|NSC|CLR|NCD)|VV($re_cloud_base)(?:///)?|(///|(?:$re_cloud_cov|///)(?:$re_cloud_base(?: ?(?:$re_cloud_type|///)(?:\($re_loc_and\))?)?|$re_cloud_type))|($re_cloud_cov\d{1,2}|$re_cloud_cov(?: \d{1,3}))) @ogc)
        {
            push @{$metar{warning}}, { warningType => 'notProcessed', s => $1 }
                if defined $1;
            if (defined $6 || (defined $4 && exists $metar{visVert})) {
                push @{$metar{cloud}}, {
                    s             => $2,
                    invalidFormat => $2
                };
            } elsif (defined $3) {
                push @{$metar{cloud}}, {
                    s        => $2,
                    noClouds => $3
                };
            } elsif (defined $4) {
                $metar{visVert} = {
                    s => $2,
                    $4 eq '///' ? (notAvailable => undef)
                                : (distance => { v => $4 * 100,
                                                 $is_taf ? () : (rp => 100),
                                                 u => 'FT' })
                };
            } else {
                push @{$metar{cloud}}, _parseCloud $5, ($is_taf ? undef : \@cy);
            }
        }
        _determineCeiling $metar{cloud} if exists $metar{cloud};
    }

=for html <!--

=over

=item METAR: B<T'T'C</>T'dT'd>

=for html --><dl><dt>METAR: <strong>T'T'<code>/</code>T'<sub>d</sub>T'<sub>d</sub></strong></dt>

current air temperature and dew point. If both are given, the relative humidity
can be determined.

=back

=cut

    # EXTENSION: FMH-1: dew point is optional
    # EXTENSION: allow // for temperature and dew point
    # EXTENSION: allow XX for temperature and dew point
    if (   !$is_taf
        && m@\G$re_unrec((?:(M)?(\d ?\d)|(?://|XX))/((M)? ?(\d ?\d)|(?://|XX))?) @ogc)
    {
        push @{$metar{warning}}, { warningType => 'notProcessed', s => $1 }
            if defined $1;
        $metar{temperature}{s} = $2;
        if (defined $4) {
            $metar{temperature}{air}{temp} = { v => $4, u => 'C' };
            $metar{temperature}{air}{temp}{v} =~ tr / //d;
            $metar{temperature}{air}{temp}{v} += 0;
            $metar{temperature}{air}{temp}{v} *= -1 if defined $3;
        } else {
            $metar{temperature}{air}{notAvailable} = undef;
        }
        if (defined $5) {
            if (defined $7) {
                $metar{temperature}{dewpoint}{temp} = { v => $7, u => 'C' };
                $metar{temperature}{dewpoint}{temp}{v} =~ tr / //d;
                $metar{temperature}{dewpoint}{temp}{v} += 0;
                $metar{temperature}{dewpoint}{temp}{v} *= -1 if defined $6;
            } else {
                $metar{temperature}{dewpoint}{notAvailable} = undef;
            }
        }
        if (   exists $metar{temperature}{air}{temp}
            && exists $metar{temperature}{dewpoint}
            && exists $metar{temperature}{dewpoint}{temp})
        {
            _setHumidity $metar{temperature};
        }
    } elsif (!$is_taf && m@\G$re_unrec(M?\d{1,2}/M?\d{1,2}) @ogc) {
        push @{$metar{warning}}, { warningType => 'notProcessed', s => $1 }
            if defined $1;
        $metar{temperature} = { s => $2, invalidFormat => $2 };
    }

=for html <!--

=over

=item METAR: {B<C<Q>> | B<C<A>>}B<PHPHPHPH>

=for html --><dl><dt>METAR: {<strong><code>Q</code></strong> | <strong><code>A</code></strong>}<strong>P<sub>H</sub>P<sub>H</sub>P<sub>H</sub>P<sub>H</sub></strong></dt>

QNH (in hectopascal) or altimeter (in hundredths in. Hg.). Some stations report
both, some stations report QFE, only.

=back

=cut

    if (!$is_taf && m@\G$re_unrec($re_qnh) @ogc) {
        my $qnh;

        push @{$metar{warning}}, { warningType => 'notProcessed', s => $1 }
            if defined $1;
        $qnh = _parseQNH $2;
        push @{$metar{QNH}}, $qnh;
        if (exists $qnh->{pressure}) {
            $qnhHPa  = $qnh->{pressure}{v} if $qnh->{pressure}{u} eq 'hPa';
            $qnhInHg = $qnh->{pressure}{v} if $qnh->{pressure}{u} eq 'inHg';
        }
    # EXTENSION: allow other formats for OPxx
    } elsif (   !$is_taf && $cy[1] eq 'OP'
             && m@\G(Q(?:NH)?[. ]?(1\d{3}|0?[7-9]\d\d)((?:\.\d)?))(?:/(A?([23]\d\.\d\d)))? @gc)
    {
        $qnhHPa  = ($2 + 0) . $3;
        push @{$metar{QNH}}, {
            s        => $1,
            pressure => { v => $qnhHPa, u => 'hPa' }
        };
        push @{$metar{QNH}}, {
            s        => $4,
            pressure => { v => $5, u => 'inHg' }
        }
            if defined $4;
    } elsif (!$is_taf && m@\G(Q(?:NH)? ?\d{3}) @gc) {
        push @{$metar{QNH}}, { s => $1, invalidFormat => $1 };
    }
    # EXTENSION: allow Altimeter after QNH
    if (   !$is_taf
        && _cyInString(\@cy, ' KHBB MG MH MN MS MT MZ OI OM RP VT ')
        && m@\G($re_qnh) @ogc)
    {
        my $qnh;

        $qnh = _parseQNH $1;
        push @{$metar{QNH}}, $qnh;
        if (exists $qnh->{pressure}) {
            $qnhHPa  = $qnh->{pressure}{v} if $qnh->{pressure}{u} eq 'hPa';
            $qnhInHg = $qnh->{pressure}{v} if $qnh->{pressure}{u} eq 'inHg';
        }
    }
    # EXTENSION: MGxx uses QFE
    if (   !$is_taf
        && _cyInString(\@cy, ' MG ')
        && m@\G(QFE ?(1\d{3}|[7-9]\d\d)[./](\d+)) @gc)
    {
        $metar{QFE} = { s => $1, pressure => { v => "$2.$3", u => 'hPa' }};
    }

    # EXTENSION: station pressure (OIxx, OPxx)
    if (   !$is_taf && $cy[1] =~ /O[IP]/
        && m@\G((1\d{3}|0?[7-9]\d\d)(?:[./](\d))?) @gc)
    {
        $metar{stationPressure} = {
            s        => $1,
            pressure => { v => ($2 + 0) . (defined $3 ? ".$3" : ''), u => 'hPa'}
        };
    }

    # EXTENSION: allow worst cloud cover
    if (!$is_taf && _cyInString(\@cy, ' LO ') && /\G($re_cloud_cov|SKC) /ogc) {
        $metar{cloudMaxCover}{s} = $1;
        $metar{cloudMaxCover}{$1 eq 'SKC' ? 'noClouds' : 'cloudCover'} = $1;
    }

=over

=item METAR: optional: B<C<RE>w'w'>

recent weather

=back

=cut

    # recent weather: some groups omitted or wrong format?
    #   YUDO 090600Z 00000KT 9999 RERA
    if (!$is_taf && exists $metar{weather}) {
        for (my $idx = $#{$metar{weather}}; $idx >= 0; $idx--) {
            my ($w, $len);

            $w = $metar{weather}[$idx];
            $len = length($w->{s}) + 1;
            if (   exists $w->{invalidFormat}
                && $w->{s} =~ m@^RE(?://|$re_weather_re)$@
                && $w->{s} . ' ' eq substr($_, pos($_) - $len, $len))
            {
                # move position in message back and delete group from weather
                pos $_ -= $len;
                $#{$metar{weather}}--;
            } else {
                last;
            }
        }
        delete $metar{weather} if $#{$metar{weather}} == -1;
    }
    while (!$is_taf && m@\G${re_unrec}RE(//|$re_weather_re) @ogc) {
        push @{$metar{warning}}, { warningType => 'notProcessed', s => $1 }
            if defined $1;
        push @{$metar{recentWeather}}, _parseWeather($2, 'RE');
    }

    # EXTENSION: allow QFF (WMAU)
    if (!$is_taf && _cyInString(\@cy, ' WMAU ') && /\G(QFF ?(\d{3,4})) /gc) {
        $metar{QFF} = {
            s        => $1,
            pressure => { v => $2, u => 'hPa' }
        }
    }

=for html <!--

=over

=item METAR: optional: B<C<WS>> {B<C<R>DRDR> | B<C<ALL RWY>>}

=for html --><dl><dt>METAR: optional: <strong><code>WS</code></strong> {<strong><code>R</code>D<sub>R</sub>D<sub>R</sub></strong> | <strong><code>ALL RWY</code></strong>}</dt>

wind shear for certain or all runways

=back

=cut

    if (!$is_taf && /\G(WS ALL RWY) /gc) {
        push @{$metar{windShear}}, {
            s           => $1,
            rwyDesigAll => undef
        };
    }
    while (!$is_taf && /\G(WS R(?:WY)?($re_rwy_des)) /ogc) {
        push @{$metar{windShear}}, {
            s        => $1,
            rwyDesig => $2
        };
    }

=for html <!--

=over

=item METAR: optional: B<C<W>TwTw>B<C</S>S>

=for html --><dl><dt>METAR: optional: <strong><code>W</code>T<sub>w</sub>T<sub>w</sub><code>/S</code>S</strong></dt>

water temperature and sea condition

=back

=cut

    if (!$is_taf && m@\G(?:W(//|\d\d)/S([\d/])) @gc) {
        $metar{waterTemp} = {
            s => "W$1",
            $1 eq '//' ? (notAvailable => undef)
                       : (temp => { v => $1 + 0, u => 'C' })
        };
        $metar{seaCondition} = {
            s => "S$2",
            $2 eq '/' ? (notAvailable => undef) : (seaCondVal => $2)
        };
    }

=for html <!--

=over

=item METAR: optional: B<C<R>DRDR>(B<C</>>)B<ERCReReRBRBR>

=for html --><dl><dt>METAR: optional: <strong><code>R</code>D<sub>R</sub>D<sub>R</sub></strong>(<strong><code>/</code></strong>)<strong>E<sub>R</sub>C<sub>R</sub>e<sub>R</sub>e<sub>R</sub>B<sub>R</sub>B<sub>R</sub></strong></dt>

state of the runway: runway deposits, extent of runway contamination, depth of
deposit, and friction coefficient or braking action

B<ERCReReRBRBR> can also be C<SNOCLO> (airport closed due to snow), B<ERCReReR>
can also be C<CLRD> if contaminations have been cleared. The runway designator
B<DRDR> can also be C<88> (all runways), C<99> (runway repeated); otherwise, if
it is greater than 50, subtract 50 and append C<R>.

=back

=cut

    while (!$is_taf && _parseRwyState \%metar) {};

=pod

A METAR may also contain supplementary information, like colour codes.
Additionally, there can be country or station specific information: pressure,
worst cloud cover, runway winds, relative humidity.

=cut

    # EXTENSION: allow colour code
    if (!$is_taf && m@\G($re_colour) @ogc) {
        $metar{colourCode} = _parseColourCode $1;
    }

    # EXTENSION: country specific things
    if (   !$is_taf
        && _cyInString(\@cy, ' SCSE ')
        && /\G(NEFO PLAYA (?:([1-9]\d+0)FT|(SKC))) /gc)
    {
        $metar{NEFO_PLAYA}{s} = $1;
        if (defined $2) {
            $metar{NEFO_PLAYA}{cloudBase} = { v => $2 + 0, u => 'FT' };
        } else {
            $metar{NEFO_PLAYA}{noClouds} = 'SKC';
        }
    }

    # EXTENSION: allow runway and radio sonde winds (LPMA)
    while (   !$is_taf
           && _cyInString(\@cy, ' LPMA ')
           && /\G($re_rs_rwy_wind) /ogc)
    {
        my $r;

        $r->{s} = $1;
        $r->{wind} = _parseWind $3 . '0' . $4, 1;
        if ($2 eq 'RS') {
            $r->{windLocation} = $2;
            $metar{windAtLoc} = $r;
        } else {
            $r->{rwyDesig} = $2;
            push @{$metar{rwyWind}}, $r;
        }
    }

=for html <!--

=over

=item TAF: optional: B<C<TX>TFTFC</>YFYFGFGFC<Z> C<TN>TFTFC</>YFYFGFGFC<Z>>

=for html --><dl><dt>TAF: optional: <strong><code>TX</code>T<sub>F</sub>T<sub>F</sub><code>/</code>Y<sub>F</sub>Y<sub>F</sub>G<sub>F</sub>G<sub>F</sub><code>Z</code>  <code>TN</code>T<sub>F</sub>T<sub>F</sub><code>/</code>Y<sub>F</sub>Y<sub>F</sub>G<sub>F</sub>G<sub>F</sub><code>Z</code></strong></dt>

operationally significant maximum or minimum temperatures within the validity
period

=back

A TAF may also contain supplementary information: turbulence, icing, wind shear,
QNH.
Additionally, there can be country or station specific information, like
obscuration.

=cut

    # TAF: look ahead for temp*At, move and process here
    # EXTENSION: allow mixed format (pre/post Aug 2007)
    while (   $is_taf
           && m@\G(?:(.+?) )??(T([XN])?(M)?(\d\d)/(?:24|($re_day)?($re_hour))Z) @o)
    {
        my $r;

        $r->{s} = $2;
        $r->{temp} = { v => $5 + 0, u => 'C' };
        $r->{temp}{v} *= -1 if defined $4;
        $r->{timeAt}{day} = $6 if defined $6;
        $r->{timeAt}{hour} = defined $7 ? $7 : 24;
        push @{$metar{TAFsupplArr}}, {
            ({ N => 'tempMinAt',
               X => 'tempMaxAt',
               0 => 'tempAt' }->{$3 || 0}) => $r
        };

        if (defined $1) {
            my $pos;

            $pos = pos $_;
            substr $_, $pos, length($1) + length($2) + 1, $2 . ' ' . $1;
            pos $_ = $pos;
            _msgModified \%metar;
        }
        pos $_ += length($2) + 1;
    }

    # "supplementary" section and additional info of TAFs
    while ($is_taf && _parseTAFsuppl \%metar, \%metar, \@cy) {};

=head3 Trends

METAR, SPECI:

 {NOSIG|TTTTT TTGGgg dddff(f)(Gfmfm(fm)){KMH|KT|MPS} {CAVOK|VVVV {w'w'|NSW}} ({NsNsNs|VVV}hshshs|NSC) ...}

TAF:

 {TTYYGGgg|{PROB C2C2 (TTTTT)|TTTTT} YYGG/YeYeGeGe} dddff(f)(Gfmfm(fm)){KMH|KT|MPS}
  {CAVOK|VVVV {w'w'|NSW} ({NsNsNs|VVV}hshshs|NSC)}
  ...

=cut

    # METAR: if NOSIG is last group but not next, move here
    if (   !$is_taf && !/\GNOSIG / && / NOSIG $/
        && (   exists $metar{QNH} || exists $metar{QFE}
            || (exists $metar{temperature} && _cyInString(\@cy, ' MH MG '))))
    {
        my $pos;

        $pos = pos $_;
        s/\G/NOSIG /;
        s/NOSIG $//;
        pos $_ = $pos;
        _msgModified \%metar;
    }

    # trendType NOSIG: METAR, only
    if (!$is_taf && /\G(NOSIG) /gc) {
        my $td;

        $td->{s} = $1;
        $td->{trendType} = $1;
        push @{$metar{trend}}, $td;

        # EXTENSION: allow rwyState after NOSIG. Not considered trend data!
        while (!$is_taf && _parseRwyState \%metar) {};
    }

    # EXTENSION: allow colour code after NOSIG
    if (!$is_taf && !exists $metar{colourCode} && m@\G($re_colour) @ogc) {
        $metar{colourCode} = _parseColourCode $1;
    }

    # EXTENSION: allow RH after NOSIG. Not considered trend data!
    if (_cyInString(\@cy, ' OOSA ') && /\G(RH(\d\d)) /gc) {
        $metar{RH}{s} = $1;
        $metar{RH}{relHumid} = $2 + 0;
    }

    # trendType:
    # - FM: significant change of conditions (TAF, only)
    # - BECMG: transition to different conditions
    # - TEMPO: temporarily different conditions (optional for TAF: with prob.)
    # - PROB: different conditions with a probability (TAF, only)
    # - (INTER is obsolete and will be replaced by TEMPO)
    #
    # changes at midnight: 0000 with FM/AT, 2400 with TL
    # EXTENSION: allow missing period
    # EXTENSION: FM: allow time with Z
    # EXTENSION: FM: allow time without minutes
    # EXTENSION: FM: allow 24Z? or 2400Z?
    # EXTENSION: allow mixed pre/post Aug 2007 format but warn about periods in
    #   old format
    # EXTENSION: METAR from Yxxx: allow FM
    while (1) {
        my ($td, $no_keys, $period_vis, $r);

        if (   ($is_taf || _cyInString(\@cy, ' Y '))
            && /\G(FM(?:($re_hour)($re_min)?|(24)(?:00)?)Z?) /ogc)
        {
            $td->{s} = $1;
            $td->{trendType} = 'FM';
            if (defined $2) {
                $td->{timeFrom}{hour}   = $2;
                $td->{timeFrom}{minute} = $3 if defined $3;
            } else {
                $td->{timeFrom}{hour} = $4;
            }
            $s_preAug2007 .= ' ' . $td->{s} if $is_taf;
        } elsif (   ($is_taf || _cyInString(\@cy, ' Y '))
                 && /\G(FM($re_day)($re_hour)($re_min)) /ogc)
        {
            $td->{s} = $1;
            $td->{trendType} = 'FM';
            $td->{timeFrom} = { day => $2, hour => $3, minute => $4 };
            $is_taf_Aug2007 = 1 if $is_taf;
        } elsif (   $is_taf
                 && /\G((BECMG|TEMPO|INTER)|PROB([34]0)(?: (TEMPO|INTER))?) /gc)
        {
            $td->{s} = $1;
            if (defined $2) {
                $td->{trendType} = $2;
            } else {
                $td->{probability} = $3;
                $td->{trendType} = defined $4 ? $4 : 'PROB';
            }

            if (/\G($re_hour|24)($re_hour|24) /ogc) {
                $td->{s} .= " $1$2";
                $td->{timeFrom}{hour} = $1;
                $td->{timeTill}{hour} = $2;
                $s_preAug2007 .= ' ' . $td->{s};
                $period_vis = $1 if "$1$2" =~ /^($re_vis_m)$/;
            } elsif (m@\G($re_day)($re_hour|24)/($re_day)($re_hour|24) @ogc) {
                $td->{s} .= " $1$2/$3$4";
                $td->{timeFrom} = { day => $1, hour => $2 };
                $td->{timeTill} = { day => $3, hour => $4 };
                $is_taf_Aug2007 = 1;
            } else {
                push @{$metar{warning}},
                                    { warningType => 'periodMissing', s => $1 };
            }
        } elsif (!$is_taf && /\G(BECMG|TEMPO) /gc) {
            $td->{s} = $1;
            $td->{trendType} = $1;

            if (/\G((?:TL2400|(?:FM|TL|AT)$re_hour$re_min)Z?) /ogc) {
                $td->{s} .= " $1";
                $1 =~ /(..)(..)(..)/;
                $td->{{ FM => 'timeFrom',
                        TL => 'timeTill',
                        AT => 'timeAt' }->{$1}} = { hour => $2, minute => $3 };

                if (/\GTL(2400Z?|$re_hour${re_min}Z?) /ogc) {
                    $td->{s} .= " TL$1";
                    @{$td->{timeTill}}{qw(hour minute)} = $1 =~ /(..)(..)/;
                }
            }
        } else {
            last;
        }
        $no_keys = keys(%$td);

        if (m@\G($re_wind) @ogc) {
            $td->{sfcWind} = { s => $1, wind => _parseWind $1, 1 };
        # EXTENSION: allow invalid formats
        } elsif (/\G(${re_wind_dir}0$re_wind_speed|\d{6}$re_wind_speed_unit) /ogc)
        {
            $td->{sfcWind} = { s => $1, wind => { invalidFormat => $1 }};
        }

        # EXTENSION: allow variation
        if (/\G($re_wind_dir\d)V($re_wind_dir\d) /ogc) {
            if (exists $td->{sfcWind}) {
                $td->{sfcWind}{s} .= ' ';
            } else {
                # TODO?: actually not "not available" but missing
                $td->{sfcWind} = {
                    s    => '',
                    wind => { dirNotAvailable=>undef, speedNotAvailable=>undef }
                };
            }
            $td->{sfcWind}{s} .= "$1V$2";
            @{$td->{sfcWind}{wind}}{qw(windVarLeft windVarRight)} =
                                                               ($1 + 0, $2 + 0);
        }

        if (/\GCAVOK /gc) {
            $td->{CAVOK} = undef;
        }

        if (!exists $td->{CAVOK}) {
            # EXTENSION: allow 'M' after re_vis_m
            if (m@\G(($re_vis_m)M?|($re_vis_km)|($re_vis_sm) ?SM) @ogc) {
                if (defined $2) {
                    $td->{visPrev}{distance} = _getVisibilityM $2;
                } elsif (defined $3) {
                    $td->{visPrev}{distance} = { v => $3, rp => 1, u => 'KM' };
                    $td->{visPrev}{distance}{v} =~ s/KM//;
                } else {
                    $td->{visPrev} = _getVisibilitySM $4, $is_auto, \@cy;
                }
                $td->{visPrev}{s} = $1;
            } elsif ($is_taf && /\G(P?[1-9]\d*)SM /gc) {
                $td->{visPrev} = _getVisibilitySM $1, $is_auto, \@cy;
                $td->{visPrev}{s} = "$1SM";
            } elsif (/\G(\d{3,4}M?) /gc) {
                $td->{visPrev}{s} = $1;
                $td->{visPrev}{invalidFormat} = $1;
            } elsif (!exists $td->{sfcWind} && $period_vis) {
                # check for ambiguous period/wind group: BECMG 2000 could mean:
                #    - 2000 is a period in pre Aug 2007 format, or
                #    - period is missing (should not be), 2000 is visibility
                push @{$metar{warning}}, {
                    warningType => 'ambigPeriodVis',
                    s           => $period_vis
                };
            }

            # EXTENSION: allow VC..
            while (m@\G(?:($re_weather)(?:/? |/(?=$re_weather[ /]))|(NSW) |(//|[+-]?(?:RE|VC|$re_weather_desc|$re_weather_prec|$re_weather_obsc|$re_weather_other)+) )@ogc)
            {
                if (defined $3) {
                    push @{$td->{weather}}, {
                        s             => $3,
                        invalidFormat => $3
                    };
                } else {
                    push @{$td->{weather}}, _parseWeather defined $1 ? $1 : $2;
                }
            }

            while (/\G((SKC|NSC)|VV($re_cloud_base)|($re_cloud_cov$re_cloud_base$re_cloud_type?|$re_cloud_cov$re_cloud_type)) /ogc)
            {
                if (defined $2) {
                    push @{$td->{cloud}}, {
                        s        => $1,
                        noClouds => $2
                    };
                } elsif (defined $3) {
                    if (exists $td->{visVert}) {
                        push @{$td->{cloud}}, {
                            s             => $1,
                            invalidFormat => $1
                        };
                    } else {
                        $td->{visVert} = {
                            s => $1,
                            $3 eq '///'
                                    ? (notAvailable => undef)
                                    : (distance => { v => $3 * 100, u => 'FT' })
                        };
                    }
                } else {
                    push @{$td->{cloud}}, _parseCloud $4;
                }
            }
            _determineCeiling $td->{cloud} if exists $td->{cloud};

            # EXTENSION: allow colour code
            if (!$is_taf && m@\G($re_colour) @ogc) {
                $td->{colourCode} = _parseColourCode $1;
            }

            # EXTENSION: allow turbulence forecast as the only item of a trend
            if (   !$is_taf
                && _cyInString(\@cy, ' Y ')
                && keys(%$td) == $no_keys
                && ($r = _turbulenceTxt))
            {
                if (exists $r->{timeFrom}) {
                    $metar{ERROR} = _makeErrorMsgPos 'other';
                    return %metar;
                }
                if (exists $r->{timeTill}) {
                    if (exists $td->{timeTill} || exists $td->{timeAt}) {
                        $metar{ERROR} = _makeErrorMsgPos 'other';
                        return %metar;
                    } else {
                        $td->{timeTill} = $r->{timeTill};
                        delete $r->{timeTill};
                    }
                }
                push @{$td->{TAFsupplArr}}, { turbulence => $r };
            }
        }

        # EXTENSION: allow rwyState after trend BECMG / TEMPO
        while (!$is_taf && _parseRwyState $td) {};

        # "supplementary" section and additional info of TAFs
        while ($is_taf && _parseTAFsuppl $td, \%metar, \@cy) {};

        push @{$metar{trend}}, $td;

        # empty trend?
        if (keys(%$td) == $no_keys) {
            $metar{ERROR} = _makeErrorMsgPos 'noTrendData';
            last;
        }
    }

    if ($is_taf_Aug2007 && $s_preAug2007 ne '') {
        $s_preAug2007 =~ s/^ //;
        push @{$metar{warning}}, {
            warningType => 'mixedFormat4TafPeriods',
            s           => $s_preAug2007
        };
    }
    return %metar if exists $metar{ERROR};

    # EXTENSION: add 'RMK' for METAR if QNH/QFE exists and no trend/RMK follow
    if (   !$is_taf
        && (   exists $metar{QNH} || exists $metar{QFE}
            || (exists $metar{temperature} && _cyInString(\@cy, ' MH MG ')))
        && /\G./
        && !m@\G.*?(?:NOSIG|BECMG|TEMPO|INTER|PROB[34]0|RMK)[/ ]@)
    {
        my $pos;

        $pos = pos $_;
        s/\G/RMK /;
        pos $_ = $pos;
        _msgModified \%metar;
    }

=head3 Remarks

Finally, there may be remarks.

 RMK ...

The parser recognises more than 80 types of remarks for METARs, plus about 50
keywords/keyword groups, and 5 types of remarks for TAFs. They include
(additional) information about wind and visibility (at different locations,
also max./min.), cloud (also types), pressure (also change), temperature (more
accurate, also max. and min.), runway state, duration of sunshine,
precipitation (also amounts, start, end), weather phenomena (with location,
moving direction), as well as administrative information (e.g.
correction/amendment, LAST, NEXT, broken measurement equipment). Some countries
publish documentation about the contents, but this section can contain any free
text.

=cut

    if (m@\GRMK[ /] ?@gc) {
        my ($notRecognised, $had_CA_RMK_prsChg);

        @{$metar{remark}} = ();

        $notRecognised = '';
        $old_pos = -1;
        while (/\G./) {
            my ($parsed, $r);

            if ($old_pos == pos $_) {
                # "cannot" happen, prevent endless loop
                $metar{ERROR} = _makeErrorMsgPos 'internal';
                return %metar;
            }
            $old_pos = pos $_;

            $parsed = 1;
            $r = {};
            if (   $notRecognised =~ /DUE(?: TO)?(?: $re_phen_desc| GROUND)?$/o
                || $notRecognised =~ /BY(?: $re_phen_desc| GROUND)?$/o)
            {
                $parsed = 0;
            } elsif (!$is_taf && _parseRwyState $r) {
                push @{$metar{remark}}, { rwyState => $r->{rwyState}[0] };
            } elsif (_parseRwyVis $r) {
                push @{$metar{remark}}, { visRwy => $r->{visRwy}[0] };
            } elsif (   _cyInString(\@cy, ' EQ LI OA ')
                     && /\G($re_cloud_cov|SKC) /ogc)
            {
                push @{$metar{remark}}, { cloudMaxCover => {
                    s => $1,
                    ($1 eq 'SKC' ? 'noClouds' : 'cloudCover') => $1
                }};
            } elsif (   _cyInString(\@cy, ' BKPR EG EQ ET FH L OA PGUA ')
                     && !$is_taf
                     && m@\G($re_colour) @ogc)
            {
                push @{$metar{remark}}, { colourCode => _parseColourCode $1 };
            } elsif (   _cyInString(\@cy, ' cJP cUS MM RK UT ')
                     && m@\G(8/([\d/])([\d/])([\d/])) @gc)
            {
                push @{$metar{remark}}, { cloudTypes => {
                    s => $1,
                    $2 eq '/' ? (cloudTypeLowNA => undef)
                              : (cloudTypeLow => $2),
                    $3 eq '/' ? (cloudTypeMiddleNA => undef)
                              : (cloudTypeMiddle => $3),
                    $4 eq '/' ? (cloudTypeHighNA => undef)
                              : (cloudTypeHigh => $4),
                }};
            } elsif (m@\G(PWINO|FZRANO|TSNO|PNO|RVRNO|NO ?SPECI|VIA PHONE|RCRNR|(?:LGT |HVY )?FROIN|SD[FGP]/HD[FGP]|VRBL CONDS|ACFT MSHP|(?:LTG DATA|RVR|CLD|WX|$re_vis|ALTM|WND) MISG|FIBI)[ /] ?@ogc)
            {
                $r->{s} = $1;
                ($r->{v} = $1) =~ tr/ /_/;
                $r->{v} =~ s/NO_?SPECI/NOSPECI/;
                $r->{v} =~ s/^$re_vis/VIS/;
                push @{$metar{remark}}, { keyword => $r };
            } elsif (m@\G/ @gc){
                push @{$metar{remark}}, { keyword => {
                    s => '/',
                    v => 'slash'
                }};
            } elsif (/\G\$ /gc){
                push @{$metar{remark}}, { needMaint => { s => '$' }};
            } elsif (   _cyInString(\@cy, ' cCA cUS ')
                     && /\G(CIG ?(?:RAG|RGD)) /gc)
            {
                $r->{s} = $1;
                ($r->{v} = $1) =~ tr/ /_/;
                $r->{v} =~ s/RGD/RAG/;
                $r->{v} =~ s/CIGRAG/CIG_RAG/;
                push @{$metar{remark}}, { keyword => $r };
            } elsif (   _cyInString(\@cy, ' cCA ')
                     && /\G(CIG VRBL? ([1-9]\d*)-([1-9]\d*)) /gc)
            {
                $r->{s} = $1;
                $r->{visibilityFrom}{distance} = { v => $2 * 100, u => 'FT' };
                $r->{visibilityTo}{distance}   = { v => $3 * 100, u => 'FT' };
                push @{$metar{remark}}, { ceilVisVariable => $r };
            } elsif (   _cyInString(\@cy, ' cCA cJP cUS BGTL EG EQ ET LI LQ MM NZ OA RK TXKF ')
                     && m@\G(SLP ?(?:(\d\d)(\d)|NO|///)) @gc)
            {
                if (!defined $2) {
                    push @{$metar{remark}}, { SLP => {
                        s            => $1,
                        notAvailable => undef
                    }};
                # TODO: really need QNH? but values are REALLY close:
                # KLWM 161454Z AUTO 31012G21KT 10SM CLR M10/M18 A2808 RMK SLP511
                #   -> 951.1 hPa
                # KQHT 021355Z 26003KT 8000 IC M15/M16 A3070 RMK SLP484
                #   -> 1048.4 hPa
                # higher QNHs possible:
                # ETNS 161520Z 11006KT 7000 FEW020 M02/M05 Q1078 WHT WHT
                #   -> SLP78?
                # UNWW 021400Z 00000MPS CAVOK M25/M29 Q1056 NOSIG RMK QFE759
                #   -> SLP56?
                } elsif (!$qnhHPa && !$qnhInHg) {
                    if ($2 > 65 || $2 < 45) { # only if within sensible range
                        my $slp;

                        $slp = "$2.$3";
                        # threshold 55 taken from mdsplib
                        $slp += $slp < 55 ? 1000 : 900;
                        push @{$metar{remark}}, { SLP => {
                            s        => $1,
                            pressure =>
                                      { v => sprintf('%.1f', $slp), u => 'hPa' }
                        }};
                    } else {
                        push @{$metar{remark}}, { SLP => {
                            s => $1,
                            invalidFormat => "no QNH, x$2.$3 hPa"
                        }};
                    }
                } else {
                    # low temperature: SLP significantly greater than QNH:
                    # KEEO 111353Z ... M22/M23 A3046 RMK ... SLP437: 1031<->1043
                    # high altitude: SLP significantly smaller than QNH:
                    # KBJN 122256Z ... 11/M08 A3013 RMK ... SLP072: 1020<->1007
                    my ($slp, @slp, $qnh);
                    my $INHG2HPA = 33.86388640341;

                    @slp = ($1, $2, $3);
                    $qnh = _rnd($qnhHPa ? $qnhHPa : $qnhInHg * $INHG2HPA, 1);
                    $slp = $qnh;                          # start with given QNH
                    $slp =~ s/..$//;                  # remove 2 trailing digits
                    $slp .= "$slp[1].$slp[2]";              # append given value
                    $slp += 100 if $slp + 50 < $qnh;     # make SLP close to QNH
                    $slp -= 100 if $slp - 50 > $qnh;
                    push @{$metar{remark}}, { SLP => {
                        s        => $slp[0],
                        pressure => { v => sprintf('%.1f', $slp), u => 'hPa' }
                    }};
                }
            } elsif (_cyInString(\@cy, ' ROTM ') && /\G(SP([23]\d\.\d{3})) /gc){
                push @{$metar{remark}}, { SLP => {
                    s        => $1,
                    pressure => { v => $2, u => 'inHg' }
                }};
            } elsif (_cyInString(\@cy, ' NZ ') && m@\GGRID($re_wind) @ogc) {
                push @{$metar{remark}}, { sfcWind => {
                    s             => "GRID$1",
                    measurePeriod => {
                        v => (_cyInString(\@cy, ' cUS ') ? 2 : 10),
                        u => 'MIN'
                    },
                    wind => _parseWind $1, 0, 1
                }};
            } elsif (   _cyInString(\@cy, ' BG EN LC LG LH LT SP UL ')
                     && m@\G($re_rwy_wind) @ogc)
            {
                $r->{rwyWind}{s} = $1;
                $r->{rwyWind}{rwyDesig} = defined $2 ? $2 : $3;
                $r->{rwyWind}{wind} = _parseWind $4;
                $r->{rwyWind}{wind}{windVarLeft} = $5 + 0 if defined $5;
                $r->{rwyWind}{wind}{windVarRight} = $6 + 0 if defined $6;
                push @{$metar{remark}}, $r;
            } elsif (_cyInString(\@cy, ' RC ') && m@\G($re_rwy_wind2) @ogc) {
                push @{$metar{remark}}, { rwyWind => {
                    s        => $1,
                    wind     => _parseWind($2),
                    rwyDesig => $3
                }};
            } elsif (   _cyInString(\@cy, ' cJP cUS BG EGUN ET LQTZ NZ RK ')
                     && m@\G($re_rsc) @ogc)
            {
                $r->{s} = $1;
                for ($1 =~ /SLR|LSR|PSR|P|SANDED|WET|DRY|IR|WR|\/\/|\d\d/g){
                    if ($_ eq '//') {
                        push @{$r->{rwySfcCondArr}}, { notAvailable => undef };
                    } elsif ($_ =~ /\d/) {
                        push @{$r->{rwySfcCondArr}}, { decelerometer => $_ };
                    } else {
                        push @{$r->{rwySfcCondArr}}, { rwySfc => $_ };
                    }
                }
                push @{$metar{remark}}, { rwySfcCondition => $r };
            } elsif (   _cyInString(\@cy, ' cCA cUS ')
                     && /\G(((?:$re_opacity_phenom[0-8])+)(?: ($re_cloud_type) (?:(ASOCTD?)|(EMBD)))?) /ogc)
            {
                $r->{s} = $1;
                $r->{opacityPhenomArr} = ();
                _parseOpacityPhenom $r, $2;
                $r->{cloudTypeAsoctd} = $3 if defined $4;
                $r->{cloudTypeEmbd}   = $3 if defined $5;
                push @{$metar{remark}}, { opacityPhenom => $r };
            } elsif (   _cyInString(\@cy, ' BG KTTS ')
                     && /\G([0-8])($re_opacity_phenom) /ogc)
            {
                $r->{s} = "$1$2";
                $r->{opacityPhenomArr} = ();
                _parseOpacityPhenom $r, "$2$1";
                push @{$metar{remark}}, { opacityPhenom => $r };
            } elsif (   _cyInString(\@cy, ' cJP MN Y ')
                     && m@\G(([0-8])(?:((?:BL)?SN|FG)|($re_cloud_type))(\d{3})(?: TO)?($re_loc)?) @ogc)
            {
                push @{$metar{remark}}, { cloudOpacityLvl => {
                    s => $1,
                    sortedArr => [
                        defined $6 ? { locationAnd => _parseLocations $6 } : (),
                        { oktas => $2 },
                        defined $3 ? { weather => _parseWeather $3, 'NI' } : (),
                        defined $4 ? { cloudType => $4 } : (),
                        { cloudBase => { v => $5 * 100, u => 'FT' }}
                ]}};
            } elsif (   _cyInString(\@cy, ' cUS EG ET LI NZ RK ')
                     && /\G(($re_cloud_cov$re_cloud_base?) V ($re_cloud_cov)) /ogc)
            {
                $r->{cloudCoverVar} = _parseCloud $2;
                $r->{cloudCoverVar}{s} = $1;
                $r->{cloudCoverVar}{cloudCover2} = $3;
                push @{$metar{remark}}, $r;
            } elsif (   _cyInString(\@cy, ' cCA cUS BI EK EQ LG LI LL MG MH MR MS NT OA OI ')
                     && /\G($re_cloud_cov$re_cloud_base$re_cloud_type?) /ogc)
            {
                push @{$metar{remark}}, { cloud => _parseCloud $1 };
            } elsif (   _cyInString(\@cy, ' U ')
                     && /\G($re_cloud_type)($re_cloud_base) /ogc)
            {
                push @{$metar{remark}}, { cloudTypeLvl => {
                    s         => "$1$2",
                    cloudType => $1,
                    $2 eq '///' ? ()
                                : (cloudBase => { v => $2 * 100, u => 'FT' })
                }};
            } elsif (   _cyInString(\@cy, ' cCA ')
                     && m@\G(TRS?( LWR)?(?: CLD|((?:[/ ]?$re_trace_cloud)+))($re_loc)?) @ogc)
            {
                $r->{s} = $1;
                $r->{isLower} = undef if defined $2;
                if (defined $3) {
                    for ($3 =~ /$re_trace_cloud/og) {
                        push @{$r->{cloudType}}, $_;
                    }
                } else {
                    $r->{cloudTypeNotAvailable} = undef;
                }
                $r->{locationAnd} = _parseLocations $4 if defined $4;
                push @{$metar{remark}}, { cloudTrace => $r };
            } elsif (   _cyInString(\@cy, ' cCA ')
                     && m@\G(((?:$re_trace_cloud[/ ])+)TR) @ogc)
            {
                $r->{s} = $1;
                for ($2 =~ /$re_trace_cloud/og) {
                    push @{$r->{cloudType}}, $_;
                }
                push @{$metar{remark}}, { cloudTrace => $r };
            } elsif (   _cyInString(\@cy, ' MR ')
                     && /\G(TRACE ($re_trace_cloud)) /ogc)
            {
                $r->{s} = $1;
                for ($2 =~ /$re_trace_cloud/og) {
                    push @{$r->{cloudType}}, $_;
                }
                push @{$metar{remark}}, { cloudTrace => $r };
            } elsif (/\GRE($re_weather_re) /ogc) {
                push @{$metar{remark}},
                               { recentWeather => [ _parseWeather($1, 'RE') ] };
            } elsif (   _cyInString(\@cy, ' KQ ')
                     && /\G(SFC $re_vis (?:($re_vis_m)|($re_vis_km))) /ogc)
            {
                $r->{s} = $1;
                $r->{locationAt} = 'SFC';
                if (defined $2) {
                    $r->{visibility}{distance} = _getVisibilityM $2;
                } else {
                    $r->{visibility}{distance} = { v => $3, rp => 1, u => 'KM'};
                    $r->{visibility}{distance}{v} =~ s/KM//;
                }
                push @{$metar{remark}}, { visibilityAtLoc => $r };
            } elsif (   _cyInString(\@cy, ' cCA cUS ')
                     && m@\G((SFC|TWR|ROOF) $re_vis ($re_vis_sm)(?: ?SM)?) @ogc)
            {
                $r->{s} = $1;
                $r->{locationAt} = $2;
                $r->{visibility} = _getVisibilitySM $3, $is_auto, \@cy;
                push @{$metar{remark}}, { visibilityAtLoc => $r };
            } elsif (   _cyInString(\@cy, ' cUS ')
                     && m@\G($re_vis ($re_vis_sm)V($re_vis_sm)(?: ?SM)?) @ogc)
            {
                $r->{visVar1} = _getVisibilitySM $2, $is_auto, \@cy;
                delete $r->{visVar1}{distance}{rp};
                $r->{visVar2} = _getVisibilitySM $3, $is_auto, \@cy;
                delete $r->{visVar2}{distance}{rp};
                $r->{visVar1}{s} = $1;
                push @{$metar{remark}}, $r;
            } elsif (   _cyInString(\@cy, ' cCA ')
                     && m@\G($re_vis(?: VRB)? ($re_vis_sm) ?- ?($re_vis_sm)(?: ?SM)?) @ogc)
            {
                $r->{visVar1} = _getVisibilitySM $2, $is_auto, \@cy;
                delete $r->{visVar1}{distance}{rp};
                $r->{visVar2} = _getVisibilitySM $3, $is_auto, \@cy;
                delete $r->{visVar2}{distance}{rp};
                $r->{visVar1}{s} = $1;
                push @{$metar{remark}}, $r;
            } elsif (   _cyInString(\@cy, ' cCA ')
                     && m@\G((/?)([RS])(\d\d)(?: AFT ?($re_hour)($re_min)? ?(?:Z|UTC)?)?\2) @ogc)
            {
                # MANOBS 10.2.19.9, .10, .11
                my $timeSince;

                if (defined $5) {
                    $timeSince = {
                        hour => $5,
                        defined $6 ? (minute => $6) : ()
                    };
                } else {
                    $timeSince = _timeSinceSynopticMain $obs_hour,
                        defined $obs_hour ? $metar{obsTime}{timeAt}{minute} : 0;
                }
                push @{$metar{remark}}, {
                    ($3 eq 'S' ? 'snowFall' : 'precipitation') => {
                        s            => $1,
                        timeSince    => $timeSince,
                        precipAmount => { v => $4 + 0,
                                          u => ($3 eq 'S' ? 'CM' : 'MM') }
                }};
            } elsif (   _cyInString(\@cy, ' cCA ')
                     && /\G(VSBY VRBL (\d\.\d)V(\d)(\.[+\d])) /gc)
            {
                $r->{visVar1} = _getVisibilitySM $2, $is_auto, \@cy;
                delete $r->{visVar1}{distance}{rp};
                $r->{visVar2} = _getVisibilitySM $4 eq '.+' ? "P$3" : "$3$4", $is_auto, \@cy;
                delete $r->{visVar2}{distance}{rp};
                $r->{visVar1}{s} = $1;
                push @{$metar{remark}}, $r;
            } elsif (   _cyInString(\@cy, ' EG ET ')
                     && /\G(VIS (\d{4})V(\d{4})) /gc)
            {
                $r->{visVar1}{distance} = _getVisibilityM $2;
                delete $r->{visVar1}{distance}{rp};
                $r->{visVar2}{distance} = _getVisibilityM $3;
                delete $r->{visVar2}{distance}{rp};
                $r->{visVar1}{s} = $1;
                push @{$metar{remark}}, $r;
            } elsif (   _cyInString(\@cy, ' cCA ')
                     && /\G(PCPN (\d+\.\d)MM PAST HR) /gc)
            {
                push @{$metar{remark}}, { precipitation => {
                    s             => $1,
                    timeBeforeObs => { hours => 1 },
                    precipAmount  => { v => $2 + 0, u => 'MM' }
                }};
            } elsif (   _cyInString(\@cy, ' BG RK ')
                     && m@\G($re_vis ?($re_vis_m_km_remark)(?: TO | )?($re_compass_dir16(?:-$re_compass_dir16)*)) @ogc)
            {
                $r->{s} = $1;
                $r->{visLocData}{locationAnd} = _parseLocations $3;
                $2 =~ m@($re_vis_m)|([1-9]\d{2,3})M|($re_vis_km)@o;
                if (defined $1) {
                    $r->{visLocData}{visibility}{distance} = _getVisibilityM $1;
                } elsif (defined $2) {
                    $r->{visLocData}{visibility}{distance} =
                                            _getVisibilityM sprintf('%04d', $2);
                } else {
                    $r->{visLocData}{visibility}{distance} =
                                                { v => $3, rp => 1, u => 'KM' };
                    $r->{visLocData}{visibility}{distance}{v} =~ s/KM//;
                }
                push @{$metar{remark}}, { visListAtLoc => $r };
            } elsif (   _cyInString(\@cy, ' cJP E KQ LQ NZ ')
                     && m@\G($re_vis((?:$re_loc $re_vis_m_km_remark)(?:(?: AND)?$re_loc $re_vis_m_km_remark)*)) @ogc)
            {
                my @visLocData;

                $r->{visListAtLoc}{s} = $1;
                $r->{visListAtLoc}{visLocData} = \@visLocData;
                for ($2 =~ m@$re_loc $re_vis_m_km_remark@og){
                    my $v;

                    m@($re_loc) (?:($re_vis_m)|([1-9]\d{2,3})M|($re_vis_km))@o;
                    $v->{locationAnd} = _parseLocations $1;
                    if (defined $2) {
                        $v->{visibility}{distance} = _getVisibilityM $2;
                    } elsif (defined $3) {
                        $v->{visibility}{distance} =
                                            _getVisibilityM sprintf('%04d', $3);
                    } else {
                        $v->{visibility}{distance} = { v => $4, rp => 1, u => 'KM' };
                        $v->{visibility}{distance}{v} =~ s/KM//;
                    }
                    push @visLocData, $v;
                }
                push @{$metar{remark}}, $r;
            } elsif (_cyInString(\@cy, ' MH ') && m@\G((\d+)KM($re_loc)) @gc) {
                $r->{s} = $1;
                $r->{visLocData}{locationAnd} = _parseLocations $3;
                $r->{visLocData}{visibility}{distance} =
                                                { v => $2, rp => 1, u => 'KM' };
                push @{$metar{remark}}, { visListAtLoc => $r };
            } elsif (m@\G($re_vis($re_loc) LWR) @ogc) {
                push @{$metar{remark}}, { phenomenon => {
                    s           => $1,
                    otherPhenom => 'VIS_LWR',
                    locationAnd => _parseLocations $2
                }};
            } elsif (   _cyInString(\@cy, ' cJP LI OA RC RP SE ')
                     && /\G(A)([23]\d)(\d\d) /gc)
            {
                push @{$metar{remark}}, { QNH => {
                    s        => "$1$2$3",
                    pressure => { v => "$2.$3", u => 'inHg' }
                }};
            } elsif (   _cyInString(\@cy, ' KQ OA ')
                     && /\G(Q(?:NH)?([01]\d{3})(?:MB)?) /gc)
            {
                push @{$metar{remark}}, { QNH => {
                    s        => $1,
                    pressure => { v => $2, u => 'hPa' }
                }};
            } elsif (_cyInString(\@cy, ' MM ') && /\G([7-9]\d\d) /gc) {
                push @{$metar{remark}}, { QFF => {
                    s => $1,
                    pressure => { v => $1, u => 'hPa' }
                }};
            } elsif (/\G(QNH([01]\d{3}\.\d)) /gc) {
                push @{$metar{remark}}, { QNH => {
                    s        => $1,
                    pressure => { v => $2, u => 'hPa' }
                }};
            } elsif (/\G(COR ($re_hour)($re_min))Z? /ogc) {
                push @{$metar{remark}}, { correctedAt => {
                    s      => $1,
                    timeAt => { hour => $2, minute => $3 }
                }};
            } elsif (   _cyInString(\@cy, ' cUS ')
                     && m@\G(SNINCR (\d+)/(\d+)) @gc)
            {
                push @{$metar{remark}}, { snowIncr => {
                    s        => $1,
                    pastHour => $2,
                    onGround => $3
                }};
            } elsif (   _cyInString(\@cy, ' cCA cJP cUS BG EG ET EQ LI LQ MM RKSO ')
                     && /\G1([01]\d{3}) /gc)
            {
                push @{$metar{remark}}, { tempMax => {
                    s             => "1$1",
                    timeBeforeObs => { hours => 6 },
                    temp          => _parseTemp($1)
                }};
            } elsif (   _cyInString(\@cy, ' cCA cJP cUS BG EG ET EQ LI LQ MM RKSO ')
                     && /\G2([01]\d{3}) /gc)
            {
                push @{$metar{remark}}, { tempMin => {
                    s             => "2$1",
                    timeBeforeObs => { hours => 6 },
                    temp          => _parseTemp($1)
                }};
            } elsif (   $had_CA_RMK_prsChg
                     && _cyInString(\@cy, ' cCA ')
                     && m@\G(5(\d{4})) @gc)
            {
                # the meaning of the 5xxxx group depends on whether there
                # was a pressure change reported (as a 4-digit group) already.
                # Probably due to buggy translation from the SAO format by KWBC.
                # (more bugs: "PAST HR": leftover from "PCPN 0.4MM PAST HR",
                #             "M": (missing) should not be copied)
                push @{$metar{remark}}, { precipitation => {
                    s             => $1,
                    timeBeforeObs => { hours => 6 },
                    precipAmount  => { v => $2 / 10, u => 'MM' }
                }};
            } elsif (   (   _cyInString(\@cy, ' cCA cJP cUS BG EG ET EQ LI LQ MM RKSO ')
                         && m@\G(5(?:([0-8])(\d{3})|////)) @gc)
                     || (   _cyInString(\@cy, ' cCA ')
                         && m@\G(([0-8])(\d{3})) (?=(?:SLP|PK |T[01]\d|$))@gc
                         && ($had_CA_RMK_prsChg = 1)))
            {
                push @{$metar{remark}}, { pressureChange => {
                    s             => $1,
                    timeBeforeObs => { hours => 3 },
                    defined $2
                      ? (pressureTendency  => $2,
                         pressureChangeVal => {
                            v => sprintf('%.1f', $3 / ($2 >= 5 ? -10 : 10) + 0),
                            u => 'hPa'
                         })
                      : (notAvailable => undef)
                }};
            } elsif (   _cyInString(\@cy, ' cCA ')
                     && m@\G(\d{3}) (?=(?:SLP|PK |T[01]\d|$))@gc)
            {
                # CXTN 251800Z AUTO ... RMK ... 001 ...
                # AAXX 25184 71492 ... 5/001 ...
                push @{$metar{remark}}, { pressureChange => {
                    s             => $1,
                    timeBeforeObs => { hours => 3 },
                    invalidFormat => $1
                }};
                $had_CA_RMK_prsChg = 1;
            } elsif (   _cyInString(\@cy, ' cCA cJP cUS BG EG ET EQ LP LQ NZ ROTM ')
                     && m@\G((?:PK|MAX)[ /]?WND ?(GRID ?)?($re_wind_dir\d$re_wind_speed)($re_wind_speed_unit)?(?:/| AT )($re_hour)?($re_min)Z?) @ogc)
            {
                push @{$metar{remark}}, { peakWind => {
                    s      => $1,
                    wind   => _parseWind($3 . (defined $4 ? $4 : 'KT'),
                                         0, defined $2),
                    timeAt => { defined $5 ? (hour => $5) : (), minute => $6 }
                }};
            } elsif (   $cy[0] eq 'KEHA'
                     && m@\G(PK[ /]?WND ($re_wind_speed) 000) @ogc)
            {
                push @{$metar{remark}}, { peakWind => {
                    s    => $1,
                    wind => _parseWind "///$2KT"
                }};
            } elsif (   $cy[0] eq 'EDLP'
                     && /\GRWY ?($re_rwy_des) ?(TRL[0 ]?(\d\d)) ([A-Z]{2}) ((?:ATIS )?)([A-Z]) /ogc)
            {
                push @{$metar{remark}}, { activeRwy => {
                    s        => "RWY$1",
                    rwyDesig => $1
                }};
                push @{$metar{remark}}, { transitionLvl => {
                    s     => $2,
                    level => $3 + 0
                }};
                push @{$metar{remark}}, { obsInitials => { s => $4 }};
                push @{$metar{remark}}, { currentATIS => {
                    s    => "$5$6",
                    ATIS => $6
                }};
            } elsif (_cyInString(\@cy, ' LSZR EDHL ') && /\G([A-Z]) /gc){
                push @{$metar{remark}}, { currentATIS => {
                    s    => $1,
                    ATIS => $1
                }};
            } elsif (_cyInString(\@cy, ' VT ') && /\G(RWY ?($re_rwy_des)) /ogc){
                push @{$metar{remark}}, { activeRwy => {
                    s        => $1,
                    rwyDesig => $2
                }};
            } elsif (_cyInString(\@cy, ' VT ') && /\G(INFO[ :]*([A-Z])) /gc) {
                push @{$metar{remark}}, { currentATIS => {
                    s    => $1,
                    ATIS => $2
                }};
            } elsif (   _cyInString(\@cy, ' cCA cJP cUS BG EG ET EQ LI RKSO ')
                     && /\G(T([01]\d{3})([01]\d{3})?) /gc)
            {
                $r->{s} = $1;
                $r->{air}{temp} = _parseTemp $2;
                if (defined $3) {
                    $r->{dewpoint}{temp} = _parseTemp $3;
                    _setHumidity $r;
                }
                push @{$metar{remark}}, { temperature => $r };
            } elsif (_cyInString(\@cy, ' cUS ') && m@\G(98(?:(\d{3})|///)) @gc){
                $r->{s} = $1;
                $r->{sunshinePeriod} = 'p';
                if (defined $2) {
                    $r->{sunshine} = { v => $2 + 0, u => 'MIN' };
                } else {
                    $r->{sunshineNotAvailable} = undef;
                }
                push @{$metar{remark}}, { radiationSun => $r };
            } elsif (   _cyInString(\@cy, ' UTTP UTSS ')
                     && /\G(QFE([01]?\d{3})) /gc)
            {
                push @{$metar{remark}}, { QFE => {
                    s        => $1,
                    pressure => { v => $2 + 0, u => 'hPa' }
                }};
            } elsif (   _cyInString(\@cy, ' cCA cUS OA OM ')
                     && m@\G(/?(DA|DENSITY ALT|PA)[ /]?([+-]?\d+)(?:FT)?/?) @gc)
            {
                push @{$metar{remark}}, { ({ DA            => 'densityAlt',
                                             'DENSITY ALT' => 'densityAlt',
                                             PA            => 'pressureAlt'
                                           }->{$2})
                                          => {
                    s        => $1,
                    altitude => { v => $3 + 0, u => 'FT' }
                }};
            } elsif (/\G(R\.?H ?\.? ?(\d\d)(?: ?PC)?) /gc) {
                push @{$metar{remark}}, { RH => { s => $1, relHumid => $2 + 0}};
            } elsif (   _cyInString(\@cy, ' KNIP ')
                     && m@\G((RH|SST|AI|OAT)/(\d\d)F?) @gc)
            {
                $r->{s} = $1;
                if ($2 eq 'SST' || $2 eq 'OAT') {
                    $r->{temp} = { v => $3 + 0, u => 'F' };
                } elsif ($2 eq 'RH') {
                    $r->{relHumid} = $3 + 0;
                } else {
                    $r->{"$2Val"} = $3 + 0;
                }
                push @{$metar{remark}}, { $2 => $r };
            } elsif (_cyInString(\@cy, ' KN ') && m@\G((RH|SST)/(\d+)) @gc) {
                $r->{s} = $1;
                if ($2 eq 'SST') {
                    $r->{temp} = { v => $3 + 0, u => 'C' };
                } else {
                    $r->{relHumid} = $3 + 0;
                }
                push @{$metar{remark}}, { $2 => $r };
            } elsif (   _cyInString(\@cy, ' U ZM ')
                     && m@\G(QFE ?(\d{3})(?:[,.](\d))?(?:/(\d{3,4}))?) @gc)
            {
                $r->{s} = $1;
                push @{$r->{pressure}},
                    { v => ($2 + 0) . (defined $3 ? ".$3" : ''), u => 'mmHg' };
                push @{$r->{pressure}}, { v => ($4 + 0), u => 'hPa' }
                    if defined $4;
                push @{$metar{remark}}, { QFE => $r };
            } elsif (/\G(((?:VIS|CHI)NO) R(?:WY)? ?($re_rwy_des)) /ogc) {
                push @{$metar{remark}}, { $2 => {
                    s => $1,
                    rwyDesig => $3
                }};
            } elsif (_cyInString(\@cy, ' cCA ') && m@\G($re_snw_cvr) @ogc) {
                $r->{s} = $1;
                $r->{snowCoverType} = defined $2 ? $2 : 'NIL';
                $r->{snowCoverType} =~ s/ONE /ONE_/;
                $r->{snowCoverType} =~ s/MU?CH /MUCH_/;
                $r->{snowCoverType} =~ s/TR(?:ACE ?)? ?/TRACE_/;
                $r->{snowCoverType} =~ s/MED(?:IUM)?/MEDIUM/;
                $r->{snowCoverType} =~ s/ PACK(?:ED)?/_PACKED/;
                push @{$metar{remark}}, { snowCover => $r };
            } elsif (_cyInString(\@cy, ' cCA ') && /\G(OBS TAKEN [+](\d+)) /gc){
                push @{$metar{remark}}, { obsTimeOffset => {
                    s       => $1,
                    minutes => $2
                }};
            } elsif (   _cyInString(\@cy, ' cCA ')
                     && /\G((?:BLN (?:DSA?PRD (\d+) ?FT\.?|VI?SBL(?: TO)? (\d+) ?FT))) /gc)
            {
                $r->{s} = $1;
                if (defined $2) {
                    $r->{disappearedAt} = { distance => { v => $2, u => 'FT' }};
                } else {
                    $r->{visibleTo} = { distance => { v => $3, u => 'FT' }};
                }
                push @{$metar{remark}}, { balloon => $r };
            } elsif (   _cyInString(\@cy, ' cCA ')
                     && /\G(RVR(?: RWY ?$re_rwy_des $re_rwy_vis ?FT\.?)+) /ogc)
            {
                for ($1 =~ /((?:RVR )?RWY ?$re_rwy_des $re_rwy_vis ?FT\.?)/og) {
                    my $v;

                    $v->{s} = "$_";

                    /($re_rwy_des) ($re_rwy_vis)/;

                    $v->{rwyDesig}      = $1;
                    $v->{RVR}{distance} = { v => $2, u => 'FT' };
                    $v->{RVR}{distance}{q} = 'isLess'
                        if $v->{RVR}{distance}{v} =~ s/^M//;
                    $v->{RVR}{distance}{q} = 'isEqualGreater'
                        if $v->{RVR}{distance}{v} =~ s/^P//;
                    $v->{RVR}{distance}{v} += 0;
                    _setVisibilityFTRVROffset $v->{RVR}{distance};
                    push @{$metar{remark}}, { visRwy => $v };
                }
            } elsif (_cyInString(\@cy, ' FQ ') && m@\G(TX/(\d\d[,.]\d)) @gc) {
                $r->{tempMaxFQ}{s} = $1;
                $r->{tempMaxFQ}{temp} = { v => $2, u => 'C' };
                $r->{tempMaxFQ}{temp}{v} =~ s/,/./;
                push @{$metar{remark}}, $r;
            } elsif (   _cyInString(\@cy, ' cCA ')
                     && /\G(NXT FCST BY (?:($re_hour)|($re_day)($re_hour)($re_min))Z) /ogc)
            {
                if (defined $2) {
                    push @{$metar{remark}}, { nextFcst => {
                        s      => $1,
                        timeBy => { hour => $2 }
                    }};
                } else {
                    push @{$metar{remark}}, { nextFcst => {
                        s      => $1,
                        timeBy => { day => $3, hour => $4, minute => $5 }
                    }};
                }
            } elsif (   _cyInString(\@cy, ' cCA ')
                     && /\G(NXT FCST WILL BE ISSUED AT ($re_day)($re_hour)($re_min)Z) /ogc)
            {
                push @{$metar{remark}}, { nextFcst => {
                    s      => $1,
                    timeAt => { day => $2, hour => $3, minute => $4 }
                }};
            } elsif (   _cyInString(\@cy, ' LT ')
                     && /\G(AMD AT ($re_day)($re_hour)($re_min)Z) /ogc)
            {
                push @{$metar{remark}}, { amdAt => {
                    s      => $1,
                    timeAt => { day => $2, hour => $3, minute => $4 }
                }};
            } elsif (   _cyInString(\@cy, ' cCA ')
                     && /\G(FCST BASED ON AUTO OBS(?: ($re_hour)-($re_hour)Z| ($re_day)($re_hour)($re_min)-($re_day)($re_hour)($re_min)Z)?\.?) /ogc)
            {
                push @{$metar{remark}}, { fcstAutoObs => {
                    s => $1,
                    defined $2
                      ? (timeFrom => { hour => $2 },
                         timeTill => { hour => $3 })
                      : (),
                    defined $4
                      ? (timeFrom => { day => $4, hour => $5, minute => $6 },
                         timeTill => { day => $7, hour => $8, minute => $9 })
                      : ()
                }};
            } elsif (_cyInString(\@cy, ' EF ') && /\G(BASED ON AUTOMETAR) /gc) {
                push @{$metar{remark}}, { fcstAutoMETAR => { s => $1 }};
            } elsif (_cyInString(\@cy, ' ED ') && /\G(ATIS ([A-Z])([A-Z-]{2})?) /gc) {
                push @{$metar{remark}}, { currentATIS => {
                    s    => $1,
                    ATIS => $2
                }};
            } elsif (   m@\G(((?:$re_data_estmd[ /])+)(?:VISUALLY )?$re_estmd) @ogc
                     || m@\G($re_estmd((?:[ /]$re_data_estmd)+)) @ogc)
            {
                $r->{s} = $1;
                for ($2 =~ /$re_data_estmd/og) {
                    s/(?<=ALT)M?/M/;
                    s/WI?NDS?(?: DATA)?/WND/;
                    s/CEILING/CIG/;
                    s/(?:CIG )?BLN/CIG BLN/;
                    s/ /_/g;
                    push @{$r->{estimatedItem}}, $_;
                    $winds_est = 1 if $_ eq 'WND';
                }
                push @{$metar{remark}}, { estimated => $r };
            } elsif (/\G((?:(THN) )?($re_cloud_cov) ABV (\d{3})) /ogc) {
                $r = _parseCloud "$3$4", undef, defined $2;
                $r->{s} = $1;
                push @{$metar{remark}}, { cloudAbove => $r };
            } elsif (   _cyInString(\@cy, ' cUS NZ RK ')
                     && /\G((FU|(?:FZ)?(?:BC)?FG|BR|(?:BL)?SN|DU|PWR PLA?NT(?: PLUME)?) ($re_cloud_cov$re_cloud_base)) /ogc)
            {
                my ($cl, $phen);

                $r->{s} = $1;
                $r->{cloud} = _parseCloud $3;
                $phen = $2;
                if ($phen =~ m@^$re_weather$@o) {
                    $r->{weather} = _parseWeather $phen, 'NI';
                } else {
                    ($r->{cloudPhenom} = $phen) =~ s/ /_/g;
                    $r->{cloudPhenom} =~ s/PLANT/PLNT/g;
                }
                push @{$metar{remark}}, { obscuration => $r };
            } elsif (   _cyInString(\@cy, ' Y ')
                     && m@\G(RF(\d\d)\.(\d)/(\d{3})\.(\d)(?:/(\d{3})\.(\d))?) @gc)
            {
                #http://reg.bom.gov.au/general/reg/aviation_ehelp/metarspeci.pdf
                push @{$metar{remark}}, { rainfall => {
                    s             => $1,
                    precipArr => [
                    { precipitation => {
                        s            => "$2.$3",
                        precipAmount => { v => ($2 + 0) . ".$3", u => 'MM' },
                        timeBeforeObs => { minutes => 10 }
                      }},
                    { precipitation => {
                      s            => "$4.$5",
                      precipAmount => { v => ($4 + 0) . ".$5", u => 'MM' },
                      defined $6
                          ? (timeBeforeObs => { minutes => 60 })
                          : (timeSince     =>
                                { hour => { v => '09', q => 'localtime' } }
                            )
                    }},
                    defined $6
                        ? { precipitation => {
                            s            => "$6.$7",
                            precipAmount => { v => ($6 +0) . ".$7", u => 'MM' },
                            timeSince    =>
                                  { hour => { v => '09', q => 'localtime' } }
                          }}
                        : ()
                    ]
                }};
            } elsif (   _cyInString(\@cy, ' KHMS ')
                     && m@\G(RSNK (M)?(\d\d(?:\.\d)?)/(${re_wind_dir}0$re_wind_speed(?:G$re_wind_speed)?)($re_wind_speed_unit)?) @ogc)
            {
                my ($temp, $unit);

                $temp = $3 + 0;
                $temp *= -1 if defined $2;
                $unit = defined $5 ? $5 : 'KT';
                push @{$metar{remark}}, { RSNK => {
                    s    => $1,
                    air  => { temp => { v => $temp, u => 'C' } },
                    wind => _parseWind "$4$unit"
                }};
            } elsif (   _cyInString(\@cy, ' KNTD ')
                     && m@\G(LAG ?PK (M)?(\d\d)/(M)?(\d\d)/(${re_wind_dir}0$re_wind_speed(?:G$re_wind_speed)?)) @ogc)
            {
                my ($temp, $dewpoint);

                $temp = $3 + 0;
                $temp *= -1 if defined $2;
                $dewpoint = $5 + 0;
                $dewpoint *= -1 if defined $4;
                push @{$metar{remark}}, { LAG_PK => {
                    s        => $1,
                    air      => { temp => { v => $temp,     u => 'C' } },
                    dewpoint => { temp => { v => $dewpoint, u => 'C' } },
                    wind     => _parseWind "$6KT"
                }};
            } elsif (   _cyInString(\@cy, ' KAEG KAUN KBVS KUKT KW22 ')
                     && /\G(P(\d{3})) /gc)
            {
                push @{$metar{remark}}, { precipitation => {
                    s             => $1,
                    timeBeforeObs => { hours => 1 },
                    $2 == 0 ? (precipTraces => undef)
                            : (precipAmount =>
                                   { v => sprintf('%.2f', $2 / 100), u => 'IN' }
                              )
                }};

# nearly the same pattern twice except for the position of $re_phen_desc
# (do not match too much but don't miss anything, either)

            } elsif (m@\G((?:PR(?:ESENT )?WX )?(DSNT )?((?:(?:AND )?(?:$re_phen_desc)[/ ]?)+)$re_phenomenon4( BBLO)?(?:$re_loc_quadr3$re_wx_mov_d3?|$re_loc_quadr3?$re_wx_mov_d3)( BBLO)?(?: ($re_cloud_type) (?:(ASOCTD?)|(EMBD)))?) @ogc)
            {
                $r->{s} = $1;
                _parsePhenomDescr $r, 'phenomDescrPre', $3;
                if (defined $4) {
                    _parsePhenom \$r, $4;
                } elsif (defined $5) {
                    @{$r->{cloudType}} = split m@[/-]@, $5;
                } elsif (defined $6) {
                    # phenomenon _can_ have intensity, but it is an EXTENSION
                    $r->{weather} = _parseWeather $6, 'NI';
                } else {
                    $r->{cloudCover} = $7;
                }
                _parsePhenomDescr $r, 'phenomDescrPost', $8 if defined $8;
                $r->{locationAnd} = _parseLocations $9, $2 if defined $9;
                $r->{locationAnd} = _parseQuadrants $11, ($2 || $10)
                    if defined $11;
                $r->{$12}{locationAnd} = _parseLocations $13 if defined $13;
                $r->{isStationary} = undef if defined $14;
                $r->{locationAnd} = _parseLocations $15, $2 if defined $15;
                $r->{locationAnd} = _parseQuadrants $17, ($2 || $16)
                    if defined $17;
                $r->{$18}{locationAnd} = _parseLocations $19 if defined $19;
                $r->{isStationary} = undef if defined $20;
                _parsePhenomDescr $r, 'phenomDescrPost', $21 if defined $21;
                $r->{cloudTypeAsoctd} = $22 if defined $23;
                $r->{cloudTypeEmbd}   = $22 if defined $24;
                $r->{locationAnd}{locationThru}{location}{inDistance} = undef
                    if defined $2 && !exists $r->{locationAnd};
                if (   exists $r->{locationAnd}
                    && exists $r->{locationAnd}{obscgMtns})
                {
                    delete $r->{locationAnd}{obscgMtns};
                    $r->{obscgMtns} = undef;
                }
                push @{$metar{remark}}, { phenomenon => $r };
            } elsif (m@\G((?:PR(?:ESENT )?WX )?(DSNT )?$re_phenomenon4(?: IS)?((?:[/ ](?:$re_phen_desc|BBLO))*)(?:$re_loc_quadr3$re_wx_mov_d3?|$re_loc_quadr3?$re_wx_mov_d3)( BBLO)?(?: ($re_cloud_type) (?:(ASOCTD?)|(EMBD)))?) @ogc)
            {
                $r->{s} = $1;
                if (defined $3) {
                    _parsePhenom \$r, $3;
                } elsif (defined $4) {
                    @{$r->{cloudType}} = split m@[/-]@, $4;
                } elsif (defined $5) {
                    # phenomenon _can_ have intensity, but it is an EXTENSION
                    $r->{weather} = _parseWeather $5, 'NI';
                } else {
                    $r->{cloudCover} = $6;
                }
                _parsePhenomDescr $r, 'phenomDescrPost', $7 if defined $7;
                $r->{locationAnd} = _parseLocations $8, $2 if defined $8;
                $r->{locationAnd} = _parseQuadrants $10, ($2 || $9)
                    if defined $10;
                $r->{$11}{locationAnd} = _parseLocations $12 if defined $12;
                $r->{isStationary} = undef if defined $13;
                $r->{locationAnd} = _parseLocations $14, $2 if defined $14;
                $r->{locationAnd} = _parseQuadrants $16, ($2 || $15)
                    if defined $16;
                $r->{$17}{locationAnd} = _parseLocations $18 if defined $18;
                $r->{isStationary} = undef if defined $19;
                _parsePhenomDescr $r, 'phenomDescrPost', $20 if defined $20;
                $r->{cloudTypeAsoctd} = $21 if defined $22;
                $r->{cloudTypeEmbd}   = $21 if defined $23;
                $r->{locationAnd}{locationThru}{location}{inDistance} = undef
                    if defined $2 && !exists $r->{locationAnd};
                if (   exists $r->{locationAnd}
                    && exists $r->{locationAnd}{obscgMtns})
                {
                    delete $r->{locationAnd}{obscgMtns};
                    $r->{obscgMtns} = undef;
                }
                push @{$metar{remark}}, { phenomenon => $r };
            } elsif (m@\G((?:PR(?:ESENT )?WX )?(DSNT )?((?:(?:AND )?$re_phen_desc[/ ]?)+)$re_phenomenon4( BBLO| VC)?(?: ($re_cloud_type) (?:(ASOCTD?)|(EMBD)))?) @ogc)
            {
                $r->{s} = $1;
                _parsePhenomDescr $r, 'phenomDescrPre', $3 if defined $3;
                if (defined $4) {
                    _parsePhenom \$r, $4;
                } elsif (defined $5) {
                    @{$r->{cloudType}} = split m@[/-]@, $5;
                } elsif (defined $6) {
                    # phenomenon _can_ have intensity, but it is an EXTENSION
                    $r->{weather} = _parseWeather $6, 'NI';
                } else {
                    $r->{cloudCover} = $7;
                }
                if (defined $8) {
                    if ($8 eq ' VC') {
                        $r->{locationAnd}{locationThru}{location}{inVicinity}
                                                                        = undef;
                    } else {
                        _parsePhenomDescr $r, 'phenomDescrPost', $8;
                    }
                }
                $r->{cloudTypeAsoctd} = $9 if defined $10;
                $r->{cloudTypeEmbd}   = $9 if defined $11;
                $r->{locationAnd}{locationThru}{location}{inDistance} = undef
                    if defined $2;
                push @{$metar{remark}}, { phenomenon => $r };

            # first check a restricted set of phenomenon and descriptions!

            } elsif (m@\G(GR ($re_gs_size)) @ogc) {
                push @{$metar{remark}}, { hailStones => {
                    s        => $1,
                    diameter => _parseFraction $2, 'IN'
                }};
            } elsif (/\G((PRES[FR]R)( PAST HR)?) /gc) {
                $r->{s} = $1;
                $r->{otherPhenom} = $2;
                _parsePhenomDescr $r, 'phenomDescrPost', $3 if defined $3;
                push @{$metar{remark}}, { phenomenon => $r };
            } elsif (/\G(CLDS LWR RWY($re_rwy_des)) /ogc) {
                push @{$metar{remark}}, { ceilingAtLoc => {
                    s           => $1,
                    cloudsLower => undef,
                    rwyDesig    => $2
                }};
            } elsif (   _cyInString(\@cy, ' SP ')
                     && /\G(([+-]?RA (?:(?:EN LA )?NOCHE|AT NIGHT) )?PP(?:(\d{3})|TRZ)) /gc)
            {
                # derived from corresponding SYNOP
                if (defined $2) {
                    push @{$metar{remark}}, { rainfall => {
                        s             => $1,
                        precipitation => {
                            s             => $3 || 'TRZ',
                            timePeriod    => 'n',
                            defined $3 ? (precipAmount =>
                                    { v => sprintf('%.1f', $3 / 10), u => 'MM' }
                                         )
                                       : (precipTraces => undef)
                    }}};
                } else {
                    push @{$metar{remark}}, { precipitation => {
                        s             => $1,
                        timeBeforeObs => { hours => 1 },
                        defined $3 ? (precipAmount =>
                                    { v => sprintf('%.1f', $3 / 10), u => 'MM' }
                                   )
                                 : (precipTraces => undef)
                    }};
                }
            } elsif (   _cyInString(\@cy, ' SP ')
                     && m@\G(BIRD HAZARD(?: RWY[ /]?($re_rwy_des(?:/$re_rwy_des)?))?) @ogc)
            {
                push @{$metar{remark}}, { birdStrikeHazard => {
                    s => $1,
                    defined $2 ? (rwyDesig => $2) : ()
                }};
            } elsif (   _cyInString(\@cy, ' cCA cJP cUS BG EG ET EQ LI MM RK ')
                     && m@\G(($re_be_weather+)($re_loc)?$re_wx_mov_d3?) @ogc)
            {
                $r->{weatherHist}{s} = $1;
                $r->{weatherHist}{locationAnd} = _parseLocations $3
                    if defined $3;
                $r->{weatherHist}{$4}{locationAnd} = _parseLocations $5
                    if defined $5;
                $r->{weatherHist}{isStationary} = undef if defined $6;
                $r->{weatherHist}{weatherBeginEnd} = ();
                for ($2 =~ /$re_be_weather/og) {
                    my (@weatherBEArr, $weatherBeginEnd);
                    my ($weather, $times) = /(.*?)((?:$re_be_weather_be|[BE]MM)+)/g;
                    for ($times =~ /$re_be_weather_be|[BE]MM/og) {
                        my %s_e;
                        /(.)(..)?(..)/;
                        $s_e{timeAt}{hour}   = $2 if defined $2;
                        $s_e{timeAt}{minute} = $3 if $3 ne 'MM';
                        push @weatherBEArr, {
                            ($1 eq 'B' ? 'weatherBegan' : 'weatherEnded')
                                                                    => \%s_e
                        };
                    }
                    $weatherBeginEnd = _parseWeather $weather, 'NI';
                    delete $weatherBeginEnd->{s};
                    $weatherBeginEnd->{weatherBEArr} = \@weatherBEArr;
                    push @{$r->{weatherHist}{weatherBeginEnd}}, $weatherBeginEnd;
                }
                push @{$metar{remark}}, $r;
            } elsif (m@\G(($re_phenomenon_other)(?: IS)?((?:[/ ](?:$re_phen_desc_when|BBLO))*)(?: ($re_cloud_type) (?:(ASOCTD?)|(EMBD)))?) @ogc)
            {
                $r->{s} = $1;
                _parsePhenom \$r, $2;
                _parsePhenomDescr $r, 'phenomDescrPost', $3 if defined $3;
                $r->{cloudTypeAsoctd} = $4 if defined $5;
                $r->{cloudTypeEmbd}   = $4 if defined $6;
                push @{$metar{remark}}, { phenomenon => $r };
            } elsif (m@\G((?:PR(?:ESENT )?WX )?(DSNT )?$re_phenomenon4((?: IS)?(?:[/ ](?:(?:AND )?$re_phen_desc|BBLO))*)(?: ?($re_cloud_type) (?:(ASOCTD?)|(EMBD)))?) @ogc)
            {
                $r->{s} = $1;
                if (defined $3) {
                    _parsePhenom \$r, $3;
                } elsif (defined $4) {
                    @{$r->{cloudType}} = split m@[/-]@, $4;
                } elsif (defined $5) {
                    # phenomenon _can_ have intensity, but it is an EXTENSION
                    $r->{weather} = _parseWeather $5, 'NI';
                } else {
                    $r->{cloudCover} = $6;
                }
                _parsePhenomDescr $r, 'phenomDescrPost', $7 if defined $7;
                $r->{cloudTypeAsoctd} = $8 if defined $9;
                $r->{cloudTypeEmbd}   = $8 if defined $10;
                $r->{locationAnd}{locationThru}{location}{inDistance} = undef
                    if defined $2;
                push @{$metar{remark}}, { phenomenon => $r };
            } elsif (/\G(AO(?:1|2A?)) /gc) {
                push @{$metar{remark}}, { obsStationType => {
                    s           => $1,
                    stationType => $1
                }};
            } elsif (m@\G(CIG (\d{3})(?:(?:(?: (APCH))?(?: RWY ?| R?)?($re_rwy_des))(?: TO)?($re_loc)?|(?: TO)?($re_loc))) @ogc)
            {
                $r->{s} = $1;
                $r->{cloudBase}  = { v => $2 * 100, u => 'FT' };
                $r->{isApproach} = undef if defined $3;
                $r->{rwyDesig} = $4 if defined $4;
                $r->{locationAnd} =_parseLocations $5 if defined $5;
                $r->{locationAnd} =_parseLocations $6 if defined $6;
                push @{$metar{remark}}, { ceilingAtLoc => $r };
            } elsif (m@\G($re_vis ($re_vis_sm)(?: ?SM)?(?: (APCH))?(?: RWY ?| R?)?($re_rwy_des)) @ogc)
            {
                $r->{s} = $1;
                $r->{visibility} = _getVisibilitySM $2, $is_auto, \@cy;
                $r->{isApproach} = undef if defined $3;
                $r->{rwyDesig} = $4;
                push @{$metar{remark}}, { visibilityAtLoc => $r };
            } elsif (/\G(NOSIG|CAVU|$re_estmd PASS (?:OPEN|CLOSED|CLSD|MARGINAL|MRGL)|PASS $re_estmd CLSD|EPC|EPO|EPM|RTS) /ogc)
            {
                $r->{s} = $1;
                $r->{v} = $1;
                if ($r->{v} =~ m@PASS OP@) {
                    $r->{v} = 'EPO';
                } elsif ($r->{v} =~ m@PASS .*?CL@) {
                    $r->{v} = 'EPC';
                } elsif ($r->{v} =~ m@PASS M@) {
                    $r->{v} = 'EPM';
                }
                push @{$metar{remark}}, { keyword => $r };
            } elsif (   _cyInString(\@cy, ' cUS ')
                     && (   /\G(WEA[: ]*(NONE)) /gc
                         || /\G(WEA ?:) ?/gc
                         || /\G(WEA) /gc))
            {
                if (defined $2) {
                    push @{$metar{remark}},
                                        { weather => { s => $1, NSW => undef }};
                } else {
                    push @{$metar{remark}},
                                          { keyword => { s => $1, v => 'WEA' }};
                }
            } elsif (_cyInString(\@cy, ' PA ') && /\G(($re_hour)($re_min)Z) /gc)
            {
                push @{$metar{remark}}, { exactObsTime => {
                    s      => $1,
                    timeAt => { hour => $2, minute => $3 }
                }};
            } elsif (   _cyInString(\@cy, ' PA ')
                     && /\G(SEA (\d)) (SWELL (\d) ($re_compass_dir16)) /gc)
            {
                push @{$metar{remark}}, { seaCondition => {
                    s          => $1,
                    seaCondVal => $2
                }};
                push @{$metar{remark}}, { swellCondition => {
                    s            => $3,
                    locationAnd  => { locationThru => { location =>
                                      { compassDir => $5 }}},
                    swellCondVal => $4
                }};
            } elsif (m@\G((?:CLIMAT ?)?($re_temp)/($re_temp)(?:/(TR|$re_precip)(?:/(NIL|$re_precip))?)?) @ogc)
            {
                $r->{s} = $1;
                $r->{temp1}{temp} = { v => $2 + 0, u => 'C' };
                $r->{temp2}{temp} = { v => $3 + 0, u => 'C' };
                if (defined $4) {
                    my ($precip1, $precip2);

                    if ($4 eq 'TR') {
                        push @{$r->{sortedArr}}, { precipTraces => undef };
                    } else {
                        $precip1 = $4;
                    }
                    if (defined $5) {
                        if ($5 eq 'NIL') {
                            push @{$r->{sortedArr}}, { precipAmount2MM => 0 };
                        } else {
                            $precip2 = $5;
                            if ($precip2 =~ s/ ?([MC]M)//) {
                                push @{$r->{sortedArr}},
                                    { precipAmount2MM =>
                                             $precip2 * ($1 eq 'CM' ? 10 : 1) };
                            } else {
                                push @{$r->{sortedArr}},
                                    { precipAmount2Inch => $precip2 + 0 };
                            }
                        }
                    }
                    if (defined $precip1) {
                        if ($precip1 =~ s/ ?([MC]M)//) {
                            unshift @{$r->{sortedArr}},
                                { precipAmount1MM =>
                                             $precip1 * ($1 eq 'CM' ? 10 : 1) };
                        } else {
                            unshift @{$r->{sortedArr}},
                                { precipAmount1Inch => $precip1 + 0 };
                        }
                    }
                }
                push @{$metar{remark}}, { climate => {
                    s => $r->{s},
                    exists $r->{sortedArr} ? (sortedArr => $r->{sortedArr}) :(),
                    temp1 => $r->{temp1},
                    temp2 => $r->{temp2}
                }};
            } elsif (m@\G((TORNADO|FUNNEL CLOUDS?|WATERSPOUT) ($re_be_weather_be+)(?: TO)?($re_loc)$re_wx_mov_d3?) @ogc) {
                $r->{s} = $1;
                $r->{weatherBeginEnd}{tornado}{v} = lc $2;
                $r->{locationAnd} = _parseLocations $4;
                $r->{$5}{locationAnd} = _parseLocations $6 if defined $6;
                $r->{isStationary} = undef if defined $7;
                $r->{weatherBeginEnd}{weatherBEArr} = ();
                for ($3 =~ /$re_be_weather_be/og) {
                    my %s_e;
                    /(.)(..)?(..)/;
                    $s_e{timeAt}{hour}   = $2 if defined $2;
                    $s_e{timeAt}{minute} = $3;
                    push @{$r->{weatherBeginEnd}{weatherBEArr}}, {
                        ($1 eq 'B' ? 'weatherBegan' : 'weatherEnded') => \%s_e
                    };
                }
                $r->{weatherBeginEnd}{tornado}{v} =~ s/ (cloud)s?/_$1/;
                push @{$metar{remark}}, { weatherHist => $r };
            } elsif (m@\G((?:FIRST|FST)(?:( STAFFED| STFD)|( MANNED))?(?: OBS?)?)[ /] ?@gc)
            {
                $r->{s} = $1;
                $r->{isStaffed} = undef if defined $2;
                $r->{isManned} = undef if defined $3;
                push @{$metar{remark}}, { firstObs => $r };
            } elsif (/\G(NEXT ($re_day)($re_hour)($re_min)(?: ?UTC| ?Z)?) /ogc){
                $r->{s} = $1;
                @{$r->{timeAt}}{qw(day hour minute)} = ($2, $3, $4)
                    if defined $2;
                push @{$metar{remark}}, { nextObs => $r };
            } elsif (m@\G(LAST(?:( STAFFED| STFD)|( MANNED))?(?: OBS?)?(?: ($re_day)($re_hour)($re_min)(?: ?UTC| ?Z)?)?)[ /] ?@ogc)
            {
                $r->{s} = $1;
                $r->{isStaffed} = undef if defined $2;
                $r->{isManned} = undef if defined $3;
                @{$r->{timeAt}}{qw(day hour minute)} = ($4, $5, $6)
                    if defined $4;
                push @{$metar{remark}}, { lastObs => $r };
            } elsif (/\G((QBB|QBJ)(\d\d0)) /gc) {
                push @{$metar{remark}}, { $2 => {
                    s => $1,
                    altitude => { v => $3 + 0, u => 'M' }
                }};
            # from mdsplib, http://avstop.com/ac/aviationweather:
            } elsif (/\G(RADAT (?:(\d\d)(\d{3})|MISG)) /gc) {
                $r->{s} = $1;
                if (defined $2) {
                    $r->{relHumid} = $2 + 0;
                    $r->{distance} = { v => $3 * 100, u => 'FT' };
                } else {
                    $r->{isMissing} = undef;
                }
                push @{$metar{remark}}, { RADAT => $r };
            } elsif ($cy[1] eq 'LF' && /\G([MB])(\d) /gc) {
                push @{$metar{remark}}, { reportConcerns => {
                    s       => "$1$2",
                    change  => $1,
                    subject => $2
                }};
            } elsif (   _cyInString(\@cy, ' EN EK ')
                     && /\G(WI?ND ((?:AT )?\d+ ?FT) ($re_wind)(?: ($re_wind_dir\d)V($re_wind_dir\d))?) /ogc)
            {
                push @{$metar{remark}}, _parseWindAtLoc($1, $2, $3, $8, $9);
            } elsif (/\G((2000FT|CNTR RWY|HARBOR|ROOF|(?:BAY )?TWR) WI?ND ($re_wind)(?: ($re_wind_dir\d)V($re_wind_dir\d))?) /ogc)
            {
                push @{$metar{remark}}, _parseWindAtLoc($1, $2, $3, $8, $9);
            } elsif (/\G((BAY TWR|WNDY HILL|KAUKAU|SUGARLOAF|CLN AIR) ($re_wind)(?: ($re_wind_dir\d)V($re_wind_dir\d))?) /ogc)
            {
                push @{$metar{remark}}, _parseWindAtLoc($1, $2, $3, $8, $9);
            } elsif (   _cyInString(\@cy, ' MN ')
                     && m@\G((?:V[./]?P[/ ])($re_wind)(?: ($re_wind_dir\d)V($re_wind_dir\d))?) @ogc)
            {
                # TODO: VP = viento pista?
                push @{$metar{remark}}, _parseWindAtLoc($1, 'VP', $2, $7, $8);
            } elsif (   !(   exists $metar{sfcWind}
                          && exists $metar{sfcWind}{wind}
                          && !exists $metar{sfcWind}{wind}{notAvailable})
                     && m@\G(($re_wind)(?: ($re_wind_dir\d)V($re_wind_dir\d))?) @ogc)
            {
                $r->{sfcWind} = {
                    s    => $1,
                    wind => _parseWind $2
                };
                $r->{sfcWind}{wind}{windVarLeft} = $7 + 0 if defined $7;
                $r->{sfcWind}{wind}{windVarRight} = $8 + 0 if defined $8;
                push @{$metar{remark}}, $r;
            } elsif (   _cyInString(\@cy, ' EQ LI OA ')
                     && /\G($re_vis ?MIN ?($re_vis_m)M?(?: TO | )?($re_compass_dir)?) /ogc)
            {
                $r->{s} = $1;
                $r->{distance} = _getVisibilityM $2;
                $r->{compassDir} = $3 if defined $3;
                push @{$metar{remark}}, { visMin => $r };
            } elsif (_cyInString \@cy, ' EQ LI ') {
                my $re_cond_moun =
                    '(?:LIB|CLD SCT|VERS INC|CNS POST|CLD CIME'
                    . '|CIME INC|GEN INC|INC|INVIS)';
                my $re_chg_moun =
                    '(?:NC|CUF'
                     . '|ELEV (?:SLW|RAPID|STF)'
                     . '|ABB (?:SLW|RAPID)'
                     . '|STF(?: ABB)?'
                     . '|VAR RAPID)';
                my $re_cond_vall =
                    '(?:NIL|FOSCHIA(?: SKC SUP)?|NEBBIA(?: SCT)?'
                    . '|CLD SCT(?: NEBBIA INF)?|MAR CLD|INVIS)';
                my $re_chg_vall =
                    '(?:NC|ELEV|DIM(?: ELEV| ABB)?|AUM(?: ELEV| ABB)?|ABB'
                    . '|NEBBIA INTER)';
                my $re_moun = "$re_loc? $re_cond_moun(?: $re_chg_moun)?";
                my $re_vall = "$re_loc? $re_cond_vall(?: $re_chg_vall)?";
                if (m@\G(MON((?:$re_moun)+)) @ogc) {
                    $r->{s} = $1;
                    $r->{condMountainLoc} = ();
                    for ($2 =~ m@$re_moun@og) {
                        my $m;
                        m@($re_loc)? ($re_cond_moun)(?: ($re_chg_moun))?@o;

                        $m->{locationAnd}     =_parseLocations $1 if defined $1;
                        $m->{cloudMountain} = {
                                               'LIB'      => 0,
                                               'CLD SCT'  => 1,
                                               'VERS INC' => 2,
                                               'CNS POST' => 3,
                                               'CLD CIME' => 5,
                                               'CIME INC' => 6,
                                               'GEN INC'  => 7,
                                               'INC'      => 8,
                                               'INVIS'    => 9
                                               }->{$2};
                        $m->{cloudEvol} = {
                                           'NC'         => 0,
                                           'CUF'        => 1,
                                           'ELEV SLW'   => 2,
                                           'ELEV RAPID' => 3,
                                           'ELEV STF'   => 4,
                                           'ABB SLW'    => 5,
                                           'ABB RAPID'  => 6,
                                           'STF'        => 7,
                                           'STF ABB'    => 8,
                                           'VAR RAPID'  => 9
                                          }->{$3}
                            if defined $3;
                        push @{$r->{condMountainLoc}}, $m;
                    }
                    push @{$metar{remark}}, { conditionMountain => $r };
                } elsif (m@\G(VAL((?:$re_vall)+)) @ogc) {
                    $r->{s} = $1;
                    $r->{condValleyLoc} = ();
                    for ($2 =~ m@$re_vall@og) {
                        my $m;
                        m@($re_loc)? ($re_cond_vall)(?: ($re_chg_vall))?@o;

                        $m->{locationAnd}     =_parseLocations $1 if defined $1;
                        $m->{cloudValley} = {
                                             'NIL'                => 0,
                                             'FOSCHIA SKC SUP'    => 1,
                                             'NEBBIA SCT'         => 2,
                                             'FOSCHIA'            => 3,
                                             'NEBBIA'             => 4,
                                             'CLD SCT'            => 5,
                                             'CLD SCT NEBBIA INF' => 6,
                                             'MAR CLD'            => 8,
                                             'INVIS'              => 9
                                            }->{$2};
                        $m->{cloudBelowEvol} = {
                                                'NC'           => 0,
                                                'DIM ELEV'     => 1,
                                                'DIM'          => 2,
                                                'ELEV'         => 3,
                                                'DIM ABB'      => 4,
                                                'AUM ELEV'     => 5,
                                                'ABB'          => 6,
                                                'AUM'          => 7,
                                                'AUM ABB'      => 8,
                                                'NEBBIA INTER' => 9
                                               }->{$3}
                            if defined $3;
                        push @{$r->{condValleyLoc}}, $m;
                    }
                    push @{$metar{remark}}, { conditionValley => $r };
                } elsif (m@\G(QU(L|K) ?([\d/])(?: ?($re_compass_dir16))?) @ogc){
                    my $key = $2 eq 'K' ? 'sea' : 'swell';

                    $r->{s} = $1;
                    if ($3 eq '/') {
                        $r->{notAvailable} = undef;
                    } else {
                        $r->{"${key}CondVal"} = $3;
                    }
                    $r->{locationAnd} = _parseLocations $4 if defined $4;
                    push @{$metar{remark}}, { "${key}Condition" => $r };
                } elsif (/\G($re_vis (MAR) ([1-9]\d*) KM) /ogc) {
                    $r->{s} = $1;
                    $r->{locationAt} = $2;
                    $r->{visibility}{distance} = { v => $3, u => 'KM' };
                    push @{$metar{remark}}, { visibilityAtLoc => $r };
                } elsif (/\G((?:WIND THR ?|WT)($re_rwy_des) ($re_wind)) /ogc) {
                    push @{$metar{remark}}, { thrWind => {
                        s        => $1,
                        rwyDesig => $2,
                        wind     => _parseWind $3
                    }};
                } else {
                    $parsed = 0;
                }
            } elsif($cy[1] eq 'LK' && /\G(REG QNH ([01]\d{3})) /gc) {
                push @{$metar{remark}}, { regQNH => {
                    s        => $1,
                    pressure => { v => $2, u => 'hPa' }
                }};
            } elsif ($cy[0] eq 'ZMUB' && /\G(\d\d) /gc) {
                push @{$metar{remark}}, { RH => {
                    s        => $1,
                    relHumid => $1
                }};
            } elsif (m@\G($re_vis ($re_vis_sm) ?SM(?: TO)? ($re_compass_dir16)) @ogc)
            {
                push @{$metar{remark}}, { visListAtLoc => {
                    s => $1,
                    visLocData => [
                      { visibility  => _getVisibilitySM($2, $is_auto, \@cy),
                        locationAnd => _parseLocations $3
                }]}};
            } elsif (m@\G($re_vis(?: TO)? ($re_compass_dir16) ($re_vis_sm) ?SM) @ogc)
            {
                push @{$metar{remark}}, { visListAtLoc => {
                    s => $1,
                    visLocData => [
                      { visibility  => _getVisibilitySM($3, $is_auto, \@cy),
                        locationAnd => _parseLocations $2
                }]}};
            } elsif (_cyInString(\@cy, ' Y ') && ($r = _turbulenceTxt)) {
                push @{$metar{remark}}, { turbulence => $r };
            } else {
                $parsed = 0;
            }

            if (!$parsed && _cyInString \@cy, ' cCA cJP cUS BG EG ET EQ LI RK ')
            {
                $parsed = 1;
                if (m@\G(4([01]\d{3}|////)([01]\d{3}|////)?) @gc) {
                    $r->{s} = $1;
                    $r->{tempMax} = {
                        s             => $2,
                        $2 eq '////'
                            ? (notAvailable => undef)
                            : (timeBeforeObs => { hours => 24 },
                               temp          => _parseTemp $2)
                    };
                    if (defined $3) {
                        $r->{tempMin} = {
                            s             => $3,
                            $3 eq '////'
                                ? (notAvailable => undef)
                                : (timeBeforeObs => { hours => 24 },
                                   temp          => _parseTemp $3)
                        };
                    }
                    push @{$metar{remark}}, { temp24h => $r };
                } elsif (m@\G(4/(\d{3})) @gc) {
                    push @{$metar{remark}}, { snowDepth => {
                        s            => $1,
                        precipAmount => { v => $2 + 0, u => 'IN' }
                    }};
                } elsif (_cyInString(\@cy, ' cCA ') && /\G(SOG ?(\d+)) /gc) {
                    push @{$metar{remark}}, { snowDepth => {
                        s            => $1,
                        precipAmount => { v => $2 + 0, u => 'CM' }
                    }};
                } elsif (   !_cyInString(\@cy, ' KAEG KAUN KBVS KUKT KW22 ')
                         && m@\G((P|6|7)(?:(\d{4})|////)) @gc)
                {
                    # Air Force Manual 15-111, Dec. '03, 2.8.1
                    $r->{s} = $1;
                    if (defined $3) {
                        if ($3 == 0) {
                            $r->{precipTraces} = undef;
                        } else {
                            $r->{precipAmount} =
                                  { v => sprintf('%.2f', $3 / 100), u => 'IN' };
                        }
                        if ($2 eq 'P') {
                            $r->{timeBeforeObs} = { hours => 1 };
                        } elsif ($2 eq '7') {
                            $r->{timeBeforeObs} = { hours => 24 };
                        } else {
                            # EXTENSION: allow 20 minutes
                            if (defined $obs_hour) {
                                my $hhmm;

                                $hhmm = $obs_hour . $metar{obsTime}{timeAt}{minute};
                                if ($hhmm =~
                                    '(?:(?:23|05|11|17)[45]|(?:00|06|12|18)[01])\d')
                                {
                                    $r->{timeBeforeObs} = { hours => 6 };
                                } elsif ($hhmm =~
                                    '(?:(?:02|08|14|20)[45]|(?:03|09|15|21)[01])\d')
                                {
                                    $r->{timeBeforeObs} = { hours => 3 };
                                } else {
                                    $r->{timePeriod} = '3or6h';
                                }
                            } else {
                                $r->{timePeriod} = '3or6h';
                            }
                        }
                    } else {
                        $r->{notAvailable} = undef;
                    }
                    push @{$metar{remark}}, { precipitation => $r };
                # EXTENSION: allow slash after 933 (PATA)
                } elsif (m@\G(933/?(\d{3})) @gc) {
                    push @{$metar{remark}}, { waterEquivOfSnow => {
                        s            => $1,
                        precipAmount =>
                                    { v => sprintf('%.1f', $2 / 10), u => 'IN' }
                    }};
                } elsif (m@\G(931(\d{3})) @gc) {
                    push @{$metar{remark}}, { snowFall => {
                        s             => $1,
                        timeBeforeObs => { hours => 6 },
                        precipAmount  =>
                                    { v => sprintf('%.1f', $2 / 10), u => 'IN' }
                    }};
                } elsif (/\G(CIG (\d{3})V(\d{3})) /gc) {
                    push @{$metar{remark}}, { variableCeiling => {
                        s => $1,
                        cloudBaseFrom => { v => $2 * 100, u => 'FT' },
                        cloudBaseTo   => { v => $3 * 100, u => 'FT' }
                    }};
                } elsif (/\G(CIG (\d{4})V(\d{4})) /gc) {
                    push @{$metar{remark}}, { variableCeiling => {
                        s => $1,
                        cloudBaseFrom => { v => $2 + 0, u => 'FT' },
                        cloudBaseTo   => { v => $3 + 0, u => 'FT' }
                    }};
                } elsif (/\G(WSHFT ?(?:AT )?($re_hour)?($re_min)Z?( FROPA)?) /ogc) {
                    $r->{windShift}{s} = $1;
                    $r->{windShift}{timeAt}{hour} = $2 if defined $2;
                    $r->{windShift}{timeAt}{minute} = $3;
                    $r->{windShift}{FROPA} = undef if defined $4;
                    push @{$metar{remark}}, $r;
                } elsif (m@\G($re_vis ($re_vis_sm)(?: ?SM)?(?: TO)? ($re_compass_dir16(?:-$re_compass_dir16)?)) @ogc){
                    push @{$metar{remark}}, { visListAtLoc => {
                        s => $1,
                        visLocData => [
                          { visibility  => _getVisibilitySM($2, $is_auto, \@cy),
                            locationAnd => _parseLocations $3
                    }]}};
                } elsif (m@\G($re_vis($re_loc ?$re_vis_sm(?: ?SM)?(?:(?: AND)?$re_loc ?$re_vis_sm(?: ?SM)?)*)) @ogc)
                {
                    my @visLocData;

                    $r->{visListAtLoc}{s} = $1;
                    $r->{visListAtLoc}{visLocData} = \@visLocData;
                    for ($2 =~ m@$re_loc ?$re_vis_sm@og) {
                        m@($re_loc) ?($re_vis_sm)@o;
                        push @visLocData, {
                            visibility => _getVisibilitySM($2, $is_auto, \@cy),
                            locationAnd => _parseLocations $1
                        };
                    }
                    push @{$metar{remark}}, $r;
                } else {
                    $parsed = 0;
                }
            }

            if (!$parsed && /\G(BA (?:GOOD|POOR)|THN SPTS IOVC|FUOCTY|ALL WNDS GRID|CONTRAILS?|FOGGY|TWLGT) /gc)
            {
                $parsed = 1;
                $r->{s} = $1;
                ($r->{v} = $1) =~ tr/\/ /_/;
                $r->{v} =~ s/CONTRAILS?/CONTRAILS/;
                push @{$metar{remark}}, { keyword => $r };
                $winds_grid = $r->{v} eq 'ALL_WNDS_GRID';
            }

            # if DSNT or DSIPTD could not be parsed and the last remark was a
            # phenomenon and no unrecognised entry is pending:
            #   assign it to the phenomenon
            if (!$parsed && $notRecognised eq '' && /\G(?:DSNT|DSIPTD) /) {
                my $last;

                $last = $#{$metar{remark}};
                if ($last > -1 && exists ${$metar{remark}}[$last]{phenomenon}) {
                    $parsed = 1;
                    /\G(?:(DSNT) |(DSIPTD) )/gc;
                    $r = ${$metar{remark}}[$last]{phenomenon};
                    $r->{s} .= ' ' . ($1 || $2);
                    if (defined $1) {
                        if (exists $r->{locationAnd}) {
                            for (ref $r->{locationAnd}{locationThru} eq 'ARRAY'
                                 ? @{$r->{locationAnd}{locationThru}}
                                 : $r->{locationAnd}{locationThru})
                            {
                                for (ref $_->{location} eq 'ARRAY'
                                     ? @{$_->{location}} : $_->{location})
                                {
                                    $_->{inDistance} = undef;
                                }
                            }
                        } else {
                           $r->{locationAnd}{locationThru}{location}{inDistance}
                                = undef;
                        }
                    } else {
                        _parsePhenomDescr $r, 'phenomDescrPost', $2;
                    }
                }
            }

            if (!$parsed) {
                my $pattern = $is_taf ? '.*' : '\S+';
                /\G($pattern) /gc;
                $notRecognised .= ' ' unless $notRecognised eq '';
                # $1 == undef "cannot" happen, prevent endless loop at while()
                $notRecognised .= $1 if defined $1;
            }
            if ($parsed && $notRecognised ne '') {
                my $top = pop @{$metar{remark}};
                push @{$metar{remark}},
                                    { notRecognised => { s => $notRecognised }};
                push @{$metar{remark}}, $top;
                $notRecognised = '';
            }
        }
        push @{$metar{remark}}, { notRecognised => { s => $notRecognised }}
            if $notRecognised ne '';
    }

    # if winds are grid/estimated: propagate this to all winds
    if ($winds_grid || $winds_est) {
        for ((map { $_->{sfcWind} || (),
                    $_->{windAtLoc} || (),
                    $_->{rwyWind} ? @{$_->{rwyWind}} : (),
                    map { $_->{windShearLvl} || ()
                        } exists $_->{TAFsupplArr} ? @{$_->{TAFsupplArr}} : ()
                  } (\%metar, exists $metar{trend} ? @{$metar{trend}} : ())),
             map {    $_->{sfcWind}
                   || $_->{rwyWind}
                   || $_->{peakWind}
                   || $_->{RSNK}
                   || $_->{LAG_PK}
                   || $_->{thrWind}
                   || $_->{windAtLoc}
                   || ()
                 } exists $metar{remark} ? @{$metar{remark}} : ())
        {
            $_->{wind}{dir}{q} = 'isGrid'
                if $winds_grid && exists $_->{wind}{dir};

            if (   $winds_est
                && !exists $_->{wind}{notAvailable}
                && !exists $_->{wind}{invalidFormat})
            {
                $_->{wind}{isEstimated} = undef;
                $_->{wind}{dir} = $_->{wind}{dir}{v}
                    if exists $_->{wind}{dir} && exists $_->{wind}{dir}{v};
            }
        }
    }

    $metar{ERROR} = _makeErrorMsgPos 'other' if /\G./;

    if (!exists $metar{ERROR}) {
        push @{$metar{warning}}, { warningType => 'windMissing' }
            unless exists $metar{sfcWind};
        push @{$metar{warning}}, { warningType => 'visibilityMissing' }
            unless exists $metar{visPrev} || exists $metar{CAVOK};
        push @{$metar{warning}}, { warningType => 'tempMissing' }
            unless $is_taf || exists $metar{temperature};
        push @{$metar{warning}}, { warningType => 'QNHMissing' }
            unless $is_taf || exists $metar{QNH} || exists $metar{QFE};
    }

    return %metar;
}

=head1 SUBROUTINES/METHODS

=cut

########################################################################
# parse_report
########################################################################
sub parse_report {

=head2 parse_report($msg,$default_msg_type)

The following arguments are expected:

=over

=item msg

string that contains the message. It is required to be
in the format specified by the I<WMO Manual No. 306>, B<without modifications
due to distribution> (which e.g. lists the initial part of messages only once
for several messages, or uses the "=" (equal sign) as a delimiter).
The Perl module C<metaf2xml::src2raw> or the program C<metafsrc2raw.pl> can be
used to create messages with the required format from files provided by various
public Internet servers.

=item default_msg_type

the default message type (applied to messages that do not start with C<METAR>,
C<SPECI>, C<TAF>, C<SYNOP> or C<BUOY>)

=back

Leading and trailing spaces are removed, multiple spaces are
replaced by a single one. Characters that are invalid in HTML or XML are also
removed.

=cut

    local $_;
    my $default_msg_type;

    ($_, $default_msg_type) = @_;

    s/ +/ /g;
    s/ $//;
    s/^ //;
    s/[^ -~]/?/g; # avoid invalid XML and HTML

=pod

If the message starts with one of the keywords C<METAR>, C<SPECI>, C<TAF>,
C<SYNOP> or C<BUOY>, the keyword is used as message type, the last 2 are also
removed.

=cut

    if (/^(?:METAR )?LWIS /) {
        $default_msg_type = 'METAR';
    } elsif (/^(METAR|SPECI|TAF|SYNOP|BUOY) /) {
        $default_msg_type = $1;
    }
    s/^(?:SYNOP|BUOY) //;
    $default_msg_type = 'SPECI'
        if /^[A-Z]{3,4} SP $re_hour$re_min A/o;

=pod

Then the correct function to parse the message is called.

=cut

    return _parseBuoy if $default_msg_type eq 'BUOY';
    return _parseSynop if $default_msg_type eq 'SYNOP';
    return _parseSao $default_msg_type
       if /^(?:METAR |SPECI )?[CKP][A-Z\d]{3} (?:S[AP]|RS)(?: COR)? $re_hour$re_min /o;
    return _parseMetarTaf $default_msg_type;
}

=pod

The return value is a hash with all the parsed components of the message. It
may also have values for the following keys:

=over

=item C<ERROR>

If a message could not be parsed C<ERROR> is a hash with the the keys
C<errorType> (the type of error) and C<s> - the original message with the
position of the error marked as C<< <@> >>.

=item C<warning>

An array of hashes describing problems which where encountered during
parsing but which didn't prevent complete parsing.

=back

=head1 SEE ALSO

=begin html

<p>
<a href="XML.pm.html">metaf2xml::XML(3pm)</a>,
<a href="metaf2xml.pl.html">metaf2xml(1)</a>,
<a href="src2raw.pm.html">metaf2xml::src2raw(3pm)</a>,
<a href="metafsrc2raw.pl.html">metafsrc2raw(1)</a>,
</p><!--

=end html

B<metaf2xml::XML>(3pm),
B<metaf2xml>(1),
B<metaf2xml::src2raw>(3pm),
B<metafsrc2raw>(1),

=for html -->

L<http://metaf2xml.sourceforge.net/>

=head1 COPYRIGHT and LICENSE

copyright (c) 2006-2012 metaf2xml @ L<http://metaf2xml.sourceforge.net/>

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
