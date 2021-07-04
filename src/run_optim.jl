using StaticArrays: include
import Optim
using Random

include("parameters.jl")
include("io.jl")
include("disentangle.jl")
include("wannierize_utils.jl")

# seedname = "aiida"
seedname = "/home/junfeng/git/Wannier.jl/test/silicon/example27/pao_new/si"
# read $file.amn as input
read_amn = true
# read the eig file (can be set to false when not disentangling)
read_eig = true
# write $file.optimize.amn at the end
write_optimized_amn = true
# will freeze if either n <= num_frozen or eigenvalue in frozen window
# num_frozen = 0 # 1
# dis_froz_min = -Inf
# frozen_window_high = 1.1959000000e+01 #1.1959000000e+01 #-Inf
# dis_froz_max = 12
# tolerance on spread
ftol = 1e-20
# tolerance on gradient
gtol = 1e-4
# maximum optimization iterations
maxiter = 200 # 3000
# history size of BFGS
m = 100

# expert/experimental features
# perform a global rotation by a phase factor at the end
do_normalize_phase = false
# randomize initial gauge
do_randomize_gauge = false
# only minimize sum_n <r^2>_n, not sum_n <r^2>_n - <r>_n^2
only_r2 = false

Random.seed!(0)

# check parameters
if do_randomize_gauge && read_amn
    error("do not set do_randomize_gauge and read_amn")
end

params = InOut.read_seedname(seedname, read_amn, read_eig)

if read_amn
    amn0 = copy(params.amn)
else
    amn0 = randn(size(params.amn)) + im * randn(size(params.amn))
end

# initial guess for U matrix
for ik = 1:params.num_kpts
    l_frozen = get_frozen_bands_k(params, ik)
    l_non_frozen = .!l_frozen

    amn0[:,:,ik] = orthonormalize_and_freeze(amn0[:,:,ik], l_frozen, l_non_frozen)
end

# 
A = minimize(params, amn0)

# fix global phase
if do_normalize_phase
    for i = 1:nwannier
        imax = indmax(abs.(A[:,i,1,1,1]))
        @assert abs(A[imax,i,1,1,1]) > 1e-2
        A[:,i,:,:,:] *= conj(A[imax,i,1,1,1] / abs(A[imax,i,1,1,1]))
    end
end

if write_optimized_amn
    InOut.write_amn("$(seedname).amn.optimized", A)
end
