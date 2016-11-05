-- -------------------------------------------------------------------------
-- Database Script to create the bird census tables for the Falsterbo
-- Lighthouse Garden bird ringing datasets.
-- -------------------------------------------------------------------------
--  Copyright (C) 2012-06-05 Alexander Weidauer
--  alex.weidauer@huckfinn.de OR weidauer@ifaoe.de
--
--  This program is free software: you can redistribute it and/or modify
--  it under the terms of the GNU General Public License as published by
--  the Free Software Foundation, either version 3 of the License, or
--  any later version.
--
--  This program is distributed in the hope that it will be useful,
--  but WITHOUT ANY WARRANTY; without even the implied warranty of
--  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
--  GNU General Public License for more details.
--
--  You should have received a copy of the GNU General Public License
--  along with this program.  If not, see <http://www.gnu.org/licenses/>.
-- --------------------------------------------------------------------------
-- Table for the rining datasets
-- --------------------------------------------------------------------------
CREATE TABLE falsterbo_lighthouse (
  lh_ident SERIAL PRIMARY KEY,
  lh_taxon VARCHAR(64),
  -- daily total catches
  lh_dsum INTEGER,
  -- Seasonal total up to and incl. selected date
  lh_ssum INTEGER,
  -- Average 1980-2009 up to and incl. selected date.
  lh_savg INTEGER,
  -- Date of the request / catches
  lh_utc  DATE
);

COMMENT ON TABLE falsterbo_lighthouse IS
'Table for the rining datasets';

COMMENT ON COLUMN falsterbo_lighthouse.lh_ident IS
'Primary key with auto increment';

COMMENT ON COLUMN falsterbo_lighthouse.lh_taxon IS
'The catched or spotted taxon usually written uppercase in english';

COMMENT ON COLUMN falsterbo_lighthouse.lh_dsum IS
'Total daily catches of a taxon';

COMMENT ON COLUMN falsterbo_lighthouse.lh_ssum IS
'Seasonal total catches of the taxon including the selected day';

COMMENT ON COLUMN falsterbo_lighthouse.lh_savg IS
'Average catches 1980-2009 of the taxon up to including the selected day';

COMMENT ON COLUMN falsterbo_lighthouse.lh_utc IS
'Date of the requested dataset';

-- --------------------------------------------------------------------------
-- INDEX STUFF falsterbo_lighthouse
-- --------------------------------------------------------------------------
CREATE INDEX falsterbo_lighthouse_ix_taxon ON falsterbo_lighthouse(lh_taxon);

COMMENT ON INDEX falsterbo_lighthouse_ix_taxon IS
'Index on taxa for fast filter operations';

CREATE INDEX falsterbo_lighthouse_ix_utc ON falsterbo_lighthouse(lh_utc);

COMMENT ON INDEX falsterbo_lighthouse_ix_utc IS
'Index on date for fast filter operations';

-- --------------------------------------------------------------------------
-- EOF
-- --------------------------------------------------------------------------
