#
#Compute the SEM model under different spatial structures
#
library(INLA)
library(parallel)
library(spdep)

#Here I use the katrina dataset from spatialprobit

library(spatialprobit)
data(Katrina)

#And index for slm model
Katrina$idx <- 1:nrow(Katrina)

#Model matrix for SLM models
mm <- model.matrix(y1 ~ 1 + flood_depth + log_medinc + small_size + large_size +
    low_status_customers + high_status_customers + owntype_sole_proprietor +
    owntype_national_chain,
  Katrina)

# (a) 0-3 months time horizon
# LeSage et al. (2011) use k=11 nearest neighbors in this case
nb <- knn2nb(knearneigh(cbind(Katrina$long, Katrina$lat), k = 11,
  longlat = TRUE))
listw <- nb2listw(nb, style = "W")
W1 <- as(listw, "CsparseMatrix")


#Variance-covarinace matrix for beta coeffients' prior
#
betaprec1 <- 1e-12 #0.0001
#Standard regression model
Q.beta1 = Diagonal(n = ncol(mm), x = 1)
Q.beta1 = betaprec1 * Q.beta1


#Compute SLM model under different number of nearest neighbours 
vnneigh <- 5:35
mneigh <- mclapply(vnneigh, function(k){

  nb <- knn2nb(knearneigh(cbind(Katrina$long, Katrina$lat), k=k, longlat=TRUE))
  listw <- nb2listw(nb, style="W")
  W1 <- as(listw, "CsparseMatrix")

  #SLM model
  m2inlaK = inla(y1 ~ -1 +
    f(idx, model = "slm",
      args.slm = list(
        rho.min = 0, rho.max = 1, W = W1, X = mm,
        Q.beta = Q.beta1),
      hyper = list(
        prec = list(initial = log(1), fixed = TRUE),
        rho = list(prior = "logitbeta", param = c(1, 1)))),
    data = Katrina,
    control.fixed = list(prec = 1e-12, prec.intercept = 1e-12),
    family = "binomial",
    control.family = list(link = "probit"),
    control.compute = list(dic = TRUE),
    verbose = FALSE)

})

#Retrieve marginal likelihoods and DICs
nnmliks <- unlist(lapply(mneigh, function(X){ X$mlik[1] }))
nndics <- unlist(lapply(mneigh, function(X){ X$dic$dic }))

vnneigh[which.max(nnmliks)]
vnneigh[which.min(nndics)]

#Posterior probabilities: UNIFORM PRIOR
ppost <- exp(nnmliks - max(nnmliks))
ppost <- ppost / sum(ppost)
names(ppost) <- 5:35

#Posterior probabilities: 1/(k^2) PRIOR
pprior2 <- 1 / ((5:35)^2)
pprior2 <- pprior2 / sum(pprior2)
ppost2 <- exp(nnmliks - max(nnmliks) + log(pprior2))
ppost2 <- ppost2 / sum(ppost2)
names(ppost2) <- 5:35



#Display marginal likelihoods and DICs
pdf(file = "katneigh2.pdf")
par(mfrow = c(1, 2))
plot(vnneigh, nnmliks, main = "Marginal log-lik", type = "l")
plot(vnneigh, nndics, main = "DIC", type = "l")
dev.off()

#Plots for posterior probabilites: UNIFORM PRIOR
pdf(file = "katneigh.pdf", height = 5, width = 7.5)
par(mfrow = c(1, 2))
plot(vnneigh, nndics, type = "l", xlab = "Number of neighbours",
  ylab = "DIC")
barplot(ppost, xlab = "Number of neighbours", ylab = "Posterior Probability")
dev.off()


#Plots for posterior probabilites: INFORMATIVE PRIOR
pdf(file = "katneighprior.pdf", height = 5, width = 7.5)
par(mfrow = c(1, 2))
barplot(pprior2, xlab = "Number of neighbours", ylab = "Prior Probability")
barplot(ppost2, xlab = "Number of neighbours", ylab = "Posterior Probability")
dev.off()


#BMA with all models
#Used to average over all models with different spatial structure
#
#library(INLABMA)
#bmamodel1 <- INLABMA(mneigh, vnneigh)#Flat prior
#bmamodel2 <- INLABMA(mneigh, vnneigh, pprior2)#Informative prior

#  It is better to use inla.merge
bmamodel1 <- inla.merge(mneigh)#Flat prior
bmamodel2 <- inla.merge(mneigh, pprior2)#Informative prior)

# Summary of coefficients in slm effect
tabaux <- bmamodel1$summary.random$idx[674:682, ]
tabaux2 <- bmamodel2$summary.random$idx[674:682, ]


#Table with fixed effects after BMA over different neighbours
#First, we include the results from the model with the highest
#posterior probability
#Next, the BMA models
tneigh <- cbind(mneigh[[18]]$summary.random[[1]][674:682, 2:3],
  mneigh[[4]]$summary.random[[1]][674:682, 2:3],
  tabaux[, 1:2], tabaux2[, 1:2])

rownames(tneigh) <- colnames(mm)


library(xtable)
print(xtable(tneigh, digits = 3))


