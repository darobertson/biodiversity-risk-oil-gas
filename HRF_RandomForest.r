
wants <- c("rgeos", "rgdal", "maptools","MASS","glm2","pscl",
           "countrycode","RColorBrewer","ROCR","binomTools","randomForest",
           "caret","ROSE","glmulti","pROC","boot","effects","PresenceAbsence",
           "interpretR","wordcloud","tm","raster")

has   <- wants %in% rownames(installed.packages())
if(any(!has)) install.packages(wants[!has])
has <- wants %in% .packages()
for(p in wants[!has]) library(p,character.only = T)


source("c:/Users/mikeha/Dropbox/Fossil fuels and biodiversity/scripts/myParDepPlot.R")


#Set seed for the random forest algorithm
set.seed(2011)

#Calculate uncertainty associated with gas concession volume
volume.uncertainty<-function(x,y)
{
  y*uncertainty.classes$Uncertainty[which(uncertainty.classes$Source == x)]
}

#Add alpha to a vetor of colours
add.alpha <- function(col, alpha=1){
  if(missing(col))
    stop("Please provide a vector of colours.")
  apply(sapply(col, col2rgb)/255, 2, 
        function(x) 
          rgb(x[1], x[2], x[3], alpha=alpha))  
}


#Calculate a normalised version of a variable.
normalise_ogm <- function(v,b,density,log)
{
  #na.v.i = which(v == -1.0)
  #v = log(v)
  v[is.infinite(v)] = NA
  # v[v < 0] = NA
  brks.v = quantile(v,probs = b,na.rm = T)
  brks.v = unique(brks.v)
  print(brks.v)
  if(log)
  {
    label.brks = exp(brks.v)
  }
  else
  {
    label.brks = (brks.v)
  }
  if(density)
  {
    temp = format(label.brks/cell.area,big.mark=",",trim=T,digits= 2)
    labels = rep("",length(label.brks)-1)
    for(i in 1:length(label.brks)-1)
    {
      labels[i] = paste(temp[i],"\n to \n",temp[i+1])
    }
  }
  else
  {
    temp = format(label.brks,big.mark=",",trim=T, digits = 2)
    labels = rep("",length(label.brks)-1)
    for(i in 1:length(label.brks)-1)
    {
      labels[i] = paste(temp[i],"\n to \n",temp[i+1])
    }
  }
  
  #v.norm = as.integer(cut(v,breaks=brks.v))
  v.norm = as.integer(cut(v,breaks=brks.v))
  
  v.norm[is.na(v.norm)] = 0.0
  #   v.norm = (v.norm/max(v.norm))
  #   v.norm = v.norm * 10
  return(list(v.norm,labels))
}

# Calculate a normalised version of a variable.
normalise_ogm_set_b <- function(v,b, labels)
{
  #na.v.i = which(v == -1.0)
  #v = log(v)
  v[is.infinite(v)] = NA
  # v[v < 0] = NA
  
  v.norm = as.integer(cut(v,breaks=b))
  
  v.norm[is.na(v.norm)] = 0.0
  #   v.norm = (v.norm/max(v.norm))
  #   v.norm = v.norm * 10
  return(list(v.norm,labels))
}


source('C:/Users/mikeha/Dropbox/Fossil fuels and biodiversity/scripts/plot_partial.R')

# Directory within which to find data file
out.dir = 'C:/Users/mikeha/Google Drive/Fossil Fuels and Biodiversity/Figures/'

#Read in the csv file for fields
df.fields<-read.csv(paste("C:/Users/mikeha/Work/Fossil Fuels and Biodiversity/Fields/field_info/",
                          "field_info_exploited_whole_fields_iso3_fieldtype_1000km.csv",sep=""),stringsAsFactors=F)

df.fields$continent<-countrycode(df.fields$ISO3_combi, "iso3c","continent")

#Extract the year in which reserve estimate was made
df.fields$reserve.yrs<-unlist(sapply(df.fields$Oil_Reserve_Date, function (x)
{
  
  s<-strsplit(x,"/")
  if(length(s[[1]] > 0))
  {
    s1<-strsplit(s[[1]][3]," ")
    return(as.numeric(s1[[1]][1]))
  } else
  {
    return(NA)
  }
  
}
))

#Extract the year in which production started
df.fields$prodn.yrs<-unlist(sapply(df.fields$Prod_Start_Date, function (x)
{  
  s<-strsplit(x,"/")
  if(length(s[[1]] > 0))
  {
    s1<-strsplit(s[[1]][3]," ")
    return(as.numeric(s1[[1]][1]))
  } else
  {
    return(NA)
  }
  
}
))

#Extract the year in which production stopped
df.fields$stop.yrs<-unlist(sapply(df.fields$Prod_Stop_Date, function (x)
{  
  s<-strsplit(x,"/")
  if(length(s[[1]] > 0))
  {
    s1<-strsplit(s[[1]][3]," ")
    return(as.numeric(s1[[1]][1]))
  } else
  {
    return(NA)
  }
  
}
))


df.fields$Year_Comb = 0
df.fields$Year_Comb[which(df.fields$Exploited == 1)] = df.fields$prodn.yrs[which(df.fields$Exploited == 1)]
df.fields$Year_Comb[which(df.fields$Exploited == 0)] = df.fields$reserve.yrs[which(df.fields$Exploited == 0)]
df.fields$Year_Comb[which(is.na(df.fields$Year_Comb))] = df.fields$reserve.yrs[which(is.na(df.fields$Year_Comb))]
df.fields$Year_Comb[which(is.na(df.fields$Year_Comb))] = df.fields$prodn[which(is.na(df.fields$Year_Comb))]

exp.oil.inds = which(df.fields$Oil_Recoverable_PP_MMbbl > 0 & df.fields$Exploited == 1)
un.oil.inds = which(df.fields$Oil_Recoverable_PP_MMbbl > 0 & df.fields$Exploited == 0)
exp.gas.inds = which(grepl("mmscfg",df.fields$Reserve_Magnitude) & 
                       df.fields$Oil_Recoverable_PP_MMbbl == 0 &
                       df.fields$Exploited == 1)
un.gas.inds = which(grepl("mmscfg",df.fields$Reserve_Magnitude) & 
                       df.fields$Oil_Recoverable_PP_MMbbl == 0 &
                       df.fields$Exploited == 0)

#For exploited fields set any production years that are NA to the median for
#the oil or gas set they belong to
if(length(which(is.na(df.fields$Year_Comb[exp.oil.inds]))) > 0)
  df.fields$Year_Comb[exp.oil.inds[which(is.na(df.fields$Year_Comb[exp.oil.inds]))]] =
  median(df.fields$Year_Comb[exp.oil.inds],na.rm=T)
