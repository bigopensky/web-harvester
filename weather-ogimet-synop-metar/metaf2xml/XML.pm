########################################################################
# metaf2xml/XML.pm 1.50
#   write data of a METAR, TAF, SYNOP or BUOY message as XML
#   or provide access to parsed data via a callback function
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

package metaf2xml::XML;

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
    our @EXPORT_OK = qw(start_xml finish_xml start_cb finish_cb print_report);
}

sub VERSION {
    return '1.50';
}

END { }

=head1 NAME

metaf2xml::XML

=head1 SYNOPSIS

 use metaf2xml::XML;

 # pass the data to a callback function:
 metaf2xml::XML::start_cb(\&cb);         # mandatory
 metaf2xml::XML::print_report(\%report); # repeat as necessary
 metaf2xml::XML::finish_cb();            # this (or finish_xml()) is optional

 # write the data as XML:
 metaf2xml::XML::start_xml(\%opts);      # mandatory
 metaf2xml::XML::print_report(\%report); # repeat as necessary
 metaf2xml::XML::finish_xml();           # this (or finish_cb()) is mandatory

=head1 DESCRIPTION

This module contains functions to write the data obtained from parsing a METAR,
TAF, SYNOP or BUOY message as XML, or pass each data item to a callback
function.

=head1 SUBROUTINES/METHODS

=cut

########################################################################
# global variable
########################################################################
# path to current data node. no elements: start_*() was not called yet
my @node_path;

########################################################################
# callback function to write XML
########################################################################
{
    my ($opts_xml, $XML);

    sub _set_opts_xml {
        $opts_xml = shift;
    }

    sub _write_xml {
        my $path = shift;
        my $type = shift;
        my $node = shift;
        my (%options, $msg);

        if ($type eq 'end') {
            my $rc;

            $rc = print $XML ' ' x $#$path . '</' . $node . '>' . "\n";

            # close output stream
            close $XML or return 0
                if $#$path == 0;

            return $rc;
        }

        if ($#$path == 0 && $type eq 'start') {
            # open output stream
            if (exists $opts_xml->{o}) {
                open $XML, ">$opts_xml->{o}" or return 0;
            } elsif (exists $opts_xml->{x}) { # TODO: obsolete
                open $XML, ">$opts_xml->{x}" or return 0;
            } else {
                return 0;
            }

            # write XML header
            print $XML '<?xml version="1.0" encoding="UTF-8"?>' . "\n"
                or return 0;

            # write XML meta data if requested
            print $XML '<!DOCTYPE data SYSTEM "metaf.dtd">' . "\n" or return 0
                if exists $opts_xml->{D};

            print $XML '<?xml-stylesheet href="' . $opts_xml->{S}
                       . '" type="text/xsl"?>' . "\n"
                    or return 0
                if exists $opts_xml->{S};
        }

        # write node of type 'start' or 'empty'
        print $XML ' ' x $#$path . '<' . $node or return 0;
        while (my $name = shift) {
            my $value = shift;

            $value =~ s/&/&amp;/g; # must be the first substitution
            $value =~ s/</&lt;/g;
            $value =~ s/>/&gt;/g;
            $value =~ s/"/&quot;/g;
            print $XML ' ' . $name . '="' . $value . '"' or return 0;
        }
        print $XML ($type eq 'start' ? '' : '/') . ">\n" or return 0;

        return 1
            unless $#$path == 0 && $type eq 'start' && exists $opts_xml->{O};

        # parse options to write to XML file (no validation here!)
        (@options{'type_metaf', 'type_synop', 'type_buoy', 'lang', 'format',
                  'src_metaf',  'src_synop',  'src_buoy',  'mode', 'hours'},
         $msg
        ) = split / /, $opts_xml->{O}, 11;
        @options{'msg_metaf', 'msg_synop', 'msg_buoy'} = split '  ', $msg, 3;

        # write node 'options'
        return _write_xml([ @$path, $node ], 'empty', 'options', %options);
    }
}

########################################################################
# from here: helper functions
########################################################################

