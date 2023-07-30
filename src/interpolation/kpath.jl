using Spglib
using Bravais: reciprocalbasis
using Brillouin:
    KPath,
    KPathInterpolant,
    cartesianize,
    latticize,
    latticize!,
    LATTICE,
    CARTESIAN,
    irrfbz_path
using WannierIO: SymbolVec3

export generate_kpath, get_kpoints, generate_w90_kpoint_path

function _new_kpath_label(
    label::T, existing_labels::Union{AbstractVector{T},AbstractSet{T}}
) where {T<:Symbol}
    max_tries = 10
    i = 1
    while i < max_tries
        new_label = Symbol(String(label) * "_$i")
        if new_label ∉ existing_labels
            return new_label
        end
        i += 1
    end
    return error("Cannot find a new label?")
end

"""
    $(SIGNATURES)

Construct a `Brillouin.KPath` from the returned `kpoint_path` of `WannierIO.read_win`.

# Arguments
- `lattice`: each column is a lattice vector
- `kpoint_path`: the returned `kpoint_path` of `WannierIO.read_win`, e.g.,
```julia
kpoint_path = [
    [:Γ => [0.0, 0.0, 0.0], :M => [0.5, 0.5, 0.0]],
    [:M => [0.5, 0.5, 0.0], :R => [0.5, 0.5, 0.5]],
]
```
"""
function generate_kpath(
    lattice::AbstractMatrix, kpoint_path::AbstractVector{T}
) where {T<:AbstractVector}
    points = Dict{Symbol,Vec3{Float64}}()
    paths = Vector{Vector{Symbol}}()

    warn_str =
        "Two kpoints in `kpoint_path` have the same label but different " *
        "coordinates, appending a number to the label of the 2nd kpoint"

    for path in kpoint_path
        @assert length(path) == 2 "each path should have 2 kpoints"
        k1, k2 = path
        @assert k1 isa Pair && k2 isa Pair "each kpoint should be a `Pair`"
        # start kpoint
        label1 = Symbol(k1.first)
        v1 = Vec3{Float64}(k1.second)
        if label1 ∈ keys(points) && points[label1] ≉ v1
            # convert to Tuple for better printing without type info
            @warn warn_str label = label1 k1 = Tuple(points[label1]) k2 = Tuple(v1)
            label1 = _new_kpath_label(label1, keys(points))
        end
        points[label1] = v1
        # end kpoint
        label2 = Symbol(k2.first)
        v2 = Vec3{Float64}(k2.second)
        if label2 ∈ keys(points) && points[label2] ≉ v2
            @warn warn_str label = label2 k1 = Tuple(points[label2]) k2 = Tuple(v2)
            label2 = _new_kpath_label(label2, keys(points))
        end
        points[label2] = v2
        # push to kpath
        if length(paths) > 0 && label1 == paths[end][end]
            push!(paths[end], label2)
        else
            push!(paths, [label1, label2])
        end
    end

    basis = reciprocalbasis([v for v in eachcol(lattice)])
    setting = Ref(LATTICE)
    kpath = KPath(points, paths, basis, setting)
    return kpath
end

"""
    $(SIGNATURES)

Generate a `KPathInterpolant` containing kpoint coordinates that are exactly
the same as wannier90.

The kpoints are generated by the following criteria:
- the kpath spacing of remaining segments are kept the same as the first segment
- merge same high-symmetry labels at the corner between two segments; keep both
    labels if the two labels (ending of the 1st segment and starting point of the
    2nd segment) are different

# Arguments
- `kpath`: a `Brillouin.KPath`
- `n_points_first_segment`: number of kpoints in the first segment, remaining
    segments will have the same spacing as the 1st segment.

# Return
- a `KPathInterpolant`.

!!! note

    This reproduce exactly the wannier90 behavior, if
    - the `kpath` is generated by [`generate_kpath`](@ref)
        - the `kpoint_path` argument of `generate_kpath` and be obtained by
            `WannierIO.read_win` which parses the `kpoint_path` block of `win` file
    - the `n_points` is the same as `win` file input parameter `bands_num_points`,
        which again can be obtained by `WannierIO.read_win`.
"""
function generate_w90_kpoint_path(
    kpath::KPath, n_points_first_segment::Integer=default_w90_kpath_num_points()
)
    # cartesian
    kpath_cart = cartesianize(kpath)
    # kpath spacing from first two kpoints
    k1, k2 = kpath_cart.paths[1][1:2]
    seg = kpath_cart.points[k2] - kpath_cart.points[k1]
    seg_norm = norm(seg)
    dk = seg_norm / n_points_first_segment

    # kpoints along path
    kpaths = Vector{Vector{Vec3{Float64}}}()
    # symmetry points
    labels = Vector{Dict{Int,Symbol}}()

    for path in kpath_cart.paths
        kpaths_line = Vector{Vec3{Float64}}()
        labels_line = Dict{Int,Symbol}()

        n_seg = length(path) - 1
        n_x_line = 0
        for j in 1:n_seg
            k1 = path[j]
            k2 = path[j + 1]

            seg = kpath_cart.points[k2] - kpath_cart.points[k1]
            seg_norm = norm(seg)

            n_x_seg = Int(round(seg_norm / dk))
            x_seg = collect(range(0, seg_norm, n_x_seg + 1))
            dvec = seg / seg_norm

            # column vector * row vector = matrix
            kpt_seg = dvec * x_seg'
            kpt_seg .+= kpath_cart.points[k1]

            if j == 1
                push!(labels_line, 1 => k1)
            else
                # remove repeated points
                popfirst!(x_seg)
                kpt_seg = kpt_seg[:, 2:end]
            end
            n_x_line += length(x_seg)
            push!(labels_line, n_x_line => k2)

            append!(kpaths_line, [v for v in eachcol(kpt_seg)])
        end

        push!(kpaths, kpaths_line)
        push!(labels, labels_line)
    end

    basis = kpath.basis
    setting = Ref(CARTESIAN)
    kpi = KPathInterpolant(kpaths, labels, basis, setting)
    # to fractional
    latticize!(kpi)

    return kpi
