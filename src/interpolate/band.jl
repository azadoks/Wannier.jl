using LinearAlgebra

function ufft(
    O_k::Array{Complex{T},5}, kpoints::Matrix{T}, xyz_k::Array{Int,3}
) where {T<:Real}
    m, n, nx, ny, nz = size(O_k)
    nk = size(kpoints, 2)

    O_R = zeros(Complex{T}, m, n, nx, ny, nz)

    for rx in 1:nx, ry in 1:ny, rz in 1:nz
        for kx in 1:nx, ky in 1:ny, kz in 1:nz
            ik = xyz_k[kx, ky, kz]
            kpt = kpoints[:, ik]
            fac = exp(-im * 2π * dot(kpt, [rx - 1; ry - 1; rz - 1]))
            O_R[:, :, rx, ry, rz] += fac * O_k[:, :, kx, ky, kz]
        end
    end

    return O_R
end

"""
nonuniform ifft for several kpoints.

    O_R: real space operator, i.e. in the frequency domain
    kpoints: kpoints in fractional coordinates, 3 x n_kpts
"""
function nuifft(O_R::Array{Complex{T},5}, kpoints::Matrix{T}) where {T<:Real}
    m, n, nx, ny, nz = size(O_R)

    nk = size(kpoints, 2)
    O_k = zeros(Complex{T}, m, n, nk)

    for ik in 1:nk
        for rx in 1:nx, ry in 1:ny, rz in 1:nz
            kpt = kpoints[:, ik]
            fac = exp(im * 2π * dot(kpt, [rx - 1; ry - 1; rz - 1]))
            O_k[:, :, ik] += fac * O_R[:, :, rx, ry, rz]
        end
    end

    O_k ./= (nx * ny * nz)

    return O_k
end

"""
From kspace operator defined on a list of kpoints,
to a 5 dimensional array defined on x, y, z.
"""
function Ok_xyz(Ok::Array{T,3}, xyz_k::Array{Int,3}) where {T<:Number}
    m, n, nk = size(Ok)
    nx, ny, nz = size(xyz_k)

    nk != nx * ny * nz && error("nk != nx * ny * nz")

    O_xyz = similar(Ok, m, n, nx, ny, nz)

    for i in 1:nx, j in 1:ny, k in 1:nz
        O_xyz[:, :, i, j, k] = Ok[:, :, xyz_k[i, j, k]]
    end

    return O_xyz
end

function get_Hk(E::Matrix{T}, A::Array{U,3}) where {T<:Number,U<:Number}
    n_bands, n_wann, n_kpts = size(A)
    size(E) != (n_bands, n_kpts) && error("size(E) != (n_bands, n_kpts)")

    Hk = zeros(U, n_bands, n_bands, n_kpts)
    for ik in 1:n_kpts
        Hk[:, :, ik] = A[:, :, ik]' * Diagonal(E[:, ik]) * A[:, :, ik]
    end

    return Hk
end

"""
interpolate band structure along a kpath
kpoints: interpolated kpoints in fractional coordinates, 3 x n_kpts, can be nonuniform.
"""
function interpolate(model::Model{T}, kpoints::Matrix{T}) where {T<:Real}
    n_kx, n_ky, n_kz = model.kgrid
    k_xyz, xyz_k = get_kpoint_mappings(model.kpoints, model.kgrid)

    n_wann = model.n_wann

    # n_bands x n_bands x n_kpts
    H_k = get_Hk(model.E, model.A)
    # n_bands x n_bands x n_kx x n_ky x n_kz
    H_k = Ok_xyz(H_k, xyz_k)

    # H_R = zeros(Complex{T}, n_wann, n_wann, n_kx, n_ky, n_kz)
    # bring to R space
    # for m = 1:n_wann
    #     for n = 1:n_wann
    #         H_R[m, n, :, :, :] = FFTW.fft(H_k[m, n, :, :, :], [3, 4, 5])
    #     end
    # end
    # H_R .= FFTW.fft(H_k, [3, 4, 5])

    # n_bands x n_bands x n_kx x n_ky x n_kz
    H_R = ufft(H_k, model.kpoints, xyz_k)

    # default fftfreq(4, 1) = [0.0  0.25  -0.5  -0.25]
    # same as kmesh.pl, but if user use a different kgrid,
    # the results is wrong.
    model.kpoints[:, 1] ≉ zeros(T, 3) && error("kpoints[:, 0] ≉ zeros(3)")

    # A simple inverse fft on parallelepiped cell has very bad interpolation
    # H_kpath = nuifft(H_R, kpoints)

    n_kpath_points = size(kpoints, 2)

    atol = 1e-10
    H_kpath = zeros(Complex{T}, n_wann, n_wann, n_kpath_points)
    kx = 2π * kpoints[1, :]
    ky = 2π * kpoints[2, :]
    kz = 2π * kpoints[3, :]
    for m in 1:n_wann, n in 1:n_wann
        # TODO: nufft3d2many
        H_kpath[m, n, :] = FINUFFT.nufft3d2(
            kx, ky, kz, 1, atol, H_R[m, n, :, :, :]; modeord=1
        )
        # H_kpath[:,m,n] = nuifft(
        #     kx, ky, kz, ham_R[:,:,:,m,n])
    end
    H_kpath ./= n_kx * n_ky * n_kz

    # diagonalize
    E_kpath = zeros(T, n_wann, n_kpath_points)
    for ik in 1:n_kpath_points
        H = H_kpath[:, :, ik]
        # @assert ishermitian(H) H
        # @warn norm(H - H') ik
        H = 0.5 * (H + H')
        F = eigen(H)
        E_kpath[:, ik] = real.(F.values)
    end

    return E_kpath
end
