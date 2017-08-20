--!/usr/bin/psql DATABASE
-- ---------------------------------------------------------------- Tool zur Erstellung von GIS-Daten fuer die Stationsliste
-- --------------------------------------------------------------
-- (C) - 2013-02-15 IFAOE.DE, A. Weidauer 
-- --------------------------------------------------------------
\i /usr/share/postgis-1.5/postgis.sql 
\i /usr/share/postgis-1.5/spatial_ref_sys.sql 

ALTER TABLE wmo ADD COLUMN stn_id SERIAL PRIMARY KEY;
SELECT addgeometrycolumn('public', 'wmo', 'geom', 4326, 'POINT', 2);
UPDATE wmo SET geom=ST_SetSRID(ST_POINT(lon,lat),4326);                                       
SELECT addgeometrycolumn('public', 'wmo', 'geom_3d', 4326, 'POINT', 3);
UPDATE wmo SET geom=ST_SetSRID(ST_POINT(lon,lat),4326);
UPDATE wmo SET geom_3d=ST_SetSRID(ST_MAKEPOINT(lon,lat,hgt),4326);
-- EXPORT in eine Shape Datei
\! ogr2ogr station-ogimet.shp  PG:dbname=ogimet -sql "select geom, stn_id, wmo, icao from wmo"
-- --------------------------------------------------------------
--  EOF
-- --------------------------------------------------------------

