# HEADER  --------------------------------------------------------------------
# Validate marine for aaerial monitoring species setup via GBIF
# 2021 - (C) Alexander Weidauer 2021 IfGDV.DE
# alex.weidauer@ifgdv.de ALL RIGHTS RESERVED
#
# The code is released under the 3-Clause BSD licence
#
# Script to harvest marine species metadata from GBIF as an entry to
# data for body metrics, images an links to other taxon databases

# REQIREMENTS ----------------------------------------------------------------
rm(list=ls())
require(rgbif)
require(stringr)

# SETTINGS -------------------------------------------------------------------
# Source File
inFile <- 'data/taxa-import-candidates-v2.tsv'

# Resulting file
outFile <- 'data/taxa-import-proof-v2.tsv'

# Read the base table
tab <- read.table(file=inFile,
                  sep="\t", header=T, fill=T)

#@ TEST DATA  smpKey <- 2481958
#@ TEST DATA smpName <- 'Gavia Stellata'

# SERVICE FUNCTIONS ---------------------------------------------------------

# Search for an alternative species if the first check fails ----------------
getOtherSpecies <- function(sciName) {

    # Prepare the result set
    result <- list(valid = F, key = 0, name = '**NONE**')

    # Search a different taxa descriptors
    query <- name_lookup(query=sciName)$data

    # Bail out if nothing was found
    if (dim(query)[1] == 0) { return(result)}

    # Filter the alternatives
    alter <- subset(query,
                    grepl('ACCEPTED', taxonomicStatus) &
                    ! is.na(authorship) &
                    ! is.na(nubKey)  )

    # Prepare a ranking vector
    alter$tcount <- 1

    # Calculate the rank ..usually links to the valid GBIF entry
    rank   <- aggregate( tcount ~ nubKey, data = alter, FUN = sum)

    # Use the rank only if there is a lager info base, else take the first nubKey
    if (max(rank$tcount)>3) {
           taxKey <- rank[max(rank$tcount) == rank$tcount, 'nubKey']
    } else {
          taxKey <- rank[ 1, 'nubKey']
    }

     # extract the taxa key
     taxKey <- as.numeric(taxKey[1])

     # load now the alternative record
     alter  <- name_usage(key = taxKey )$data

     # Prepare the result set
     result$valid <- T
     result$key   <- as.numeric(alter[1,'key'])
     result$name  <- as.character(alter[1,'species'])
     return(result)
}


# GetMetadata for habitat and ThreadStates ------------------------------------
getMetadata <- function(sciName, taxaKey) {

    # Init the resultset
    result = list(valid = F, name='*NONE**', key=0, isMarine=F, isTerra=F, isFresh=F,
                  status='**NONE**')

    # Search the species
    query <- name_lookup(query=sciName)$data

    # Bail out if nothing was found
    if (dim(query)[1] == 0) {
       return(result)
    }

    # Filter the habitat subset
    habitat <- subset( query,
                       ! is.na(query$habitats) &
                         grepl('ACCEPTED', taxonomicStatus) &
                         query$key == taxaKey,
                         select = habitats)

    # Prepare the resultset for the habitat descriptors
    result$name <- sciName
    result$key  <- taxaKey
    result$isMarine <- grepl('MARINE',habitat)
    result$isFresh  <- grepl('FRESHWATER',habitat)
    result$isTerra  <- grepl('TERRESTRIAL',habitat)

    # Filter the threat status
    status <- subset( query,
                     ! is.na(query$threatStatuses) &
                      query$key == taxaKey &
                      grepl('ACCEPTED', taxonomicStatus),
                      select = threatStatuses)

    # Make the list unique an build a string
    status <- str_split(as.character(status),',', simplify=TRUE)
    status <- str_trim(status)
    status <- unique(status)
    status <- paste(status, collapse=', ')
    status <- gsub('_','-',status)

    # Return the result set
    result$status <- status
    result$valid <- T
    return(result)
}

