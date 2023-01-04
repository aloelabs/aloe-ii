// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.15;

import {Math} from "openzeppelin-contracts/utils/math/Math.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {ERC20, SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";

import {IUniswapV3MintCallback} from "v3-core/contracts/interfaces/callback/IUniswapV3MintCallback.sol";
import {IUniswapV3Pool} from "v3-core/contracts/interfaces/IUniswapV3Pool.sol";

import {FixedPoint96} from "./libraries/FixedPoint96.sol";
import {LiquidityAmounts} from "./libraries/LiquidityAmounts.sol";
import {Oracle} from "./libraries/Oracle.sol";
import {Positions} from "./libraries/Positions.sol";
import {TickMath} from "./libraries/TickMath.sol";
import {Uniswap} from "./libraries/Uniswap.sol";

import {Lender} from "./Lender.sol";

interface ILiquidator {
    function callback0(bytes calldata data, uint256 assets1, uint256 liabilities0) external;

    function callback1(bytes calldata data, uint256 assets0, uint256 liabilities1) external;
}

interface IManager {
    function callback(bytes calldata data) external returns (int24[] memory positions);
}

contract Borrower is IUniswapV3MintCallback {
    using SafeTransferLib for ERC20;
    using Positions for int24[6];
    using Uniswap for Uniswap.Position;

    uint8 public constant B = 3;

    uint256 public constant MIN_SIGMA = 2e16;

    uint256 public constant MAX_SIGMA = 15e16;

    /// @notice The Uniswap pair in which the vault will manage positions
    IUniswapV3Pool public immutable UNISWAP_POOL;

    /// @notice The first token of the Uniswap pair
    ERC20 public immutable TOKEN0;

    /// @notice The second token of the Uniswap pair
    ERC20 public immutable TOKEN1;

    /// @notice TODO
    Lender public immutable LENDER0;

    /// @notice TODO
    Lender public immutable LENDER1;

    struct PackedSlot {
        address owner;
        bool isInCallback;
    }

    struct SolvencyCache {
        uint160 a;
        uint160 b;
        uint160 c;
    }

    PackedSlot public packedSlot;

    int24[6] public positions;

    constructor(IUniswapV3Pool pool, Lender lender0, Lender lender1) {
        UNISWAP_POOL = pool;
        LENDER0 = lender0;
        LENDER1 = lender1;

        TOKEN0 = lender0.asset();
        TOKEN1 = lender1.asset();

        require(pool.token0() == address(TOKEN0));
        require(pool.token1() == address(TOKEN1));
    }

    function initialize(address owner) external {
        require(packedSlot.owner == address(0));
        packedSlot.owner = owner;
    }

    // TODO liquidations
    function liquidate(ILiquidator callee, bytes calldata data) external {
        require(!packedSlot.isInCallback);

        SolvencyCache memory c = _getSolvencyCache();

        Assets memory mem = _getAssetsWithdrawingPositions(c);
        (uint256 liabilities0, uint256 liabilities1) = _getLiabilities();

        uint256 liquidationIncentive = _computeLiquidationIncentive(
            mem.fixed0 + mem.fluid0C,
            mem.fixed1 + mem.fluid1C,
            liabilities0,
            liabilities1,
            c.c
        );

        uint256 priceX96;
        uint256 liabilities;
        uint256 assets;

        priceX96 = Math.mulDiv(c.a, c.a, FixedPoint96.Q96);
        liabilities = liabilities1 + Math.mulDiv(liabilities0, priceX96, FixedPoint96.Q96) + liquidationIncentive;
        assets = mem.fluid1A + mem.fixed1 + Math.mulDiv(mem.fixed0, priceX96, FixedPoint96.Q96);

        if (liabilities <= assets) {
            priceX96 = Math.mulDiv(c.b, c.b, FixedPoint96.Q96);
            liabilities = liabilities1 + Math.mulDiv(liabilities0, priceX96, FixedPoint96.Q96) + liquidationIncentive;
            assets = mem.fluid1B + mem.fixed1 + Math.mulDiv(mem.fixed0, priceX96, FixedPoint96.Q96);

            if (liabilities <= assets) revert();
        }

        uint256 assets0 = TOKEN0.balanceOf(address(this));
        if (assets0 > liabilities0) {
            TOKEN0.safeTransfer(address(LENDER0), liabilities0);
            LENDER0.repay(0, address(this));

            assets0 -= liabilities0;
            liabilities0 = 0;
        } else {
            TOKEN0.safeTransfer(address(LENDER0), assets0);
            LENDER0.repay(assets0, address(this));

            liabilities0 -= assets0;
            assets0 = 0;
        }

        uint256 assets1 = TOKEN1.balanceOf(address(this));
        if (assets1 > liabilities1) {
            TOKEN1.safeTransfer(address(LENDER1), liabilities1);
            LENDER1.repay(0, address(this));

            assets1 -= liabilities1;
            liabilities1 = 0;
        } else {
            TOKEN1.safeTransfer(address(LENDER1), assets1);
            LENDER1.repay(assets1, address(this));

            liabilities1 -= assets1;
            assets1 = 0;
        }

        // If both are zero or neither is zero, there's nothing more to do
        if (liabilities0 + liabilities1 == 0 || liabilities0 * liabilities1 > 0) {
            // TODO send pure ETH reward
        } else if (liabilities0 == 0) {
            TOKEN1.safeApprove(address(callee), type(uint256).max);
            callee.callback0(data, assets1, liabilities0);
            TOKEN1.safeApprove(address(callee), 0);

            priceX96 = Math.mulDiv(c.c, c.c, FixedPoint96.Q96);

            uint256 repay0 = liabilities0 - LENDER0.borrowBalanceStored(address(this));
            uint256 maxLoss1 = Math.mulDiv(repay0 * 1.05e9, priceX96, 1e9 * FixedPoint96.Q96);
            require(assets1 - TOKEN1.balanceOf(address(this)) <= maxLoss1);

            // TODO: conditionally send pure ETH reward
        } else {
            TOKEN0.safeApprove(address(callee), type(uint256).max);
            callee.callback1(data, assets0, liabilities1);
            TOKEN1.safeApprove(address(callee), 0);

            uint256 repay1 = liabilities1 - LENDER1.borrowBalanceStored(address(this));
            uint256 maxLoss0 = Math.mulDiv(repay1 * 1.05e9, FixedPoint96.Q96, 1e9 * priceX96);
            require(assets0 - TOKEN0.balanceOf(address(this)) <= maxLoss0);

            // TODO: conditionally send pure ETH reward
        }
    }

    function modify(IManager callee, bytes calldata data, bool[2] calldata allowances) external {
        require(msg.sender == packedSlot.owner, "Aloe: only owner");
        require(!packedSlot.isInCallback);

        if (allowances[0]) TOKEN0.safeApprove(address(callee), type(uint256).max);
        if (allowances[1]) TOKEN1.safeApprove(address(callee), type(uint256).max);

        packedSlot.isInCallback = true;
        int24[] memory positions_ = callee.callback(data);
        packedSlot.isInCallback = false;

        if (allowances[0]) TOKEN0.safeApprove(address(callee), 1);
        if (allowances[1]) TOKEN1.safeApprove(address(callee), 1);

        // Write new Uniswap positions to storage iff they're properly formatted and unique.
        // We rely on `_isSolvent` to ensure `_positions.length % 2 == 0` and that each
        // position obeys Uniswap's expectations for ticks, e.g. tickLower < tickUpper
        positions.write(positions_);

        (, int24 currentTick, , , , , ) = UNISWAP_POOL.slot0();
        require(
            _isSolvent(
                positions_,
                Uniswap.FeeComputationCache(
                    currentTick,
                    UNISWAP_POOL.feeGrowthGlobal0X128(),
                    UNISWAP_POOL.feeGrowthGlobal1X128()
                ),
                _getSolvencyCache()
            ),
            "Aloe: need more margin"
        );
    }

    function borrow(uint256 amount0, uint256 amount1, address recipient) external {
        require(packedSlot.isInCallback);

        if (amount0 != 0) LENDER0.borrow(amount0, recipient);
        if (amount1 != 0) LENDER1.borrow(amount1, recipient);
    }

    // Technically uneccessary. but:
    // --> Keep because it allows us to use transfer instead of transferFrom, saving allowance reads in the underlying asset contracts
    // --> Keep for integrator convenience
    // --> Keep because it allows integrators to repay debts without configuring the `allowances` bool array
    function repay(uint256 amount0, uint256 amount1) external {
        require(packedSlot.isInCallback);

        if (amount0 != 0) {
            TOKEN0.safeTransfer(address(LENDER0), amount0);
            LENDER0.repay(amount0, address(this));
        }
        if (amount1 != 0) {
            TOKEN1.safeTransfer(address(LENDER1), amount1);
            LENDER1.repay(amount1, address(this));
        }
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
    ) external returns (uint256 burned0, uint256 burned1, uint256 collected0, uint256 collected1) {
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

    /// @dev Callback for Uniswap V3 pool.
    function uniswapV3MintCallback(uint256 amount0, uint256 amount1, bytes calldata) external {
        require(msg.sender == address(UNISWAP_POOL));
        if (amount0 != 0) TOKEN0.safeTransfer(msg.sender, amount0);
        if (amount1 != 0) TOKEN1.safeTransfer(msg.sender, amount1);
    }

    function _getAssetsWithdrawingPositions(SolvencyCache memory c2) private returns (Assets memory assets) {
        assets.fixed0 = TOKEN0.balanceOf(address(this));
        assets.fixed1 = TOKEN1.balanceOf(address(this));

        int24[] memory positions_ = positions.read();
        uint256 count = positions_.length;
        delete positions;

        unchecked {
            for (uint256 i; i < count; i += 2) {
                uint160 L;
                uint160 U;
                uint128 liquidity;

                {
                    // Load lower and upper ticks from the `positions_` array
                    int24 l = positions_[i];
                    int24 u = positions_[i + 1];
                    // Fetch amount of `liquidity` in the position
                    (liquidity, , , , ) = UNISWAP_POOL.positions(keccak256(abi.encodePacked(address(this), l, u)));

                    // Withdraw all `liquidity` from the position, adding earned fees as fixed assets
                    (uint256 burned0, uint256 burned1) = UNISWAP_POOL.burn(l, u, liquidity);
                    (uint256 collected0, uint256 collected1) = UNISWAP_POOL.collect(
                        address(this),
                        l,
                        u,
                        type(uint128).max,
                        type(uint128).max
                    );
                    assets.fixed0 += collected0 - burned0;
                    assets.fixed1 += collected1 - burned1;

                    // Compute lower and upper sqrt ratios
                    L = TickMath.getSqrtRatioAtTick(l);
                    U = TickMath.getSqrtRatioAtTick(u);
                }

                // Compute the value of `liquidity` (in terms of token1) at both probe prices
                assets.fluid1A += LiquidityAmounts.getValueOfLiquidity(c2.a, L, U, liquidity);
                assets.fluid1B += LiquidityAmounts.getValueOfLiquidity(c2.b, L, U, liquidity);

                // Compute what amounts underlie `liquidity` at the current TWAP
                {
                    (uint256 amount0, uint256 amount1) = LiquidityAmounts.getAmountsForLiquidity(c2.c, L, U, liquidity);
                    assets.fluid0C += amount0;
                    assets.fluid1C += amount1;
                }
            }
        }
    }

    // ⬇️⬇️⬇️⬇️ VIEW FUNCTIONS ⬇️⬇️⬇️⬇️  ------------------------------------------------------------------------------

    function getUniswapPositions() public view returns (int24[] memory) {
        return positions.read();
    }

    function _getSolvencyCache() private view returns (SolvencyCache memory c) {
        (int24 arithmeticMeanTick, ) = Oracle.consult(UNISWAP_POOL, 1200);
        uint256 sigma = 0.025e18; // TODO fetch real data from the volatility oracle

        // compute prices at which solvency will be checked
        uint160 sqrtMeanPriceX96 = TickMath.getSqrtRatioAtTick(arithmeticMeanTick);
        (uint160 a, uint160 b) = _computeProbePrices(sqrtMeanPriceX96, sigma);
        c = SolvencyCache(a, b, sqrtMeanPriceX96);
    }

    function _isSolvent(
        int24[] memory positions_,
        Uniswap.FeeComputationCache memory c1,
        SolvencyCache memory c2
    ) private view returns (bool) {
        Assets memory mem = _getAssets(positions_, c1, c2);
        (uint256 liabilities0, uint256 liabilities1) = _getLiabilities();

        // liquidation incentive. counted as liability because account will owe it to someone.
        // compensates liquidators for inventory risk.
        uint256 liquidationIncentive = _computeLiquidationIncentive(
            mem.fixed0 + mem.fluid0C,
            mem.fixed1 + mem.fluid1C,
            liabilities0,
            liabilities1,
            c2.c
        );
        // some useless configurations (e.g. just borrow and hold) create no inventory risk for
        // liquidators, but may still need to be liquidated due to interest accrual. to service gas
        // costs and prevent overall griefing, we give liabilities an extra bump.
        // note: requiring some minimum amount of margin would accomplish something similar,
        //       but it's unclear what that amount would be for a given arbitrary asset
        // TODO simply require a minimum deposit of ETH when creating the margin account
        // could offer different, governance-controlled tiers. so unlimited tier may require
        // 100 * baseRateGasPrice * expectedGasNecessaryForLiquidation, but governance could
        // say "Oh you only put 10 * baseRate, you can still use the product but you have a cap
        // on total leverage and/or total borrows"
        liabilities1 += liquidationIncentive;

        // combine
        uint224 priceX96;
        uint256 liabilities;
        uint256 assets;

        priceX96 = uint224(Math.mulDiv(c2.a, c2.a, FixedPoint96.Q96));
        liabilities = liabilities1 + Math.mulDiv(liabilities0, priceX96, FixedPoint96.Q96);
        assets = mem.fluid1A + mem.fixed1 + Math.mulDiv(mem.fixed0, priceX96, FixedPoint96.Q96);
        if (liabilities > assets) return false;

        priceX96 = uint224(Math.mulDiv(c2.b, c2.b, FixedPoint96.Q96));
        liabilities = liabilities1 + Math.mulDiv(liabilities0, priceX96, FixedPoint96.Q96);
        assets = mem.fluid1B + mem.fixed1 + Math.mulDiv(mem.fixed0, priceX96, FixedPoint96.Q96);
        if (liabilities > assets) return false;

        return true;
    }

    struct Assets {
        uint256 fixed0;
        uint256 fixed1;
        uint256 fluid1A;
        uint256 fluid1B;
        uint256 fluid0C;
        uint256 fluid1C;
    }

    function _getAssets(
        int24[] memory positions_,
        Uniswap.FeeComputationCache memory c1,
        SolvencyCache memory c2
    ) private view returns (Assets memory assets) {
        assets.fixed0 = TOKEN0.balanceOf(address(this));
        assets.fixed1 = TOKEN1.balanceOf(address(this));

        uint256 count = positions_.length;
        for (uint256 i; i < count; i += 2) {
            Uniswap.Position memory position = Uniswap.Position(positions_[i], positions_[i + 1]);
            if (position.lower == position.upper) continue;

            Uniswap.PositionInfo memory info = position.info(UNISWAP_POOL);

            (uint256 temp0, uint256 temp1) = position.fees(UNISWAP_POOL, info, c1);
            assets.fixed0 += temp0;
            assets.fixed1 += temp1;

            uint160 lower = TickMath.getSqrtRatioAtTick(position.lower);
            uint160 upper = TickMath.getSqrtRatioAtTick(position.upper);

            assets.fluid1A += LiquidityAmounts.getValueOfLiquidity(c2.a, lower, upper, info.liquidity);
            assets.fluid1B += LiquidityAmounts.getValueOfLiquidity(c2.b, lower, upper, info.liquidity);

            (temp0, temp1) = LiquidityAmounts.getAmountsForLiquidity(c2.c, lower, upper, info.liquidity);
            assets.fluid0C += temp0;
            assets.fluid1C += temp1;
        }
    }

    function _getLiabilities() private view returns (uint256 amount0, uint256 amount1) {
        amount0 = LENDER0.borrowBalanceStored(address(this));
        amount1 = LENDER1.borrowBalanceStored(address(this));
    }

    // ⬆️⬆️⬆️⬆️ VIEW FUNCTIONS ⬆️⬆️⬆️⬆️  ------------------------------------------------------------------------------
    // ⬇️⬇️⬇️⬇️ PURE FUNCTIONS ⬇️⬇️⬇️⬇️  ------------------------------------------------------------------------------

    function _computeProbePrices(uint160 sqrtMeanPriceX96, uint256 sigma) private pure returns (uint160 a, uint160 b) {
        unchecked {
            sigma *= B;

            if (sigma < MIN_SIGMA) sigma = MIN_SIGMA;
            else if (sigma > MAX_SIGMA) sigma = MAX_SIGMA;

            a = uint160((sqrtMeanPriceX96 * FixedPointMathLib.sqrt(1e18 - sigma)) / 1e9);
            b = uint160((sqrtMeanPriceX96 * FixedPointMathLib.sqrt(1e18 + sigma)) / 1e9);
        }
    }

    function _computeLiquidationIncentive(
        uint256 assets0,
        uint256 assets1,
        uint256 liabilities0,
        uint256 liabilities1,
        uint160 sqrtMeanPriceX96
    ) private pure returns (uint256 reward1) {
        unchecked {
            uint256 meanPriceX96 = Math.mulDiv(sqrtMeanPriceX96, sqrtMeanPriceX96, FixedPoint96.Q96);

            if (liabilities0 > assets0) {
                // shortfall is the amount that cannot be directly repaid using Borrower assets at this price
                uint256 shortfall = liabilities0 - assets0;
                // to cover it, a liquidator may have to use their own assets, taking on inventory risk.
                // to compensate them for this risk, they're allowed to seize some of the surplus asset.
                reward1 += Math.mulDiv(shortfall, 0.05e9 * meanPriceX96, 1e9 * FixedPoint96.Q96);
            }

            if (liabilities1 > assets1) {
                // shortfall is the amount that cannot be directly repaid using Borrower assets at this price
                uint256 shortfall = liabilities1 - assets1;
                // to cover it, a liquidator may have to use their own assets, taking on inventory risk.
                // to compensate them for this risk, they're allowed to seize some of the surplus asset.
                reward1 += Math.mulDiv(shortfall, 0.05e9, 1e9);
            }
        }
    }
}
