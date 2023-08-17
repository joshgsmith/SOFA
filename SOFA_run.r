# SOFA (Sea Otter Forage Analysis), Version 2.0
# Step 2, Model fitting.
# Source this script to fit the SOFA model to sea otter foraging data. 
#

rm(list=ls())

require(svDialogs)
require(rstudioapi)
require(readxl)
require(openxlsx)
require(tcltk)
require(parallel)
require(rstan)
rstan::rstan_options(javascript=FALSE)
#
# Create Generic function for stopping script in case of error:
stop_quietly <- function() {
	opt <- options(show.error.messages = FALSE)
	on.exit(options(opt))
	stop()
}
rspnse = dlg_message(c("This script is used to set up and run SOFA, fitting the model ",
											 "to a data project that has been prepared by the SOFA_prep script. ",
											 "If you have not already prepared a project, cancel and do that now. ",
											 "Otherwise, you will now be able to select a project to work with, ",
											 "set the necessary user settings and select from various options, ",
											 "and then run the model fitting (which takes a long time). ", 
											 "Once complete you can view results using the 'SOFA_sum' script. ",
											 "Continue?"), "okcancel")$res
if(rspnse == "cancel"){
	stop_quietly()
}
proj_list = dir('./projects') 
Projectpath = dlg_dir('./projects/', "Select Project folder")$res
Projectname = basename(Projectpath)
Sys.sleep(.5)
# Projectname = rselect.list(proj_list, preselect = NULL, multiple = FALSE,
# 						 title = "Select Project name",
# 						 graphics = getOption("menu.graphics"))
#
MnN1 = as.numeric(dlg_input(message = "Min dives/bout for estimating prey attributes", 
														default = 3)$res)
MnN2 = as.numeric(dlg_input(message = "Min dives/bout for estimating effort allocation", 
														default = 10)$res)
nsamples = as.numeric(dlg_input(message = "Number posterior samples from Bayesian fitting", 
																default = 5000)$res)
nburnin = as.numeric(dlg_input(message = "Number of burn-in samples for Bayesian fitting", 
															 default = 1000)$res)
# Process data---------------------------------------------------------------
# Load data (after selecting Projectname from available sub-folders of data folder)
dat = read_excel(paste0("./projects/",Projectname,"/Forage_dat.xlsx"))
# Load reference spreadsheets
dfPr = read_excel(paste0("./projects/",Projectname,"/Prey_Key.xlsx"))
dfPtp = read_excel(paste0("./projects/",Projectname,"/Prey_Key.xlsx"),sheet = "Prey_Types")
dfPcl = read_excel(paste0("./projects/",Projectname,"/Prey_Key.xlsx"),sheet = "Prey_Classes")
dfSz = read_excel(paste0("./projects/",Projectname,"/Sizeclass_key.xlsx"))
dfPaw = read_excel(paste0("./projects/",Projectname,"/Pawsz.xlsx"))
dfM = read_excel(paste0("./projects/",Projectname,"/Mass_lng_dat.xlsx"))
dfE = read_excel(paste0("./projects/",Projectname,"/Energy_dat.xlsx"))
dfElst = read_excel(paste0("./projects/",Projectname,"/Prey_Spcs.xlsx"))
if(length(!is.na(dfPr$PreyType))<length(!is.na(dfPr$PreyCode))){
	dlg_message(c("The Prey_Key spreadsheet has not been completed properly, ",
								"please go back and edit. Stopping program."))
	stop_quietly()
}
# Check if file exists to adjust size of specific prey for specific group variable levels
if(file.exists(paste0("./projects/",Projectname,"/Adjust_size_group.xlsx"))){
	Adj_Sz_grp = 1
	dfSzAd = read_excel(paste0("./projects/",Projectname,"/Adjust_size_group.xlsx"))
}else{
	Adj_Sz_grp = 0
	dfSzAd = numeric()
}
# Make the last prey type UNID:
Nptps = max(dfPtp$TypeN); dfPtp = rbind(dfPtp[2:nrow(dfPtp),],dfPtp[1,])
dfPtp$TypeN[nrow(dfPtp)] = Nptps + 1
#  Create vector of selection variables for data sub-setting or grouping 
slctvars = c("Area", "Site", "Period", "Sex", "Ageclass", "Ottername", "Pup")
# Note: determine which of these potential selection variables has enough levels
ix = numeric()
for (i in 1:length(slctvars)){
	col = which(colnames(dat)==slctvars[i])
	lvls = as.matrix(table(dat[,col]))
	if(length(lvls[which(lvls[,1]>100),1])<2){
		ix = c(ix,i)
	} 
}
if(length(ix)>0){
	slctvars = slctvars[-ix]
}
#
rspns = dlg_message(c("Do you wish to analyze the full data set? If you answer 'no', ", 
											"it is assumed you wish to analyze just a sub-set of the data,",
											"in which case you will next be asked to select a sub-set of data ", 
											"based on values of one of the data variables (Area, Period, etc.))",
											"Analyze full data set?"), "yesno")$res