########################################################################
# invoke callback function for start and end of a node, set @node_path
########################################################################
{
    my $node_callback;

    sub _set_cb {
        $node_callback = shift;
        return ref $node_callback eq 'CODE';
    }

    # arguments: type, node[, name, value, ...]
    sub _new_node {
        my $rc;

        $rc = &$node_callback(\@node_path, @_);
        push @node_path, $_[1] if $_[0] eq 'start';
        return $rc;
    }

    sub _end_node {
        my $node = pop @node_path;

        return &$node_callback(\@node_path, 'end', $node);
    }
}

########################################################################
# walk through data structure, sort items to comply with the DTD
########################################################################
sub _walk_data {
    my ($r, $node, $xml_tag) = @_;

    $r = $r->{$node};

    $node = $xml_tag if $xml_tag;
    if (ref $r eq 'HASH') {
        my (@subnodes, @attrs);

        # nodes with special attributes and no subnodes
        return _new_node 'empty', 'ERROR',
                         errorType => $r->{errorType}, s => $r->{s}
            if $node eq 'ERROR';
        return _new_node 'empty', 'warning',
                         warningType => $r->{warningType},
                         exists $r->{s} ? (s => $r->{s}) : ()
            if $node eq 'warning';

        # force special sequence to comply with the DTD
        if ($node eq 'phenomenon') {
            push @subnodes, map { exists $r->{$_} ? $_ : () }
                qw(phenomDescrPre phenomDescrPost weather cloudType cloudCover
                   lightningType otherPhenom obscgMtns locationAnd MOV MOVD
                   isStationary cloudTypeAsoctd cloudTypeEmbd);
            push @attrs, s => $r->{s};
        } else {
            push @subnodes, sort map {
                         $_ eq 'v' || $_ eq 'u' || $_ eq 'q' || $_ eq 's'
                      || $_ eq 'rp' || $_ eq 'rn' || $_ eq 'occurred'
                    ? () : $_
                } keys %$r;

            # sort attributes, so XML looks nicer
            push @attrs, occurred => $r->{occurred}
                if $node eq 'timeBeforeObs' && exists $r->{occurred};
            for (qw(s v rp rn u q)) {
                push @attrs, $_ => $r->{$_} if exists $r->{$_};
            }
        }

        # *Arr are arrays with different subnodes, suppress node
        if ($#subnodes > -1) {
            _new_node 'start', $node, @attrs or return 0
                unless $node =~ /Arr$/;
            for (@subnodes) {
                _walk_data($r, $_) or return 0;
            }
            _end_node or return 0 unless $node =~ /Arr$/;
        } else {
            _new_node 'empty', $node, @attrs or return 0
                unless $node =~ /Arr$/;
        }
    } elsif (ref $r eq 'ARRAY') {
        if ($#$r > -1) {
            for (@$r) {
                _walk_data({ $node => $_ }, $node) or return 0;
            }
        } else {
            _new_node 'empty', $node or return 0;
        }
    } else {
        _new_node 'empty', $node, defined $r ? ( v => $r ) : () or return 0;
    }
    return 1;
}

########################################################################
# compare version strings
########################################################################
sub _version_matches {
    my $version = shift;

    if ($version ne VERSION()) {
        _walk_data { ERROR => { errorType => 'versionsDiffer',
                                s         =>   "report: '$version' <@> "
                                             . "XML.pm: '" . VERSION() . "'"
                              }
                   }, 'ERROR';
        return 0;
    }
    return 1;
}

########################################################################
# from here: exported functions
########################################################################

########################################################################
# start_cb
########################################################################

=head2 start_cb(\&cb)

This function sets the function to be called for each node and its attributes
and then starts the nodes "data" and "reports".

See L<finish_cb()|finish_cb__> for how to complete the processing of reports.

The following argument is expected:

=over

=item C<cb>

Reference to the callback function.

The following arguments are passed to the callback function:

=over

=item C<path>

This is a reference to an array containing the names of all parent nodes of the
current node.

=item C<type>

This will have one the values C<empty>, C<start> or C<end>.
For each C<start>, the function is also called with the matching C<end> after
all subnodes have been processed.
For C<empty> (a node without subnodes, but possibly attributes), the function
is only called once.

