#Set up connection to the SQLite database
library(DBI)
library(RSQLite)
connection <- dbConnect(RSQLite::SQLite(), dbname = "clinton.sqlite")
all_tables <-  dbListTables(connection)
docs <- dbGetQuery(connection, sprintf("SELECT * FROM %s", "docs"))
dbDisconnect(connection)

# drop unneccasry columns
library(data.table)
docs = data.table(docs)
DF = docs[,c("posted_date","pdf_link","author","doc_class","message_num","case_num", "reason",
             "declass_date", "id","full_path","is_document","doc_date","pdf_url" ):=NULL]

# data wrangling

  #>>> legend: CLASSIFICATION{CONFIDENTIAL = 1, SECRET = 2}
  #>>>         SUBJECT{REPLY = 1, FORWARD = 2}

#classification
DF$classification[DF$classification == 'CONFIDENTIAL'] = 1
DF$classification[DF$classification == 'SECRET'] = 2
DF$classification <- as.numeric(DF$classification)

#subject
"check if the email was a reply"
setDT(DF)[subject %like% "RE:", message_type:=1] #reply: 1
setDT(DF)[subject %like% "FW:", message_type:=2] #forward: 2
DF[is.na(message_type),message_type:=0] #normal


### 2. contact list ----
#Create correspondants list
message <- setDT(tstrsplit(as.character(DF$body), "Subject:", fixed=TRUE))[]
message <- message[ ,`:=`(V2 = NULL, V3 = NULL, V4 = NULL)] #remove the body of messages

#nCC
c <- setDT(tstrsplit(as.character(message$V1), "Cc:", fixed=TRUE))[]
c2 <- c[ ,`:=`(V3 = NULL, V4 = NULL)]
c <- setDT(tstrsplit(as.character(c2$V2), "nSent:", fixed=TRUE))[]
c <- c[ ,`:=`(V2 = NULL)]
names(c)[names(c) == "V1"] = "cc" #extract CCs to a column

#nTo
d <- setDT(tstrsplit(as.character(c2$V1), "To:", fixed=TRUE))[]
d2 <- d[ ,`:=`(V3 = NULL, V4 = NULL, V5 = NULL, V6 = NULL)]
d <- setDT(tstrsplit(as.character(d2$V2), "Sent:", fixed=TRUE))[]
d <- d[ ,`:=`(V2 = NULL, V3=NULL)]
names(d)[names(d) == "V1"] = "to" #extract CCs to a column

#nFrom
e <- setDT(tstrsplit(as.character(d2$V1), "Sent:", fixed=TRUE))[]
e <- e[ ,`:=`(V2 = NULL)]
names(e)[names(e) == "V1"] = "from" #extract Senders to a column

#binding appropriate columns together 
people <- cbind(e, d, c)

### 2.3 cleaning up
library(dplyr)
people <- as.data.frame(sapply(people, function(x) gsub('From:', "", x)))
people <- as.data.frame(sapply(people, function(x) gsub('\\\\n', "", x)))
people <- as.data.frame(sapply(people, function(x) gsub("'", "", x)))
#people <- as.data.frame(sapply(people, function(x) gsub('[[:punct:]]', "", x)))
people <- as.data.frame(sapply(people, function(x) gsub("[[:digit:]]+", "", x)))

people <- mutate_each(people, funs(tolower))

people <- as.data.frame(sapply(people, function(x) gsub("confidential.*","", x)))
people <- as.data.frame(sapply(people, function(x) gsub("re:*","", x)))
people <- as.data.frame(sapply(people, function(x) gsub("fw:*","", x)))
people <- as.data.frame(sapply(people, function(x) gsub("fwd:*","", x)))
people <- as.data.frame(sapply(people, function(x) gsub("sent*","", x)))
people <- as.data.frame(sapply(people, function(x) gsub("subject*","", x)))
people <- as.data.frame(sapply(people, function(x) gsub("classified*","", x)))
people <- as.data.frame(sapply(people, function(x) gsub("unclassified*","", x)))
people <- as.data.frame(sapply(people, function(x) gsub("date*","", x)))
people <- as.data.frame(sapply(people, function(x) gsub("months*","", x)))
people <- as.data.frame(sapply(people, function(x) gsub("//*","", x)))