if (rspns=="yes"){
	SBST = 0
}else{
	SBST = 1
}
if (SBST==1){
	slctvar = tk_select.list(slctvars, preselect = NULL, multiple = FALSE,
													 title = "Which variable?")
	# 	slctvar = rselect.list(slctvars, preselect = NULL, multiple = FALSE,
	#  						 title = "Which variable?",
	#  						 graphics = getOption("menu.graphics"))
	col = which(colnames(dat)==slctvar)
	lvls = rownames(as.matrix(table(dat[,col])))
	lvls = tk_select.list(lvls, preselect = NULL, multiple = TRUE,
												title = paste0("Which values of ",slctvar)) 
	# lvls = rselect.list(lvls, preselect = NULL, multiple = TRUE,
	# 									 title = paste0("Which values of ",slctvar) ,
	# 									 graphics = getOption("menu.graphics")) 
	iis = numeric()
	slctvardef = paste0(slctvar,"-")
	for(i in 1:length(lvls)){
		slctvardef = paste0(slctvardef,lvls[i])
		ii = which(dat[,col]==lvls[i])
		iis = c(iis,ii)
	}
	dat = dat[iis,]
	slctvars = c("Area", "Site", "Period", "Sex", "Ageclass", "Ottername", "Pup")
	# Note: determine which of these potential selection variables has enough levels
	ix = numeric()
	for (i in 1:length(slctvars)){
		if(slctvars[i]==slctvar){
			ix = c(ix,i)
		}else{
			col = which(colnames(dat)==slctvars[i])
			lvls = as.matrix(table(dat[,col]))
			if(length(lvls[which(lvls[,1]>100),1])<2){
				ix = c(ix,i)
			} 
		}
	}
	slctvars = slctvars[-ix]
}
#
source("./code/Fdatprocess.R")
rslt = try(suppressWarnings ( Fdatprocess(dat,dfPr,dfPtp,dfPcl,dfSz,dfPaw,dfM,dfE,dfElst,Adj_Sz_grp,dfSzAd)))
if(!is.list(rslt)){
	errtxt = dlg_message(c("An error occured in data processing. This is likely due to a ",
												 "formatting error in either the raw data or Prey_Key spreadsheet.",
												 "Go back and re-check both, following instructions in manual"), "ok")$res
	stop_quietly()
}
Fdat = rslt$Fdat; Boutlist=rslt$Boutlist
Cal_dns_mn = rslt$Cal_dns_mn; Cal_dns_sg = rslt$Cal_dns_sg
logMass_sg = rslt$logMass_sg
Nbouts = rslt$Nbouts; Ndives = rslt$Ndives; Nobs = rslt$Nobs; NPtypes = rslt$NPtypes
MassLngFits = rslt$MassLngFits
rm(rslt)
rspns = dlg_message(c("Do you wish to review plots of mass-length data fits?"), "yesno")$res
if (rspns=="yes"){
	# Generate mass-length plots by prey code
	for(pr in 1:nrow(dfPr)){
		if(!is.na(dfPr$PreyType[pr])){
			if(dfPr$PreyType[pr] != "UNID"){
				ft = MassLngFits[[pr]]
				plot(exp(ft$model$x),exp(ft$model$y),main=dfPr$Description[pr],
						 xlab="size (mm)",ylab="mass (g)")
				lines(exp(ft$prdct$x),exp(ft$prdct$ypred),col="red")
				# exp(ft$coefficients[1] + ft$coefficients[2]*log(44.23413))
			}
		}
	}
}
#  Allow user to set by-groups for analysis based on grouping variables
rspns = dlg_message(c("You also have the option of setting 'by-groups' for analysis: ",
											"this means that one or more categorical variables are used to ", 
											"divide the data into groups, and stats will be generated ",
											"for each group level."), "ok")$res
rspns = dlg_message(c("Do you wish to analayze data by group, with the by-group",
											"levels determined by one or more categorical variables?"), "yesno")$res