=item C<node>

This is the name of the current node.

=item [C<name>, C<value>, ...]

This is an (optionally empty) list of pairs of node attribute names and values.
If C<type> is C<end>, the list is always empty.

=back

The callback function should return one the following values:

=over

=item 0

An error occurred which should abort the processing.

=item 1

No error occurred.

=back

=back

The function will return one of the following values:

=over

=item 0

The function was called in improper sequence, or the argument C<cb> was not a
reference to a function, or the callback function returned an error
when processing the opening of the nodes "data" or "reports".

=item 1

No error occurred.

=back

=cut

sub start_cb {
    # check state
    return 0 if $#node_path != -1;

    # set callback function and state
    _set_cb shift or return 0;
    push @node_path, '';

    # start processing
    _new_node 'start', 'data' or return 0;
    return _new_node 'start', 'reports',
                     xmlns => 'http://metaf2xml.sourceforge.net/' . VERSION(),
                     query_start => gmtime().'';
}

########################################################################
# start_xml
########################################################################

=head2 start_xml(\%opts)

This function sets the options relevant for writing the data as XML and starts
to write the XML file.

See L<finish_cb()|finish_cb__> for how to complete the processing of reports.

The following argument is expected:

=over

=item C<opts>

Reference to hash of options. The following keys of the hash are recognised:

=over

=item C<o>, with value B<E<lt>out_fileE<gt>>

enables writing the data to <out_file>

=item C<D>

include DOCTYPE and reference to the DTD

=item C<S>, with value B<E<lt>xslt_fileE<gt>>

include reference to the stylesheet <xslt_file>

=item C<O>, with value B<E<lt>optionsE<gt>>

include <options> (a space separated list of options)

=back

Without the key C<o>, no output is generated.

=back

The function will return one of the following values:

=over

=item 0

The function was called in improper sequence or the callback function returned
an error when opening the output file or writing the XML for the nodes "data"
or "reports" to it.

=item 1

No error occurred.

=back

=cut

sub start_xml {
    _set_opts_xml shift;
    return start_cb \&_write_xml;
}

########################################################################
# print_report
########################################################################

=head2 print_report(\%report)

This function invokes the callback function for each data item in C<report>. If
L<start_xml(\%opts)|start_xml___opts_> was invoked initially, an internal
callback function is used which writes the data as XML.

The function can be called as often as necessary.

See L<finish_cb()|finish_cb__> for how to complete the processing of reports.

The following argument is expected:

=over

=item C<report>

reference to hash of data

=back

The function will return one of the following values:

=over

=item 0

The function was called in improper sequence, or the versions of C<report> and
this module do not match, or the callback function returned an error when
processing data from C<report>.

The internal callback function to write the data as XML will return an error if
writing to the output file failed.

=item 1

No error occurred.

=back

=cut

