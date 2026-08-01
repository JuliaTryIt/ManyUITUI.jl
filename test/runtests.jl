using TestItemRunner

@testitem "Aqua.jl" begin
    import Aqua
    Aqua.test_all(ManyUITUI; piracies=false)
end

@run_package_tests
