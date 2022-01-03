# -----------------------------------------------------------------------
# Reverse engineering of EURING Bird Names via GBIF & EOL
# 2021 - (C) Alexander Weidauer 2021 IfGDV.DE
# alex.weidauer@ifgdv.de
#
# The code is released under 3-Clause BSD License 
#
# The script is part of a bootstrapping strategy to resolve EURING entries 
# reversely for mining processes in other open taxa databased to get proper
# descriptions, body length and pictures for an aerial species identification  
#
# Taxize was difficult to handle to solve the euring names reversly 
# -----------------------------------------------------------------------

# Load taxize
require(taxize)

# Load EURING
require(birdring)
data(species)

# Plain file output
fname  <- 'data/euring-rev-names-2.dat' 

# Prepare result table
result <- data.frame(Code = 0,        Name = 'Indet.', 
                     Rev  ='Indet.' , Common = 'Unknown' )

# Write new file with header ..just in case
cat('Code\tScientific\tCommon\tReverse\n',file=fname)

# Iterate over the stuff without the first indet. column
nrow <- dim(species)[1]
for(ix in 1144:nrow) {
  
  # Get code number
  cod <- as.character(species[ix, 'Code'])
  
  # Get scientific name 
  sci <- as.character(species[ix, 'Name'])
  
  # Find the scientific name on GBIF
  id.rec  <- get_gbifid(sci, message = F, ask = F, rows=1:1)
  
  # Skip if not found
  if (! is.na(id.rec) ) {
    
    # Resolve the revese and for taxite understood name
    id.tab  <- as.data.frame(id.rec)
    rev.sci <- id2name(id.tab$ids, db = 'gbif')[[1]]
    rev <- rev.sci$name;
    
    # Find common name, at the moment no way to determine 
    # the language (is ignored)
    if (! is.na(rev) ) {
      coml <- unlist(sci2comm(sci = rev, db = 'eol', language = 'en'))
      com  <- coml[1]
      if (is.na(com)) { com <-'NA' } 
    } else {
      rev <- 'NA'
      com <- 'NA'
    }  

    # Append the result 
    result  <- rbind(result,
                     data.frame(Code = cod, Name   = sci, 
                                Rev  = rev, Common = com))
    
    com <- gsub("'", "\\\\'", com)

    # Format for plain writing 
    fmt <- sprintf("%d\t'%s'\t'%s'\t'%s'\n", as.numeric(cod), sci, com, rev)
    
    # Give a user response
    cat(fmt)
    
    # Write plain file 
    cat(fmt, file=fname, append = T)
  }
}

# Write the result table
write.table(result, file='harvested-euring-2.tab', row.names = F)

# EOF
