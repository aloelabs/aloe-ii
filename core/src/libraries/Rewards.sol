// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.17;

/// @title Rewards
/// @notice Implements logic for staking rewards
/// @author Aloe Labs, Inc.
/// @author Inspired by Yield Protocol (https://github.com/yieldprotocol/yield-utils-v2/blob/main/src/token/ERC20Rewards.sol)
library Rewards {
    bytes32 private constant REWARDS_SLOT = keccak256("aloe.ii.rewards");

    struct PoolState {
        uint168 accumulated; // Accumulated rewards per token for the period, scaled up by 1e18
        uint32 lastUpdated; // Last time the rewards per token accumulator was updated
        uint56 rate; // Wei rewarded per second among all token holders
    }

    struct UserState {
        uint88 earned; // Accumulated rewards for the user until the checkpoint
        uint168 checkpoint; // RewardsPerToken the last time the user rewards were updated
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
    function setRate(uint56 rate) internal {
        Storage storage store = _getStorage();
        PoolState memory poolState = store.poolState;

        // Update each component of `poolState`, making sure to `_accumulate` first
        poolState.accumulated = _accumulate(poolState);
        poolState.lastUpdated = uint32(block.timestamp);
        poolState.rate = rate;

        store.poolState = poolState;
        // TODO: emit RewardsSet(rate);
    }

    function trackMintBurn(
        address user,
        uint256 userBalance,
        uint256 oldTotalSupply,
        uint256 newTotalSupply
    ) internal {
        Storage storage store = _getStorage();
        PoolState memory poolState = store.poolState;

        poolState.accumulated = _accumulate(poolState);
        poolState.lastUpdated = uint32(block.timestamp);
        poolState.rate = _rate(poolState.rate, oldTotalSupply, newTotalSupply);

        store.poolState = poolState;

        updateUserState(store, poolState.accumulated, user, userBalance);
    }

    function updateUserState(
        Storage storage store,
        uint168 accumulated,
        address user,
        uint256 balance
    ) internal {
        unchecked {
            UserState memory userState = store.userStates[user];

            userState.earned += uint88(balance * (accumulated - userState.checkpoint) / 1e18);
            userState.checkpoint = accumulated;

            store.userStates[user] = userState;
        }
    }

    function beforeTransfer() internal view returns (Storage storage store, uint168 accumulator) {
        store = _getStorage();
        accumulator = _accumulate(store.poolState);
    }

    function _accumulate(PoolState memory poolState) private view returns (uint168) {
        unchecked {
            uint256 deltaT = block.timestamp - poolState.lastUpdated;
            return poolState.accumulated + uint168(poolState.rate * deltaT);
        }
    }

    function _rate(uint56 rate, uint256 oldTotalSupply, uint256 newTotalSupply) private pure returns (uint56) {
        unchecked {
            if (oldTotalSupply == 0) oldTotalSupply = 1;
            if (newTotalSupply == 0) newTotalSupply = 1;

            return uint56(rate * oldTotalSupply / newTotalSupply);
        }
    }

    function _getStorage() private pure returns (Storage storage store) {
        bytes32 position = REWARDS_SLOT;
        assembly ("memory-safe") {
            store.slot := position
        }
    }
}