if(length(which(is.na(df.fields$Year_Comb[un.oil.inds]))) > 0)
  df.fields$Year_Comb[un.oil.inds[which(is.na(df.fields$Year_Comb[un.oil.inds]))]] =
  median(df.fields$Year_Comb[un.oil.inds],na.rm=T)
if(length(which(is.na(df.fields$Year_Comb[exp.gas.inds]))) > 0)
  df.fields$Year_Comb[exp.gas.inds[which(is.na(df.fields$Year_Comb[exp.gas.inds]))]] =
  median(df.fields$Year_Comb[exp.gas.inds],na.rm=T)
if(length(which(is.na(df.fields$Year_Comb[un.gas.inds]))) > 0)
  df.fields$Year_Comb[un.gas.inds[which(is.na(df.fields$Year_Comb[un.gas.inds]))]] =
  median(df.fields$Year_Comb[un.gas.inds],na.rm=T)


# cut the dataset to those that are in the period for which we have socio-economic data
#First remove exploited fields with production start date prior to 1996
remove.inds<-which(df.fields$Year_Comb < 1996)
if(length(remove.inds) > 0) df.fields<-df.fields[-remove.inds,]

#Also remove those exploited fields with reserve estimate date prior to 1996
remove.inds<-which(is.na(df.fields$prodn.yrs) & df.fields$Exploited ==1 & df.fields$reserve.yrs < 1996)
if(length(remove.inds) > 0) df.fields<-df.fields[-remove.inds,]

#Remove PA overlap for fields for which PA designation year is equal to or greater than the production year
PA.amend.inds = which((df.fields$prodn.yrs <= df.fields$PA_Yr) & df.fields$PA_Yr < 3000)
df.fields[PA.amend.inds,c("PA_ov_comb","PA_Cat","PA_Yr")] = 0

# Add Socio-economic data to the dataset: GDP, GNI, Government effectiveness, distance from roads?

rol = read.csv("C:/Users/mikeha/Dropbox/Fossil fuels and biodiversity/WGI_Rule_Of_Law.csv",stringsAsFactors = F,
               na.strings = "#N/A")
coc = read.csv("C:/Users/mikeha/Dropbox/Fossil fuels and biodiversity/WGI_Control_of_Corruption.csv",stringsAsFactors = F,
               na.strings = "#N/A")
rq = read.csv("C:/Users/mikeha/Dropbox/Fossil fuels and biodiversity/WGI_Regulatory_Quality.csv",stringsAsFactors = F,
              na.strings = "#N/A")
ge = read.csv("C:/Users/mikeha/Dropbox/Fossil fuels and biodiversity/WGI_Government_Effectiveness.csv",stringsAsFactors = F,
              na.strings = "#N/A")


# These government effectiveness indicators are highly significantly correlated, therefore pick the most relevant
# rol = Reflects perceptions of the extent to which agents have confidence in 
#       and abide by the rules of society, and in particular the quality of contract enforcement, 
#       property rights, the police, and the courts, as well as the likelihood of crime and violence.
#
# rq = Reflects perceptions of the ability of the government to formulate and implement sound policies 
#      and regulations that permit and promote private sector development.
#
# ge = Reflects perceptions of the quality of public services, the quality of the civil service 
#      and the degree of its independence from political pressures, the quality of policy formulation 
#      and implementation, and the credibility of the government's commitment to such policies.
# 
# coc = Reflects perceptions of the extent to which public power is exercised for
#       private gain, including both petty and grand forms of corruption, as well as
#       "capture" of the state by elites and private interests.

#GDP
gdp.pcap = read.csv("C:/Users/mikeha/Work/Fossil Fuels and Biodiversity/socio-economic/ny.gdp.pcap.cd_Indicator_en_csv_v2/ny.gdp.pcap.cd_Indicator_en_csv_v2.csv",
                    stringsAsFactors = F,
                    na.strings = "")

gdp = read.csv("C:/Users/mikeha/Work/Fossil Fuels and Biodiversity/socio-economic/ny.gdp.mktp.cd_Indicator_en_csv_v2/ny.gdp.mktp.cd_Indicator_en_csv_v2.csv",
               stringsAsFactors = F,
               na.strings = "")

gni = read.csv("C:/Users/mikeha/Work/Fossil Fuels and Biodiversity/socio-economic/ny.gnp.pcap.cd_Indicator_en_csv_v2/ny.gnp.pcap.cd_Indicator_en_csv_v2.csv",
               stringsAsFactors = F,
               na.strings = "")

gini = read.csv("C:/Users/mikeha/Work/Fossil Fuels and Biodiversity/socio-economic/si.pov.gini_Indicator_en_csv_v2/si.pov.gini_Indicator_en_csv_v2.csv",
               stringsAsFactors = F,
               na.strings = "")


source("C:/Users/mikeha/Dropbox/Fossil fuels and biodiversity/scripts/Fossil_Fuel_Functions.R")

#Take the value of the year nearest to prodn start year (exploited) or reserve year (unexploited)
df.fields$rol = unlist(mapply(GetSocioEconomicDataForCountryYear,
                              c=df.fields$ISO3_combi,
                              prodn.yr=df.fields$Year_Comb,
                              reserve.yr=df.fields$Year_Comb,
                              exploited=df.fields$Exploited,
                              data.source="rol",
                              country.colname="WBCode"))


df.fields$coc = unlist(mapply(GetSocioEconomicDataForCountryYear,
                              c=df.fields$ISO3_combi,
                              prodn.yr=df.fields$Year_Comb,
                              reserve.yr=df.fields$Year_Comb,
                              exploited=df.fields$Exploited,
                              data.source="coc",
                              country.colname="WBCode"))

df.fields$rq = unlist(mapply(GetSocioEconomicDataForCountryYear,
                             c=df.fields$ISO3_combi,
                             prodn.yr=df.fields$Year_Comb,
                             reserve.yr=df.fields$Year_Comb,
                             exploited=df.fields$Exploited,
                             data.source="rq",
                             country.colname="WBCode"))


df.fields$ge = unlist(mapply(GetSocioEconomicDataForCountryYear,
                             c=df.fields$ISO3_combi,
                             prodn.yr=df.fields$Year_Comb,
                             reserve.yr=df.fields$Year_Comb,
                             exploited=df.fields$Exploited,
                             data.source="ge",
                             country.colname="WBCode"))

df.fields$gdp.pcap = unlist(mapply(GetSocioEconomicDataForCountryYear,
                                   c=df.fields$ISO3_combi,
                                   prodn.yr=df.fields$Year_Comb,
                                   reserve.yr=df.fields$Year_Comb,
                                   exploited=df.fields$Exploited,
                                   data.source="gdp.pcap",
                                   country.colname="Country.Code"))


