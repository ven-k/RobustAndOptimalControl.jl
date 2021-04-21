""" The implementation is primarily based on a paper by Glover and Doyle, and
the code is best read with this docment at hand. All references to equations
in docstrings and comments are to the version of the paper given below:

  @article{glover1988state,
    title={State-space formulae for all stabilizing controllers that satisfy an
           H-infinity norm bound and relations to relations to risk sensitivity},
    author={Glover, Keith and Doyle, John C},
    journal={Systems & control letters},
    volume={11},
    number={3},
    pages={167--172},
    year={1988},
    publisher={Citeseer}
  }
"""


"""
    flag = function hinfassumptions(P::ExtendedStateSpace; verbose=true)

Check the assumptions for using the γ-iteration synthesis in Theorem 1. In
future revisions, we could suggest possible changes to P should the system not
be feasible for synthesis. However, this has not been too successful so far..!
"""
function hinfassumptions(P::ExtendedStateSpace; verbose = true)

    A, B1, B2, C1, C2, D11, D12, D21, D22 = ssdata(P)

    # Check assumption A1
    if !_stabilizable(A, B2)
        verbose && @warn(
            "The system A is not stabilizable through B2, ",
            "violation of assumption A1."
        )
        return false
    end
    if !_detectable(A, C2)
        verbose && @warn(
            "The system A is not detectable through C2, ",
            "violation of assumption A1."
        )
        return false
    end

    # Check assumption A2
    if rank(D12) < size(D12, 2)
        verbose &&
            @warn("The matrix D12 does not have full rank, ", "violation of assumption A2.")
        return false
    end
    if rank(D21) < size(D21, 1)
        verbose &&
            @warn("The matrix D21 does not have full rank, ", "violation of assumption A2.")
        return false
    end

    # Check assumption A5
    if rank(A - B2 * pinv(D12) * C1) < size(A, 1)
        verbose && @warn(
            "The matrix (A - B2*D12^-*C1) does not have full",
            "rank, violation of assumption A5."
        )
        return false
    end
    # Check assumption A6
    if rank(A - B1 * pinv(D21) * C2) < size(A, 1)
        verbose && @warn(
            "The matrix (A - B1*D21Pinv*C2) does not ",
            "have full rank, violation of assumption A6."
        )
        return false
    end

    # All assumptions have passed, and we may proceed with the synthesis
    verbose && println("All assumtions are satisfied!")
    return true
end

"""
    flag = _stabilizable(A::AbstractMatrix, B::AbstractMatrix)

Applies the Hautus lemma to check if the pair is stabilizable
"""
function _stabilizable(A::AbstractMatrix, B::AbstractMatrix)
    eigValsA = eigvals(A)
    for ii in eachindex(eigValsA)
        if real(eigValsA[ii]) >= 0
            if rank([eigValsA[ii] * I - A B]) != size(A, 1)
                return false
            end
        end
    end
    return true
end

"""
    flag = _detectable(A::AbstractMatrix, C::AbstractMatrix)

Applies the Hautus lemma to check if the pair is detectable
"""
function _detectable(A::AbstractMatrix, C::AbstractMatrix)
    eigValsA = eigvals(A)
    for ii = 1:length(eigValsA)
        if real(eigValsA[ii]) >= 0
            if rank([eigValsA[ii] * I - A; C]) != size(A, 1)
                return false
            end
        end
    end
    return true
end

"""
    flag, K, γ = hinfsynthesize(P::ExtendedStateSpace; maxIter=20, interval=(2/3,20), verbose=true)

Computes an H-infinity optimal controller K for an extended plant P such that
||F_l(P, K)||∞ < γ for the largest possible γ given P. The routine is
known as the γ-iteration, and is based on the paper "State-space formulae for
all stabilizing controllers that satisfy an H∞-norm bound and relations to
risk sensitivity" by Glover and Doyle. See the Bib-entry below [1] above.
"""
function hinfsynthesize(
    P::ExtendedStateSpace;
    maxIter = 20,
    interval = (2 / 3, 20),
    verbose = false,
    tolerance = 1e-10,
)

    # Transform the system into a suitable form
    Pbar, Ltrans12, Rtrans12, Ltrans21, Rtrans21 = _transformp2pbar(P)

    # Run the γ iterations
    XinfFeasible, YinfFeasible, FinfFeasible, HinfFeasible, gammFeasible =
        _γiterations(Pbar, maxIter, interval, verbose, tolerance)

    if !isempty(gammFeasible)
        # Synthesize the controller and trnasform it back into the original coordinates
        Ac, Bc, Cc, Dc = _synthesizecontroller(
            Pbar,
            XinfFeasible,
            YinfFeasible,
            FinfFeasible,
            HinfFeasible,
            gammFeasible,
            Ltrans12,
            Rtrans12,
            Ltrans21,
            Rtrans21,
        )

        # Return the controller, the optimal gain γ, and a true flag
        C = ss(Ac, Bc, Cc, Dc)
        γ = gammFeasible
        flag = true
    else
        # Return and empty controller, empty gain γ, and a false flag
        C = []
        γ = []
        flag = false
    end
    return flag, C, gammFeasible
