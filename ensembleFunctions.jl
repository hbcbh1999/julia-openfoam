function setParams(case,topT,bottomT,hc,endTime,deltaT,writeInterval)
    case.controlDict["endTime"] = int(endTime)
    case.controlDict["deltaT"] = float(deltaT)
    case.controlDict["writeInterval"] = float(writeInterval)
    case.T["boundaryField"]["bottominside"]["variables"] = "\"Text=$(bottomT);hc=$(hc);gradT=(Text-T)*hc;\""
    case.T["boundaryField"]["bottomoutside"]["variables"] = "\"Text=$(bottomT);hc=$(hc);gradT=(Text-T)*hc;\""
    case.T["boundaryField"]["topinside"]["variables"] = "\"Text=$(topT);hc=$(hc);gradT=(Text-T)*hc;\""
    case.T["boundaryField"]["topoutside"]["variables"] = "\"Text=$(topT);hc=$(hc);gradT=(Text-T)*hc;\""
end

function initAndRunTruth(case,truthFolder,endTime)
    baseCase = "/users/a/r/areagan/OpenFOAM/areagan-2.2.1/run/juliabase"
    println("initiating truth model at $(truthFolder)")
    initCase(case,baseCase)
    # make a truth run
    println("making truth run")
    # run(case,`./Allrun`)
    println("running the case 20 times:")
    for t=1:endTime
        println("$(t)")
        case.controlDict["endTime"] = t
        writeDict(case,case.controlDict,"controlDict","system")
        run(case,`./Allrun`)
        case.controlDict["startTime"] = t
    end
end

# this is just going to be the end time T
function readFlux(case,t,faces)
    # println(stringG(t))
    # truth = readVar(case,stringG(t),"T")
    # println("read in a variable of size:")
    # println(size(truth))
    flux = mean(readVarSpec(case,stringG(t),"phi",faces[3]))
    println("the flux at time $(t) is $(flux)")
    flux
end

function reshapeInterally(case,points)
    # this will go read the case from T and reshape it an internal variable
    case.T["valueReshaped"] = zeros(size(points))
    for j in 1:length(points)
        case.T["valueReshaped"][j] = case.T["value"][points[j]]
    end
end

function buildObservations(case,start,end_assimilation,window,points)
    # this thing is huuuge, so be careful?
    # could also just go pull observations at each time step
    # observations = zeros(Float64,length(start:window:end_assimilation),size(points)[1],size(points)[2])
    observations = cell(length(start:window:end_assimilation))
    for t in start:window:end_assimilation
        obs = readVar(case,stringG(t),"T")
        obs_reshaped = zeros(size(points))
        for i in 1:length(points)
            obs_reshaped[i] = obs[points[i]]
        end
        observations[t-start+1] = obs_reshaped
    end
    println("done building the observations vector")
    observations
end

