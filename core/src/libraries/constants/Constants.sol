// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.23;

/// @dev The initial value of `Lender`'s `borrowIndex`
uint256 constant ONE = 1e12;

/// @dev An additional scaling factor applied to borrowed amounts before dividing by `borrowIndex` and storing.
/// 72 matches the type of `borrowIndex` in `Ledger` to guarantee that the stored borrow units fit in uint256.
uint256 constant BORROWS_SCALER = ONE << 72;

/// @dev The maximum percentage yield per second, scaled up by 1e12. The current value is equivalent to
/// `((1 + 706354 / 1e12) ** (24 * 60 * 60)) - 1` ⇒ +6.3% per day or +53% per week. If the rate is consistently at
/// this maximum value, the `Lender` will function for 1 year before `borrowIndex` overflows.
/// @custom:math
/// > 📘 Useful Math
/// >
/// > - T: number of years before overflow, assuming maximum rate
/// > - borrowIndexInit: `ONE`
/// > - borrowIndexMax: 2^72 - 1
/// >
/// > - maxAPR: ln(borrowIndexMax / borrowIndexInit) / T
/// > - maxAPY: exp(maxAPR) - 1
/// > - MAX_RATE: (exp(maxAPR / secondsPerYear) - 1) * 1e12
uint256 constant MAX_RATE = 706354;

/*//////////////////////////////////////////////////////////////
                        FACTORY DEFAULTS
//////////////////////////////////////////////////////////////*/

/// @dev The default amount of Ether required to take on debt in a `Borrower`. The `Factory` can override this value
/// on a per-market basis. Incentivizes calls to `Borrower.warn`.
uint208 constant DEFAULT_ANTE = 0.01 ether;

/// @dev The default number of standard deviations of price movement used to determine probe prices for `Borrower`
/// solvency. The `Factory` can override this value on a per-market basis. Expressed x10, e.g. 50 → 5σ
uint8 constant DEFAULT_N_SIGMA = 50;

/// @dev Assume someone is manipulating the Uniswap TWAP oracle. To steal money from the protocol and create bad debt,
/// they would need to change the TWAP by a factor of (1 / LTV), where the LTV is a function of volatility. We have a
/// manipulation metric that increases as an attacker tries to change the TWAP. If this metric rises above a certain
/// threshold, certain functionality will be paused, e.g. no new debt can be created. The threshold is calculated as
/// follows:
///
/// \\( \text{manipulationThreshold} =
/// \frac{log_{1.0001}\left( \frac{1}{\text{LTV}} \right)}{\text{MANIPULATION_THRESHOLD_DIVISOR}} \\)
uint8 constant DEFAULT_MANIPULATION_THRESHOLD_DIVISOR = 12;

/// @dev The default portion of interest that will accrue to a `Lender`'s `RESERVE` address.
/// Expressed as a reciprocal, e.g. 16 → 6.25%
uint8 constant DEFAULT_RESERVE_FACTOR = 16;

/*//////////////////////////////////////////////////////////////
                        GOVERNANCE CONSTRAINTS
//////////////////////////////////////////////////////////////*/

/// @dev The lowest number of standard deviations of price movement allowed for determining `Borrower` probe prices.
/// Expressed x10, e.g. 40 → 4σ
uint8 constant CONSTRAINT_N_SIGMA_MIN = 40;

/// @dev The highest number of standard deviations of price movement allowed for determining `Borrower` probe prices.
/// Expressed x10, e.g. 80 → 8σ
uint8 constant CONSTRAINT_N_SIGMA_MAX = 80;

/// @dev The minimum value of the `manipulationThresholdDivisor`, described above
uint8 constant CONSTRAINT_MANIPULATION_THRESHOLD_DIVISOR_MIN = 10;

/// @dev The maximum value of the `manipulationThresholdDivisor`, described above
uint8 constant CONSTRAINT_MANIPULATION_THRESHOLD_DIVISOR_MAX = 16;

/// @dev The lower bound on what any `Lender`'s reserve factor can be. Expressed as reciprocal, e.g. 4 → 25%
uint8 constant CONSTRAINT_RESERVE_FACTOR_MIN = 4;

/// @dev The upper bound on what any `Lender`'s reserve factor can be. Expressed as reciprocal, e.g. 20 → 5%
uint8 constant CONSTRAINT_RESERVE_FACTOR_MAX = 20;

/// @dev The maximum amount of Ether that `Borrower`s can be required to post before taking on debt
uint216 constant CONSTRAINT_ANTE_MAX = 0.5 ether;

/*//////////////////////////////////////////////////////////////
                            LIQUIDATION
//////////////////////////////////////////////////////////////*/

/// @dev \\( 1 + \frac{1}{\text{MAX_LEVERAGE}} \\) should be greater than the maximum feasible single-block
/// `accrualFactor` so that liquidators have time to respond to interest updates
uint256 constant MAX_LEVERAGE = 200;

/// @dev The minimum discount that a healthy `Borrower` should be able to offer a liquidator when swapping
/// assets. Expressed as reciprocal, e.g. 20 → 5%
uint256 constant LIQUIDATION_INCENTIVE = 20;

/// @dev The minimum time that must pass between calls to `Borrower.warn` and `Borrower.liquidate`.
uint256 constant LIQUIDATION_GRACE_PERIOD = 5 minutes;

