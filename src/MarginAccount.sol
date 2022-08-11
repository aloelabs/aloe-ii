// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.15;

import "@rari-capital/solmate/src/tokens/ERC20.sol";
import {SafeTransferLib} from "@rari-capital/solmate/src/utils/SafeTransferLib.sol";
import "@rari-capital/solmate/src/utils/ReentrancyGuard.sol";

import "@uniswap/v3-core/contracts/interfaces/callback/IUniswapV3MintCallback.sol";
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";

import {Uniswap} from "src/libraries/Uniswap.sol";
import {TokenPlus} from "src/TokenPlus.sol";

interface IManager {
    function callback(bytes calldata data) external returns (Uniswap.Position[] memory positions);
}

contract MarginAccount is ReentrancyGuard, IUniswapV3MintCallback {
    using SafeTransferLib for ERC20;

    IUniswapV3Pool public immutable pool;

    TokenPlus public immutable token0;

    TokenPlus public immutable token1;

    address public immutable owner;

    bool inCallback = false;

    Uniswap.Position[] uniswapPositions;

    constructor(
        IUniswapV3Pool _pool,
        TokenPlus _token0,
        TokenPlus _token1,
        address _owner
    ) {
        pool = _pool;
        token0 = _token0;
        token1 = _token1;
        owner = _owner;
    }

    // TODO liquidations

    function modify(
        address callee,
        bytes calldata data,
        uint256[4] calldata allowances
    ) external nonReentrant {
        require(msg.sender == owner, "Aloe: only owner");

        if (allowances[0] != 0) token0.approve(owner, allowances[0]);
        if (allowances[1] != 0) token1.approve(owner, allowances[1]);
        if (allowances[2] != 0) token0.asset().approve(owner, allowances[2]);
        if (allowances[3] != 0) token1.asset().approve(owner, allowances[3]);

        inCallback = true;
        Uniswap.Position[] memory _uniswapPositions = IManager(callee).callback(data);
        inCallback = false;

        if (allowances[0] != 0) token0.approve(owner, 0);
        if (allowances[1] != 0) token1.approve(owner, 0);
        if (allowances[2] != 0) token0.asset().approve(owner, 0);
        if (allowances[3] != 0) token1.asset().approve(owner, 0);

        // TODO solvency check
        // TODO copy _uniswapPositions to uniswapPositions
    }

    function borrow(uint256 amount0, uint256 amount1) external {
        require(inCallback);

        if (amount0 != 0) token0.borrow(amount0);
        if (amount1 != 0) token1.borrow(amount1);
    }

    function repay(uint256 amount0, uint256 amount1) external {
        require(inCallback);

        if (amount0 != 0) token0.repay(amount0);
        if (amount1 != 0) token1.repay(amount1);
    }

    function uniswapDeposit(
        int24 lower,
        int24 upper,
        uint128 liquidity
    ) external returns (uint256 amount0, uint256 amount1) {
        require(inCallback);

        (amount0, amount1) = pool.mint(address(this), lower, upper, liquidity, "");
    }

    function uniswapWithdraw(
        int24 lower,
        int24 upper,
        uint128 liquidity
    )
        external
        returns (
            uint256 burned0,
            uint256 burned1,
            uint256 collected0,
            uint256 collected1
        )
    {
        require(inCallback);

        (burned0, burned1) = pool.burn(lower, upper, liquidity);

        // Collect all owed tokens including earned fees
        (collected0, collected1) = pool.collect(
            address(this),
            lower,
            upper,
            type(uint128).max,
            type(uint128).max
        );
    }

    /// @dev Callback for Uniswap V3 pool.
    function uniswapV3MintCallback(
        uint256 amount0,
        uint256 amount1,
        bytes calldata
    ) external {
        require(msg.sender == address(pool));
        if (amount0 != 0) token0.asset().safeTransfer(msg.sender, amount0);
        if (amount1 != 0) token1.asset().safeTransfer(msg.sender, amount1);
    }
}