df.fields$gdp = unlist(mapply(GetSocioEconomicDataForCountryYear,
                              c=df.fields$ISO3_combi,
                              prodn.yr=df.fields$Year_Comb,
                              reserve.yr=df.fields$Year_Comb,
                              exploited=df.fields$Exploited,
                              data.source="gdp",
                              country.colname="Country.Code"))

df.fields$gni = unlist(mapply(GetSocioEconomicDataForCountryYear,
                              c=df.fields$ISO3_combi,
                              prodn.yr=df.fields$Year_Comb,
                              reserve.yr=df.fields$Year_Comb,
                              exploited=df.fields$Exploited,
                              data.source="gni",
                              country.colname="Country.Code"))


df.fields$gini = unlist(mapply(GetSocioEconomicDataForCountryYear,
                              c=df.fields$ISO3_combi,
                              prodn.yr=df.fields$Year_Comb,
                              reserve.yr=df.fields$Year_Comb,
                              exploited=df.fields$Exploited,
                              data.source="gini",
                              country.colname="Country.Code"))




#Need to combine the Field type data
df.fields$Field_type_combined = ""
#Exploited fields
exp.inds<-which(df.fields$FIELD_TYPE != "")
if(length(exp.inds) > 0) df.fields$Field_type_combined[exp.inds] <- df.fields$FIELD_TYPE[exp.inds]
#Unexploited fields
unexp.inds<-which(df.fields$FIELD_TYPE_1 != "")
if(length(unexp.inds) > 0) df.fields$Field_type_combined[unexp.inds] <- df.fields$FIELD_TYPE_1[unexp.inds]


#Convert pipeline distance from m to km
df.fields$Pipe_Dist = df.fields$Pipe_Dist/1000

#Remove proposed PA categories and group international MAB with other non-IUCN sites
df.fields$PA_Cat[which(df.fields$PA_Cat == 8)] = 0
df.fields$PA_Cat[which(df.fields$PA_Cat %in% c(90,91,92,93))] = 7

# Create a data frame with just the predictor and response variables in
#predictors <- c('rol', 'coc', 'rq', 'ge', 'gdp.pcap', 'gdp', 'gni','gini', 'Oil_Recoverable_PP_MMbbl', 'Pipe_Dist', 'PA_ov_comb', 'PA_Cat','Field_type_combined')
#Excluding GINI because it's spatial coverage is patchy
predictors <- c('ge', 'gdp.pcap', 'gdp', 'Oil_Recoverable_PP_MMbbl', 'Pipe_Dist', 'PA_ov_comb', 'PA_Cat','Field_type_combined','ISO3_combi')
data_to_model = subset(df.fields,
                       Oil_Recoverable_PP_MMbbl > 0,
                            select = c(predictors,"Exploited","Field_Id"))

# Create a data frame with just the predictor and response variables in
#predictors_gas <- c('rol', 'coc', 'rq', 'ge', 'gdp.pcap', 'gdp', 'gni','gini', 'Reserve_Magnitude', 'Pipe_Dist', 'PA_ov_comb', 'PA_Cat','Field_type_combined')
predictors_gas <- c('ge', 'gdp.pcap', 'gdp', 'Reserve_Magnitude', 'Pipe_Dist', 'PA_ov_comb', 'PA_Cat','Field_type_combined','ISO3_combi')
data_to_model_gas = subset(df.fields,
                           grepl("mmscfg",Reserve_Magnitude) & 
                           Oil_Recoverable_PP_MMbbl == 0,
                           select = c(predictors_gas,"Exploited","Field_Id"))



# Model the exploitation of oil fields ------------------------------------

# Remove rows with no data in at least one variable. Note that this might be fine-tuned after it is decided which of the correlated variables to keep.
marker = vector(length = 0)
for (ii in 1:dim(data_to_model)[1])
{
  if ("TRUE" %in% (is.na(data_to_model[ii,])))
  {
    marker = c(marker, ii)
  }
  else
  {
    if (data_to_model$Pipe_Dist[ii] == -1)
    {
      marker = c(marker, ii)
    }
    else if (data_to_model$Exploited[ii] == -1)
    {
        marker = c(marker, ii)
    }
    
  }
}


data_to_model = data_to_model[setdiff(1:dim(data_to_model)[1], marker),]

oil.countries = table(data_to_model$ISO3_combi)
oil.countries = oil.countries[order(-oil.countries)]
exp.oil.countries = table(data_to_model$ISO3_combi[which(data_to_model$Exploited == 1)])
exp.oil.countries = exp.oil.countries[order(-exp.oil.countries)]
un.oil.countries = table(data_to_model$ISO3_combi[which(data_to_model$Exploited == 0)])
un.oil.countries = un.oil.countries[order(-un.oil.countries)]

#Match the countries for plotting
a = exp.oil.countries
b = un.oil.countries
matched.oil.countries = cbind(a,
                              b[match(rownames(a),rownames(b))])


# Print the correlation matrix
cor(cbind(data_to_model[,predictors[-((length(predictors)-1):length(predictors))]],
          as.numeric(as.factor(data_to_model$Field_type_combined))), use = "complete.obs")

# High correlation between governance indicators and between oil available indicators and between gni and gdp.pcap
# Do not use variables correlated > 0.9

# Set PA variables to be factors
data_to_model$PA_ov_comb = as.factor(data_to_model$PA_ov_comb)
data_to_model$PA_Cat = as.factor(data_to_model$PA_Cat)
data_to_model$Field_type_combined = as.factor(data_to_model$Field_type_combined)

training.data.oil<-data_to_model

predictors_to_use = c('ge' , 'gdp' , 'Oil_Recoverable_PP_MMbbl' , 'Pipe_Dist' , 'PA_Cat' , 'PA_ov_comb' , 'Field_type_combined') 
# Search for the optimal value of mtry
bb = tuneRF(training.data.oil[,predictors_to_use],as.factor(training.data.oil$Exploited))

# Run model with optimal value of mtry
rf1.oil = randomForest(as.factor(Exploited) ~ ge + gdp + Oil_Recoverable_PP_MMbbl + Pipe_Dist + PA_Cat + PA_ov_comb + Field_type_combined,
                       data=training.data.oil, mtry = bb[which.min(bb[,2]),1], importance=TRUE)
rf1.oil
# Plot relative variable importance
varImpPlot(rf1.oil)
importance(rf1.oil)

