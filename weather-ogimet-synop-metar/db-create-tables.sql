-- ------------------------------------------------------
-- DB fuer die Verarbeitung von Wetternachrichten
-- ------------------------------------------------------
-- (c) A. Weidauer alex.weidauer@huckfinn.de 
-- ------------------------------------------------------
-- ICAO Ortstabelle der Flugplatzstandorte
-- ------------------------------------------------------
DROP IF EXISTS TABLE ICAO;
CREATE TABLE ICAO (
  icao varchar(8),  -- Schluessel
  site varchar(50), -- Ortsname
  lon double precision, -- geogr. Laenge 
  lat double precision, -- geogr. Breite
  hgt double precision  -- Hoehe ueber NN
);

-- ------------------------------------------------------
-- WMO Tabelle der Wetterstationen
-- ------------------------------------------------------
DROP TABLE WMO;
CREATE TABLE WMO (
   wmo varchar(10),  -- Schluessel Wetterstation
   icao varchar(8),  -- Schluessel FP
   Site varchar(80), -- Ortsname 
   country varchar(80), -- Land
   lon double precision, -- geogr. Laenge
   lat double precision, -- geogr. Breite
   hgt double precision  -- Hoehe uener NN
 );

-- ------------------------------------------------------
-- Tabelle der Metar Nachrichten
-- ------------------------------------------------------
DROP IF EXISTS  TABLE metar_msg;
CREATE TABLE metar_msg (
	obs_ptc  varchar(10), -- Wetterprotokoll
	obs_site varchar(10), -- Beobachtungsort
	obs_time timestamp without time zone, -- Beobactungszeit ZULU
	obs_msg	 varchar(10),  -- Meldungstyp
	error    varchar(255), -- evt. Fehler
	obs_code varchar(255), -- originale Nachricht
-- Oberflaechendaten 
	sfc_at_unt	varchar(8), -- Temperatur
	sfc_at_val	double precision,
	sfc_dp_unt	varchar(8), -- Taupunkt
	sfc_dp_val	double precision,
	sfc_p_unt	varchar(8), -- Luftdruck
	sfc_p_val	double precision,
	sfc_rh_unt	varchar(8), -- relative Luftfeuchte
	sfc_rh_val	double precision,
-- Windrichtung
	sfc_wd_dneg	double precision, -- Windrichtung Abweichng negativ
	sfc_wd_dpos	double precision, -- Windrichtung Abweichung positiv
	sfc_wd_from	varchar(8),       -- Ansprache Wind aus Richtung
	sfc_wd_unt	varchar(8),       
	sfc_wd_val	double precision, -- Windrichtung
	sfc_ws_unt	varchar(8),
	sfc_ws_val	double precision, -- Messungsinterval 
	sfc_wv_unt	varchar(8),
	sfc_wv_val	double precision, -- Windgeschwindigkeit
-- Sichtweiten
	pv_vs_ddist	double precision,  -- Sichtweite Messfehler
	pv_vs_unt	 varchar(8),      
	pv_vs_untx	 varchar(10),      -- Modifikator der Einheit  
	pv_vs_val	 double precision, -- Sichtweite Wert
	pv_vs_valx	 varchar(32),      -- Sichtweite Modifikator
-- Wolkenschichten allg.
	cld_level integer,                 -- Anzahl der Wolkenschichten 
	cld_bs_min double precision,       -- unter Wolkngrenze 
	cld_bs_max double precision,       -- obere Wolkengrenze
	cld_bs_unt varchar(8),             -- Einheit
	cld_ds_sum double precision,       -- Bedeckungsgrad gesamt
	cld_ds_avg double precision,       -- Bedeckungsgrad Mittel
	cld_bs_dgh_max double precision,   -- Genauigkeit obere Grenze
-- Erste Schicht
	cld_bs_dgh_0 double precision,     -- Level 0
	cld_bs_val_0 double precision,     -- Hoehe untere Wolkenschicht 
	cld_ds_val_0 double precision,     -- Bedeckungsgrad 
	cld_ds_key_0 varchar(8),           -- Schluessel untere Schicht
	Cld_ds_unt_0 varchar(10),          -- Eineit Beeckung untere Schicht
-- Zweite Schicht
	cld_bs_dgh_1 double precision,
	cld_bs_val_1 double precision,
	cld_ds_val_1 double precision,
	cld_ds_key_1 varchar(8),
	cld_ds_unt_1 varchar(10),
-- Dritte Schicht
	cld_bs_dgh_2 double precision,
	cld_bs_val_2 double precision,
	cld_ds_val_2 double precision,
	cld_ds_key_2 varchar(8),
	cld_ds_unt_2 varchar(10),
-- Vierte Schicht
	cld_bs_dgh_3 double precision,
	cld_bs_val_3 double precision,
	cld_ds_val_3 double precision,
	cld_ds_key_3 varchar(8),
	cld_ds_unt_3 varchar(10),
-- Fuenfte Schicht
	cld_bs_dgh_4 double precision,
	cld_bs_val_4 double precision,
	cld_ds_val_4 double precision,
	cld_ds_key_4 varchar(8),
	cld_ds_unt_4 varchar(10),
-- Sechste Schicht
	cld_bs_dgh_5 double precision,
	cld_bs_val_5 double precision,
	cld_ds_val_5 double precision,
	cld_ds_key_5 varchar(8),
	cld_ds_unt_5 varchar(10),
-- Wettererscheinungen max 6 Eintraege
	wth_num integer,       -- Anzahl
-- Wetter Einrag 1        
	wth_dsc_0 varchar(256), -- Beschreibung 
	wth_key_0 varchar(32),  -- Schluessel
-- Wetter Einrag 2        
	wth_dsc_1 varchar(256),
	wth_key_1 varchar(32),
-- Wetter Einrag 3
	wth_dsc_2 varchar(256),
	wth_key_2 varchar(32),
-- Wetter Einrag 4
	wth_dsc_3 varchar(256),
	wth_key_3 varchar(32),
-- Wetter Einrag 5
	wth_dsc_4 varchar(256),
	wth_key_4 varchar(32),
-- Wetter Einrag 6
	wth_dsc_5 varchar(256),
	wth_key_5 varchar(32)
);