end

function generate_w90_kpoint_path(
    lattice::AbstractMatrix,
    kpoint_path::AbstractVector{T},
    n_points_first_segment::Integer=default_w90_kpath_num_points(),
) where {T<:AbstractVector}
    kpath = generate_kpath(lattice, kpoint_path)
    return generate_w90_kpoint_path(kpath, n_points_first_segment)
end

"""
    $(SIGNATURES)

Get a 1D vector of distance from the 1st kpoint along the kpath.

# Arguments
- `kpi`: a `KPathInterpolant`

# Return
- `x`: a vector containing the distance of each kpoint w.r.t. the 1st kpoint.
    Can be used as the x-axis value for plotting band structures, in Cartesian length.
"""
function get_linear_path(kpi::KPathInterpolant)
    kpi_cart = cartesianize(kpi)
    x = Vector{Float64}()

    for path in kpi_cart.kpaths
        n_points = length(path)

        push!(x, 0)
        for j in 2:n_points
            k1 = path[j - 1]
            k2 = path[j]
            dx = norm(k2 - k1)
            push!(x, dx)
        end
    end

    return cumsum(x)
end

"""
    $(SIGNATURES)

Get the kpoints coordinates from a `KPathInterpolant`.

# Arguments
- `kpi`: `KPathInterpolant`

# Return
- `kpoints`: a length-`n_kpoints` vector, each element is a kpath kpoint
    fractional coordinates
"""
function get_kpoints(kpi::KPathInterpolant)
    return map(latticize(kpi)) do k
        Vec3(k)
    end
end

"""
    $(SIGNATURES)

Get a `Brillouin.KPath` for arbitrary cell (can be non-standard).

Internally use `Brillouin.jl`.

# Arguments
- `lattice`: `3 * 3`, each column is a lattice vector
- `atom_positions`: `3 * n_atoms`, fractional coordinates
- `atom_numbers`: `n_atoms` of integer, atomic numbers
"""
function generate_kpath(
    lattice::AbstractMatrix, atom_positions::AbstractVector, atom_numbers::AbstractVector{T}
) where {T<:Integer}
    vecs = [v for v in eachcol(lattice)]
    cell = Spglib.Cell(vecs, Vector.(atom_positions), atom_numbers)
    kpath = irrfbz_path(cell)
    return kpath
end

"""
    $(SIGNATURES)

Get a `Brillouin.KPath` for arbitrary cell (can be non-standard).

Internally use `Brillouin.jl`.

# Arguments
- `lattice`: `3 * 3`, each column is a lattice vector
- `atom_positions`: `3 * n_atoms`, fractional coordinates
- `atom_labels`: `n_atoms` of string, atomic labels
"""
function generate_kpath(
    lattice::AbstractMatrix, atom_positions::AbstractVector, atom_labels::AbstractVector{T}
) where {T<:AbstractString}
    atom_numbers = get_atom_number(atom_labels)
    return generate_kpath(lattice, atom_positions, atom_numbers)
end

"""
    $(SIGNATURES)

Generate a `KPath` for the `Model`.
"""
function generate_kpath(model::Model)
    return generate_kpath(model.lattice, model.atom_positions, model.atom_labels)
end