outpred.oil<-predict(rf1.oil, type = "prob")
roc.curve(training.data.oil$Exploited, outpred.oil[,2], col = "red",lty="dashed") 


# Partial plots for oil full model --------------------------------------------


png(paste(out.dir,"oil_Full_partial_plots_uncertainty_post1996.png",sep=""),
    width = 17/2.54,
    height = 17/2.54,
    units = 'in',
    res = 300)

ylims=c(0,1)
yaxis.labs = seq(0,1,0.2)
i = 1


layout(matrix(1:12,nrow=3,ncol=4),widths = c(2,5,5,5))
par(mar=rep(0,4))
plot(1, type="n", axes=F, xlab="", ylab="", ylim = ylims)

plot(1, type="n", axes=F, xlab="", ylab="", ylim = ylims)
mtext("Probability of exploitation", side = 2, line = -3, cex = 1.5)
plot(1, type="n", axes=F, xlab="", ylab="", ylim = ylims)
par(mar=c(4,0.5,0.5,0.5))
pdp.ge <- myParDepPlot("ge",rf1.oil, training.data.oil,robust=T,ci=T, logit=F,u.quant = 0.75, l.quant = 0.25,
                     main="",xlab="government effectiveness",ylab="",mgp=c(2.5,1,0))
dec.ge.exp = quantile(training.data.oil$ge[which(training.data.oil$Exploited == 1)],seq(0,1,0.05),na.rm=T)
dec.ge.un = quantile(training.data.oil$ge[which(training.data.oil$Exploited == 0)],seq(0,1,0.05),na.rm=T)
segments(dec.ge.exp,0,dec.ge.exp,0.03,col = rgb(1,0,0,0.8),lwd=2)
segments(dec.ge.un,0.03,dec.ge.un,0.06,col = rgb(0,0,1,0.8),lwd=2)
mtext(side = 3,text = LETTERS[i],font=2, adj = 0.01, padj=1.5)
i = i + 1

pdp.gdp <- myParDepPlot("gdp",rf1.oil, training.data.oil,robust=T,ci=T, logit=F,u.quant = 0.75, l.quant = 0.25,
                      main="",xlab="GDP",ylab="",mgp=c(2.5,1,0))
dec.gdp.exp = quantile(training.data.oil$gdp[which(training.data.oil$Exploited == 1)],seq(0,1,0.05),na.rm=T)
dec.gdp.un = quantile(training.data.oil$gdp[which(training.data.oil$Exploited == 0)],seq(0,1,0.05),na.rm=T)
segments(dec.gdp.exp,0,dec.gdp.exp,0.03,col = rgb(1,0,0,0.8),lwd=2)
segments(dec.gdp.un,0.03,dec.gdp.un,0.06,col = rgb(0,0,1,0.8),lwd=2)
mtext(side = 3,text = LETTERS[i],font=2, adj = 0.01, padj=1.5)
i = i + 1

pdp.oil <- myParDepPlot("Oil_Recoverable_PP_MMbbl",rf1.oil, training.data.oil,robust=T,ci=T, logit=F,u.quant = 0.75, l.quant = 0.25,
                      main="",xlab="Oil recoverable (MMbbl)",ylab="",mgp=c(2.5,1,0))
dec.oil.exp = quantile(training.data.oil$Oil_Recoverable_PP_MMbbl[which(training.data.oil$Exploited == 1)],seq(0,1,0.05),na.rm=T)
dec.oil.un = quantile(training.data.oil$Oil_Recoverable_PP_MMbbl[which(training.data.oil$Exploited == 0)],seq(0,1,0.05),na.rm=T)
segments(dec.oil.exp,0,dec.oil.exp,0.03,col = rgb(1,0,0,0.8),lwd=2)
segments(dec.oil.un,0.03,dec.oil.un,0.06,col = rgb(0,0,1,0.8),lwd=2)
mtext(side = 3,text = LETTERS[i],font=2, adj = 0.01, padj=1.5)
i = i + 1

pdp.dist <- myParDepPlot("Pipe_Dist",rf1.oil, training.data.oil,robust=T,ci=T, logit=F,u.quant = 0.75, l.quant = 0.25,
                       main="",xlab="Distance to nearest pipeline (km)",ylab="",yaxt="n",mgp=c(2.5,1,0))
dec.dist.exp = quantile(training.data.oil$Pipe_Dist[which(training.data.oil$Exploited == 1)],seq(0,1,0.05),na.rm=T)
dec.dist.un = quantile(training.data.oil$Pipe_Dist[which(training.data.oil$Exploited == 0)],seq(0,1,0.05),na.rm=T)
segments(dec.dist.exp,0,dec.dist.exp,0.03,col = rgb(1,0,0,0.8),lwd=2)
segments(dec.dist.un,0.03,dec.dist.un,0.06,col = rgb(0,0,1,0.8),lwd=2)
mtext(side = 3,text = LETTERS[i],font=2, adj = 0.01, padj=1.5)
i = i + 1

pdp.pa.cat <- myParDepPlot("PA_Cat",rf1.oil, training.data.oil,robust=T,ci=T, logit=F,u.quant = 0.75, l.quant = 0.25,
                         main="",xlab="Protected area category",ylab="",yaxt="n",mgp=c(2.5,1,0),xaxt="n")
axis(side=1,at=pdp.pa.cat$bp,labels=0:(length(pdp.pa.cat$x)-1),cex.axis=0.9)
mtext(side = 3,text = LETTERS[i],font=2, adj = 0.01, padj=1.5)
i = i + 1

pdp.pa.ov <-myParDepPlot("PA_ov_comb",rf1.oil, training.data.oil,robust=T,ci=T, logit=F,u.quant = 0.75, l.quant = 0.25,
                        main="",xlab="Protected area overlap",ylab="",yaxt="n",mgp=c(2.5,1,0),xaxt="n")
axis(side=1,at=pdp.pa.ov$bp,labels=letters[1:length(pdp.pa.ov$x)])
mtext(side = 3,text = LETTERS[i],font=2, adj = 0.01, padj=1.5)
i = i + 1

pdp.field <- myParDepPlot("Field_type_combined",rf1.oil, training.data.oil,robust=T,ci=T, logit=F,u.quant = 0.75, l.quant = 0.25,
                        main="",xlab="Oil field type",ylab="",yaxt="n",mgp=c(2.5,1,0),xaxt="n")
axis(side=1,at=pdp.field$bp,labels=LETTERS[1:length(pdp.field$x)],cex.axis=0.9)
mtext(side = 3,text = LETTERS[i],font=2, adj = 0.01, padj=1.5)
i = i + 1

dev.off()




# Model exploitation of gas fields ----------------------------------------

