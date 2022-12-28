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
import {TickMath} from "./libraries/TickMath.sol";
import {Uniswap} from "./libraries/Uniswap.sol";

import {Lender} from "./Lender.sol";

interface IManager {
    function callback(bytes calldata data) external returns (Uniswap.Position[] memory positions);
}

contract Borrower is IUniswapV3MintCallback {
    using SafeTransferLib for ERC20;
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

    /// @notice TODO
    address public owner;

    struct PackedSlot {
        bool isInCallback;
        bool isLocked;
    }

    struct SolvencyCache {
        uint160 a;
        uint160 b;
        uint160 c;
    }

    PackedSlot public packedSlot;

    Uniswap.Position[] public uniswapPositions; // TODO constrain the number of uniswap positions (otherwise gas danger)

    constructor(IUniswapV3Pool _pool, Lender _lender0, Lender _lender1) {
        UNISWAP_POOL = _pool;
        LENDER0 = _lender0;
        LENDER1 = _lender1;

        TOKEN0 = _lender0.asset();
        TOKEN1 = _lender1.asset();

        require(_pool.token0() == address(TOKEN0));
        require(_pool.token1() == address(TOKEN1));
    }

    function initialize(address _owner) external {
        require(owner == address(0));
        owner = _owner;
    }

    // TODO liquidations
    function liquidate() external {
        SolvencyCache memory c = _getSolvencyCache();

        (, int24 currentTick, , , , , ) = UNISWAP_POOL.slot0();
        bool isSolvent = _isSolvent(
            uniswapPositions,
            Uniswap.FeeComputationCache(
                currentTick,
                UNISWAP_POOL.feeGrowthGlobal0X128(),
                UNISWAP_POOL.feeGrowthGlobal1X128()
            ),
            c
        );

        if (!isSolvent) owner = msg.sender;
    }

    function modify(IManager callee, bytes calldata data, bool[2] calldata allowances) external {
        require(msg.sender == owner, "Aloe: only owner");
        require(!packedSlot.isLocked);
        packedSlot.isLocked = true; // TODO remove?

        if (allowances[0]) TOKEN0.safeApprove(address(callee), type(uint256).max);
        if (allowances[1]) TOKEN1.safeApprove(address(callee), type(uint256).max);

        packedSlot.isInCallback = true;
        Uniswap.Position[] memory _uniswapPositions = callee.callback(data); // TODO prevent duplicate uniswap positions
        packedSlot.isInCallback = false;

        if (allowances[0]) TOKEN0.safeApprove(address(callee), 0);
        if (allowances[1]) TOKEN1.safeApprove(address(callee), 0);

        SolvencyCache memory c = _getSolvencyCache();

        (, int24 currentTick, , , , , ) = UNISWAP_POOL.slot0();
        require(
            _isSolvent(
                _uniswapPositions,
                Uniswap.FeeComputationCache(
                    currentTick,
                    UNISWAP_POOL.feeGrowthGlobal0X128(),
                    UNISWAP_POOL.feeGrowthGlobal1X128()
                ),
                c
            ),
            "Aloe: need more margin"
        );

        uint256 len = uniswapPositions.length;
        for (uint256 i; i < _uniswapPositions.length; i++) {
            if (i < len) uniswapPositions[i] = _uniswapPositions[i];
            else uniswapPositions.push(_uniswapPositions[i]);
        }

        packedSlot = PackedSlot(false, false);
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
    function uniswapV3MintCallback(uint256 _amount0, uint256 _amount1, bytes calldata) external {
        require(msg.sender == address(UNISWAP_POOL)); // TODO
        if (_amount0 != 0) TOKEN0.safeTransfer(msg.sender, _amount0);
        if (_amount1 != 0) TOKEN1.safeTransfer(msg.sender, _amount1);
    }

    // ⬇️⬇️⬇️⬇️ VIEW FUNCTIONS ⬇️⬇️⬇️⬇️  ------------------------------------------------------------------------------

    function getUniswapPositions() external view returns (Uniswap.Position[] memory) {
        return uniswapPositions; // TODO maybe make it easier to get uint128 liquidity for each of these?
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
        Uniswap.Position[] memory _uniswapPositions,
        Uniswap.FeeComputationCache memory c1,
        SolvencyCache memory c2
    ) private view returns (bool) {
        Assets memory mem = _getAssets(_uniswapPositions, c1, c2);
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
        unchecked {
            liabilities0 = (liabilities0 * 1.005e18) / 1e18;
            liabilities1 = (liabilities1 * 1.005e18) / 1e18 + liquidationIncentive;
        } // TODO is unchecked safe here?

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
        Uniswap.Position[] memory _uniswapPositions,
        Uniswap.FeeComputationCache memory c1,
        SolvencyCache memory c2
    ) private view returns (Assets memory assets) {
        assets.fixed0 = TOKEN0.balanceOf(address(this));
        assets.fixed1 = TOKEN1.balanceOf(address(this));

        uint256 count = _uniswapPositions.length;
        for (uint256 i; i < count; i++) {
            Uniswap.PositionInfo memory info = _uniswapPositions[i].info(UNISWAP_POOL);

            (uint256 temp0, uint256 temp1) = _uniswapPositions[i].fees(UNISWAP_POOL, info, c1);
            assets.fixed0 += temp0;
            assets.fixed1 += temp1;

            uint160 lower = TickMath.getSqrtRatioAtTick(_uniswapPositions[i].lower);
            uint160 upper = TickMath.getSqrtRatioAtTick(_uniswapPositions[i].upper);

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

    function _computeProbePrices(
        uint160 _sqrtMeanPriceX96,
        uint256 _sigma
    ) private pure returns (uint160 a, uint160 b) {
        _sigma *= B;

        if (_sigma < MIN_SIGMA) _sigma = MIN_SIGMA;
        else if (_sigma > MAX_SIGMA) _sigma = MAX_SIGMA;

        unchecked {
            a = uint160((_sqrtMeanPriceX96 * FixedPointMathLib.sqrt(1e18 - _sigma)) / 1e9);
            b = uint160((_sqrtMeanPriceX96 * FixedPointMathLib.sqrt(1e18 + _sigma)) / 1e9);
        }
    }

    function _computeLiquidationIncentive(
        uint256 _assets0,
        uint256 _assets1,
        uint256 _liabilities0,
        uint256 _liabilities1,
        uint160 _sqrtMeanPriceX96
    ) private pure returns (uint256 reward1) {
        uint256 meanPriceX96 = Math.mulDiv(_sqrtMeanPriceX96, _sqrtMeanPriceX96, FixedPoint96.Q96);

        unchecked {
            if (_liabilities0 > _assets0) {
                // shortfall is the amount that cannot be directly repaid using Borrower assets at this price
                uint256 shortfall = _liabilities0 - _assets0;
                // to cover it, a liquidator may have to use their own assets, taking on inventory risk.
                // to compensate them for this risk, they're allowed to seize some of the surplus asset.
                reward1 += Math.mulDiv(shortfall, 0.05e9 * meanPriceX96, 1e9 * FixedPoint96.Q96);
            }

            if (_liabilities1 > _assets1) {
                // shortfall is the amount that cannot be directly repaid using Borrower assets at this price
                uint256 shortfall = _liabilities1 - _assets1;
                // to cover it, a liquidator may have to use their own assets, taking on inventory risk.
                // to compensate them for this risk, they're allowed to seize some of the surplus asset.
                reward1 += Math.mulDiv(shortfall, 0.05e9, 1e9);
            }
        }
    }
}
