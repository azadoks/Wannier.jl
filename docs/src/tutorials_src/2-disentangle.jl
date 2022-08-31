# # 2. Disentanglement of entangled manifold

#=
In the second tutorial, we will run the disentanglement algorithm on
the silicon valence + conduction bands. As usual, we need to

1. generate the `amn`, `mmn`, and `eig` files by using `Quantum ESPRESSO` (QE)
2. construct a [`Model`](@ref Model) for `Wannier.jl`, by reading the `win`, `amn`, `mmn`, and `eig` files
3. run `Wannier.jl` [`disentangle`](@ref disentangle) on the `Model` to minimize the spread
4. write the maximal localized gauge to a new `amn` file

!!! note

    These tutorials assume you have already been familiar with the
    Wannierization workflow using `QE` and `Wannier90`, a good starting
    point could be the tutorials of
    [`Wannier90`](https://github.com/wannier-developers/wannier90).
=#

# ## Preparation
# Load the package
using Wannier
using Printf  # for pretty print

# Path of current tutorial
CUR_DIR = "2-disentangle"

#=
!!! tip

    Use the `run.sh` script which automate the scf, nscf, pw2wannier90 steps.
=#

#=
## Model generation

We will use the [`read_w90`](@ref) function to read the
`win`, `amn`, `mmn`, and `eig` files, and construct a [`Model`](@ref Model) that abstracts the calculation
=#
model = read_w90("$CUR_DIR/si2")

#=
!!! tip

    The [`read_w90`](@ref) function will parse the `win` file and set the frozen window for the `Model` according to
    the `dis_froz_min` and `dis_froz_max` parameters in the `win` file. However, you can also change these parameters
    by calling the [`set_frozen_win!`](@ref) function.
=#

#=
## Disentanglement and maximal localization

The [`disentangle`](@ref disentangle) function
will disentangle and maximally localize the spread
functional, and returns the gauge matrices `A`,
=#
A = disentangle(model)

# The initial spread is
omega(model)

# The final spread is
omega(model, A)

#=
!!! note

    The convergence thresholds is determined by the
    keyword arguments of [`disentangle`](@ref disentangle), e.g., `f_tol` for the tolerance on spread,
    and `g_tol` for the tolerance on the norm of spread gradient, etc. You can use stricter thresholds
    to further minimize a bit the spread.
=#

#=
## Save the new gauge

Again, we save the new gauge to an `amn` file,
which can be used as the new initial guess for `Wannier90`,
or reuse it in `Wannier.jl`.
=#
write_amn("$CUR_DIR/si2.dis.amn", A)

#=
Great! Now you have finished the disentanglement tutorial.

As you can see, the workflow is very similar to the previous tutorial:
the Wannierization functions, `max_localize` and `disentangle`,
accept a `Model` and some convergence thresholds, and return the gauge matrices. This interface are also adopted in
other Wannierization algorithms, shown in later tutorials.
=#