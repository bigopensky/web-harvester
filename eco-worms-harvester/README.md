# WoRMS Harvester

The tool **worms-harvester** is Q&D solution to read and search
datasets from the taxonomic database
[WoRMS](http://www.marinespecies.org/).
The aim of a World Register of Marine Species (WoRMS) is to
provide an authoritative and comprehensive list of names of marine
organisms, including information on synonymy. While highest priority
goes to valid names, other names in use are included so that this
register can serve as a guide to interpret taxonomic literature.

## Installation

The tool worms-harvester.pl is a pure perl program and depends on the modules

* *Perl Web Service Toolkit* [SOAP::Lite](https://metacpan.org/pod/SOAP::Lite),
* [Data::Dumper](https://metacpan.org/pod/Data::Dumper) for debugging tasks and
* [Pod::Usage](https://metacpan.org/pod/Pod::Usage)

for the embedded help context.

Please follow the instructions of [Comprehensive Perl Archive
Network](http://www.cpan.org/modules/INSTALL.html) to install the listed modules
and the [Download and install Perl](https://www.perl.org/get.html) for the runtime environment.

## Functionality 

The tool works like a classical unix tool with some command modes

worms-harvester.pl MODE PARAM [OPTIONS..]

and a resulting data context written to the standard output channel.
There are 5 different modes, to search taxa, request ID's and list
a susequent information context, to query and build a hierachical
taxonomic species context:

* -i --search-id NAME
  Find taxon name by AphiaID

* -n --search-record NAME
  Find taxon by name

* -r --get-record ID
   Get the record for a specific AphiaID

* -s --search-fuzzy PATTERN
  Pattern search with max 50 results (EXPERIMENTAL)

* -c --get-children ID
  Get subsequent taxa fo a specific AphiaID

Due to it's Q&D role the adustment of the hierarchie is made
on the distinct taxonomic levels:

KINGDOM, PHYLUM, ORDER, CLASS, FAMILY, GENUS, SPECIES

(to determin the taxonomic distictness
[1](http://www.fc.up.pt/pessoas/amsantos/bea/clarwarw1999.pdf) for
example).  To maintain an canonic taxonomic classisfication/ meaning
the flags for synonyme names are provided.

The primary key in the WoRMS information context is called **AphiaID**.

The resulting context is writte in three the text formats DUMP, CSV and SQL.
Please follow the help context to get info's about the format structure.

## Examples:

### Get the primary key for an species aka AphiaID

> worms-harvester.pl -i Abra

```
INTEGER APHIA.ID 138474
```

### Search the info context specified by a name

> worms-harvester.pl -n Abra

```
WORMS ID 138474 
 INTEGER         APHIA.ID 
  STRING             NAME 'Abra'
  STRING           AUTHOR 'Lamarck, 1818'
  STRING             RANK 'Genus'
  STRING           STATUS 'accepted'
 INTEGER   VALID.APHIA.ID 138474
  STRING       VALID.NAME 'Abra'
  STRING     VALID_AUTHOR 'Lamarck, 1818'
  STRING          KINGDOM 'Animalia'
  STRING           PHYLUM 'Mollusca'
  STRING            CLASS 'Bivalvia'
  STRING            ORDER 'Cardiida'
  STRING           FAMILY 'Semelidae'
  STRING            GENUS 'Abra'
  STRING         CITATION 'Bouchet, P.; Gofas, S. (2012). Abra. In:  MolluscaBase (2017). Accessed through:  World Register of Marine Species at http://www.marinespecies.org/aphia.php?p=taxdetails&id=138474 on 2017-08-20'
EOF
```
### Get a record specified by an ID

> worms-harvester.pl -r 138474

```
WORMS ID 138474 
 INTEGER         APHIA.ID 1
  STRING             NAME 'Abra'
  STRING           AUTHOR 'Lamarck, 1818'
  STRING             RANK 'Genus'
  STRING           STATUS 'accepted'
 INTEGER   VALID.APHIA.ID 138474
  STRING       VALID.NAME 'Abra'
  STRING     VALID_AUTHOR 'Lamarck, 1818'
  STRING          KINGDOM 'Animalia'
  STRING           PHYLUM 'Mollusca'
  STRING            CLASS 'Bivalvia'
  STRING            ORDER 'Cardiida'
  STRING           FAMILY 'Semelidae'
  STRING            GENUS 'Abra'
  STRING         CITATION 'Bouchet, P.; Gofas, S. (2012). Abra. In:  MolluscaBase (2017). Accessed through:  World Register of Marine Species at http://www.marinespecies.org/aphia.php?p=taxdetails&id=138474 on 2017-08-20'
EOF
```
### Get children and filter ID and Name

> worms-harvester.pl -c 138474 | grep ' VALID\.' | less

```
   INTEGER   VALID.APHIA.ID 458015
    STRING       VALID.NAME 'Abra aegyptiaca'
   INTEGER   VALID.APHIA.ID 293683
    STRING       VALID.NAME 'Abra aequalis'
   INTEGER   VALID.APHIA.ID 293684
    STRING       VALID.NAME 'Abra affinis'
   INTEGER   VALID.APHIA.ID 507240
    STRING       VALID.NAME 'Abra africana'
````

## License

Copyright (C) 2012 Alexander Weidauer

Contact: alex.weidauer(AT)huckfinn.de

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