-- ------------------------------------------------------
-- Tabelle Synop Nachrichten Felder siehe oben
-- ------------------------------------------------------
DROP IF EXISTS TABLE synop_msg;
CREATE TABLE synop_msg (
	obs_ptc varchar(10),
	obs_site varchar(10),
	obs_time timestamp without time zone,
	obs_msg	 varchar(10),
	error varchar(255),
	obs_code varchar(255),
--
	sfc_at_unt	varchar(8),
	sfc_at_val	double precision,
	sfc_dp_unt	varchar(8),
	sfc_dp_val	double precision,
	sfc_p_unt	varchar(8),
	sfc_p_val	double precision,
	sfc_rh_unt	varchar(8),
	sfc_rh_val	double precision,
--
	slp_p_unt	varchar(8),
	slp_p_val	double precision,
--
	sfc_wd_dneg	double precision,
	sfc_wd_dpos	double precision,
	sfc_wd_from	varchar(8),
	sfc_wd_unt	varchar(8),
	sfc_wd_val	double precision,
	sfc_ws_unt	varchar(8),
	sfc_ws_val	double precision,
	sfc_wv_unt	varchar(8),
	sfc_wv_val	double precision,
--
	pv_vs_ddist	double precision,
	pv_vs_unt	 varchar(8),
	pv_vs_untx	 varchar(10),
	pv_vs_val	 double precision,
	pv_vs_valx	 varchar(32),
--
	cld_level integer,
	cld_bs_min double precision,
	cld_bs_max double precision,
	cld_bs_unt varchar(8),
	cld_ds_sum double precision,
	cld_ds_avg double precision,
	cld_bs_dgh_max double precision,
--
	cld_bs_dgh_0 double precision,
	cld_bs_val_0 double precision,
	cld_ds_val_0 double precision,
	cld_ds_key_0 varchar(8),
	cld_ds_unt_0 varchar(10),
	cld_ct_key_0 varchar(8),
--
	cld_bs_dgh_1 double precision,
	cld_bs_val_1 double precision,
	cld_ds_val_1 double precision,
	cld_ds_key_1 varchar(8),
	cld_ds_unt_1 varchar(10),
	cld_ct_key_1 varchar(8),
--
	cld_bs_dgh_2 double precision,
	cld_bs_val_2 double precision,
	cld_ds_val_2 double precision,
	cld_ds_key_2 varchar(8),
	cld_ds_unt_2 varchar(10),
	cld_ct_key_2 varchar(8),
--
	cld_bs_dgh_3 double precision,
	cld_bs_val_3 double precision,
	cld_ds_val_3 double precision,
	cld_ds_key_3 varchar(8),
	cld_ds_unt_3 varchar(10),
	cld_ct_key_3 varchar(8),
--
        cld_bs_dgh_4 double precision,
	cld_bs_val_4 double precision,
	cld_ds_val_4 double precision,
	cld_ds_key_4 varchar(8),
	cld_ds_unt_4 varchar(10),
	cld_ct_key_4 varchar(8),
--
	cld_bs_dgh_5 double precision,
	cld_bs_val_5 double precision,
	cld_ds_val_5 double precision,
	cld_ds_key_5 varchar(8),
	cld_ds_unt_5 varchar(10),
	cld_ct_key_5 varchar(8),
-- Niederschlag
	pcp_samples integer,  -- Anzahl der Niederschlagsmessungen
-- Messung 1
	pcp_am0_val double precision, -- Menge
	pcp_am0_unt varchar(8),       -- Einheit
	pcp_tb0_val double precision, -- Dauer
	pcp_tb0_unt varchar(8),        -- Einheit
-- Messung 2
	pcp_am1_val double precision,
	pcp_am1_unt varchar(8),
	pcp_tb1_val double precision,
	pcp_tb1_unt varchar(8),
-- Messung 3
	pcp_am2_val double precision,
	pcp_am2_unt varchar(8),
	pcp_tb2_val double precision,
	pcp_tb2_unt varchar(8),
-- Messung 4
	pcp_am3_val double precision,
	pcp_am3_unt varchar(8),
	pcp_tb3_val double precision,
	pcp_tb3_unt varchar(8),
-- Messung 5
	pcp_am4_val double precision,
	pcp_am4_unt varchar(8),
	pcp_tb4_val double precision,
	pcp_tb4_unt varchar(8),
-- Messung 6
	pcp_am5_val double precision,
	pcp_am5_unt varchar(8),
	pcp_tb5_val double precision,
	pcp_tb5_unt varchar(8),

-- Wettererscheinungen Beschreinung der Zeitraume
	Wth_tbf_val integer,    -- Anzahl
	wth_tbf_unt varchar(8), -- Einheit
-- Wettererscheinungen jetzt
	wth_now_dsc varchar(127),
	wth_now_key varchar(8),
-- Wetterscheinungen am Klimatermin davor 1  
	wth_bef0_dsc varchar(127),
	wth_bef0_key varchar(8),
-- Wttererscheinungen am Klimatermin davor 2
	wth_bef1_dsc varchar(127),
	wth_bef1_key varchar(8)
);
-- ------------------------------------------------------
-- EOF
-- ------------------------------------------------------
