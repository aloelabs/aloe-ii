// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.15;

import "@rari-capital/solmate/src/utils/FixedPointMathLib.sol";

import {FixedPoint96} from "src/libraries/FixedPoint96.sol";
import {FullMath} from "src/libraries/FullMath.sol";
import {TickMath} from "src/libraries/TickMath.sol";
import {Uniswap} from "src/libraries/Uniswap.sol";

import {Kitty} from "src/Kitty.sol";
import "src/UniswapHelper.sol";

interface IManager {
    function callback(bytes calldata data) external returns (Uniswap.Position[] memory positions);
}

contract MarginAccount is UniswapHelper {
    using SafeERC20 for IERC20;
    using Uniswap for Uniswap.Position;

    uint8 public constant B = 2;

    uint256 public constant MIN_SIGMA = 2e16;

    uint256 public constant MAX_SIGMA = 15e16;

    Kitty public immutable KITTY0;

    Kitty public immutable KITTY1;

    address public immutable OWNER;

    struct PackedSlot {
        bool isInCallback;
        bool isLocked;
    }

    PackedSlot public packedSlot;

    Uniswap.Position[] uniswapPositions;

    constructor(
        IUniswapV3Pool _pool,
        Kitty _kitty0,
        Kitty _kitty1,
        address _owner
    ) UniswapHelper(_pool) {
        KITTY0 = _kitty0;
        KITTY1 = _kitty1;
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

    function _isSolvent(
        Uniswap.Position[] memory _uniswapPositions,
        int24 _arithmeticMeanTick,
        uint256 _feeGrowthGlobal0X128,
        uint256 _feeGrowthGlobal1X128,
        uint256 _sigma
    ) private view returns (bool) {
        (uint160 a, uint160 b) = _computeProbePrices(TickMath.getSqrtRatioAtTick(_arithmeticMeanTick), _sigma);
        // TODO lots of for-loop optimization to be done across getFixedAssets and the 2 calls to getFluidAssets

        (uint256 liabilities0, uint256 liabilities1) = _getLiabilities();
        (uint256 fixedAssets0, uint256 fixedAssets1, uint256 fluidAssets1A, uint256 fluidAssets1B) = _getAssets(
            _uniswapPositions,
            _arithmeticMeanTick,
            _feeGrowthGlobal0X128,
            _feeGrowthGlobal1X128,
            a,
            b,
            true // TODO
        );

        // liquidation incentive
        liabilities0 = FullMath.mulDiv(liabilities0, 1.08e18, 1e18);
        liabilities1 = FullMath.mulDiv(liabilities1, 1.08e18, 1e18);

        // combine
        uint224 priceX96;
        uint256 liabilities;
        uint256 assets;

        priceX96 = uint224(FullMath.mulDiv(a, a, FixedPoint96.Q96));
        liabilities = liabilities1 + FullMath.mulDiv(liabilities0, priceX96, FixedPoint96.Q96);
        assets = fluidAssets1A + fixedAssets1 + FullMath.mulDiv(fixedAssets0, priceX96, FixedPoint96.Q96);
        if (liabilities > assets) return false;

        priceX96 = uint224(FullMath.mulDiv(b, b, FixedPoint96.Q96));
        liabilities = liabilities1 + FullMath.mulDiv(liabilities0, priceX96, FixedPoint96.Q96);
        assets = fluidAssets1B + fixedAssets1 + FullMath.mulDiv(fixedAssets0, priceX96, FixedPoint96.Q96);
        if (liabilities > assets) return false;

        return true;
    }

    function _getLiabilities() private view returns (uint256 amount0, uint256 amount1) {
        amount0 = KITTY0.borrowBalanceCurrent(address(this));
        amount1 = KITTY1.borrowBalanceCurrent(address(this));
    }

    function _getAssets(
        Uniswap.Position[] memory _uniswapPositions,
        int24 _arithmeticMeanTick,
        uint256 _feeGrowthGlobal0X128,
        uint256 _feeGrowthGlobal1X128,
        uint160 _a,
        uint160 _b,
        bool _includeKittyReceipts
    )
        private
        view
        returns (
            uint256 fixed0,
            uint256 fixed1,
            uint256 fluid1A,
            uint256 fluid1B
        )
    {
        fixed0 = TOKEN0.balanceOf(address(this));
        fixed1 = TOKEN1.balanceOf(address(this));
        if (_includeKittyReceipts) {
            fixed0 += KITTY0.balanceOfUnderlying(address(this));
            fixed1 += KITTY1.balanceOfUnderlying(address(this));
        }

        for (uint256 i; i < _uniswapPositions.length; i++) {
            Uniswap.PositionInfo memory info = _uniswapPositions[i].info(UNISWAP_POOL);

            (uint256 temp0, uint256 temp1) = _uniswapPositions[i].fees(
                UNISWAP_POOL,
                info,
                _arithmeticMeanTick,
                _feeGrowthGlobal0X128,
                _feeGrowthGlobal1X128
            );
            fixed0 += temp0;
            fixed1 += temp1;

            fluid1A += _uniswapPositions[i].valueOfLiquidity(_a, info.liquidity);
            fluid1B += _uniswapPositions[i].valueOfLiquidity(_b, info.liquidity);
        }
    }

    // ⬆️⬆️⬆️⬆️ VIEW FUNCTIONS ⬆️⬆️⬆️⬆️  ------------------------------------------------------------------------------
    // ⬇️⬇️⬇️⬇️ PURE FUNCTIONS ⬇️⬇️⬇️⬇️  ------------------------------------------------------------------------------

    function _computeProbePrices(uint160 _sqrtMeanPriceX96, uint256 _sigma)
        private
        pure
        returns (uint160 a, uint160 b)
    {
        _sigma *= B;

        if (_sigma < MIN_SIGMA) _sigma = MIN_SIGMA;
        else if (_sigma > MAX_SIGMA) _sigma = MAX_SIGMA;

        a = uint160(FullMath.mulDiv(_sqrtMeanPriceX96, FixedPointMathLib.sqrt(1e18 - _sigma), 1e9)); // TODO don't need FullMath here. more gas efficient to use standard * and / ?
        b = uint160(FullMath.mulDiv(_sqrtMeanPriceX96, FixedPointMathLib.sqrt(1e18 + _sigma), 1e9));
    }
}
