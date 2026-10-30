# Project functions extracted from funksjoner.qmd.
# Original calculations and function names are retained.
# Authors: Olav Skarpaas and Matthew Grainger.
# Load with source("funksjoner.R", encoding = "UTF-8").
# Required packages are loaded by Horgen_analysis.qmd.

#' Calculate coverage
#'
#' @param rutedata quadrate data
#' @param artsdata species data
#' @param artsgruppe Species 
#'
#' @return coverage 
#' @export
#' @author Olav Skarpaas
#'
beregn.dekning <- function(rutedata,artsdata,artsgruppe){
  dekning <- rep(0,nrow(rutedata))
  for(i in 1:nrow(rutedata))
  {
    utvalgte.data <- artsdata[,artsgruppe]==1 & artsdata$Rute==rutedata$RuteID[i] & artsdata$År==rutedata$År[i]
    if(length(utvalgte.data)>0) dekning[i] <- sum(artsdata$Dekning[utvalgte.data],na.rm=T)
  }
  return(dekning)
}


#' Calculate area weight
#'
#' @param x Quadrate data
#' @param design Linje or Rose
#' @param lokalitetsbredde Width of locality 
#' @param rutebredde with of quadrate (defaults to 1)
#'
#' @return area weighting of survey to calculate estimates
#' @keywords internal
#' @author Olav Skarpaas
#'

beregn.arealvekt <- function(x,design,lokalitetsbredde=NA,rutebredde=1){
  if(design=="Linje")
  {
    return(rep(lokalitetsbredde/rutebredde,length(x)))
  }
  if(design=="Rose")
  {
    r1 <- x             # radius for indre sirkel (rutas avstand fra startpunktet)
    r2 <- x+rutebredde  # radius for ytre sirkel
    return( (pi*r2^2 - pi*r1^2)/8 )
  }
}




#' Bootstrap population
#'
#' @param tetthet density 
#' @param forekomstareal Occurrence area 
#' @param nboot number of bootstrap iterations (defaults to 2000)
#'
#' @return bootstraped estimates of population per age stage
#' @keywords internal
#' @author Olav Skarpaas
#'
boot.pop <- function(tetthet,forekomstareal,nboot=2000){
  tetthet <- tetthet[!is.na(tetthet)]
  if(length(tetthet)==0) {print("Ingen individer"); return(rep(NA,nboot))}
  tetthet.boot <- boot(tetthet,statistic=function(x,k){mean(x[k])},R=nboot)
  forekomstareal.boot <- boot(forekomstareal,statistic=function(x,k){sum(x[k])},R=nboot)
  tetthet.boot$t * forekomstareal.boot$t
}

#' Calculate the Occurrence area
#'
#' @param transektdata transect data 
#' @param utvalgt.lokalitet chosen locality 
#' @param year year
#' @param design Linje or Rose
#' @param lokalitetsbredde Width of locality 
#' @param rutebredde with of quadrate (defaults to 1)
#' @param forekomst_transekt "Dragehode" column in data
#' @param forekomst_avstand "Forekomst dragehode (m)" column in data
#'
#' @keywords internal
#' @author Olav Skarpaas
beregn.forekomstareal <- function(transektdata,utvalgt.lokalitet,year,design,lokalitetsbredde,rutebredde=1,
                                  forekomst_transekt="Dragehode",forekomst_avstand="Forekomst dragehode (m)"){
  x <- list()
  for(i in 1:length(year))
  {
    transekter <- transektdata[transektdata$Lokalitet==utvalgt.lokalitet & transektdata$År==year[i],]
    
    if(all(is.na(transekter[,forekomst_transekt])))
    {
    
      next
    }
    if(all(transekter[,forekomst_transekt]==0))
    {
      next
    }
    forekomstruter <- as.numeric(unlist(sapply(transekter[,forekomst_avstand],strsplit,split=',')))
    forekomstruter <- forekomstruter[!is.na(forekomstruter)]
    forekomstareal <- beregn.arealvekt(forekomstruter,design[i],lokalitetsbredde[i],rutebredde=rutebredde)
    x[[i]] <- forekomstareal
  }
  mangler <- unlist(lapply(x,is.null))
  if(any(mangler))
  {
    erstattes <- which(mangler)
    registrert <- which(!mangler)
    #print(erstattes)
    #print(registrert)
    for(i in erstattes)
    {
      delta <- abs((registrert+0.5) - i)
      #print(delta)
      j <- registrert[delta==min(delta)]
      #print(j)
      x[[i]] <- x[[j]]
    }
  }
  return(x)
}


