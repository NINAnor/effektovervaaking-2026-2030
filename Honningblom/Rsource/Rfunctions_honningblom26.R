# Functions for population estimates of Herminium monorchis in Norway.
# Loaded from analysis script with source().
# Written by Bård Pedersen

estim.fa.linje <- function(lengde,bredde,andeler) {
  return(lengde*bredde*andeler)
}

estim.fa.rose <- function(ua,andeler) {
  return(ua*andeler)
}

estim.fa.tetthet <- function(x) {
  x[x==0] <- NA
  return(colMeans(x,na.rm = TRUE))
}

ratioest <- function(z){
  ll <- length(z)
  y <- z[1:(ll/2)]
  x <- z[(1+(ll/2)):ll]
  if (sum(x,na.rm = T) == 0) {return(0)}
  if (sum(y,na.rm = T) == 0) {return(0)}
  
  naivest <- mean(y,na.rm = T)/mean(x,na.rm = T)
  if (is.na(naivest) | is.nan(naivest)) {return(0)}
  
  corrterm <- try(cov((y/x),x,use="pairwise.complete.obs")/mean(x,na.rm = T),silent = T)
  if (!is.numeric(corrterm) | is.na(corrterm) | is.nan(corrterm)) {return(naivest)}
  if ((corrterm > naivest) | (naivest - corrterm > 1)) {return(naivest)}
  testsig <- try(cor.test(y/x,x)[[3]],silent = T)
  if (!is.numeric(testsig) | is.na(testsig) | is.nan(testsig)) {return(naivest)}
  if (testsig > 0.05) {return(naivest)}
  return(naivest - corrterm)
}

ratioest2 <- function(z){
  ll <- length(z)
  y <- z[1:(ll/2)]
  x <- z[(1+(ll/2)):ll]
  if (sum(x,na.rm = T) == 0) {return(0)}
  if (sum(y,na.rm = T) == 0) {return(0)}
  
  naivest <- mean(y,na.rm = T)/mean(x,na.rm = T)
  if (is.na(naivest) | is.nan(naivest)) {return(0)}
  
  corrterm <- try(cov((y/x),x,use="pairwise.complete.obs")/mean(x,na.rm = T),silent = T)
  if (!is.numeric(corrterm) | is.na(corrterm) | is.nan(corrterm)) {return(naivest)}
  if ((corrterm > naivest) | (naivest - corrterm > 1)) {return(naivest)}
  testsig <- try(cor.test(y/x,x)[[3]],silent = T)
  if (!is.numeric(testsig) | is.na(testsig) | is.nan(testsig)) {return(naivest)}
  if (testsig > 0.05) {return(naivest)}
  return(naivest)
}

nbinom.likelihood <- function(x,n.transektruter,n.forekomstruter,antall,
                              n.analyseruter.per.transektruter) {
  
  # Veid maksimum likelihood funksjon negativ binomisk fordeling
  
  cond.dnbinom <- function(y,x) {
    return(dnbinom(y,size=x[1],prob=x[2]))#/(1-dnbinom(0,size=x[1],prob=x[2])))
  }
  
  x[1] <- exp(x[1])
  x[2] <- inv.logit(x[2])
  transektledd <- NA
  if (n.analyseruter.per.transektruter == 1) {
    transektledd <- (log(dnbinom(0,size=x[1],prob=x[2]))*(n.transektruter - n.forekomstruter)) + 
      ((log(1-dnbinom(0,size=x[1],prob=x[2])))*n.forekomstruter)
  }
  if (n.analyseruter.per.transektruter == 2) {
    transektledd <- (log(dnbinom(0,size=x[1],prob=x[2])^2)*(n.transektruter - n.forekomstruter)) + 
      ((log(1-(dnbinom(0,size=x[1],prob=x[2])^2)))*n.forekomstruter)
  }
  
  analyseledd <- sum(log(sapply(antall,cond.dnbinom,x)))
  
  return(-1*((n.transektruter*transektledd) + (length(antall)*analyseledd))/(n.transektruter+length(antall)))
}