# Remove rows with no data in at least one variable. Note that this might be fine-tuned after it is decided which of the correlated variables to keep.
marker = vector(length = 0)
for (ii in 1:dim(data_to_model_gas)[1])
{
  if ("TRUE" %in% (is.na(data_to_model_gas[ii,])))
  {
    marker = c(marker, ii)
  }
  else
  {
    if (data_to_model_gas$Pipe_Dist[ii] == -1)
    {
      marker = c(marker, ii)
    }
    else
    {
      if (data_to_model_gas$Exploited[ii] == -1)
      {
        marker = c(marker, ii)
      }
    }
  }
}


data_to_model_gas = data_to_model_gas[setdiff(1:dim(data_to_model_gas)[1], marker),]


# Print the correlation matrix
cor(cbind(data_to_model_gas[,c('ge', 'gdp.pcap', 'gdp', 'Pipe_Dist', 'PA_ov_comb', 'PA_Cat')],
          as.numeric(as.factor(data_to_model_gas$Field_type_combined)),
    as.numeric(as.factor(data_to_model_gas$Reserve_Magnitude))), use = "complete.obs")

# High correlation between governance indicators and between oil available indicators and between gni and gdp.pcap
# Do not use variables correlated > 0.9

# Set PA variables to be factors
data_to_model_gas$PA_ov_comb = as.factor(data_to_model_gas$PA_ov_comb)
data_to_model_gas$PA_Cat = as.factor(data_to_model_gas$PA_Cat)
data_to_model_gas$Field_type_combined = as.factor(data_to_model_gas$Field_type_combined)
data_to_model_gas$Reserve_Magnitude = as.factor(data_to_model_gas$Reserve_Magnitude)
data_to_model_gas$Reserve_Magnitude = factor(data_to_model_gas$Reserve_Magnitude,
                                                 levels = c("< 100,000 mmscfg",
                                                            "100,000-1mil mmscfg",
                                                            "1-10 million mmscfg",
                                                            "> 10 million mmscfg"))

training.data.gas=data_to_model_gas

gas.countries = table(training.data.gas$ISO3_combi)
gas.countries = gas.countries[order(-gas.countries)]

exp.gas.countries = table(training.data.gas$ISO3_combi[which(training.data.gas$Exploited == 1)])
exp.gas.countries = exp.gas.countries[order(-exp.gas.countries)]
un.gas.countries = table(training.data.gas$ISO3_combi[which(training.data.gas$Exploited == 0)])
un.gas.countries= un.gas.countries[order(-un.gas.countries)]

a = exp.gas.countries
b = un.gas.countries
matched.gas.countries = cbind(a,
                              b[match(rownames(a),rownames(b))])


predictors_to_use = c('ge', 'gdp'  , 'Reserve_Magnitude' , 'Pipe_Dist' , 'PA_Cat' , 'PA_ov_comb' , 'Field_type_combined') 
# Search for the optimal value of mtry
bb = tuneRF(training.data.gas[,predictors_to_use],as.factor(training.data.gas$Exploited))

# Run model with optimal value of mtry
rf1.gas = randomForest(as.factor(Exploited) ~ ge + gdp + Reserve_Magnitude + Pipe_Dist + PA_Cat + PA_ov_comb + Field_type_combined,
                       data=training.data.gas, mtry = bb[which.min(bb[,2]),1], importance=TRUE)
rf1.gas


# Plot relative variable importance
varImpPlot(rf1.gas)
importance(rf1.gas)

outpred.gas<-predict(rf1.gas, type = "prob")
roc.curve(training.data.gas$Exploited, outpred.gas[,2], col = "red",lty="dashed") 


# Plot partial plots for full gas model ----------------------------------------


png(paste(out.dir,"gas_Full_partial_plots_uncertainty_post1996.png",sep=""),
    width = 17/2.54,
    height = 17/2.54,
    units = 'in',
    res = 300)

ylims=c(0,1)
yaxis.labs = seq(0,1,0.2)
i = 1

layout(matrix(1:12,nrow=3,ncol=4),widths = c(2,5,5,5))
par(mar=rep(0,4))
plot(1, type="n", axes=F, xlab="", ylab="", ylim = ylims)

plot(1, type="n", axes=F, xlab="", ylab="", ylim = ylims)
mtext("Probability of exploitation", side = 2, line = -3, cex = 1.5)
plot(1, type="n", axes=F, xlab="", ylab="", ylim = ylims)
par(mar=c(4,0.5,0.5,0.5))
pdp.ge <- myParDepPlot("ge",rf1.gas, training.data.gas,robust=T,ci=T, logit=F,u.quant = 0.75, l.quant = 0.25,
                       main="",xlab="government effectiveness",ylab="",mgp=c(2.5,1,0))
dec.ge.exp = quantile(training.data.gas$ge[which(training.data.gas$Exploited == 1)],seq(0,1,0.05),na.rm=T)
dec.ge.un = quantile(training.data.gas$ge[which(training.data.gas$Exploited == 0)],seq(0,1,0.05),na.rm=T)
segments(dec.ge.exp,0,dec.ge.exp,0.03,col = rgb(1,0,0,0.8),lwd=2)
segments(dec.ge.un,0.03,dec.ge.un,0.06,col = rgb(0,0,1,0.8),lwd=2)
mtext(side = 3,text = LETTERS[i],font=2, adj = 0.01, padj=1.5)
i = i + 1

pdp.gdp <- myParDepPlot("gdp",rf1.gas, training.data.gas,robust=T,ci=T, logit=F,u.quant = 0.75, l.quant = 0.25,
                        main="",xlab="GDP",ylab="",mgp=c(2.5,1,0))
dec.gdp.exp = quantile(training.data.gas$gdp[which(training.data.gas$Exploited == 1)],seq(0,1,0.05),na.rm=T)
dec.gdp.un = quantile(training.data.gas$gdp[which(training.data.gas$Exploited == 0)],seq(0,1,0.05),na.rm=T)
segments(dec.gdp.exp,0,dec.gdp.exp,0.03,col = rgb(1,0,0,0.8),lwd=2)
segments(dec.gdp.un,0.03,dec.gdp.un,0.06,col = rgb(0,0,1,0.8),lwd=2)
mtext(side = 3,text = LETTERS[i],font=2, adj = 0.01, padj=1.5)
i = i + 1

pdp.gas <- myParDepPlot("Reserve_Magnitude",rf1.gas, training.data.gas,robust=T,ci=T, logit=F,u.quant = 0.75, l.quant = 0.25,
                      main="",xlab=expression(paste("Reserve (10"^{-12}," cubic feet)",sep="")),ylab="",mgp=c(2.5,1,0),xaxt="n")