#' Calculate population structure
#'
#' @param utvalgt.lokalitet chosen locality
#' @param lokalitetsdata data for that locality
#' @param transektdata transect data 
#' @param rutedata quadrate data
#' @param rutebredde quadrate width (defaults to 1)
#' @param fert Fertile plants column
#' @param veg Vegetative plants column
#' @param sma seedlins column
#' @param tot total plants column
#' @param forekomst_transekt occurrence transect data
#' @param forekomst_avstand occurrence distance
#' @param quantiles quantiles to be calsulated (dafaults to 0.025, 0.975)
#'
#' @return population structure list per location
#' @export
#' @author Olav Skarpaas
#'

beregn.popstruktur <- function(utvalgt.lokalitet,lokalitetsdata,transektdata,rutedata,rutebredde=1,
                               fert="Fert.planter",veg="Veg.planter",sma="Småplanter",tot="Ant.DR",
                               forekomst_transekt="Dragehode",forekomst_avstand="Forekomst dragehode (m)",
                               quantiles=c(0.025,0.975)){
  year <- lokalitetsdata[lokalitetsdata$Lokalitet==utvalgt.lokalitet,"År"]
  design <- lokalitetsdata[lokalitetsdata$Lokalitet==utvalgt.lokalitet,"Design"]
  lokalitetsbredde <- lokalitetsdata[lokalitetsdata$Lokalitet==utvalgt.lokalitet,"Lokalitetsbredde"]
  print(paste(utvalgt.lokalitet, year, design,"bredde:",lokalitetsbredde))
  nboot <- 2000
  nq <- length(quantiles)
  nyear <- length(year)
  nFert <- numeric(nyear)
  nVeg <- numeric(nyear)
  nSma <- numeric(nyear)
  nTot <- numeric(nyear)
  Fert.CI <- matrix(NA,nyear,nq)
  Veg.CI <- matrix(NA,nyear,nq)
  Sma.CI <- matrix(NA,nyear,nq)
  Tot.CI <- matrix(NA,nyear,nq)

  forekomstareal.liste <- beregn.forekomstareal(transektdata,utvalgt.lokalitet,year,design,lokalitetsbredde,rutebredde,forekomst_transekt,forekomst_avstand)
  #print(forekomstareal.liste)
  
  for(i in 1:length(year))
  {
    forekomstareal <- forekomstareal.liste[[i]]
    saveRDS(forekomstareal, paste0("data/derived_data/", utvalgt.lokalitet,"_forekomstareal","_",i,".RDS"))
    print(year[i])
    ruter <- rutedata[rutedata$Lokalitet==utvalgt.lokalitet & rutedata$År==year[i] & rutedata[,tot]>0,]
    saveRDS(ruter, paste0("data/derived_data/", utvalgt.lokalitet,"_ruter","_",i ,".RDS"))

    print("Fertile")
    if(!is.na(fert)) x <- boot.pop(ruter[,fert],forekomstareal,nboot)
    else x <- NA
    #print(summary(x))
    nFert[i] <- mean(x); Fert.CI[i,] <- quantile(x,quantiles,na.rm=T)

    print("Vegetative")
    if(!is.na(veg)) x <- boot.pop(ruter[,veg],forekomstareal,nboot)
    else x <- NA
    #print(summary(x))
    nVeg[i] <- mean(x); Veg.CI[i,] <- quantile(x,quantiles,na.rm=T)
    
    print("Småplanter")
    if(!is.na(sma)) x <- boot.pop(ruter[,sma],forekomstareal,nboot)
    else x <- NA
    #print(summary(x))
    nSma[i] <- mean(x); Sma.CI[i,] <- quantile(x,quantiles,na.rm=T)

    print("Totalt")
    if(!is.na(tot)) x <- boot.pop(ruter[,tot],forekomstareal,nboot)
    else x <- NA
    print(summary(x))
    nTot[i] <- mean(x); Tot.CI[i,] <- quantile(x,quantiles,na.rm=T)
  }
  
  popstr <- list(lokalitet=utvalgt.lokalitet,year=year,nFert=nFert,nVeg=nVeg,nSma=nSma,nTot=nTot,Fert.CI=Fert.CI,Veg.CI=Veg.CI,Sma.CI=Sma.CI,Tot.CI=Tot.CI)
  return(popstr)
}



#' Base plot population structure
#'
#' @param popstr population structure data 
#'
#' @return Baseplots of population structure per location
#' @author Olav Skarpaas
#' @export
#' 