param.est.andel <- function(serie = NULL,
                            ant.trans.ruter = NULL,
                            napt = 1,
                            n.forekomstruter = 0) {
  
  # ForsC8ker C% reskalere rutestC8rrelsene for hvert C%r slik at
  # antall planter i hver analyserute er i samsvar med en
  # binomisk fordeling. Dette er nC8dvendig for enkelte C%r i TeneskjC&r
  # populasjonen der det er ekstremt mange planter i enkelte av analyse-
  # rutene, som medfC8rer at ingen aktuelle fordelingsmodeller (poisson,
  # ZIP, hurdeled poisson, binomisk, ZI neg.binomisk osv.) fungerer som en
  # modell for dataene.
  
  # Reskalering av rutene innebC&rer C% fordele de observerte
  # plantene i ei analyserute over sc.f reskalerte ruter og C8ke
  # antall transektruter (uten planter) med den samme faktoren sc.f.
  
  # Denne manipulasjonen antar implisitt at plantene er jevnt fordelt innenfor
  # analyserutene. Antagelsen har antagelig liten btydning sammenliknet med
  # antagelsen om uavhengighet mellom transektrutene, som er den kritiske 
  # antagelsen i denne sammenheng.
  
  sc.f <- 10^((max(serie,na.rm = TRUE) %/% c(300) > 10) +
                (max(serie,na.rm = TRUE) %/% c(300) > 0))
  
  antall <- rep(ceiling(serie/sc.f),sc.f)
  antall <- antall[!is.na(antall)]
  mini.nbinom <- nlminb(c(1,1), 
                        objective=nbinom.likelihood,
                        n.transektruter=ant.trans.ruter*sc.f,
                        n.forekomstruter=n.forekomstruter,
                        antall=antall,
                        n.analyseruter.per.transektruter=napt)
  mini.nbinom$par <- c(exp(mini.nbinom$par[1]),inv.logit(mini.nbinom$par[2]))
  
  andel <- pnbinom(0,mini.nbinom$par[1],mini.nbinom$par[2],lower.tail = FALSE)
  return(andel)
}

estim.ua.rose <- function(x)
  # Tilsvarende funksjon hos Olav, "beregn.arealvekt", beregner arealet til 
  # de ulike delarealene i rose-designet. Denne funksjonen er her endret slik 
  # den beregner delen av det undersC8kte omrC%det ved lokaliteten som det ett
  # transekt i rose-designet representerer.
  
{
  r1 <- 0             # radius for indre sirkel (transektets startpunkt)
  r2 <- x             # radius for ytre sirkel (transektets endepunkt)
  return( (pi*r2^2 - pi*r1^2)/8 )
}

estim.pop.size <- function(transektruteserier = NULL,
                           analyseruteserier = NULL,
                           transects = NULL,
                           transektlengder = NULL,
                           design = NULL,
                           n.analyseruter.per.transektruter = NULL,
                           transekt.rute.lengde = NULL,
                           loc = NULL,
                           transektbredde = NULL,
                           years = NULL,
                           grense = 0) {
  
  # Estimer tetthet av individer, fertile- og vegetative planter innenfor
  # forekomstarealet som gjennomsnittlig tetthet i analyseruter med planter.
  
  # Estimer populasjonsstC8rrelsene for hvert C%r som 
  # forekomstareal * tettheten  innenfor forekomstarealet.
  
  if (design == "Line") {
    
    
    andeler <- colMeans(transektruteserier)
    zero.fa <- andeler <= grense
    naf <- colSums(transektruteserier)
    
    for (year in years[zero.fa]) {
      # Parameter-basert estimering av forekomstarealet
      andeler[year] <- param.est.andel(serie = analyseruteserier[,year],
                                       ant.trans.ruter = dim(transektruteserier)[1],
                                       napt = n.analyseruter.per.transektruter[loc],
                                       n.forekomstruter = naf[year])
    }
    
    fa <- estim.fa.linje(lengde = dim(transektruteserier)[1] * transekt.rute.lengde[loc],
                         bredde = transektbredde,
                         andeler = andeler)
    
    popsize <- round(estim.fa.tetthet(analyseruteserier) * fa)
    popsize[is.nan(popsize)] <- 0
    
  } else { # design == "Rose"
    ua <- 0
    for (tname in unique(transects$names)) {
      transl <- transektlengder[transects$names == tname][1]
      ua <- ua + estim.ua.rose(transl)
    }
    
    andeler <- colMeans(transektruteserier)
    zero.fa <- andeler <= grense
    naf <- colSums(transektruteserier)
    for (year in years[zero.fa]) {
      # Parameter-basert estimering av forekomstarealet
      andeler[year] <- param.est.andel(serie = analyseruteserier[,year],
                                       ant.trans.ruter = dim(transektruteserier)[1],
                                       napt = n.analyseruter.per.transektruter[loc],
                                       n.forekomstruter = naf[year])
      
    }
    
    fa <- estim.fa.rose(ua = ua,
                        andeler = andeler)
    popsize <- round(estim.fa.tetthet(analyseruteserier) * fa)
    popsize[is.nan(popsize)] <- 0
  }
  return(list(popsize = popsize, fa = fa))
}

# Sjekk om en vektor inneholder minst C)n verdi som ikke er NA.
notOnlyNAs <- function(x) {return(length(x[!is.na(x)]) > 0)}