function initializeEnsemble(Nens,topT,bottomT,deltaT,writeInterval,hc,init,truth)
    println("initializing all $(Nens) ensemble models")
    ens = Array(OpenFoam,Nens)
    writeInterval = 1
    endTime = 1
    for i=1:Nens
        println("initializing ensemble $(i)")
        caseFolder = "/users/a/r/areagan/scratch/run/ensembleTest/ens$(dec(i,3))-$(dec(Nens,3))-$(topT)-$(bottomT)-shorter"
        ens[i] = OpenFoam(caseFolder)
        ens[i].controlDict["endTime"] = int(endTime)
        ens[i].controlDict["startTime"] = 0
        ens[i].controlDict["deltaT"] = float(deltaT)
        ens[i].controlDict["writeInterval"] = float(writeInterval)
        ens[i].T["boundaryField"]["bottominside"]["variables"] = "\"Text=$(bottomT);hc=$(hc);gradT=(Text-T)*hc;\""
        ens[i].T["boundaryField"]["bottomoutside"]["variables"] = "\"Text=$(bottomT);hc=$(hc);gradT=(Text-T)*hc;\""
        ens[i].T["boundaryField"]["topinside"]["variables"] = "\"Text=$(topT);hc=$(hc);gradT=(Text-T)*hc;\""
        ens[i].T["boundaryField"]["topoutside"]["variables"] = "\"Text=$(topT);hc=$(hc);gradT=(Text-T)*hc;\""
        baseCase = "/users/a/r/areagan/OpenFOAM/areagan-2.2.1/run/juliabase"
        if init
            initCase(ens[i],baseCase)
        
            # pick a random time from the truth, read it in, set that to the 0
            println("picking random time to read from model")
            seed = int(floor(rand()*9600)+1)
            println("reading from model at time $(seed)")
            initialT = readVar(truth,stringG(seed),"T")
	    # also care about these variables
            initialPhi = readVar(truth,stringG(seed),"phi")
            initialU = readVar(truth,stringG(seed),"U")
	    # p was not actually saved on the base case
            # initialP = readVar(truth,stringG(seed),"p")
            println("setting internal field")
            ens[i].T["internalField"] = string("nonuniform List<scalar>\n$(length(initialT))\n(\n",join(initialT,"\n"),"\n)\n")
            # ens[i].T["internalField"] = string("nonuniform List<scalar>\n$(length(truth))\n(\n",join(readVar(truth,stringG(seed),"T"),"\n"),"\n)\n")
            ens[i].phi["internalField"] = string("nonuniform List<scalar>\n$(length(initialPhi))\n(\n",join(initialPhi,"\n"),"\n)\n")
            tmp = Array(String,size(initialU)[2]);
            for j=1:size(initialU)[2]
                tmp[j] = "("*join(initialU[:,j]," ")*")"
            end
            ens[i].U["internalField"] = string("nonuniform List<vector>\n$(length(tmp))\n(\n",join(tmp,"\n"),"\n)\n")
            # ens[i].p["internalField"] = string("nonuniform List<scalar>\n$(length(initialP))\n(\n",join(initialP,"\n"),"\n)\n")
            println("writing T at time 0")
            writeVolScalarField(ens[i],ens[i].T,"T","0")
            writeSurfaceScalarField(ens[i],ens[i].phi,"phi","0")
            writeVolVectorField(ens[i],ens[i].U,"U","0")
            # writeVolScalarField(ens[i],ens[i].p,"p","0")
        end
    
        # println("test that they run for 1 timestep")
        # run(ens[i],`./Allrun`)
        # t = 0
        # println("read that value back in ")
    
        ens[i].T["value"] = readVar(ens[i],"0","T")
        # println("the first 10 of the read on T is")
        # println(ens[i].T["value"][1:10])
        # println("the size of the read on T is")
        # println(size(ens[i].T["value"]))
    
        # println("reshape it")
        ens[i].T["valueReshaped"] = zeros(size(points))
        for j in 1:length(points)
            ens[i].T["valueReshaped"][j] = ens[i].T["value"][points[j]]
        end
        # println(ens[i].T["valueReshaped"][1:3,:])

        println("done")
    end
    ens
end

function runEnsemble(ens,t)
    for i=1:length(ens)
        println("running ensemble $(i)")
        ens[i].controlDict["startTime"] = t
        ens[i].controlDict["endTime"] = t+1
        writeDict(ens[i],ens[i].controlDict,"controlDict","system")
        run(ens[i],`./Allrun`)
    end
end

function assimilate(observations,t,R,points,Nens,ens)
    x,y = size(points) # 1000,40
    Tscaling = 1.0
    zone_size = 10
    X_f = ones(Float64,(R*2+zone_size)*y,Nens) # 15*40,20
    stddev = 0.5
    delta = 0.0
    L = R

    # forecast = zeros(Float64,x,y)
    # analysis = zeros(Float64,x,y)

    for i=1:Nens
        # read in the value
        ens[i].T["value"] = readVar(ens[i],stringG(t),"T")
        # reshape the values
        ens[i].T["valueReshaped"] = zeros(size(points))
        for j in 1:length(points)
            ens[i].T["valueReshaped"][j] = ens[i].T["value"][points[j]]
        end
    end

    for i in 0:zone_size:984
        println("assimilating at x=$(i+1) through x=$(i+zone_size)")
	
        local_obs = observations[mod(linspace(i-R,i+R+zone_size-1,R*2+zone_size),x)+1,:]
        local_obs_flat = reshape(local_obs',length(local_obs))
	
        for j=1:Nens
            local_ens = ens[j].T["valueReshaped"][mod(linspace(i-R,i+R+zone_size-1,R*2+zone_size),x)+1,:]
            X_f[:,j] = reshape(local_ens',length(local_obs))
        end
    
	# forecast[i+1:i+zone_size,:] = reshape(mean(X_f[R*y+1:(R+zone_size)*y,:],2),y,zone_size)'

        # X_a = ETKF(X_f,local_obs_flat,eye(length(local_obs)),eye(length(local_obs)).*stddev,delta)
        X_a = EnKF(X_f,local_obs_flat,eye(length(local_obs)),eye(length(local_obs)).*stddev,delta)

	# analysis[i+1:i+zone_size,:] = reshape(mean(X_a[R*y+1:(R+zone_size)*y,:],2),y,zone_size)'
    
        for j=1:Nens
            ens[j].T["value"][reshape(points[i+1:i+zone_size,:]',zone_size*y)] = X_a[R*y+1:(R+zone_size)*y,j]
        end
    end
    
    # write it out
    for i=1:Nens
        ens[i].T["internalField"] = string("nonuniform List<scalar>\n$(length(ens[i].T["value"]))\n(\n",join(ens[i].T["value"],"\n"),"\n)\n") # "uniform 300"
        writeVolScalarField(ens[i],ens[i].T,"T",string(t))
    end
    
    # forecast,analysis
end
