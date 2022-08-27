@testset "interpolate w90 kpath" begin
    win = read_win(joinpath(FIXTURE_PATH, "valence/band/silicon.win"))
    recip_lattice = Wannier.get_recip_lattice(win.unit_cell)
    kpi, E = read_w90_band(
        joinpath(FIXTURE_PATH, "valence/band/mdrs/silicon"), recip_lattice
    )

    # num points of 1st segment
    n_points = 100
    test_kpi = Wannier.interpolate_w90(win.kpoint_path, n_points)

    @test all(isapprox.(test_kpi.kpaths, kpi.kpaths; atol=1e-5))
    # If in the kpath block of win file, there are two kpoints with same label but
    # different coordinates, I will append a number to the repeated label in read_win,
    # so I only compare label without number.
    test_labels = test_kpi.labels
    for (i, lab) in enumerate(test_labels)
        new_lab = deepcopy(lab)
        for (k, v) in lab
            sv = String(v)
            delim = "_"
            if occursin(delim, sv)
                # only remove the last number suffix
                sv = join(split(sv, delim)[1:(end - 1)], delim)
                pop!(new_lab, k)
                push!(new_lab, k => Symbol(sv))
            end
        end
        test_labels[i] = new_lab
    end
    @test test_labels == kpi.labels
    @test test_kpi.basis ≈ kpi.basis
    @test Symbol(test_kpi.setting) == Symbol(kpi.setting)
end

@testset "get x kpath" begin
    win = read_win(joinpath(FIXTURE_PATH, "valence/band/silicon.win"))
    recip_lattice = Wannier.get_recip_lattice(win.unit_cell)
    band = read_w90_band(joinpath(FIXTURE_PATH, "valence/band/mdrs/silicon"))
    kpi = Wannier.get_kpath_interpolant(
        band.kpoints, band.symm_idx, band.symm_label, recip_lattice
    )
    @test all(isapprox.(band.x, Wannier.get_x(kpi); atol=1e-5))
end