axis(side=1,at=pdp.gas$bp,labels=c("< 0.1","0.1-1","1-10","> 10"),cex.axis=0.9)
mtext(side = 3,text = LETTERS[i],font=2, adj = 0.01, padj=1.5)
i = i + 1

pdp.dist <- myParDepPlot("Pipe_Dist",rf1.gas, training.data.gas,robust=T,ci=T, logit=F,u.quant = 0.75, l.quant = 0.25,
                         main="",xlab="Distance to nearest pipeline (km)",ylab="",yaxt="n",mgp=c(2.5,1,0))
dec.dist.exp = quantile(training.data.gas$Pipe_Dist[which(training.data.gas$Exploited == 1)],seq(0,1,0.05),na.rm=T)
dec.dist.un = quantile(training.data.gas$Pipe_Dist[which(training.data.gas$Exploited == 0)],seq(0,1,0.05),na.rm=T)
segments(dec.dist.exp,0,dec.dist.exp,0.03,col = rgb(1,0,0,0.8),lwd=2)
segments(dec.dist.un,0.03,dec.dist.un,0.06,col = rgb(0,0,1,0.8),lwd=2)
mtext(side = 3,text = LETTERS[i],font=2, adj = 0.01, padj=1.5)
i = i + 1

pdp.pa.cat <- myParDepPlot("PA_Cat",rf1.gas, training.data.gas,robust=T,ci=T, logit=F,u.quant = 0.75, l.quant = 0.25,
                           main="",xlab="Protected area category",ylab="",yaxt="n",mgp=c(2.5,1,0),xaxt="n")
axis(side=1,at=pdp.pa.cat$bp,labels=0:(length(pdp.pa.cat$x)-1),cex.axis=0.9)
mtext(side = 3,text = LETTERS[i],font=2, adj = 0.01, padj=1.5)
i = i + 1

pdp.pa.ov <-myParDepPlot("PA_ov_comb",rf1.gas, training.data.gas,robust=T,ci=T, logit=F,u.quant = 0.75, l.quant = 0.25,
                         main="",xlab="Protected area overlap",ylab="",yaxt="n",mgp=c(2.5,1,0),xaxt="n")
axis(side=1,at=pdp.pa.ov$bp,labels=letters[1:length(pdp.pa.ov$x)])
mtext(side = 3,text = LETTERS[i],font=2, adj = 0.01, padj=1.5)
i = i + 1

pdp.field <- myParDepPlot("Field_type_combined",rf1.gas, training.data.gas,robust=T,ci=T, logit=F,u.quant = 0.75, l.quant = 0.25,
                          main="",xlab="Gas field type",ylab="",yaxt="n",mgp=c(2.5,1,0),xaxt="n")
axis(side=1,at=pdp.field$bp,labels=LETTERS[1:length(pdp.field$x)], cex.axis = 0.8)
mtext(side = 3,text = LETTERS[i],font=2, adj = 0.01, padj=1.5)
i = i + 1
dev.off()



# Read data on KBA overlap of unexploited fields --------------------------
kba.file = "c:/Users/mikeha/Work/Fossil Fuels and Biodiversity/KBA analysis/Fields_all_future_moll_bd_KBA_CN.csv"
kba = read.csv(kba.file)

# Read in the shapefile containing features for unexploited fields  ------------
#Specify the input directory
indsn="C:/Users/mikeha/Work/Fossil Fuels and biodiversity/Fields/"

shp.name = "Fields_all_future_moll_bd_no_dup"

shp.unexploited = readShapeSpatial(paste(indsn,shp.name,sep=""),
                                   repair=T,delete_null_obj=T, force_ring = F)

proj4string(shp.unexploited) = "+proj=moll +datum=WGS84"

shp.data = shp.unexploited@data



shp.data$PA_v_cm = factor(shp.data$PA_v_cm)
shp.data$FIELD_I = (as.character(shp.data$FIELD_I))

#Add new columns for:
# Predicted exploitation: -1 indicates could not be calculated
#shp.data$pred.exploitation = -1
shp.data$prob.exploited = -1
shp.data$prob.unexploited = -1



#Construct the array of values to go into the risk matrix for anomalies
outpred.oil<-predict(rf1.oil, type = "prob")
outpred.gas<-predict(rf1.gas, type = "prob")


#Check the threshold probability ----------
auc.roc.plot(DATA = data.frame(seq(1:length(training.data.oil$Exploited)),
                               training.data.oil$Exploited,
                               outpred.oil[,2]),
            threshold = 10,
            find.auc = T,
            opt.thresholds = T,
            opt.methods = 5,
            xlab="1-Specificity (false positives)",
            ylab="Sensitivity (true positives)",
            main = "ROC plot",
            color = TRUE)

auc.roc.plot(DATA = data.frame(seq(1:length(training.data.gas$Exploited)),
                               training.data.gas$Exploited,
                               outpred.gas[,2]),
             threshold = 10,
             find.auc = T,
             opt.thresholds = T,
             opt.methods = 5,
             xlab="1-Specificity (false positives)",
             ylab="Sensitivity (true positives)",
             main = "ROC plot",
             color = TRUE)


roc.curve(training.data.oil$Exploited, outpred.oil[,2], col = "black",lwd=2,main="",las=1) 
roc.curve(training.data.gas$Exploited, outpred.gas[,2], add = T, col = "blue",lwd=2,las=1,main="") 

#Search for fields that are in the training data for oil or gas fields
# add the modelled probabilities of exploitation value
# First seach for those for which oil estimates are available
oil.estimated.inds = which(shp.data$FIELD_I %in% training.data.oil$Field_Id)
for(ii in oil.estimated.inds)
{
  training.data.ind = which(training.data.oil$Field_Id == shp.data$FIELD_I[ii])
  if(length(training.data.ind) == 1)
  {
    shp.data[ii,c("prob.unexploited","prob.exploited")] = outpred.oil[training.data.ind,]
  }
  else if(length(training.data.ind) > 1)
  {
    print(paste("training.data.ind > 1 ",training.data.ind))
  }
  
}

gas.estimated.inds = which(shp.data$FIELD_I %in% training.data.gas$Field_Id)
for(ii in gas.estimated.inds)
{
  training.data.ind = which(training.data.gas$Field_Id == shp.data$FIELD_I[ii])
  if(length(training.data.ind) == 1)
  {
    shp.data[ii,c("prob.unexploited","prob.exploited")] = outpred.gas[training.data.ind,]
  }
  else if(length(training.data.ind) > 1)
  {
    print(paste("training.data.ind > 1 ",training.data.ind))
  }
}


