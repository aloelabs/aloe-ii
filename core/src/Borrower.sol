// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.15;

import {Math} from "openzeppelin-contracts/utils/math/Math.sol";
import {ERC20, SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";

import {IUniswapV3MintCallback} from "v3-core/contracts/interfaces/callback/IUniswapV3MintCallback.sol";
import {IUniswapV3Pool} from "v3-core/contracts/interfaces/IUniswapV3Pool.sol";

import {Q96} from "./libraries/constants/Q.sol";
import {BalanceSheet, Assets, Prices} from "./libraries/BalanceSheet.sol";
import {LiquidityAmounts} from "./libraries/LiquidityAmounts.sol";
import {Oracle} from "./libraries/Oracle.sol";
import {Positions} from "./libraries/Positions.sol";
import {TickMath} from "./libraries/TickMath.sol";

import {Lender} from "./Lender.sol";

interface ILiquidator {
    function callback0(bytes calldata data, uint256 assets1, uint256 liabilities0) external;

    function callback1(bytes calldata data, uint256 assets0, uint256 liabilities1) external;
}

interface IManager {
    function callback(bytes calldata data) external returns (uint144 positions);
}

contract Borrower is IUniswapV3MintCallback {
    using SafeTransferLib for ERC20;
    using Positions for int24[6];

    uint8 public constant B = 3;

    /// @notice The Uniswap pair in which the vault will manage positions
    IUniswapV3Pool public immutable UNISWAP_POOL;

    /// @notice The first token of the Uniswap pair
    ERC20 public immutable TOKEN0;

    /// @notice The second token of the Uniswap pair
    ERC20 public immutable TOKEN1;

    /// @notice The lender of `TOKEN0`
    Lender public immutable LENDER0;

    /// @notice The lender of `TOKEN1`
    Lender public immutable LENDER1;

    struct PackedSlot {
        address owner;
        bool isInCallback;
    }

    PackedSlot public packedSlot;

    int24[6] public positions;

    /*//////////////////////////////////////////////////////////////
                       CONSTRUCTOR & INITIALIZER
    //////////////////////////////////////////////////////////////*/

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

    /*//////////////////////////////////////////////////////////////
                           MAIN ENTRY POINTS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Liquidates the borrower, using all available assets to pay down liabilities. If
     * some or all of the payment cannot be made in-kind, `callee` is expected to swap one asset
     * for the other at a venue of their choosing.
     * @dev TODO: describe reward
     * @param callee A smart contract capable of swapping `TOKEN0` for `TOKEN1` and vice versa
     * @param data Encoded parameters that get forwarded to `callee` callbacks
     * @param strain Almost always set to `1` to pay off all debt and receive maximum reward. If
     * liquidity is thin and swap price impact would be too large, you can use higher values to
     * reduce swap size and make it easier for `callee` to do its job. `2` would be half swap size,
     * `3` one third, and so on.
     */
    function liquidate(ILiquidator callee, bytes calldata data, uint256 strain) external {
        require(!packedSlot.isInCallback);

        // Fetch prices from oracle
        Prices memory prices = getPrices();

        uint256 liabilities0;
        uint256 liabilities1;

        uint256 incentive1;
        uint256 priceX96;

        {
            // Withdraw Uniswap positions while tallying assets
            Assets memory assets = _getAssets(positions.read(), prices, true);
            // Fetch liabilities from lenders
            (liabilities0, liabilities1) = _getLiabilities();
            // Calculate liquidation incentive
            (incentive1, priceX96) = BalanceSheet.computeLiquidationIncentive(
                assets.fixed0 + assets.fluid0C, // total assets0 at `prices.c` (the TWAP)
                assets.fixed1 + assets.fluid1C, // total assets1 at `prices.c` (the TWAP)
                liabilities0,
                liabilities1,
                prices.c
            );
            // Ensure only unhealthy accounts can be liquidated
            require(!BalanceSheet.isHealthy(prices, assets, liabilities0, liabilities1, incentive1), "Aloe: healthy");
        }

        // NOTE: The health check values assets at the TWAP and is difficult to manipulate. However,
        // the instantaneous price does impact what tokens we receive when burning Uniswap positions.
        // As such, additional calls to `TOKEN0.balanceOf` and `TOKEN1.balanceOf` are required for
        // precise inventory.

        // Figure out what portion of `liabilities0` can be repaid using existing assets
        uint256 repayable0 = Math.min(liabilities0, TOKEN0.balanceOf(address(this)));
        unchecked {
            liabilities0 -= repayable0;
        }

        // Figure out what portion of `liabilities1` can be repaid using existing assets
        uint256 repayable1 = Math.min(liabilities1, TOKEN1.balanceOf(address(this)));
        unchecked {
            liabilities1 -= repayable1;
        }

        if (liabilities0 + liabilities1 == 0 || (liabilities0 > 0 && liabilities1 > 0)) {
            // If both are zero or neither is zero, there's nothing more to do
            // TODO: compensate liquidators for txn costs using ANTE
        } else if (liabilities0 > 0) {
            uint256 converted0 = liabilities0 / strain;

            uint256 maxLoss1 = Math.mulDiv(converted0, priceX96, Q96) + incentive1 / strain;
            TOKEN1.safeTransfer(address(callee), maxLoss1);

            callee.callback0(data, maxLoss1, converted0);

            // TODO: compensate liquidators for txn costs using ANTE

            repayable0 += converted0;
        } else {
            uint256 converted1 = liabilities1 / strain;

            uint256 maxLoss0 = Math.mulDiv(converted1 + incentive1 / strain, Q96, priceX96);
            TOKEN0.safeTransfer(address(callee), maxLoss0);

            callee.callback1(data, maxLoss0, converted1);

            // TODO: compensate liquidators for txn costs using ANTE

            repayable1 += converted1;
        }

        _repay(repayable0, repayable1);
    }

    /**
     * @notice Allows the owner to manage their account by handing control to some `callee`. Inside the
     * callback `callee` has access to all sub-commands (`uniswapDeposit`, `uniswapWithdraw`, `borrow`,
     * and `repay`) and if `allowances` are set, it also has permission to transfer ERC20s. Whatever
     * `callee` does, the account MUST be healthy after the callback.
     * @param callee The smart contract that will get temporary control of this account
     * @param data Encoded parameters that get forwarded to `callee`
     * @param allowances Whether to approve `callee` to transfer ERC20s. The first entry is for `TOKEN0`,
     * and the 2nd is for `TOKEN1`.
     */
    function modify(IManager callee, bytes calldata data, bool[2] calldata allowances) external {
        require(msg.sender == packedSlot.owner, "Aloe: only owner");
        require(!packedSlot.isInCallback);

        if (allowances[0]) TOKEN0.safeApprove(address(callee), type(uint256).max);
        if (allowances[1]) TOKEN1.safeApprove(address(callee), type(uint256).max);

        packedSlot.isInCallback = true;
        int24[] memory positions_ = positions.write(callee.callback(data));
        packedSlot.isInCallback = false;

        if (allowances[0]) TOKEN0.safeApprove(address(callee), 1);
        if (allowances[1]) TOKEN1.safeApprove(address(callee), 1);

        Prices memory prices = getPrices();
        Assets memory assets = _getAssets(positions_, prices, false);
        (uint256 liabilities0, uint256 liabilities1) = _getLiabilities();

        require(BalanceSheet.isHealthy(prices, assets, liabilities0, liabilities1), "Aloe: need more margin");
    }

    /*//////////////////////////////////////////////////////////////
                              SUB-COMMANDS
    //////////////////////////////////////////////////////////////*/

    /// @dev Callback for Uniswap V3 pool.
    function uniswapV3MintCallback(uint256 amount0, uint256 amount1, bytes calldata) external {
        require(msg.sender == address(UNISWAP_POOL));

        if (amount0 > 0) TOKEN0.safeTransfer(msg.sender, amount0);
        if (amount1 > 0) TOKEN1.safeTransfer(msg.sender, amount1);
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

        (burned0, burned1, collected0, collected1) = _uniswapWithdraw(lower, upper, liquidity);
    }

    function borrow(uint256 amount0, uint256 amount1, address recipient) external {
        require(packedSlot.isInCallback);

        if (amount0 > 0) LENDER0.borrow(amount0, recipient);
        if (amount1 > 0) LENDER1.borrow(amount1, recipient);
    }

    // Technically uneccessary. but:
    // --> Keep because it allows us to use transfer instead of transferFrom, saving allowance reads in the underlying asset contracts
    // --> Keep for integrator convenience
    // --> Keep because it allows integrators to repay debts without configuring the `allowances` bool array
    function repay(uint256 amount0, uint256 amount1) external {
        require(packedSlot.isInCallback);

        _repay(amount0, amount1);
    }

    /*//////////////////////////////////////////////////////////////
                             BALANCE SHEET
    //////////////////////////////////////////////////////////////*/

    function getUniswapPositions() external view returns (int24[] memory) {
        return positions.read();
    }

    function getPrices() public view returns (Prices memory prices) {
        (int24 arithmeticMeanTick, ) = Oracle.consult(UNISWAP_POOL, 1200);
        uint256 sigma = 0.025e18; // TODO fetch real data from the volatility oracle

        // compute prices at which solvency will be checked
        uint160 sqrtMeanPriceX96 = TickMath.getSqrtRatioAtTick(arithmeticMeanTick);
        (uint160 a, uint160 b) = BalanceSheet.computeProbePrices(sqrtMeanPriceX96, sigma, B);
        prices = Prices(a, b, sqrtMeanPriceX96);
    }

    function _getAssets(
        int24[] memory positions_,
        Prices memory prices,
        bool withdraw
    ) private returns (Assets memory assets) {
        assets.fixed0 = TOKEN0.balanceOf(address(this));
        assets.fixed1 = TOKEN1.balanceOf(address(this));

        uint256 count = positions_.length;
        unchecked {
            for (uint256 i; i < count; i += 2) {
                // Load lower and upper ticks from the `positions_` array
                int24 l = positions_[i];
                int24 u = positions_[i + 1];
                // Fetch amount of `liquidity` in the position
                (uint128 liquidity, , , , ) = UNISWAP_POOL.positions(keccak256(abi.encodePacked(address(this), l, u)));

                if (liquidity == 0) continue;

                // Compute lower and upper sqrt ratios
                uint160 L = TickMath.getSqrtRatioAtTick(l);
                uint160 U = TickMath.getSqrtRatioAtTick(u);

                // Compute the value of `liquidity` (in terms of token1) at both probe prices
                assets.fluid1A += LiquidityAmounts.getValueOfLiquidity(prices.a, L, U, liquidity);
                assets.fluid1B += LiquidityAmounts.getValueOfLiquidity(prices.b, L, U, liquidity);

                // Compute what amounts underlie `liquidity` at the current TWAP
                (uint256 amount0, uint256 amount1) = LiquidityAmounts.getAmountsForLiquidity(prices.c, L, U, liquidity);
                assets.fluid0C += amount0;
                assets.fluid1C += amount1;

                if (!withdraw) continue;

                // Withdraw all `liquidity` from the position, adding earned fees as fixed assets
                (uint256 b0, uint256 b1, uint256 c0, uint256 c1) = _uniswapWithdraw(l, u, liquidity);
                assets.fixed0 += c0 - b0;
                assets.fixed1 += c1 - b1;
            }
        }
    }

    function _getLiabilities() private view returns (uint256 amount0, uint256 amount1) {
        amount0 = LENDER0.borrowBalanceStored(address(this));
        amount1 = LENDER1.borrowBalanceStored(address(this));
    }

    /*//////////////////////////////////////////////////////////////
                                 HELPERS
    //////////////////////////////////////////////////////////////*/

    function _uniswapWithdraw(
        int24 lower,
        int24 upper,
        uint128 liquidity
    ) private returns (uint256 burned0, uint256 burned1, uint256 collected0, uint256 collected1) {
        (burned0, burned1) = UNISWAP_POOL.burn(lower, upper, liquidity);
        (collected0, collected1) = UNISWAP_POOL.collect(
            address(this),
            lower,
            upper,
            type(uint128).max,
            type(uint128).max
        );
    }

    function _repay(uint256 amount0, uint256 amount1) private {
        if (amount0 > 0) {
            TOKEN0.safeTransfer(address(LENDER0), amount0);
            LENDER0.repay(amount0, address(this));
        }
        if (amount1 > 0) {
            TOKEN1.safeTransfer(address(LENDER1), amount1);
            LENDER1.repay(amount1, address(this));
        }
    }
}
