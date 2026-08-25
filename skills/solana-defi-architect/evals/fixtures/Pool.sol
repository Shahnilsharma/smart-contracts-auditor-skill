// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @notice Minimal eval fixture — a deliberately simplified two-token constant-product pool.
/// This exists ONLY to exercise evm-defi-architect eval #2 (an audit request against an
/// existing, non-trivial contract on a non-default chain). It is intentionally small and
/// contains real, findable issues (see NOTES) rather than being production code — do not
/// deploy this as-is.
contract Pool {
    IERC20 public immutable tokenA;
    IERC20 public immutable tokenB;

    uint256 public reserveA;
    uint256 public reserveB;

    mapping(address => uint256) public lpBalance;
    uint256 public totalLp;

    event Swap(address indexed trader, address tokenIn, uint256 amountIn, uint256 amountOut);
    event LiquidityAdded(address indexed provider, uint256 amountA, uint256 amountB, uint256 lpMinted);

    constructor(address _tokenA, address _tokenB) {
        tokenA = IERC20(_tokenA);
        tokenB = IERC20(_tokenB);
    }

    // NOTE (intentional, for eval purposes): no minimum-liquidity lock on first deposit,
    // no slippage/minAmountOut parameter on swap, and no reentrancy guard despite external
    // calls before state updates in swap() — these are exactly the kind of findings the
    // audit-checklist.md categories (access control is fine here; reentrancy, input
    // validation/slippage, and MEV/front-running are NOT) should surface.

    function addLiquidity(uint256 amountA, uint256 amountB) external {
        tokenA.transferFrom(msg.sender, address(this), amountA);
        tokenB.transferFrom(msg.sender, address(this), amountB);

        uint256 lpMinted = totalLp == 0 ? amountA : (amountA * totalLp) / reserveA;
        lpBalance[msg.sender] += lpMinted;
        totalLp += lpMinted;

        reserveA += amountA;
        reserveB += amountB;

        emit LiquidityAdded(msg.sender, amountA, amountB, lpMinted);
    }

    function swap(address tokenIn, uint256 amountIn) external {
        bool isA = tokenIn == address(tokenA);
        require(isA || tokenIn == address(tokenB), "bad token");

        (IERC20 tIn, IERC20 tOut, uint256 rIn, uint256 rOut) = isA
            ? (tokenA, tokenB, reserveA, reserveB)
            : (tokenB, tokenA, reserveB, reserveA);

        uint256 amountOut = (amountIn * rOut) / (rIn + amountIn);

        // external call before reserves are updated below — reentrancy-shaped
        tIn.transferFrom(msg.sender, address(this), amountIn);
        tOut.transfer(msg.sender, amountOut);

        if (isA) {
            reserveA += amountIn;
            reserveB -= amountOut;
        } else {
            reserveB += amountIn;
            reserveA -= amountOut;
        }

        emit Swap(msg.sender, tokenIn, amountIn, amountOut);
    }
}