shp.data$field.info.ind = 
  unlist(sapply(shp.data$FIELD_ID,
                        function(x) 
                          {
                          i = which(df.fields$Field_Id == x)
                          ifelse(length(i) > 0,
                                 i,
                                 0)}))



fi.i = which(shp.data$field.info.ind > 0)

shp.data$PA_ov_comb = 0
shp.data$PA_Cat = 0
shp.data$PA_ov_comb[fi.i] = df.fields$PA_ov_comb[shp.data$field.info.ind[fi.i]]
shp.data$PA_Cat[fi.i] = df.fields$PA_Cat[shp.data$field.info.ind[fi.i]]


#All with prob of exploitation > 0.44 from the ROC curves
all.at.risk.inds = which(shp.data$prob.exploited > 0.44) 

fut.in.exp = readShapeSpatial("C:/Users/mikeha/Work/Fossil fuels and biodiversity/Fields/Fields_all_future_moll_within_exploited",
                              repair=T,delete_null_obj=T, force_ring = F)
proj4string(fut.in.exp) = "+proj=moll +datum=WGS84"

at.risk.in.exp = which(shp.data$FIELD_ID[all.at.risk.inds] %in% fut.in.exp$FIELD_ID)



if(length(at.risk.in.exp) > 0){
  all.at.risk.inds = all.at.risk.inds[-at.risk.in.exp]
  #field.threatened.binomials = field.threatened.binomials[-at.risk.in.exp]
}




#add a rank index to each at risk field
shp.data$rank.prob.exploited = -9999
#add a distace from unexploitation
shp.data$dist.prob.exploited = -9999

shp.data$InvArea[which(shp.data$InvArea < 0)] =
  shp.data$SumInvArea[which(shp.data$InvArea < 0)]/
  shp.data$CntInvArea[which(shp.data$InvArea < 0)]

#Calculate the geometric mean biodiversity metric
shp.data$GM.bd = exp((log(shp.data$InvArea*1E9)+log(shp.data$SpCount))/2)
shp.data$rank.prob.exploited[all.at.risk.inds[order(-shp.data$prob.exploited[all.at.risk.inds])]] = seq(1:length(all.at.risk.inds))
shp.data$dist.prob.exploited[all.at.risk.inds] = (shp.data$prob.exploited[all.at.risk.inds])

#Calculate median values of geomstric mean biodiversity and exploitation risk for 'at risk' unexploited fields
med.at.risk.gm.bd = median(shp.data$GM.bd[all.at.risk.inds])
med.at.risk.dist = median(shp.data$dist.prob.exploited[all.at.risk.inds])

# Assign a realm to each field 

realm = raster("c:/Users/mikeha/Work/Fossil Fuels and Biodiversity/raster_realm")

un.pts = gCentroid(shp.unexploited,byid=T)

shp.data$Realm = extract(realm,un.pts)

#Loop over each field id in the shp.data

med.at.risk.gm.bd.terr = median(shp.data$GM.bd[all.at.risk.inds[which(shp.data$Realm[all.at.risk.inds] == 1.0)]])
med.at.risk.gm.bd.mar = median(shp.data$GM.bd[all.at.risk.inds[which(shp.data$Realm[all.at.risk.inds] == 2.0)]])

med.at.risk.dist.terr = median(shp.data$dist.prob.exploited[all.at.risk.inds[which(shp.data$Realm[all.at.risk.inds] == 1.0)]])
med.at.risk.dist.mar = median(shp.data$dist.prob.exploited[all.at.risk.inds[which(shp.data$Realm[all.at.risk.inds] == 2.0)]])

# Now plot out the data ---------------------------------------------------


# Find the fields that are high potential risk
# Find any at risk fields that are contained within KBAs
kba.inds = which(kba$KBA > 0)
kba.at.risk.inds = kba.inds[which(kba.inds %in% all.at.risk.inds)]
upper.quadrant.inds = all.at.risk.inds[which((shp.data$GM.bd[all.at.risk.inds] > med.at.risk.gm.bd) &
                                               (shp.data$dist.prob.exploited[all.at.risk.inds] > med.at.risk.dist))]

upp.quadrant.inds.terr = all.at.risk.inds[which((shp.data$GM.bd[all.at.risk.inds] > med.at.risk.gm.bd.terr) &
                                                  (shp.data$dist.prob.exploited[all.at.risk.inds] > med.at.risk.dist.terr) &
                                                  (shp.data$Realm[all.at.risk.inds] == 1.0))]

upp.quadrant.inds.mar = all.at.risk.inds[which((shp.data$GM.bd[all.at.risk.inds] > med.at.risk.gm.bd.mar) &
                                                  (shp.data$dist.prob.exploited[all.at.risk.inds] > med.at.risk.dist.mar) &
                                                  (shp.data$Realm[all.at.risk.inds] == 2.0))]

upper.quadrant.inds = union(upp.quadrant.inds.mar,upp.quadrant.inds.terr)

kba.uq.additions = setdiff(kba.at.risk.inds,upper.quadrant.inds)
upper.quadrant.inds = union(upper.quadrant.inds,kba.at.risk.inds)

cols.vec = rep(1,length(all.at.risk.inds))
i = which(shp.data$FIELD_I[all.at.risk.inds] %in% training.data.gas$Field_Id)
cols.vec[i] = 2


border.vec = rep(rgb(0,0,0,0.5),length(all.at.risk.inds))
i = sapply(kba.uq.additions,function(x) which(all.at.risk.inds == x))
border.vec[i] = rgb(1,0,0,0.5)
cols.vec[i] = 3

# Output importance plot ROC curves & risk matrix -----------------------------


png(paste(out.dir,"ROC_curves_risk_matrix.png",sep=""),
    width = 18/2.54,
    height = 20/2.54,
    units = 'in',
    res = 600)

layout(matrix(c(1,1,2,2,3,3,4,5,5,6,6,7),ncol = 6,byrow = T),widths = c(0.2,0.4,0.2,0.4,0.2,0.4))
par(mar=c(4,3.5,0.5,0.1))
par(mgp=c(2.5,1,0))
par(cex=1)

l = 1
roc.curve(training.data.oil$Exploited, outpred.oil[,2], col = "black",lwd=2,main="",las=1) 
roc.curve(training.data.gas$Exploited, outpred.gas[,2], add = T, col = "blue",lwd=2,las=1,main="") 
mtext(side = 3,letters[l],adj = 0.01,cex=1.2,font=2,padj=1.5)
l = l + 1

legend(x = 0.4,y =0.3,
       legend = c("Oil", "Gas"),
       lwd = 2,
       col=c("black","blue"),
       bty = "n",cex=0.8)


par(mar=c(4,3,0.5,0.1))