# Get vernacularName and Media Links -----------------------------------------
getEnName <- function(taxKey) {

     # try to get the names
     verNames <- name_usage(key=taxKey, language="en", data='vernacularNames')$data

     # Bail out if nothing was found
     if ( dim(verNames)[1] == 0) {
       return('**NONE**')
     }

     # Filter the results because there are different language entries present
     prfNames <-  subset(verNames, language =='eng')

     # Bail out if nothing was found
     if ( dim(prfNames)[1] == 0) {
       return('**NONE**')
     }

     # Prepare a ranking table
     prfNames$tname  <- prfNames$vernacularName # TODO create a name parser
     prfNames$tcount <- 1
     rank <- aggregate( tcount ~ tname, data = prfNames, FUN=sum )

     # Use the rank only if there is a lager info base, else take the first name
     if (max(rank$tcount)>3) {
       name <- rank[max(rank$tcount) == rank$tcount, 'tname']
     } else {
       name <- rank[ 1, 'tname']
     }
     return(name[1])
}

# CleanUp linknames as scalar ------------------------------------------------
strEmptyHttp <- function(str, pat='^http') {
   if (length(str)==0)   return('**NONE**');
   return(as.character(unlist(str)))
}

# Harvester function ----------------------------------------------------------
#' Harvester function to get the author and ID by the scientific name
getGbifData <- function(sciName) {

    # Init the result
    result  <- list(valid=FALSE ,
                    gbif='',
                    key=0,
                    rank='NONE',
                    name='**NONE**',
                    class='',
                    author='',
                    lnkWiki='**NONE**',
                    lnkWorms='**NONE**',
                    lnkItis='**NONE**',
                    lnkIUCN='**NONE**',
                    lnkGBIF='',
                    hbtMarine=F,
                    hbtTerra=F,
                    hbtFWater=F,
                    threadStatus='**NONE**')

    # Find the animal record
    sciData <- name_usage(name = sciName)$data
    numRows <- dim(sciData)[1]

    # Bail out if no item was found
    if (numRows == 0) {
      return(result)
    }

    # Filter the accepted gbif record
    sciRec  <- subset( sciData,
                       grepl('^gbif:',   taxonID) &
                       grepl('ACCEPTED', taxonomicStatus))

    # Bail out if no record was filtered
    theRow <- dim(sciRec)[1]
    if (theRow == 0) {
      return(result)
    }

    # Warning for duplicate entries
    if (theRow > 1) {
      cat("WARNING: Choosing the first candidate of",sciName,"\n");
      sciRec <- sciRec[1,]
    }
    # sciRec$key

    # Fill the result record
    result$author   <- str_trim(sciRec$authorship)
    result$gbif     <- str_to_upper(sciRec$taxonID)
    result$key      <- sciRec$key
    result$name     <- getEnName(sciRec$key)
    sciRec$key
    result$class    <- sciRec$class

    # If the references column is present
    if ( ! is.null( sciData[['references']])) {

      # get the englich wikipedia link
      result$lnkWiki  <- strEmptyHttp(
        subset( sciData,
                grepl('^http://en.wikipedia.org',    references) &
                  grepl('ACCEPTED', taxonomicStatus))[1,'references'])

      # get the ITIS link
      result$lnkItis  <- strEmptyHttp(
        subset( sciData,
                grepl('^https://www.itis.gov',    references) &
                  grepl('ACCEPTED', taxonomicStatus))[1,'references'])


      result$lnkWorms  <- strEmptyHttp(
        subset( sciData,
                grepl('^http://www.marinespecies.org',    references) &
                  grepl('ACCEPTED', taxonomicStatus))[1,'references'])

      result$lnkIUCN  <- strEmptyHttp(
        subset( sciData,
                grepl('.iucnredlist.org',    references) &
                  grepl('ACCEPTED', taxonomicStatus))[1,'references'])

    } else {
      # find another way to get links
    }

    # Create the GBIF link
    result$lnkGBIF  <- sprintf('https://www.gbif.org/species/%s', sciRec$key)

    # Read the habitat and theard status
    meta <- getMetadata(sciName, sciRec$key)

    if (meta$valid) {
       result$hbtMarine <- meta$isMarine
       result$hbtTerra  <- meta$isTerra
       result$hbtFWater <- meta$isFresh
       result$threadStatus <- meta$status
    }

    # Prepare the result record
    result$rank   <- sciRec$rank
    result$valid  <- TRUE

    return(result)
}