sub print_report {
    my $report = shift;

    return 0 if $#node_path == -1;

    $report->{version} = '' unless exists $report->{version};

    if (exists $report->{isSynop}) {
        _new_node 'start', 'synop', 's', $report->{msg} or return 0;

        return _end_node
            unless _version_matches $report->{version};

        for (qw(ERROR warning
                obsStationType callSign obsTime reportModifier
                windIndicator stationPosition obsStationId precipInd wxInd
                baseLowestCloud visPrev visibilityAtLoc totalCloudCover
                sfcWind temperature stationPressure SLP gpSurface
                pressureChange precipitation weatherSynop cloudTypes
                exactObsTime))
        {
            _walk_data $report, $_ or return 0
                if exists $report->{$_};
        }

        for (2..5) {
            if (exists $report->{"section$_"}) {
                if ($#{$report->{"section$_"}} > -1) {
                    _new_node 'start', "synop_section$_", 's', $_ x 3
                        or return 0;
                    _walk_data { Arr => $report->{"section$_"} }, 'Arr'
                        or return 0;
                    _end_node or return 0;
                } else {
                    _new_node 'empty', "synop_section$_", 's', $_ x 3
                }
            }
        }

        return _end_node;
    } elsif (exists $report->{isBuoy}) {
        _new_node 'start', 'buoy', 's', $report->{msg};

        return _end_node
            unless _version_matches $report->{version};

        for (qw(ERROR warning
                obsStationType buoyId obsTime windIndicator stationPosition
                qualityPositionTime))
        {
            _walk_data $report, $_ or return 0
                if exists $report->{$_};
        }

        for (1..4) {
            if (exists $report->{"section$_"}) {
                if ($#{$report->{"section$_"}} > -1) {
                    _new_node 'start', "buoy_section$_", 's', $_ x 3
                        or return 0;
                    _walk_data { Arr => $report->{"section$_"} }, 'Arr'
                        or return 0;
                    _end_node or return 0;
                } else {
                    _new_node 'empty', "buoy_section$_", 's', $_ x 3
                }
            }
        }

        return _end_node;
    } else {
        my $is_taf;

        $is_taf = exists $report->{isTaf};
        _new_node 'start', $is_taf ? 'taf' : 'metar', 's', $report->{msg};

        return _end_node
            unless _version_matches $report->{version};

        for (qw(ERROR warning isSpeci
                obsStationId obsTime issueTime fcstPeriod reportModifier
                fcstCancelled fcstNotAvbl
                skyObstructed sfcWind windShearLvlArr
                CAVOK visPrev visMin visRwy RVRNO weather cloud visVert
                temperature QNH QFE waterTemp seaCondition stationPressure
                cloudMaxCover recentWeather QFF windShear rwyState
                colourCode NEFO_PLAYA RH windAtLoc rwyWind TAFsupplArr))
        {
            _walk_data $report, $_ or return 0
                if exists $report->{$_};
        }

        if (exists $report->{trend}) {
            for my $td (@{$report->{trend}}) {
                _new_node 'start', 'trend', 's', $td->{s};
                for (qw(trendType timeAt timeFrom timeTill probability
                        sfcWind CAVOK visPrev visVert weather cloud
                        rwyState colourCode TAFsupplArr))
                {
                    _walk_data $td, $_ or return 0
                        if exists $td->{$_};
                }
                _end_node or return 0;
            }
        }

        _walk_data $report, 'TAFinfoArr' or return 0
            if exists $report->{TAFinfoArr};
        _walk_data $report, 'remark', $is_taf ? 'tafRemark' : 'remark'
                or return 0
            if exists $report->{remark};

        return _end_node;
    }
}

########################################################################
# finish_cb, finish_xml
########################################################################

=head2 finish_cb()

This function and L<finish_xml()|finish_xml__> do the same thing and can be
used interchangeably.

Either function must be invoked to complete the writing to the XML file (i.e. if
L<start_xml(\%opts)|start_xml___opts_> was invoked initially), or if
L<start_xml(\%opts)|start_xml___opts_> or L<start_cb(\&cb)|start_cb___cb_> are
to be invoked later (again). Otherwise the use is optional, depending on the
mode of operation of the callback function and/or the calling program.

No arguments are expected.

The function will return one of the following values:

=over

=item 0

The function was called in improper sequence or the callback function returned
an error when processing the closure of the nodes "reports" or "data".

The internal callback function to write the data as XML will return an error if
writing to the output file or closing it failed.

=item 1

No error occurred.

=back

=cut

sub finish_cb {
    my $rc;

    # check state
    return 0 if $#node_path == -1;

    if ($#node_path != 2) {
        @node_path = ('', 'data');     # there was an error, overwrite path
        $rc = 0;
    } else {
        $rc = _end_node;               # close node "reports"
    }
    $rc = 0 unless _end_node;   # close node "data"
    $#node_path = -1;           # set state

    return $rc;
}

=head2 finish_xml()

See L<finish_cb()|finish_cb__>.

=cut

sub finish_xml { return finish_cb; }

=head1 SEE ALSO

=begin html

<p>
<a href="parser.pm.html">metaf2xml::parser(3pm)</a>,
<a href="metaf2xml.pl.html">metaf2xml(1)</a>,
</p><!--

=end html

B<metaf2xml::parser>(3pm),
B<metaf2xml>(1),

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