/// @dev The minimum `closeFactor` necessary to conclude a liquidation auction. To actually conclude the auction,
/// `Borrower.liquidate` must result in a healthy balance sheet (in addition to this `closeFactor` requirement).
/// Expressed in basis points.
/// NOTE: The ante is depleted after just 4 `Borrower.warn`ings. By requiring that each auction repay at least
/// 68%, we ensure that after 4 auctions, no more than 1% of debt remains ((1 - 0.6838)^4). Increasing the threshold
/// would reduce that further, but we don't want to prolong individual auctions unnecessarily since the incentive
/// (and loss to `Borrower`s) increases with time.
uint256 constant TERMINATING_CLOSE_FACTOR = 6837;

/// @dev The minimum scaling factor by which `sqrtMeanPriceX96` is multiplied or divided to get probe prices
uint256 constant PROBE_SQRT_SCALER_MIN = 1.026248453011e12;

/// @dev The maximum scaling factor by which `sqrtMeanPriceX96` is multiplied or divided to get probe prices
uint256 constant PROBE_SQRT_SCALER_MAX = 3.078745359035e12;

/// @dev Equivalent to \\( \frac{10^{36}}{1 + \frac{1}{liquidationIncentive} + \frac{1}{maxLeverage}} \\)
uint256 constant LTV_NUMERATOR = uint256(LIQUIDATION_INCENTIVE * MAX_LEVERAGE * 1e36) /
    (LIQUIDATION_INCENTIVE * MAX_LEVERAGE + LIQUIDATION_INCENTIVE + MAX_LEVERAGE);

/// @dev The minimum loan-to-value ratio. Actual ratio is based on implied volatility; this is just a lower bound.
/// Expressed as a 1e12 percentage, e.g. 0.10e12 → 10%. Must be greater than `TickMath.MIN_SQRT_RATIO` because
/// we reuse a base 1.0001 logarithm in `BalanceSheet`
uint256 constant LTV_MIN = LTV_NUMERATOR / (PROBE_SQRT_SCALER_MAX * PROBE_SQRT_SCALER_MAX);

/// @dev The maximum loan-to-value ratio. Actual ratio is based on implied volatility; this is just a upper bound.
/// Expressed as a 1e12 percentage, e.g. 0.90e12 → 90%
uint256 constant LTV_MAX = LTV_NUMERATOR / (PROBE_SQRT_SCALER_MIN * PROBE_SQRT_SCALER_MIN);

/*//////////////////////////////////////////////////////////////
                            IV AND TWAP
//////////////////////////////////////////////////////////////*/

/// @dev The timescale of implied volatility, applied to measurements and calculations. When `BalanceSheet` detects
/// that an `nSigma` event would cause insolvency in this time period, it enables liquidations. So if you squint your
/// eyes and wave your hands enough, this is (in expectation) the time liquidators have to act before the protocol
/// accrues bad debt.
uint32 constant IV_SCALE = 24 hours;

/// @dev The initial value of implied volatility, used when `VolatilityOracle.prepare` is called for a new pool.
/// Expressed as a 1e12 percentage at `IV_SCALE`, e.g. {0.12e12, 24 hours} → 12% daily → 229% annual. Error on the
/// side of making this too large (resulting in low LTV).
uint104 constant IV_COLD_START = 0.127921282726e12;

/// @dev The maximum rate at which (reported) implied volatility can change. Raw samples in `VolatilityOracle.update`
/// are clamped (before being stored) so as not to exceed this rate.
/// Expressed in 1e12 percentage points at `IV_SCALE` **per second**, e.g. {115740, 24 hours} means daily IV can
/// change by 0.0000116 percentage points per second → 1 percentage point per day.
uint256 constant IV_CHANGE_PER_SECOND = 115740;

/// @dev The maximum amount by which (reported) implied volatility can change with a single `VolatilityOracle.update`
/// call. If updates happen as frequently as possible (every `FEE_GROWTH_SAMPLE_PERIOD`), this cap is no different
/// from `IV_CHANGE_PER_SECOND` alone.
uint104 constant IV_CHANGE_PER_UPDATE = uint104(IV_CHANGE_PER_SECOND * FEE_GROWTH_SAMPLE_PERIOD);

/// @dev The gain on the EMA update when IV is increasing. Expressed as reciprocal, e.g. 20 → 0.05
int256 constant IV_EMA_GAIN_POS = 20;

/// @dev The gain on the EMA update when IV is decreasing. Expressed as reciprocal, e.g. 100 → 0.01
int256 constant IV_EMA_GAIN_NEG = 100;

/// @dev To estimate volume, we need 2 samples. One is always at the current block, the other is from
/// `FEE_GROWTH_AVG_WINDOW` seconds ago, +/- `FEE_GROWTH_SAMPLE_PERIOD / 2`. Larger values make the resulting volume
/// estimate more robust, but may cause the oracle to miss brief spikes in activity.
uint256 constant FEE_GROWTH_AVG_WINDOW = 72 hours;

/// @dev The length of the circular buffer that stores feeGrowthGlobals samples.
/// Must be in interval
/// \\( \left[ \frac{\text{FEE_GROWTH_AVG_WINDOW}}{\text{FEE_GROWTH_SAMPLE_PERIOD}}, 256 \right) \\)
uint256 constant FEE_GROWTH_ARRAY_LENGTH = 32;

/// @dev The minimum number of seconds that must elapse before a new feeGrowthGlobals sample will be stored. This
/// controls how often the oracle can update IV.
uint256 constant FEE_GROWTH_SAMPLE_PERIOD = 4 hours;

/// @dev To compute Uniswap mean price & liquidity, we need 2 samples. One is always at the current block, the other is
/// from `UNISWAP_AVG_WINDOW` seconds ago. Larger values make the resulting price/liquidity values harder to
/// manipulate, but also make the oracle slower to respond to changes.
uint32 constant UNISWAP_AVG_WINDOW = 30 minutes;
