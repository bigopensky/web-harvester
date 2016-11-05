# Ringing DB  Falsterbo Garden Birds

This little project, initiated in 2012, provides a tool to harvest bird census and ringing data from the Swedish ringing station at Falsterbo, Lighthouse Garden.

URL: http://www.falsterbofagelstation.se/

and it enables to store this information in a postgresql database.

Scientists can use the resulting phenological information to better understand migration patterns recorded with automated sensor systems situated on coastal and offshore stations, such as the Falsterbo Lighthouse or the platform FINO 2 in the Baltic Sea.

URL: http://www.fino2.de/fino2.php

In combination with data from national weather stations (e.g. German Weather Service, DWD) and other harvestable long-term weather data bases, such as OGIMET.COM, it is possible to analyze why and when events of mass migration occur.

This bunch of scripts is the first step towards a combined publicly available phenology network for migratory birds studied with various methods throughout Europe.

The sensor systems currently running on the platform FINO 2 are

VARS: http://www.ifaoe.de/en/equipment/vars/

FIXED BEAM aka BIRD-SCAN : http://www.ifaoe.de/en/equipment/bird-scan/

and

LOTEK: http://www.lotek.com/vhf-radio-receivers-dataloggers.htm

We have issued our software snippets under the GPL, due to the free data policy of our Swedish colleagues. But if you use the Falsterbo datasets please be correct and inform the scientists at Falsterbo about your activities, the purpose of your study and the conditions of usage. Please keep in mind that the collection of biological datasets is a demanding and invaluable job, involving numerous unpaid volunteers. So be nice to the community and use these tools and the harvested data responsibly.

We hope you enjoy the stuff.

DEPT. OF ORNITHOLOGY at IFAOE.DE

 

## Installation

The software runs under and is tested in a LINUX environment.
You have to be familar with bash, perl, and postgresql programming.

### Create the database and checking the structure
``` bash
$ createdb ringing
$ psql ringing < psql ringing_falsterbo < create-db.sql 
```

* Check the database structure.
``` bash
$ psql ringng -c '\d'
                        List of relations
 Schema |               Name                |   Type   | Owner 
--------+-----------------------------------+----------+-------
 public | falsterbo_lighthouse              | table    | iaw
 public | falsterbo_lighthouse_lh_ident_seq | sequence | iaw
(2 rows)

$ psql ringing -c '\d falsterbo_lighthouse'
                                    Table "public.falsterbo_lighthouse"
  Column  |         Type          |                                Modifiers                                
----------+-----------------------+-------------------------------------------------------------------------
 lh_ident | integer               | not null default nextval('falsterbo_lighthouse_lh_ident_seq'::regclass)
 lh_taxon | character varying(64) | 
 lh_dsum  | integer               | 
 lh_ssum  | integer               | 
 lh_savg  | integer               | 
 lh_utc   | date                  | 
Indexes:
    "falsterbo_lighthouse_pkey" PRIMARY KEY, btree (lh_ident)
    "falsterbo_lighthouse_ix_taxon" btree (lh_taxon)
    "falsterbo_lighthouse_ix_utc" btree (lh_utc)
```

## Checkout the harvester 
 
You can use the harvester in normal request mode to generate a text table or a set of sql statements. The man page is embedded in the perl script and give you some usage infos.

``` bash

$ ./fb-get.pl --help
NAME
    fb-get - Read Falsterbo bird census records at a date

SYNOPSIS
    fb-get [--date ISO8601|today [--offset] [--verbose] [--format text|sql]\
    [--delete] [--table sqlTable] [--fields sqlFieldNames]

DESCRIPTION
    fb-get is a Harvester to read and parse records from the Falsterbo
    Lighthouse Garden bird ringing station in sweden. It extracts bird ringing
    statistics for a special day and a given offset (in days). SQL und plain
    text can be used as output.

EXAMPLES
    fb-get
    fb-get --date 2014-04-10 --offset 12
    fb-get --date today --offset -10 --format sql --delete

OPTIONS
    --date TEXT
            The date where the record offset is anchored. Default is 'today'.
            The Syntax is defined by the -d option of the UNIX date command.

    --delete
            Delete existing datasets in SQL mode. This option inserts a the
            SQl command DELETE FROM $TABLE WHERE DATE = $DATE + $OFFSET.

    --fields TEXT
            Option to change the five SQL field names in exact this order.
            Default is 'DATE DSUM SSUM SAVG SPEC'
            DATE    The date field has to be the first
            DSUM    Day sum of the catched birds the second field.
            SSUM    Saisonal sum of the cached birds the third field.
           SAVG    Saisonal average of the cached birds the forth field.

            SPEC    The taxon of the cached birds the last field.

    --format text|sql
            Output format tabbed text or SQL

    --help  Print a brief help message and exits.

    --offset INTEGER
            The offset in time before/after the --date. Negtive value means
            days before the $DATE and a positive value means days after the
            $DATE.

    --table TEXT
            Option to change the SQL table name. Default is
            'falsterbo_lighthouse'

    --verbose
            Show some more info's while the script is working.

OUTPUT TEXT
    All fields are TAB separated.
    > ./fb-get.pl --offset -1
    DATE DSUM SSUM SAVG SPEC
    2015-04-08 2 42 24 WINTER WREN
    2015-04-08 1 13 8 EURASIAN SISKIN
    2015-04-08 5 32 50 DUNNOCK
    2015-04-08 3 93 209 EUROPEAN ROBIN
    2015-04-08 1 13 13 SONG THRUSH
    2015-04-08 1 7 6 COMMON CHIFFCHAFF
    2015-04-08 1 99 119 GOLDCREST
    2015-04-08 5 6 10 BLUE TIT
    2015-04-08 1 1 0 WOOD NUTHATCH
    2015-04-08 1 18 40 CHAFFINCH
OUTPUT SQL
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

AUTHOR
    (c) - 2012 Alexander Weidauer;
    weidauer@ifaoe.de or
    alex.weidauer@huckfinn.de
```

To build a persistent info source you should run the harvester and store the results in your database. The temporal granularity for the bird rining activieties in Falsterbo is one day.   

``` bash 
$ ./fb-get.pl --format sql --delete \
   --fields 'lh_utc lh_dsum lh_ssum lh_savg lh_taxon' | psql ringing;
DELETE 20
INSERT 0 20
```
Ok, lets fill the database with requests for the last 6 days.

``` bash
$ for d in {0..5}; do
> dt=$(date -d "today-$d days" +'%Y-%m-%d');
> echo "..get data at $dt";
> echo $dt >> six-days.log;
> ./fb-get.pl --date today --offset -$d --format sql --delete \
>   --fields 'lh_utc lh_dsum lh_ssum lh_savg lh_taxon' | psql ringing six-days.log;
> sleep 4; # Be nice to the server
> done
..get data at 2015-10-05
..get data at 2015-10-04
..get data at 2015-10-03
..get data at 2015-10-02
..get data at 2015-10-01
..get data at 2015-09-30
```

If you write a cronjob and read the record of yesterday at 02:00 AM you will update your database daily.

Enjoy Alex. 