plot.popstruktur <- function(popstr){
  thisyear=lubridate::year(Sys.time())
  tidsrom=c(2016.5, thisyear)
  plot(popstr$year,popstr$nTot,ylim=c(0,max(popstr$Tot.CI,na.rm=T)),type="o",main=popstr$lokalitet,xlab="Ãr",ylab="Antall individer",xlim=tidsrom)
  polygon(c(popstr$year,rev(popstr$year)),c(popstr$Tot.CI[,1],rev(popstr$Tot.CI[,2])),col=rgb(0.5,0.5,0.5,alpha=0.2),border=NA)
  lines(popstr$year,popstr$nFert,col="red",type="o"); polygon(c(popstr$year,rev(popstr$year)),c(popstr$Fert.CI[,1],rev(popstr$Fert.CI[,2])),col=rgb(1,0,0,alpha=0.2),border=NA)
  lines(popstr$year,popstr$nVeg,col="green",type="o"); polygon(c(popstr$year,rev(popstr$year)),c(popstr$Veg.CI[,1],rev(popstr$Veg.CI[,2])),col=rgb(0,1,0,alpha=0.2),border=NA)
  lines(popstr$year,popstr$nSma,col="blue",,type="o"); polygon(c(popstr$year,rev(popstr$year)),c(popstr$Sma.CI[,1],rev(popstr$Sma.CI[,2])),col=rgb(0,0,1,alpha=0.2),border=NA)
  #lines(popstr$year,popstr$nSma+popstr$nVeg+popstr$nFert,lty=2,type="o")
  legend("topleft",c("Totalt","Fertile","Vegetative","Småplanter"),lty=c(1,1,1,1),pch=c(1,1,1,1),col=c("black","red","green","blue"),bty="n")
}


#' Base plot group trends
#'
#' @param lokalitetsdata locality data
#' @param gruppevariabel grouping variable 
#' @param lokalitetsestimater local estimates data
#' @param reverser Reverse the axis? default is FALSE
#' @param lokalitetsnavn locality name
#' @param lokfarge locality colour
#' @param regsymbol Regional symbol
#' @param natlinje linetype for naturtype
#'
#' @return baseplots of group trends
#' @author Olav Skarpaas
#' @export
#'
plot.gruppetrender <- function(lokalitetsdata,gruppevariabel,lokalitetsestimater,
                               reverser=FALSE,lokalitetsnavn,lokfarge,regsymbol,natlinje){
  thisyear=lubridate::year(Sys.time())
  tidsrom=c(2016.5, thisyear)
  
  gruppe <- unique(lokalitetsdata[,gruppevariabel])
  if(reverser) gruppe <- rev(gruppe)
  ngrp <- length(gruppe)
  par(mfcol=c(4,ngrp),mar=c(2,4,2,0.2))
  for(i in 1:ngrp)
  {
    grp <- as.character(gruppe[i])
    print(grp)
    lok <- as.character(unique(lokalitetsdata[lokalitetsdata[,gruppevariabel]==grp,"Lokalitet"]))
    farge <- lokfarge[lok]
    #print(lok)
    #print(farge
    
    variabler <- c("nTot","nFert","nVeg","nSma")
    if(i==1) ylab <- c("Antall totalt","Antall fertile","Antall vegetative","Antall småplanter")
    else ylab <- rep("",length(variabler))
    xlab <- c(rep("",length(variabler)-1),"Ãr")
    main <- c(grp,rep("",length(variabler)-1))
    for(i in 1:length(variabler))
    {
      noplot <- TRUE
      for(j in 1:length(lok))
      {
        #print(lok[j])
        reg <- as.character(unique(lokalitetsdata[lokalitetsdata$Lokalitet==lok,"Region"]))
        symbol <- regsymbol[reg]
        nat <- as.character(unique(lokalitetsdata[lokalitetsdata$Lokalitet==lok,"Hovednaturtype"]))
        linje <- natlinje[nat]
        #print(linje)
        
        popstr <- lokalitetsestimater[lok[j]][[1]]
        if(length(popstr)==1) {print("Ingen estimater"); next}
        if(noplot)
        {
          plot(popstr$year,popstr[variabler[i]][[1]],xlim=tidsrom,ylim=c(1,70000),type="o",col=farge[j],     #pch=symbol,lty=linje,
               main=main[i],xlab=xlab[i],ylab=ylab[i],log="y")
          noplot <- FALSE
        }
        else lines(popstr$year,popstr[variabler[i]][[1]],type="o",col=farge[j]) #,pch=symbol,lty=linje)
      }
    }
  }
}

#

#' Calculate growth rate
#'
#' @param rutedata quadrate data
#' @param popvar population variable (Total Dragehode )
#' @param idvar Id of the quadrate (RuteID)
#'
#' @return growthrate estimates
#' @author Olav Skarpaas
#' @export