r = 1:20
plot(matched.oil.countries[r,1],matched.oil.countries[r,2],
     xlim=c(0,1100),
     ylim=c(0,1100),
     ylab="",xlab="",
     pch=16,col="red",
     cex=0.5,mgp=c(2.5,0.75,0))
mtext(side = 2,"Unexploited oil field count",cex=0.9,line=2.1)
mtext(side = 1,"Exploited oil field count",cex=0.9,line=2.5)

abline(a = 0, b = 1, lwd=2,lty=2)
wordcloud::textplot(matched.oil.countries[r,1],matched.oil.countries[r,2],
                    rownames(matched.oil.countries)[r],new = F,cex=0.5,font=2)
mtext(side = 3,letters[l],adj = 0.01,cex=1.2,font=2,padj=1.5)
l = l + 1

plot(matched.gas.countries[r,1],matched.gas.countries[r,2],
     xlim=c(0,500),
     ylim=c(0,500),
     ylab="",xlab="",
     pch=16,col="red",
     cex=0.5,mgp=c(2.5,0.75,0))
mtext(side = 2,"Unexploited gas field count",cex=0.9,line=2.1)
mtext(side = 1,"Exploited gas field count",cex=0.9,line=2.5)
abline(a = 0, b = 1, lwd=2,lty=2)
wordcloud::textplot(matched.gas.countries[r,1],matched.gas.countries[r,2],rownames(matched.gas.countries)[r],
                    new = F,cex=0.5,font=2)
mtext(side = 3,letters[l],adj = 0.01,cex=1.2,font=2,padj=1.5)
l = l + 1


par(mar=c(5,0.5,0.5,0.5))
plot(1, type="n", axes=F, xlab="", ylab="")

palette(c(rgb(0,0,0,0.5),rgb(0,0,1,0.5),rgb(1,0,0,0.5)))

#x = geometric mean biodiversity, y = ranked probability of exploitation
par(xpd=NA)
terr.at.risk.inds = all.at.risk.inds[which(shp.data$Realm[all.at.risk.inds] == 1.0)]
terr.col.inds = which(shp.data$Realm[all.at.risk.inds] == 1.0)
plot(log(shp.data$GM.bd[terr.at.risk.inds]),
     shp.data$dist.prob.exploited[terr.at.risk.inds],
     ylab="Probability of exploitation",
     xlab="",
     xaxt="n",     
     pch=21,
     bg=cols.vec[terr.col.inds],
     col = border.vec[terr.col.inds],las = 1)
par(xpd=F)
axis(1,at=seq(-3,3),labels = format(exp(seq(-3,3)),scientific = T,digits=1))
mtext(side = 1, text = "Geometric mean of Spp. rich. & RR",adj = -2.5,
      line = 2.25)

rect(par("usr")[1], par("usr")[3], par("usr")[2], par("usr")[4], col = 
       "#d9d9d9")

uq.poly.x=c(log(med.at.risk.gm.bd.terr),
            par("usr")[2],
            par("usr")[2],
            log(med.at.risk.gm.bd.terr),
            log(med.at.risk.gm.bd.terr))
uq.poly.y=c(med.at.risk.dist.terr,
            med.at.risk.dist.terr,
            par("usr")[4],
            par("usr")[4],
            med.at.risk.dist.terr)
polygon(uq.poly.x,uq.poly.y,border = NA,col="#fcbba1")
rect(par("usr")[1], par("usr")[3], par("usr")[2], par("usr")[4], col = 
       NA)

points(log(shp.data$GM.bd[terr.at.risk.inds]),
     shp.data$dist.prob.exploited[terr.at.risk.inds],
     pch=21,
     bg=cols.vec[terr.col.inds],
     col = border.vec[terr.col.inds])

mtext(side = 3,letters[l],adj = 0.01,cex=1.2,font=2,padj=1.5)
l = l + 1
abline(v = log(med.at.risk.gm.bd.terr), col="red", lty="dashed",lwd=2)
abline(h = med.at.risk.dist.terr, col="red", lty="dashed",lwd=2)

par(xpd=NA)


legend(x = 0,y =0.3,
       legend = c("Oil", "Gas","KBA"),
       pch=21,
       pt.bg=c(rgb(0,0,0,0.5),rgb(0,0,1,0.5),rgb(1,0,0,0.5)),
       col = c(rgb(0,0,0,0.5),rgb(0,0,0,0.5),rgb(1,0,0,0.5)),
       horiz=T,
       bty = "n")


par(xpd=F)

#x = geometric mean biodiversity, y = ranked probability of exploitation
mar.at.risk.inds = all.at.risk.inds[which(shp.data$Realm[all.at.risk.inds] == 2.0)]
mar.col.inds = which(shp.data$Realm[all.at.risk.inds] == 2.0)
plot(log(shp.data$GM.bd[mar.at.risk.inds]),
     shp.data$dist.prob.exploited[mar.at.risk.inds],
     ylab="",
     yaxt="n",
     xlab="",
     xaxt="n",     
     pch=21,
     bg=cols.vec[mar.col.inds],
     col = border.vec[mar.col.inds],las = 1)
axis(1,at=seq(-3,3),labels = format(exp(seq(-3,3)),scientific = T,digits=1))
axis(2,labels = F)
# mtext(side = 1, text = "Geometric mean of Spp. rich. & RR",
#       line = 2.25)

rect(par("usr")[1], par("usr")[3], par("usr")[2], par("usr")[4], col = 
       "#d9d9d9")

uq.poly.x=c(log(med.at.risk.gm.bd.mar),
            par("usr")[2],
            par("usr")[2],
            log(med.at.risk.gm.bd.mar),
            log(med.at.risk.gm.bd.mar))
uq.poly.y=c(med.at.risk.dist.mar,
            med.at.risk.dist.mar,
            par("usr")[4],
            par("usr")[4],
            med.at.risk.dist.mar)
polygon(uq.poly.x,uq.poly.y,border = NA,col="#fcbba1")
rect(par("usr")[1], par("usr")[3], par("usr")[2], par("usr")[4], col = 
       NA)

points(log(shp.data$GM.bd[mar.at.risk.inds]),
       shp.data$dist.prob.exploited[mar.at.risk.inds],
       pch=21,
       bg=cols.vec[mar.col.inds],
       col = border.vec[mar.col.inds])

mtext(side = 3,letters[l],adj = 0.01,cex=1.2,font=2,padj=1.5)
abline(v = log(med.at.risk.gm.bd.mar), col="red", lty="dashed",lwd=2)
abline(h = med.at.risk.dist.mar, col="red", lty="dashed",lwd=2)



dev.off()

