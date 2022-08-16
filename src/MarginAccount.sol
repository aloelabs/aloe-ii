// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.15;

import "@rari-capital/solmate/src/utils/FixedPointMathLib.sol";

import {FixedPoint96} from "src/libraries/FixedPoint96.sol";
import {FullMath} from "src/libraries/FullMath.sol";
import {TickMath} from "src/libraries/TickMath.sol";
import {Uniswap} from "src/libraries/Uniswap.sol";

import {TokenPlus} from "src/TokenPlus.sol";
import "src/UniswapHelper.sol";

interface IManager {
    function callback(bytes calldata data) external returns (Uniswap.Position[] memory positions);
}

contract MarginAccount is UniswapHelper {
    using SafeERC20 for IERC20;

    TokenPlus public immutable KITTY0;

    TokenPlus public immutable KITTY1;

    address public immutable OWNER;

    struct PackedSlot {
        bool isInCallback;
        bool isLocked;
    }

    PackedSlot public packedSlot;

    Uniswap.Position[] uniswapPositions;

    constructor(
        IUniswapV3Pool _pool,
        TokenPlus _token0,
        TokenPlus _token1,
        address _owner
    ) UniswapHelper(_pool) {
        KITTY0 = _token0;
        KITTY1 = _token1;
        OWNER = _owner;
    }

    // TODO liquidations

    function modify(
        address callee,
        bytes calldata data,
        uint256[4] calldata allowances
    ) external {
        require(msg.sender == OWNER, "Aloe: only owner");
        require(!packedSlot.isLocked);
        packedSlot.isLocked = true;

        if (allowances[0] != 0) KITTY0.approve(OWNER, allowances[0]);
        if (allowances[1] != 0) KITTY1.approve(OWNER, allowances[1]);
        if (allowances[2] != 0) TOKEN0.approve(OWNER, allowances[2]);
        if (allowances[3] != 0) TOKEN1.approve(OWNER, allowances[3]);

        packedSlot.isInCallback = true;
        Uniswap.Position[] memory _uniswapPositions = IManager(callee).callback(data);
        packedSlot.isInCallback = false;

        if (allowances[0] != 0) KITTY0.approve(OWNER, 0);
        if (allowances[1] != 0) KITTY1.approve(OWNER, 0);
        if (allowances[2] != 0) TOKEN0.approve(OWNER, 0);
        if (allowances[3] != 0) TOKEN1.approve(OWNER, 0);

        // TODO solvency check
        // TODO copy _uniswapPositions to uniswapPositions
        packedSlot.isLocked = false;
    }

    function borrow(uint256 amount0, uint256 amount1) external {
        require(packedSlot.isInCallback);

        if (amount0 != 0) KITTY0.borrow(amount0);
        if (amount1 != 0) KITTY1.borrow(amount1);
    }

    function repay(uint256 amount0, uint256 amount1) external {
        require(packedSlot.isInCallback);

        if (amount0 != 0) KITTY0.repay(amount0);
        if (amount1 != 0) KITTY1.repay(amount1);
    }

    function uniswapDeposit(
        int24 lower,
        int24 upper,
        uint128 liquidity
    ) external returns (uint256 amount0, uint256 amount1) {
        require(packedSlot.isInCallback);

        (amount0, amount1) = UNISWAP_POOL.mint(address(this), lower, upper, liquidity, "");
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
        require(packedSlot.isInCallback);

        (burned0, burned1) = UNISWAP_POOL.burn(lower, upper, liquidity);

        // Collect all owed tokens including earned fees
        (collected0, collected1) = UNISWAP_POOL.collect(
            address(this),
            lower,
            upper,
            type(uint128).max,
            type(uint128).max
        );
    }

    // ⬇️⬇️⬇️⬇️ VIEW FUNCTIONS ⬇️⬇️⬇️⬇️  ------------------------------------------------------------------------------
    // ⬆️⬆️⬆️⬆️ VIEW FUNCTIONS ⬆️⬆️⬆️⬆️  ------------------------------------------------------------------------------
    // ⬇️⬇️⬇️⬇️ PURE FUNCTIONS ⬇️⬇️⬇️⬇️  ------------------------------------------------------------------------------
}