if (rspns=="no"){
	GrpOpt = 0
}else{
	GrpOpt = 1
}
if(GrpOpt==1){
	Grpvar = tk_select.list(slctvars, preselect = NULL, multiple = TRUE,
													title = "Which variables?")	
	# Grpvar = rselect.list(slctvars, preselect = NULL, multiple = TRUE,
	# 											title = "Which variables?",
	# 											graphics = getOption("menu.graphics"))
	Ngrpvar = length(Grpvar)
}
# Determine group ID for each bout, if GrpOpt = 1
if(GrpOpt==0){
	Boutlist$Grp = rep(1,Nbouts)
	Ngrp = 1
}else{
	Grp = Boutlist %>%
		group_by_at(Grpvar) %>%
		summarize(Nbouts = length(Bout))
	Grouplist = as.data.frame(cbind(GroupID = seq(1,nrow(Grp)),Grp))
	if(Ngrpvar==1){
		Groupname = Grouplist[ , Grpvar ]
	}else{
		Groupname = apply( Grouplist[ , Grpvar ] , 1 , paste , collapse = "-" )
	}
	Grouplist = cbind(Grouplist,Groupname)
	tmp = merge(Boutlist,Grouplist[,-ncol(Grouplist)],by=Grpvar)
	tmp = tmp[order(tmp$BoutN),]; Boutlist$Grp = tmp$GroupID; rm(tmp)
	Ngrp = max(Boutlist$Grp)
}  
#
# Analyze bouts to get bout-specific stats
source("./code/Boutprocess.R")
stan.data = try(suppressWarnings ( Boutprocess(Fdat,Nbouts,NPtypes,Boutlist,MnN1,MnN2,GrpOpt,Ngrp)))
if(!is.list(stan.data)){
	errtxt = dlg_message(c("An error occured in processing bout statistics. This is likely due to a ",
												 "formatting error in the raw data, prey types with too few observations,",
												 "or group levels with too few data records. Go back and re-check data ",
												 "and Prey_Key set-up, following instructions in manual"), "ok")$res
	stop_quietly()
}
#
# Fit Bayesian model ------------------------------------------------------
#
# options(mc.cores = parallel::detectCores())
# rstan_options(auto_write = TRUE)
cores = detectCores()
ncore = max(3,min(20,cores-3))
Niter = round(nsamples/ncore)
#
if(GrpOpt==0){
	params <- c("tauB","maxPunid","CRmn","ERmn","LMmn","SZ","SZ_u",
							"HT","HT_u","CR","ER","eta","Pi","Omega",
							"phi1","phi2","psi1","psi2","LM",
							"sigCR","sigSZ","sigSZ_u","sigHT","sigHT_u","sigLM") 
	# "muSZ","muSZ_u","psi1_u","psi2_u",
}else{
	params <- c("tauB","tauG","maxPunid","CRmn","ERmn","LMmn","SZ",
							"SZ_u","HT","HT_u","CR","ER","eta","Pi",
							"Omega","phi1","phi2","psi1","psi2","LM",
							"sigCR","sigSZ","sigSZ_u","sigHT","sigHT_u","sigLM",
							"CRgmn","ERgmn","LMgmn","SZg","SZg_u","HTg","CRg","ERg",
							"LMg","etaG","PiG","OmegaG","phi1G","psi1G",
							"sg1","sg2","sg3","sg4","sg5","sg6") 
	# "muSZ","muSZ_u","muSZG","muSZG_u","psi1_u","psi2_u","psi1G_u",
}
#
# Stan model to fit:
if (GrpOpt==0){
	fitmodel = "SOFAfit.stan"
}else{
	fitmodel = "SOFAfit_Grp.stan"
}
#
# Compile model if necessary, or load pre-compiled version if available
testfile = paste0("./code/",substr(fitmodel ,1,nchar(fitmodel)-5),"_dso.rdata")
if(file_test("-f", testfile) ==TRUE){
	load(testfile)
}else{
	Stan_model.dso = stan_model(file = paste0("./code/",fitmodel),
															model_name = substr(fitmodel ,1,nchar(fitmodel)-5))
	save(Stan_model.dso,file=testfile)
}
#
rspnse = dlg_message(c("That completes set-up, the model will now be fit using ",
											 "Bayesian methods (rstan). Fitting can take several hours, ",
											 "depending on size of the data file and speed of the computer. ",
											 "NOTE: if an error occurs it is likely because rstan or rtools are ",
											 "not installed properly, keep track of error codes for debugging.",
											 "Continue?"), "okcancel")$res
if(rspnse == "cancel"){
	stop_quietly()
}
#
suppressWarnings ( 
	out <- sampling(Stan_model.dso,
									data = stan.data,    # named list of data
									pars = params,       # list of params to monitor
									init = "random",     # initial values     "random", 
									chains = ncore,         # number of Markov chains
									warmup = nburnin,       # number of warmup iterations per chain
									iter = Niter,         # total number of iterations per chain
									cores = ncore,          # number of cores (if <20, increase iter)
									refresh = 50        # show progress every 'refresh' iterations
									#               control = list(adapt_delta = 0.99, max_treedepth = 15)
	)
) 
mcmc <- as.matrix(out)
vn = colnames(mcmc)
Nsims = nrow(mcmc)
sumstats = summary(out)$summary
vns = row.names(sumstats)
paramnames = params
rm(params,Stan_model.dso,out)
# save image file of results for post-fit processing and review:
dir.create(paste0("./projects/",Projectname,"/results"),showWarnings = F)
#
if (GrpOpt==0){
	if (SBST==1){
		save.image(paste0("./projects/",Projectname,"/results/Rslt_",slctvardef,"_",
											format(Sys.time(), "%Y_%b_%d_%H"),"hr.rdata"))
	}else{
		save.image(paste0("./projects/",Projectname,"/results/Rslt_All_", 
											format(Sys.time(), "%Y_%b_%d_%H"),"hr.rdata"))
	}
}else{
	save.image(paste0("./projects/",Projectname,"/results/Rslt_Grp_", 
										format(Sys.time(), "%Y_%b_%d_%H"),"hr.rdata"))
}
fintxt = c("That completes model fitting, check psrf values and other diagnostics. ",
					 "The results have been saved to the 'results' sub-folder of the project. ",
					 "You can view summary plots and tables by running the 'SOFA_sum' script. ")
dlg_message(fintxt)