end

"""
    Ac, Bc Cc, Dc = _synthesizecontroller(P::ExtendedStateSpace, Xinf, Yinf, F, H, γ, Ltrans12, Rtrans12, Ltrans21, Rtrans21)

Syntheize a controller by operating on the scaled state-space description of the
system (i.e., the state-space realization of Pbar) using the solutions from the
γ-iterations. The controller is synthesized in the coordinates of Pbar, and then
transformed back to the original coordinates by the linear transformations
Ltrans12, Rtrans12, Ltrans21 and Rtrans21.
"""
function _synthesizecontroller(
    P::ExtendedStateSpace,
    Xinf::AbstractMatrix,
    Yinf::AbstractMatrix,
    F::AbstractMatrix,
    H::AbstractMatrix,
    γ::Number,
    Ltrans12::AbstractMatrix,
    Rtrans12::AbstractMatrix,
    Ltrans21::AbstractMatrix,
    Rtrans21::AbstractMatrix,
)

    A = P.A
    B1 = P.B1
    B2 = P.B2
    C1 = P.C1
    C2 = P.C2
    D11 = P.D11
    D12 = P.D12
    D21 = P.D21
    D22 = P.D22

    gSq = γ * γ

    B = [B1 B2]
    C = [C1; C2]

    # Dimensionality
    P1 = size(C1, 1)
    P2 = size(C2, 1)
    M1 = size(B1, 2)
    M2 = size(B2, 2)

    # Equation (11)
    F11 = F[1:(M1-P2), :]
    F12 = F[(M1-P2+1):M1, :]
    F2 = F[(M1+1):(M1+M2), :]

    # Equation (12)
    H11 = H[:, 1:(P1-M2)]
    H12 = H[:, (P1-M2+1):P1]
    H2 = H[:, (P1+1):(P1+P2)]

    # Definition of D in the assumptions section
    D1111 = D11[1:(P1-M2), 1:(M1-P2)]
    D1112 = D11[1:(P1-M2), (M1-P2+1):M1]
    D1121 = D11[(P1-M2+1):P1, 1:(M1-P2)]
    D1122 = D11[(P1-M2+1):P1, (M1-P2+1):M1]

    # Equation 19
    D11hat = ((-D1121 * D1111') / (gSq * I - D1111 * D1111')) * D1112 - D1122

    # Equation 20
    D12hatD12hat = I - (D1121 / (gSq * I - D1111' * D1111)) * D1121'
    _assertrealandpsd(D12hatD12hat; msg = " in equation (20)")
    D12hat = cholesky(D12hatD12hat).L

    # Equation 21
    D21hatD21hat = I - (D1112' / (gSq * I - D1111 * D1111')) * D1112
    _assertrealandpsd(D21hatD21hat; msg = " in equation (21)")
    D21hat = cholesky(D21hatD21hat).U

    # Equation 27
    Zinv = (I - Yinf * Xinf / gSq)

    # Equation 22
    B2hat = (B2 + H12) * D12hat

    # Equation 23 (using the inverse of 27)
    C2hat = -D21hat * (C2 + F12) / Zinv

    # Equation 24
    B1hat = -H2 + (B2hat / D12hat) * D11hat

    # Equation 25 (using the inverse of 27)
    C1hat = F2 / Zinv + (D11hat / D21hat) * C2hat

    # Equation 26
    Ahat = A + H * C + (B2hat / D12hat) * C1hat

    Acontroller = Ahat

    B1controller = B1hat * Ltrans21
    B2controller = B2hat

    C1controller = Rtrans12 * C1hat
    C2controller = C2hat

    Bcontroller = [B1controller B2controller]
    Ccontroller = [C1controller; C2controller]

    D11controller = Rtrans12 * D11hat * Ltrans21
    D12controller = D12hat * Ltrans21
    D21controller = Rtrans12 * D21hat
    D22controller = zeros(size(D11hat))
    Dcontroller = [D11controller D12controller; D21controller D22controller]

    # TODO implement loop shift for any system not satisfying A4

    return Acontroller, Bcontroller[:, 1:P2], Ccontroller[1:M2, :], Dcontroller[1:M2, 1:P2]
end

"""
    _assertrealandpsd(A::AbstractMatrix, msg::AbstractString)

Check that a matrix is real and PSD - throw an error otherwise.
"""
function _assertrealandpsd(A::AbstractMatrix; msg = "")
    if any(real(eigvals(A)) .<= 0)
        error(string("The matrix", msg, " is not PSD."))
    end
    if any(imag(eigvals(A)) .!= 0)
        error(string("The matrix", msg, " is not real."))
    end
end

"""
    flag =  _checkfeasibility(Xinf, Yinf, γ, tolerance, iteration; verbose=true)

Check the feasibility of the computed solutions Xinf, Yinf and the algebraic
Riccatti equations, return true if the solution is valid, and false otherwise.
"""
function _checkfeasibility(
    Xinf::AbstractMatrix,
    Yinf::AbstractMatrix,
    γ::Number,
    tolerance::Number,
    iteration::Number;
    verbose = true,
)

    minXev = minimum(real.(eigvals(Xinf)))
    minYev = minimum(real.(eigvals(Yinf)))
    specrad = maximum(abs.(eigvals(Xinf * Yinf))) / (γ^2)

    if verbose
        if iteration == 1
            println("iteration, γ")
        end
        println(iteration, " ", γ)
    end

    if minXev < -tolerance
        # Failed test, eigenvalues of Xinf must be positive real
        return false
    end
    if minYev < -tolerance
        # Failed test, eigenvalues of Yinf must be positive real
        return false
    end
    if specrad > 1
        # Failed test, spectral radius of XY must be greater than γ squared
        return false
    end
    return true
end

"""
    solution = _solvehamiltonianare(H)

Solves a hamiltonian Alebraic Riccati equation using the Schur-decomposition,
for additional details, see

  @article{laub1979schur,
    title={A Schur method for solving algebraic Riccati equations},
    author={Laub, Alan},
    journal={IEEE Transactions on automatic control},
    volume={24},
    number={6},
    pages={913--921},
    year={1979},
    publisher={IEEE}
  }
"""
function _solvehamiltonianare(H)

    S = schur(H)
    S = ordschur(S, real.(S.values) .< 0)

    (m, n) = size(S.Z)
    U11 = S.Z[1:div(m, 2), 1:div(n, 2)]
    U21 = S.Z[div(m, 2)+1:m, 1:div(n, 2)]

    return U21 / U11
end

"""
    solution = _solvematrixequations(P::ExtendedStateSpace, γ::Number)

Solves the dual matrix equations in the γ-iterations (equations 7-12 in Doyle).
"""
function _solvematrixequations(P::ExtendedStateSpace, γ::Number)

    A = P.A
    B1 = P.B1
    B2 = P.B2
    C1 = P.C1
    C2 = P.C2
    D11 = P.D11
    D12 = P.D12
    D21 = P.D21
    D22 = P.D22

    P1 = size(C1, 1)
    P2 = size(C2, 1)
    M1 = size(B1, 2)
    M2 = size(B2, 2)

    γ² = γ * γ

    B = [B1 B2]
    C = [C1; C2]

    # Equation (7)
    D1dot = [D11 D12]
    R = [-γ²*I zeros(M1, M2); zeros(M2, M1) zeros(M2, M2)] + D1dot' * D1dot

    # Equation (8)
    Ddot1 = [D11; D21]
    Rbar = [-γ²*I zeros(P1, P2); zeros(P2, P1) zeros(P2, P2)] + Ddot1 * Ddot1'

    # Form hamiltonian for X and Y, equation (9) and (10)
    HX = [A zeros(size(A)); -C1'*C1 -A'] - ([B; -C1' * D1dot] / R) * [D1dot' * C1 B']
    HY = [A' zeros(size(A)); -B1*B1' -A] - ([C'; -B1 * Ddot1'] / Rbar) * [Ddot1 * B1' C]

    # Solve matrix equations
    Xinf = _solvehamiltonianare(HX)
    Yinf = _solvehamiltonianare(HY)

    # Equation (11)
    F = -R \ (D1dot' * C1 + B' * Xinf)

    # Equation (12)
    H = -(B1 * Ddot1' + Yinf * C') / Rbar

    return Xinf, Yinf, F, H
end

"""
    flag = _γiterations(A, B1, B2, C1, C2, D11, D12, D21, D22, maxIter, interval, verbose, tolerance)

Rune the complete set of γ-iterations over a specified search interval with a
set number of iterations. It is possible to break the algorithm if the number
of iterations become too large. This should perhaps be tken care of by
specifying an interval and tolerance for γ. In addition, the algorithm simply
terminates without a solution if the maximum possible γ on the defined
interval is infeasible. Here we could consider increasing the bounds somewhat
and warn the user if this occurrs.
"""
function _γiterations(
    P::ExtendedStateSpace,
    maxIter::Number,
    interval::Tuple,
    verbose::Bool,
    tolerance::Number,
)

    XinfFeasible, YinfFeasible, FinfFeasible, HinfFeasible, gammFeasible =
        [], [], [], [], []

    γ = maximum(interval)

    for iteration = 1:maxIter

        # Solve the matrix equations
        Xinf, Yinf, F, H = _solvematrixequations(P, γ)

        # Check Feasibility
        isFeasible =
            _checkfeasibility(Xinf, Yinf, γ, tolerance, iteration; verbose = verbose)

        if isFeasible
            XinfFeasible = Xinf
            YinfFeasible = Yinf
            FinfFeasible = F
            HinfFeasible = H
            gammFeasible = γ
            γ = γ - abs.(interval[2] - interval[1]) / (2^iteration)
        else
            γ = γ + abs.(interval[2] - interval[1]) / (2^iteration)
            if γ > maximum(interval)
                break
            end
        end
    end
    return XinfFeasible, YinfFeasible, FinfFeasible, HinfFeasible, gammFeasible
end

"""
    Pbar, Ltrans12, Rtrans12, Ltrans21, Rtrans21 = _transformP2Pbar(P::ExtendedStateSpace)

Transform the original system P to a new system Pbar, in which D12bar = [0; I]
and D21bar = [0 I] in order to satisfy the feasibility assumption A3 (see Doyle)
"""
function _transformp2pbar(P::ExtendedStateSpace)

    # Compute the transformation
    Ltrans12, Rtrans12 = _scalematrix(P.D12)
    Ltrans21, Rtrans21 = _scalematrix(P.D21)

    # Transform the system
    Abar = P.A
    B1bar = P.B1 * Rtrans21
    B2bar = P.B2 * Rtrans12
    C1bar = Ltrans12 * P.C1
    C2bar = Ltrans21 * P.C2
    D11bar = Ltrans12 * P.D11 * Rtrans21
    D12bar = Ltrans12 * P.D12 * Rtrans12
    D21bar = Ltrans21 * P.D21 * Rtrans21
    D22bar = Ltrans21 * P.D22 * Rtrans12
    Pbar = ss(Abar, B1bar, B2bar, C1bar, C2bar, D11bar, D12bar, D21bar, D22bar)

    return Pbar, Ltrans12, Rtrans12, Ltrans21, Rtrans21
end

"""
    Tl, Tr = _scalematrix(A::AbstractMatrix; method::String)

Find a left and right transform of A such that Tl*A*Tr = [I, 0], or
Tl*A*Tr = [I; 0], depending on the dimensionality of A.
"""
function _scalematrix(A::AbstractMatrix; method = "QR"::String)
    # Check the rank condition
    if (minimum(size(A)) > 0)
        if rank(A) != minimum(size(A))
            error(ErrorException("Cannot scale the system, assumption A2 is violated"))
        end
    else
        error(
            ErrorException(
                "Cannot scale the system, minimum size of A must begreater than 0",
            ),
        )
    end

    # Perform scaling with the cosen method
    if method == "QR"
        return _coordinatetransformqr(A)
    elseif method == "SVD"
        return _coordinatetransformsvd(A)
    else
        error(
            ErrorException(
                string(
                    "The method",
                    method,
                    " is not supported, use 'QR' or 'SVD' instad.",
                ),
            ),
        )
    end
end

"""
    Tl, Tr =  _computeCoordinateTransformQR(A::AbstractMatrix)

Use the QR decomposition to find a transformaiton [Tl, Tr] such that
Tl*A*Tr becomes [0;I], [0 I] or I depending on the dimensionality of A.
"""
function _coordinatetransformqr(A::AbstractMatrix)
    m, n = size(A)
    if m == n
        # Square matrix with full rank
        Q, R = qr(A)
        LeftTransform = Q'
        RightTransform = inv(R)
    elseif m > n
        # Rectangular matrix with rank = n
        Q, R = qr(A)
        LeftTransform = [Q[:, (n+1):(m)]'; Q[:, 1:n]']
        RightTransform = inv(R[1:n, 1:n])
    elseif m < n
        # Rectangular matrix with rank = m
        Q, R = qr(A')
        LeftTransform = inv(R[1:m, 1:m])'
        RightTransform = [Q[:, m+1:n] Q[:, 1:m]]
    end
    return LeftTransform, RightTransform
end

"""
    Tl, Tr =  _computeCoordinateTransformSVD(A::AbstractMatrix)

Use the SVD to find a transformaiton [Tl, Tr] such that
Tl*A*Tr becomes [0;I], [0 I] or I depending on the dimensionality of A.
"""
function _coordinatetransformsvd(A::AbstractMatrix)
    m, n = size(A)
    if m == n
        # Square matrix with full rank
        U, S, V = svd(A)
        LeftTransform = inv(Diagonal(S)) * U'
        RightTransform = V
    elseif m > n
        # Rectangular matrix with rank = n
        U, S, V = svd(A; full = true)
        LeftTransform = [U[:, n+1:m]'; inv(Diagonal(S)) * U[:, 1:n]']
        RightTransform = V
    elseif m < n
        # Rectangular matrix with rank = m
        U, S, V = svd(A; full = true)
        LeftTransform = inv(Diagonal(S)) * U'
        RightTransform = [V[:, m+1:n] V[:, 1:m]]
    end
    return LeftTransform, RightTransform
end

"""
    P = hInf_partition(G, WS, WU, WT)

This is a relly ugly function which should be re-written using the new type
ExtendedStateSpace in the event of time. The reason for it's current appearance
is that I wanted to be absolutely sure that it was doing what I wanted it to do.

Transform a SISO or MIMO system G, with weighting functions WS, WU, WT into
and LFT with an isolated controller, and write the resulting system, P(s),
on a state-space form. Valid inputs for G are transfer functions (with dynamics,
can be both MIMO and SISO, both in tf and ss forms). Valid inputs for the
weighting functions are empty entries, numbers (static gains), and transfer
fucntion objects on a the trasfer function or the state-space form.
"""
function hinfpartition(G::Any, WS::Any, WU::Any, WT::Any)
    # Convert the systems into state-space form
    Ag, Bg, Cg, Dg = _input2ss(G)
    Asw, Bsw, Csw, Dsw = _input2ss(WS)
    Auw, Buw, Cuw, Duw = _input2ss(WU)
    Atw, Btw, Ctw, Dtw = _input2ss(WT)

    # Check that the system is realizable
    if size(Cg, 1) != size(Btw, 2) && size(Btw, 2) != 0
        println([size(Cg, 1), size(Btw, 2)])
        throw(
            DimensionMismatch(
                "You must have the same number of outputs y=C2xg+D21w+D22u as there are inputs to WT",
            ),
        )
    end
    if size(Cg, 1) != size(Bsw, 2) && size(Bsw, 2) != 0
        println([size(Cg, 1), size(Bsw, 2)])
        error(
            DimensionMismatch(
                "You must have the same number of states x=Agxg+B1w+B2u as there are inputs to WS",
            ),
        )
    end
    if size(Bg, 2) != size(Buw, 2) && size(Buw, 2) != 0
        println([size(Bg, 2), size(Buw, 2)])
        error(
            DimensionMismatch(
                "You must have the same number of controls u as there are inputs to WU",
            ),
        )
    end
    if (
        size(Ag, 1) == 0 ||
        size(Ag, 2) == 0 ||
        size(Bg, 1) == 0 ||
        size(Bg, 2) == 0 ||
        size(Cg, 1) == 0 ||
        size(Cg, 2) == 0 ||
        size(Dg, 1) == 0 ||
        size(Dg, 2) == 0
    )
        error(
            DimensionMismatch(
                "Expansion of systems dimensionless A,B,C or D is not yet supported",
            ),
        )
    end

    # Form A
    (mAg, nAg) = size(Ag)
    (mAsw, nAsw) = size(Asw)
    (mAuw, nAuw) = size(Auw)
    (mAtw, nAtw) = size(Atw)

    if size(Bsw, 1) != 0 && size(Bsw, 2) != 0
        BswCg = Bsw * Cg
    else
        BswCg = zeros(mAsw, nAg)
    end
    if size(Btw, 1) != 0 && size(Btw, 2) != 0
        BtwCg = Btw * Cg
    else
        BtwCg = zeros(mAtw, nAg)
    end

    @debug ([(mAg, nAg), (mAsw, nAsw), (mAuw, nAuw), (mAtw, nAtw)])
    A = [
        Ag zeros(mAg, nAsw) zeros(mAg, nAuw) zeros(mAg, nAtw)
        -BswCg Asw zeros(mAsw, nAuw) zeros(mAsw, nAtw)
        zeros(mAuw, nAg) zeros(mAuw, nAsw) Auw zeros(mAuw, nAtw)
        BtwCg zeros(mAtw, nAsw) zeros(mAtw, nAuw) Atw
    ]

    if size(Buw, 2) == 0
        Buw = zeros(0, size(Bg, 2))
    end

    (mBg, nBg) = size(Bg)
    (mBsw, nBsw) = size(Bsw)
    (mBuw, nBuw) = size(Buw)
    (mBtw, nBtw) = size(Btw)

    Bw = [zeros(mBg, nBsw); Bsw; zeros(mBuw, nBsw); zeros(mAtw, nBsw)]
    Bu = [Bg; zeros(mBsw, nBg); Buw; zeros(mAtw, nBg)]

    (mCg, nCg) = size(Cg)
    (mCsw, nCsw) = size(Csw)
    (mCuw, nCuw) = size(Cuw)
    (mCtw, nCtw) = size(Ctw)

    if size(Dsw, 1) != 0 && size(Dsw, 1) != 0
        DswCg = Dsw * Cg
    else
        DswCg = zeros(0, nAg)
    end
    if size(Dtw, 1) != 0 && size(Dtw, 1) != 0
        DtwCg = Dtw * Cg
    else
        DtwCg = zeros(0, nAg)
    end

    Cz = [
        -DswCg Csw zeros(mCsw, nAuw) zeros(mCsw, nAtw)
        zeros(mCuw, nAg) zeros(mCuw, nAsw) Cuw zeros(mCuw, nAtw)
        DtwCg zeros(mCtw, nAsw) zeros(mCtw, nAuw) Ctw
    ]
    Cy = [-Cg zeros(mCg, nAsw) zeros(mCg, nAuw) zeros(mCg, nAtw)]


    if size(Duw, 2) == 0
        Duw = zeros(0, size(Bg, 2))
    end

    (mDg, nDg) = size(Dg)
    (mDsw, nDsw) = size(Dsw)
    (mDuw, nDuw) = size(Duw)
    (mDtw, nDtw) = size(Dtw)

    Dzw = [Dsw; zeros(mDuw, nDsw); zeros(mDtw, nDsw)]
    Dzu = [zeros(mDsw, nDuw); Duw; zeros(mDtw, nDuw)]
    Dyw = Matrix{Float64}(I, mCg, nDuw)
    Dyu = -Dg

    P = ss(A, Bw, Bu, Cz, Cy, Dzw, Dzu, Dyw, Dyu)
    return P
end

"""
    convert_input_to_ss(H)

Help function used for type conversion in hinfpartition()
"""
function _input2ss(H::Any)
    if isa(H, LTISystem)
        if isa(H, TransferFunction)
            Hss = ss(H)
        else
            Hss = H
        end
        Ah, Bh, Ch, Dh = Hss.A, Hss.B, Hss.C, Hss.D
    elseif isa(H, Number)
        Ah, Bh, Ch, Dh = zeros(0, 0), zeros(0, 1), zeros(1, 0), H * ones(1, 1)
    else
        Ah, Bh, Ch, Dh = zeros(0, 0), zeros(0, 0), zeros(0, 0), zeros(0, 0)
    end
    return Ah, Bh, Ch, Dh
end

"""
    hinfsignals(P::ExtendedStateSpace, G::LTISystem, C::LTISystem)

Use the extended state-space model, a plant and the found controller to extract
the closed loop transfer functions operating solely on the state-space.

- `Pcl : w → z` : From input to the weighted functions
- `S   : w → e` : From input to error
- `CS  : w → u` : From input to control
- `T   : w → y` : From input to output
"""
function hinfsignals(P::ExtendedStateSpace, G::LTISystem, C::LTISystem)

    common_timeevol(P,G,C)
    A, B1, B2, C1, C2, D11, D12, D21, D22 = ssdata(P)
    Ag, Bg, Cg, Dg = ssdata(ss(G))
    Ac, Bc, Cc, Dc = ssdata(ss(C))

    # Precompute the inverse
    M = inv(I - Dc * D22)
    A11 = A + B2 * M * Dc * C2
    A12 = B2 * M * Cc
    A21 = Bc * C2 + Bc * D22 * M * Dc * C2
    A22 = Ac + Bc * D22 * M * Cc
    B11 = B1 + B2 * M * Dc * D21
    B21 = Bc * D21 + Bc * D22 * M * Dc * D21

    C_w2z_11 = C1 + D12 * M * Dc * C2
    C_w2z_12 = D12 * M * Cc
    D_w2z = D11 + D12 * M * Dc * D21

    Pw2z = ss([A11 A12; A21 A22], [B11; B21], [C_w2z_11 C_w2z_12], D_w2z, timeevol(P))

    C_w2e_11 = C2 + D22 * M * Dc * C2
    C_w2e_12 = D22 * M * Cc
    D_w2e = D21 + D22 * M * Dc * D21

    Pw2e = ss([A11 A12; A21 A22], [B11; B21], [C_w2e_11 C_w2e_12], D_w2e, timeevol(P))

    C_w2u_11 = M * Dc * C2
    C_w2u_12 = M * Cc
    D_w2u = M * Dc * D21

    Pw2u = ss([A11 A12; A21 A22], [B11; B21], [C_w2u_11 C_w2u_12], D_w2u, timeevol(P))

    Abar = [A11 A12; A21 A22]
    Bbar = [B11; B21]
    C_w2y_11 = M * Dc * C2
    C_w2y_12 = M * Cc
    D_w2y = M * Dc * D21
    Cbar1 = [Cg zeros(size(Cg, 1), size(Abar, 2) - size(Cg, 2))]
    Cbar2 = [Dg * C_w2y_11 Dg * C_w2y_12]
    Dbar = Dg * M * Dc * D21

    Pw2y = ss(Abar, Bbar, Cbar1 + Cbar2, Dbar, timeevol(P))

    Pcl = Pw2z
    S = Pw2e
    CS = Pw2u
    T = Pw2y

    return Pcl, S, CS, T
end


"""
    bilineard2c(Ad::AbstractArray, Bd::AbstractArray, Cd::AbstractArray, Dd::AbstractArray, Ts::Number; tolerance=1e-12)

Balanced Bilinear transformation in State-Space. This method computes a
continuous time equivalent of a discrete time system, such that

    G_c(z) = z2s[G_d(z)]

in a manner which accomplishes the following
  (i)   Preserves the infinity L-infinity norm over the transformation
  (ii)  Finds a system which balances B and C, in the sense that ||B||_2=||C||_2
  (iii) Satisfies G_d(z) = s2z[z2s[G_d(z)]] for some map s2z[]
"""
function bilineard2c(
    Ad::AbstractArray,
    Bd::AbstractArray,
    Cd::AbstractArray,
    Dd::AbstractArray,
    Ts::Number;
    tolerance = 1e-12,
)

    Id = Matrix{Float64}(I, size(Ad, 1), size(Ad, 2))

    Pd = Ad - Id
    Qd = Ad + Id
    ialpha = 2 / Ts #Should be this, but the nyquist frequency doesnt add up unless
    ialpha = 1 / Ts

    Ac = ialpha * (Pd / Qd)
    Bc = Qd \ Bd
    Cc = 2 * ialpha * (Cd / Qd)
    Dc = Dd - (Cd / Qd) * Bd

    # Scaling for improved numerical stability
    σB = maximum(svd(Bc).S)
    σC = maximum(svd(Cc).S)
    if σB > tolerance && σC > tolerance
        λd = sqrt(σB / σC)
    else
        λd = 1
        error(
            "Warning, the problem is poorly cnditioned. Consider an alternate discretization scheme.",
        )
    end
    Bc /= λd
    Cc *= λd

    return Ac, Bc, Cc, Dc
end

"""
    bilineard2c(sys::StateSpace)

Applies a Balanced Bilinear transformation to continuous-time statespace object
"""
function bilineard2c(sys::StateSpace)
    Ad, Bd, Cd, Dd = ssdata(sys)
    Ts = sys.Ts

    if Ts <= 0
        error("Error, the input must be a discrete time system.")
    end

    Ac, Bc, Cc, Dc = bilineard2c(Ad, Bd, Cd, Dd, Ts)
    return ss(Ac, Bc, Cc, Dc)
end

"""
    bilineard2c(sys::ExtendedStateSpace)

Applies a Balanced Bilinear transformation to continuous-time extended statespace object
"""
function bilineard2c(sys::ExtendedStateSpace)
    Ad = get_A(sys)
    Bd = get_B(sys)
    Cd = get_C(sys)
    Dd = get_D(sys)
    Ts = sys.Ts

    m1 = size(get_B1(sys), 2)
    m2 = size(get_B2(sys), 2)
    p1 = size(get_C1(sys), 1)
    p2 = size(get_C2(sys), 1)

    if Ts <= 0
        error("Error, the input must be a discrete time system.")
    end

    Ac, Bc, Cc, Dc = bilineard2c(Ad, Bd, Cd, Dd, Ts)

    A = Ac
    B1 = Bc[:, 1:m1]
    B2 = Bc[:, (m1+1):(m1+m2)]
    C1 = Cc[1:p1, :]
    C2 = Cc[(p1+1):(p1+p2), :]
    D11 = Dc[1:p1, 1:m1]
    D12 = Dc[1:p1, (m1+1):(m1+m2)]
    D21 = Dc[(p1+1):(p1+p2), 1:m1]
    D22 = Dc[(p1+1):(p1+p2), (m1+1):(m1+m2)]

    return ss(A, B1, B2, C1, C2, D11, D12, D21, D22)
end

"""
    bilinearc2d(Ac::AbstractArray, Bc::AbstractArray, Cc::AbstractArray, Dc::AbstractArray, Ts::Number; tolerance=1e-12)

Balanced Bilinear transformation in State-Space. This method computes a
discrete time equivalent of a continuous-time system, such that

    G_d(z) = s2z[G_c(s)]

in a manner which accomplishes the following
  (i)   Preserves the infinity L-infinity norm over the transformation
  (ii)  Finds a system which balances B and C, in the sense that ||B||_2=||C||_2
  (iii) Satisfies G_c(s) = z2s[s2z[G_c(s)]] for some map z2s[]
"""
function bilinearc2d(
    Ac::AbstractArray,
    Bc::AbstractArray,
    Cc::AbstractArray,
    Dc::AbstractArray,
    Ts::Number;
    tolerance = 1e-12,
)

    Id = Matrix{Float64}(I, size(Ac, 1), size(Ac, 2))
    alpha = Ts / 2 #Should be this, but the nyquist frequency doesnt add up
    alpha = Ts

    # Check that the bilinear tranformation is possible
    if minimum(svd(Id - alpha * Ac).S) < 1e-12
        error(
            "The transformation is extremely poorly conditioned, with min(svd(Id - alpha * Ac).S) < 1e-12. Consider an alternate discretization scheme.",
        )
    end

    PP = Id - alpha * Ac
    QQ = Id + alpha * Ac

    Ad = PP \ QQ
    Bd = (PP \ Bc)
    Cd = 2 * alpha * (Cc / PP)

    # Scaling for improved numerical stability
    σB = maximum(svd(Bd).S)
    σC = maximum(svd(Cd).S)
    if σB > tolerance && σC > tolerance
        λc = sqrt(σB / σC)
    else
        λc = 1
        error(
            "Warning, the problem is poorly cnditioned. Consider an alternate discretization scheme.",
        )
    end

    Bd /= λc
    Cd *= λc

    Dd = alpha * Cc / PP * Bc + Dc
    return Ad, Bd, Cd, Dd, Ts
end

"""
    bilinearc2d(sys::StateSpace, Ts::Number)

Applies a Balanced Bilinear transformation to a discrete-time statespace object
"""
function bilinearc2d(sys::StateSpace{Continuous}, Ts::Number)
    Ac, Bc, Cc, Dc = ssdata(sys)

    if Ts <= 0
        throw(ArgumentError("Error, the the discretization time Ts must be positive."))
    end

    Ad, Bd, Cd, Dd = bilinearc2d(Ac, Bc, Cc, Dc, Ts)
    return ss(Ad, Bd, Cd, Dd, Ts)
end

"""
    bilinearc2d(sys::ExtendedStateSpace, Ts::Number)

Applies a Balanced Bilinear transformation to a discrete-time extended statespace object
"""
function bilinearc2d(sys::ExtendedStateSpace{Continuous}, Ts::Number)
    Ac = get_A(sys)
    Bc = get_B(sys)
    Cc = get_C(sys)
    Dc = get_D(sys)

    m1 = size(get_B1(sys), 2)
    m2 = size(get_B2(sys), 2)
    p1 = size(get_C1(sys), 1)
    p2 = size(get_C2(sys), 1)

    if Ts <= 0
        error("Error, the the discretization time Ts must be positive.")
    end

    Ad, Bd, Cd, Dd = bilinearc2d(Ac, Bc, Cc, Dc, Ts)

    A = Ad
    B1 = Bd[:, 1:m1]
    B2 = Bd[:, (m1+1):(m1+m2)]
    C1 = Cd[1:p1, :]
    C2 = Cd[(p1+1):(p1+p2), :]
    D11 = Dd[1:p1, 1:m1]
    D12 = Dd[1:p1, (m1+1):(m1+m2)]
    D21 = Dd[(p1+1):(p1+p2), 1:m1]
    D22 = Dd[(p1+1):(p1+p2), (m1+1):(m1+m2)]

    return ss(A, B1, B2, C1, C2, D11, D12, D21, D22, Ts)
end