# Prepare the table ----------------------------------------------------------
work <- tab[,c('KEY','KEY_ALT')]
work$GBIF      <- '**NONE**'
work$SRANK     <- tab$LEVEL
work$RANK      <- '**NONE**'
work$SCI_NAME  <- tab$LAT_NAME
work$ACC_NAME  <- '**NONE**'
work$OEN_NAME  <- tab$EN_NAME
work$HEN_NAME  <- '**NONE**'
work$AUTHOR    <- tab$AUTHOR
work$CLASS     <- '**NONE**'
work$MARINE    <- F
work$TERRESTIC <- F
work$FRESHWATER  <- F
work$PROGRAM   <- tab$GROUP1
work$GROUP     <- tab$GROUP2
work$ARTIFCIAL <- (tab$GROUP3 == 'unknown')
work$STATUS    <- ''
work$BDY_LEN   <- tab$BDY_LEN
work$BDY_SPAN  <- tab$BDY_SPAN
work$LNK_GBIF  <- ''
work$LNK_IUCN  <- ''
work$LNK_ITIS  <- ''
work$LNK_WIKI  <- ''
work$LNK_WORMS <- ''

#@ TEST RUN getGbifData('Gavia stellata')

# Iterate over the old table entries -----------------------------------------
numRows <- dim(tab)[1]
for(ixRow in (1:numRows) ) {
  # ixRow <- 285

  # Read the nth row
  row     <- work[ixRow,]
  sciName <- row$SCI_NAME

  # Give a response
  cat(ixRow,'of', numRows, 'NAME:', sciName,'\n')

  # Ingnor the fancier EURING stuff
  if (row$SRANK == 'UI' ) { next }

  # Check if the name is empty (excel can be stupid)
  if (str_trim(sciName) == '' ) { next }

  # Try to ge data with the EURING species
  gbif <- getGbifData(sciName)

  # Run next if nothing was found and the entry is not a species
  if ( ! gbif$valid & (row$SRANK != 'S') ) { next }

  # Try to fin an alternative name
  if ( ! gbif$valid ) {

    # Get the data
    alt <- getOtherSpecies(sciName)

    # Go to the next row if nothing was found
    if (! alt$valid) { next }

    # Set the scientific name
    sciName <- alt$name

    # Give a responsthat the name was changed
    cat(ixRow,'of', numRows, 'ALTER NAME: ', sciName,'\n')

    # Try to get the info's with the new name
    gbif <- getGbifData(sciName)

    # Take the next record if nothing was found
    if ( ! gbif$valid  ) { next }
  }

  # Fill the alternative column with the GBIF when empty
  if ( row$KEY_ALT == '' ) { row$KEY_ALT <- gbif$gbif }

  # Write the fields
  row$ACC_NAME   <- sciName
  row$GBIF       <- gbif$key
  row$RANK       <- gbif$rank
  row$HEN_NAME   <- gbif$name
  row$AUTHOR     <- gbif$author
  row$CLASS      <- gbif$class
  row$MARINE     <- gbif$hbtMarine
  row$TERRESTIC  <- gbif$hbtTerra
  row$FRESHWATER <- gbif$hbtFWater
  row$STATUS     <- gbif$threadStatus
  row$LNK_GBIF   <- gbif$lnkGBIF
  row$LNK_IUCN   <- gbif$lnkIUCN
  row$LNK_ITIS   <- gbif$lnkItis
  row$LNK_WORMS  <- gbif$lnkWorms
  row$LNK_WIKI   <- gbif$lnkWiki

  # Update the work table
  work[ixRow, ]  <- row

  # Be nice to the GBIF server
  Sys.sleep(1)
}

# Write the resulting table --------------------------------------------------
write.table(work, file=outFile, row.names = F)

# EOF ------------------------------------------------------------------------