people <- as.data.frame(sapply(people, function(x) gsub("monday*","", x)))
people <- as.data.frame(sapply(people, function(x) gsub("tuesday*","", x)))
people <- as.data.frame(sapply(people, function(x) gsub("wednesday*","", x)))
people <- as.data.frame(sapply(people, function(x) gsub("thursday*","", x)))
people <- as.data.frame(sapply(people, function(x) gsub("friday*","", x)))
people <- as.data.frame(sapply(people, function(x) gsub("saturday*","", x)))
people <- as.data.frame(sapply(people, function(x) gsub("sunday*","", x)))


## split to & cc columns
#function to split rows to columns
split_columns <- function(x,y){
  a <- setDT(tstrsplit(as.character(people$to), ";", fixed=TRUE))[]
  return(a)
}

rec <- split_columns(people,to)
cc <- split_columns(people,cc)

people_splited <- cbind(people$from, rec, cc) #create new dataframe with seperated columns
colnames(people_splited)[1] <- "from"

people_selected <- as.data.frame(people_splited[, 1:6, with = FALSE]) #selecting the first 5 columns

## make edge list 
Matrix2Edge <- function(x){
   data <- x
  final <- data.frame("a"=character(),"b"=character())
  
  #the idea is to iterate over the columns of  the dataframe, melt it, and each time drop the melted column
  for (i in 1:(ncol(data)-1)){
    id = paste("V", i, sep="")
    edge_list <- melt(data, id = (id))
    data[id] <- NULL
    keeps <- c(id, "value")
    edge_list <- edge_list[keeps]
    colnames(edge_list) <- colnames(final)
    final <- rbind(final,edge_list)
  }
  final <- final[!(final$b=="" | final$b==" "),]
  return(final)
}


## try the edge list with only melting on "from" column
el <- melt(people_selected, id = ("from"))
el <- subset(el, select = -c(variable) )
el <- el[rowSums(is.na(el)) == 0,]
el$from <- trimws(el$from)  #remove white space
el$value <- trimws(el$value)
el$from[grep("clinton", el$from)] <- "h"  #change all clinton emails
el$value[grep("clinton", el$value)] <- "h"



write.csv(el, file = "H_el.csv")

---------------
edge_list <- Matrix2Edge(people_selected)

#delete empty/NA fields
#edge_list <- edge_list[nchar(edge_list$b) < 35 ] 
edge_list <- edge_list[rowSums(is.na(edge_list)) == 0,]
colnames(edge_list) <- c('from','to')

write.csv(edge_list, file = "H_edgelist2.csv")


### 3. Entity resolution
edge_list <- read.csv(file.choose(), sep = ",")

dist.name<-adist(edge_list$a,edge_list$b, partial = TRUE, ignore.case = TRUE)






library(RecordLinkage)
rpairs=compare.dedup(edge_list)

simmilarity_index <- function(x, y){
  
  sim_index <- 1- stringdist(x, y, method = "lv")/max(nchar(as.character(x)), nchar(as.character(y)))
  return(sim_index)  
}

library(stringdist)

for (i in 1:nrow(edge_list)){
  for (j in 1:i){
    if (simmilarity_index(edge_list$a[i],edge_list$a[j]) > 0.8){
      edge_list$a[i] <- edge_list$a[j]
    }
  }
}

for (i in 1:nrow(edge_list)){
  for (j in 1:i){
    if (simmilarity_index(edge_list$b[i],edge_list$b[j]) > 0.8){
      edge_list$b[i] <- edge_list$b[j]
    }
  }
}

#### to do:
            # check if there is any forwarded confidential emails
            # optimize section 2 {creating coressapondant list}
            # better entity resolution
            # use all the columns for the edge list -> spark
            # DO THE NETWORK ANALYSIS BASED ON USER'S KEY WORDS