beregn.vekstrate <- function(rutedata,popvar,idvar){
  vekstrate <- rep(NA,nrow(rutedata))
  year <- sort(as.numeric(unique(rutedata$År)))
  nyear <- length(year)
  if(nyear<2) return(NA)
  for(i in 1:(nyear-1))
  {
    t1 <- rutedata$År==year[i]
    t2 <- rutedata$År==year[i+1]
    idmatch <- match(rutedata[t1,idvar],rutedata[t2,idvar])
    vekstrate[t1] <- rutedata[t2,popvar][idmatch] / rutedata[t1,popvar] 
  }
  rutedata$vekstrate <- vekstrate
  return(rutedata)
}


#' GGplot version of plot.popstruktur
#'
#' @param popstr population structure
#'
#' @return plots of population structure
#' @author Matthew Grainger
#' @export
#'

ggplot.popstruktur <- function(popstr){
  require(tidyverse)
  title=popstr$lokalitet
  popstr=as_tibble(popstr)
  names(popstr)<-c( "lokalitet" ,"year",      "Fertile",     "Vegetative",      "Småplanter",      "Totalt",     
                    "Fert.CI",   "Veg.CI",    "Sma.CI",    "Tot.CI" )
  
  
  popstrCI=popstr %>% 
    mutate("Fert.CI_upper"= Fert.CI[,2]) %>% 
    mutate("Fert.CI_lower"= Fert.CI[,1]) %>% 
    mutate("Tot.CI_upper"= Tot.CI[,2]) %>% 
    mutate("Tot.CI_lower"= Tot.CI[,1]) %>%
    mutate("Veg.CI_upper"= Veg.CI[,2]) %>% 
    mutate("Veg.CI_lower"= Veg.CI[,1]) %>%
    mutate("Sma.CI_upper"= Sma.CI[,2]) %>% 
    mutate("Sma.CI_lower"= Sma.CI[,1]) %>%
    select(!lokalitet) %>% 
    pivot_longer(!year, names_to = "key", values_to = "value") %>% 
    filter(key%in% c("Fert.CI", "Veg.CI","Sma.CI", "Tot.CI")) %>% 
    mutate(var=gsub(".CI","", key))
  
  popstrCI=popstrCI%>% 
    mutate(var=rep(c("Fertile", "Vegetative", "Småplanter", "Totalt"),(dim(popstrCI)[1]/4))) %>% 
    mutate(upper=value[,2]) %>% 
    mutate(lower=value[,1]) %>% 
    select(!value)
  
  
  
  popstr_plot=popstr %>% 
    mutate("Fert.CI_upper"= Fert.CI[,2]) %>% 
    mutate("Fert.CI_lower"= Fert.CI[,1]) %>% 
    mutate("Tot.CI_upper"= Tot.CI[,2]) %>% 
    mutate("Tot.CI_lower"= Tot.CI[,1]) %>%
    mutate("Veg.CI_upper"= Veg.CI[,2]) %>% 
    mutate("Veg.CI_lower"= Veg.CI[,1]) %>%
    mutate("Sma.CI_upper"= Sma.CI[,2]) %>% 
    mutate("Sma.CI_lower"= Sma.CI[,1]) %>%
    select(!lokalitet) %>% 
    pivot_longer(!year, names_to = "key", values_to = "value") %>%
    #filter(!key%in% c("Fert.CI", "Veg.CI","Sma.CI", "Tot.CI")) %>% 
    filter(key%in% c("Fertile", "Småplanter", "Totalt", "Vegetative")) %>% 
    mutate(upper=popstrCI$upper) %>% 
    mutate(lower=popstrCI$lower)
  
  p=popstr_plot%>% 
    ggplot(aes(year,value[,1], colour=key))+
    geom_point(size=2)+
    geom_ribbon(aes(ymin=lower, ymax=upper, fill=popstr_plot$key), alpha=0.2)+
    scale_fill_manual(values = c("darkred", "darkblue", "darkgrey", "darkgreen"), guide="none")+
    geom_line( size=1.2)+
    scale_colour_manual(values = c("darkred", "darkblue", "darkgrey", "darkgreen"))+
    labs(x="År", y= "Antall individer")+
    ggtitle(title)+
    theme_classic()
  
  ggsave(
    paste0("C:/Users/ruben.roos/NINA/154027 - Effektovervåking av trua arter og naturtyper 2024 - Documents/154027-03 Dragehode/R Dragehode 2025/Figurer/ggplots" ,title, ".png"))              
  
}              
