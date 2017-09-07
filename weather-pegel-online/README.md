# Read data from Pegel Online in Germany

## Pegel Online 

[Pegel Online](https://www.pegelonline.wsv.de) is a german web site
for estuarine and river water level data. The data are provided at a
minute level. The small harvester example written in perl is used to
compare dataset from pegelonline with the datasets produced by the
[IMK-Station](http://www.imk-mv.de/) a sensor coastal network along the
coast of Mecklenburg-Western/Pommerania in Germany.

## Environment

The tool is written for *IX environment, uses the system command <date>
and needs the perl packages:

* LWP::Simple - WEB access
* Data::Dumper - Debug purposes
* Statistics::Basic - group data over 10 min intervals with (average/ standard derivation)
* URI::Escape - Escape german Umlaut's
* IO::String  - Deal with the web content line wise

## Usage  
```
./harvester.pl station_index:[0..6] [date] [WSV|IMK] to get datasets

./harvester.pl -l or --list to list the station index

./harvester.pl -h or --help to get some help 
```
## Examples

Examples:

> ./harvester.pl 0 today
> ./harvester.pl 1 'yesterday-1 day'

## License

 Copyright (C) 2016 Alexander Weidauer
 Contact: alex.weidauer@huckfinn.de

 This program is free software: you can redistribute it and/or modify
 it under the terms of the GNU General Public License as published by
 the Free Software Foundation, either version 3 of the License, or
 any later version.

 This program is distributed in the hope that it will be useful,
 but WITHOUT ANY WARRANTY; without even the implied warranty of
 MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 GNU General Public License for more details.

 You should have received a copy of the GNU General Public License
 along with this program.  If not, see <http://www.gnu.org/licenses/>.


