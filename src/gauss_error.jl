include("basis.jl")
include("vector.jl")
include("config.jl")
include("check.jl")

using Optim

make_sym(A::AbstractMatrix{<:Real}) = (transpose(A) + A) / 2


"""
Model for discrete data and kernel.



```julia
GaussErrorMatrixUnfolder(
    omegas::Array{Array{T, 2}, 1} where T<:Real,
    method::String="EmpiricalBayes",
    alphas::Union{AbstractVector{<:Real}, Nothing}=nothing,
    low::Union{AbstractVector{<:Real}, Nothing}=nothing,
    high::Union{AbstractVector{<:Real}, Nothing}=nothing,
    alpha0::Union{AbstractVector{<:Real}, Nothing}=nothing
    )
```
`omegas` -- array of matrices that provide information about basis functions

`method` -- constant selection method, possible options: "EmpiricalBayes" and "User"

`alphas` -- array of constants, in case method="User" should be provided by user

`low` -- lower limits for alphas

`high` -- higher limits for alphas

`alpha0` -- unitial values for alphas

**Fields**

* `omegas::Array{Array{T, 2}, 1} where T<:Real`
* `n::Int` -- size of square omega matrix
* `method::String`
* `alphas::Union{AbstractVector{<:Real}, Nothing}`
* `low::Union{AbstractVector{<:Real}, Nothing}`
* `high::Union{AbstractVector{<:Real}, Nothing}`
* `alpha0::Union{AbstractVector{<:Real}, Nothing}`
"""
mutable struct GaussErrorMatrixUnfolder
    omegas::Array{Array{T, 2}, 1} where T<:Real
    n::Int
    method::String
    alphas::Union{AbstractVector{<:Real}, Nothing}
    low::Union{AbstractVector{<:Real}, Nothing}
    high::Union{AbstractVector{<:Real}, Nothing}
    alpha0::Union{AbstractVector{<:Real}, Nothing}

    function GaussErrorMatrixUnfolder(
        omegas::Array{Array{T, 2}, 1} where T<:Real,
        method::String="EmpiricalBayes",
        alphas::Union{AbstractVector{<:Real}, Nothing}=nothing,
        low::Union{AbstractVector{<:Real}, Nothing}=nothing,
        high::Union{AbstractVector{<:Real}, Nothing}=nothing,
        alpha0::Union{AbstractVector{<:Real}, Nothing}=nothing
        )
        m = check_args(omegas, method, alphas, low, high, alpha0)
        @info "GaussErrorMatrixUnfolder is created"
        return new(omegas, m, method, alphas, low, high, alpha0)
    end
end


"""
```julia
solve(
    unfolder::GaussErrorMatrixUnfolder,
    kernel::AbstractMatrix{<:Real},
    data::AbstractVector{<:Real},
    data_errors::AbstractVecOrMat{<:Real}
    )
```

**Arguments**
* `unfolder` -- model
* `kernel` -- discrete kernel
* `data` -- function values
* `data_errors` -- function errors

**Returns:** `Dict{String, AbstractVector{Real}}` with coefficients ("coeff"), errors ("errors") and optimal constants ("alphas").
"""
function solve(
    unfolder::GaussErrorMatrixUnfolder,
    kernel::AbstractMatrix{<:Real},
    data::AbstractVector{<:Real},
    data_errors::AbstractVecOrMat{<:Real}
    )
    @info "Starting solve..."
    data_errors = check_args(unfolder, kernel, data, data_errors)
    data_errorsInv = make_sym(pinv(data_errors))
    B = make_sym(transpose(kernel) * data_errorsInv * kernel)
    b = transpose(kernel) * transpose(data_errorsInv) * data
    alpha0 = unfolder.alpha0
    if unfolder.method == "EmpiricalBayes"
        unfolder.alphas = find_optimal_alpha(
            unfolder.omegas, B, b,
            unfolder.alpha0, unfolder.low, unfolder.high
            )
    elseif unfolder.method != "User"
        @error "Unknown method" + unfolder.method
        Base.eror("Unknown method" + unfolder.method)
    end
    Ba0 = B + transpose(unfolder.alphas) * unfolder.omegas
    iBa0 = make_sym(pinv(Ba0))
    r = iBa0 * b
    @info "Ending solve..."
    return Dict("coeff" => r, "errors" => iBa0, "alphas" => unfolder.alphas)
end


"""
Model for continuous kernel. Data can be either discrete or continuous.



```julia
GaussErrorUnfolder(
    basis::Basis,
    omegas::Array{Array{T, 2}, 1} where T<:Real,
    method::String="EmpiricalBayes",
    alphas::Union{AbstractVector{<:Real}, Nothing} =nothing,
    low::Union{AbstractVector{<:Real}, Nothing} =nothing,
    high::Union{AbstractVector{<:Real}, Nothing} =nothing,
    alpha0::Union{AbstractVector{<:Real}, Nothing} =nothing
    )
```

`basis` -- basis for reconstruction

`omegas` -- array of matrices that provide information about basis functions

`method` -- constant selection method, possible options: "EmpiricalBayes" and "User"

`alphas` -- array of constants, in case method="User" should be provided by user

`low` -- lower limits for alphas

`high` -- higher limits for alphas

`alpha0` -- unitial values for alphas

**Fields**
* `basis::Basis`
* `solver::GaussErrorMatrixUnfolder`
"""
mutable struct GaussErrorUnfolder
    basis::Basis
    solver::GaussErrorMatrixUnfolder

    function GaussErrorUnfolder(
        basis::Basis,
        omegas::Array{Array{T, 2}, 1} where T<:Real,
        method::String="EmpiricalBayes",
        alphas::Union{AbstractVector{<:Real}, Nothing} =nothing,
        low::Union{AbstractVector{<:Real}, Nothing} =nothing,
        high::Union{AbstractVector{<:Real}, Nothing} =nothing,
        alpha0::Union{AbstractVector{<:Real}, Nothing} =nothing
        )
        solver = GaussErrorMatrixUnfolder(
            omegas, method, alphas, low, high, alpha0
        )
        @info "GaussErrorUnfolder is created."
        return new(basis, solver)
    end
end


"""
```julia
solve(
    gausserrorunfolder::GaussErrorUnfolder,
    kernel::Union{Function, AbstractMatrix{<:Real}},
    data::Union{Function, AbstractVector{<:Real}},
    data_errors::Union{Function, AbstractVector{<:Real}},
    y::Union{AbstractVector{<:Real}, Nothing}=nothing,
    )
```

**Arguments**
* `gausserrorunfolder` -- model
* `kernel` -- discrete or continuous kernel
* `data` -- function values
* `data_errors` -- function errors
* `y` -- points to calculate function values and its errors (when data is given as a function)

**Returns:** `Dict{String, AbstractVector{Real} with coefficients ("coeff"), errors ("errors") and optimal constants ("alphas").
"""
function solve(
    gausserrorunfolder::GaussErrorUnfolder,
    kernel::Union{Function, AbstractMatrix{<:Real}},
    data::Union{Function, AbstractVector{<:Real}},
    data_errors::Union{Function, AbstractVector{<:Real}},
    y::Union{AbstractVector{<:Real}, Nothing}=nothing,
    )
    @info "Starting solve..."
    kernel_array, data_array, data_errors_array = check_args(
        gausserrorunfolder, kernel, data, data_errors, y
        )
    result = solve(
        gausserrorunfolder.solver,
        kernel_array, data_array, data_errors_array
        )
    @info "Ending solve..."
    return result
end
