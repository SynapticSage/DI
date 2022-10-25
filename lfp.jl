module lfp
    using DataFrames
    using NetCDF
    using Infiltrator
    using ProgressMeter
    import ..Load
    using DrWatson
    export lfppath, load_lfp, save_lfp, load_cycles, save_cycles, cyclepath

    # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # 
    # LFP
    # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # 

    export lfppath
    """
        lfppath(animal::String, day::Int; tet=nothing, type::String="nc", 
                     ref=nothing)

    Obtains path to lfp file
    """
    function lfppath(animal::String, day::Int; tet=nothing, type::String="nc", 
                     ref=nothing, write=false)
        pathstring(ref,::Nothing) = DrWatson.datadir("exp_raw",
                                     "visualize_raw_neural", 
                                     "$(animal)_$(day)_rhythm$ref.$type")
        pathstring(ref,tet::T where T<:Int) = DrWatson.datadir("exp_raw",
                              "visualize_raw_neural", 
                              "$(animal)_$(day)_rhythm$(ref)_$(tet).$type")
        if ref === nothing
            ref = if isfile(pathstring("ref",tet))
                ref = true;
            elseif isfile(pathstring("",tet))
                ref = false;
            else
                if write == false
                    error("No rhythm file $(pathstring("ref",tet))")
                else
                    ref = false;
                end
            end
        end
        if ref
            pathstring("ref",tet)
        else
            pathstring("",tet)
        end
    end

    function load_lfp(pos...; tet=nothing, vars=nothing, kws...)
        if tet isa Vector
            lfp = [load_lfp(pos...; tet=t, vars=vars)
                   for t in tet]
            lfp = vcat(lfp...)
        else
            lfpPath = lfppath(pos...; tet=tet)
            @info lfpPath
            v = NetCDF.open(lfpPath)
            if "Var1" in keys(v.vars)
                v.vars["time"] = v.vars["Var1"]
                pop!(v.vars, "Var1")
            end
            keyset = keys(v.vars)
            if vars !== nothing
                keyset = String.(vars)
            end
            lfp = Dict(var => Array(v.vars[var]) 
                       for var in keyset)
            lfp = DataFrame(Dict(var => vec(lfp[var]) 
                                 for var in keyset))
        end
        return lfp
    end

    function save_lfp(l::AbstractDataFrame, pos...; tet=nothing, kws...)
        function getkeys(lfpPath::String)
            ncFile = NetCDF.open(lfpPath)
            K = keys(ncFile.vars)
            NetCDF.close(ncFile) # id of the ncfile handle itself, may not be needed in new version
            K
        end
        if length(unique(l.tetrode)) == 1
            tet = l.tetrode[1];
        end
        @infiltrate
        lfpPath = lfppath(pos...; tet, write=true)
        @debug "path=$lfpPath"
        if isfile(lfpPath)
            rm(lfpPath)
        end
        @infiltrate
        d=NcDim("sample", size(l,1))
        varlist = Vector{NcVar}([])
        for k in names(l)
            var = NetCDF.NcVar(k, d)
            var.nctype=NetCDF.getNCType(eltype(original_nc[k]))
            push!(varlist,var)
        end
        NetCDF.create(lfpPath, varlist)
        ncFile = NetCDF.open(lfpPath; mode=NC_WRITE)
        for (i,(key,value)) in enumerate(zip(names(l),eachcol(l)))
            @debug "file=$lfpPath ∃, but key=$key ∉ keys"
            NetCDF.putvar(ncFile[key], Array(value))
        end
    end

    function split_lfp_by_tet(pos...; lfp=nothing, vars=nothing, kws...)
        if lfp === nothing
            lfp = load_lfp(pos...; vars=vars)
        end
        if vars === nothing
            vars = names(lfp)
        end
        lfp = NetCDF.open(lfppath(pos...))
        lfp = groupby(lfp, :tetrode)
        @showprogress for l in lfp
            save_lfp(l, pos...; tet=l.tetrode[begin], vars=vars, kws...)
        end
    end

    # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # 
    # Oscillation cycles
    # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # 

    function cyclepath(animal::String, day::Int, tetrode::Union{String,Int}; type::String="csv")
        DrWatson.datadir("exp_raw", "visualize_raw_neural",
                                  "$(animal)_$(day)_tet=$(tetrode)_cycles.$type")
    end
    function save_cycles(cycles, pos...)
        cycles |> CSV.write(cyclepath(pos...))
    end
    function load_cycles(pos...; type="csv", kws...)
        Load.load_table(pos...; tablepath=:cycles, type=type, kws...)
    end


end
