// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.17;

/// @title Rewards
/// @notice Implements logic for staking rewards
/// @author Aloe Labs, Inc.
/// @author Inspired by Yield Protocol (https://github.com/yieldprotocol/yield-utils-v2/blob/main/src/token/ERC20Rewards.sol)
library Rewards {
    bytes32 private constant REWARDS_SLOT = keccak256("aloe.ii.rewards");

    struct PoolState {
        uint112 accumulated; // Accumulated rewards per token for the period, scaled up by 1e7
        uint32 lastUpdated; // Last time the rewards per token accumulator was updated
        uint112 rate; // Wei rewarded per second per share, scaled up by 1e17. Lower bounded by max(1e10, expectedTotalSupply) -- before applying scaling factor
    }

    struct UserState {
        uint144 earned; // Accumulated rewards for the user until the checkpoint
        uint112 checkpoint; // PoolState.accumulated the last time the user rewards were updated
    }

    struct Storage {
        PoolState poolState;
        mapping(address => UserState) userStates;
    }

    /**
     * @notice Sets the pool's reward rate. May be 0.
     * @param rate The reward rate in token units per second per share. If `totalSupply == 0`, we
     * pretend it's 1 when dealing with the `rate`.
     */
    function setRate(uint112 rate) internal {
        Storage storage store = _getStorage();
        PoolState memory poolState = store.poolState;

        // Update each component of `poolState`, making sure to `_accumulate` first
        poolState.accumulated = _accumulate(poolState);
        poolState.lastUpdated = uint32(block.timestamp);
        poolState.rate = rate;

        store.poolState = poolState;
        // TODO: emit RewardsSet(rate);
    }

    /**
     * @notice Since `poolState.rate` is specified in [token units per second per share], a change
     * in `totalSupply` would result in a different overall [token units per second] for the pool.
     * This function adjusts for that, updating the accumulator and the rate to keep things consistent.
     * @dev Use `Rewards.pre()` to easily obtain the first two arguments
     * @param store The rewards storage pointer
     * @param accumulated Up-to-date `poolState.accumulated`, i.e. the output of `_accumulate`
     * @param oldTotalSupply The `totalSupply` before mint/burn
     * @param newTotalSupply The `totalSupply` after mint/burn
     */
    function updatePoolState(
        Storage storage store,
        uint112 accumulated,
        uint256 oldTotalSupply,
        uint256 newTotalSupply
    ) internal {
        store.poolState = previewPoolState(store, accumulated, oldTotalSupply, newTotalSupply);
    }

    /**
     * @notice Tracks how much reward a `user` earned while holding a particular `balance`. Should be
     * called anytime their balance changes.
     * @dev Use `Rewards.pre()` to easily obtain the first two arguments
     * @param store The rewards storage pointer
     * @param accumulated Up-to-date `poolState.accumulated`, i.e. the output of `_accumulate`
     * @param user The user whose balance (# of shares) is about to change
     * @param balance The user's balance (# of shares) -- before it changes
     */
    function updateUserState(Storage storage store, uint112 accumulated, address user, uint256 balance) internal {
        store.userStates[user] = previewUserState(store, accumulated, user, balance);
    }

    function previewPoolState(
        Storage storage store,
        uint112 accumulated,
        uint256 oldTotalSupply,
        uint256 newTotalSupply
    ) internal view returns (PoolState memory poolState) {
        poolState = store.poolState;

        poolState.accumulated = accumulated;
        poolState.lastUpdated = uint32(block.timestamp);
        poolState.rate = _rate(poolState.rate, oldTotalSupply, newTotalSupply);
    }

    function previewUserState(
        Storage storage store,
        uint112 accumulated,
        address user,
        uint256 balance
    ) internal view returns (UserState memory userState) {
        unchecked {
            userState = store.userStates[user];

            userState.earned += uint144((balance * (accumulated - userState.checkpoint)) / 1e7);
            userState.checkpoint = accumulated;
        }
    }

    /// @dev Returns arguments to be used in `updatePoolState` and `updateUserState`. No good semantic
    /// meaning here, just a coincidence that both functions need this information.
    function load() internal view returns (Storage storage store, uint112 accumulator) {
        store = _getStorage();
        accumulator = _accumulate(store.poolState);
    }

    /// @dev Accumulates rewards based on the current `rate` and time elapsed since last update
    function _accumulate(PoolState memory poolState) private view returns (uint112) {
        unchecked {
            uint256 deltaT = block.timestamp - poolState.lastUpdated;
            return poolState.accumulated + uint112(poolState.rate * deltaT / 1e10);
        }
    }

    /// @dev Adjusts `rate` to account for changes in `totalSupply`
    function _rate(uint112 rate, uint256 oldTotalSupply, uint256 newTotalSupply) private pure returns (uint112) {
        unchecked {
            if (oldTotalSupply == 0) oldTotalSupply = 1;
            if (newTotalSupply == 0) newTotalSupply = 1;

            return uint112((rate * oldTotalSupply) / newTotalSupply);
        }
    }

    /// @dev Diamond-pattern-style storage getter
    function _getStorage() private pure returns (Storage storage store) {
        bytes32 position = REWARDS_SLOT;
        assembly ("memory-safe") {
            store.slot := position
        }
    }
}
