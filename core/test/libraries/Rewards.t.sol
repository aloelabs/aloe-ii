// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.17;

import "forge-std/Test.sol";

import {ERC20, MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";

import {Rewards} from "src/libraries/Rewards.sol";

contract MockERC20Rewards is MockERC20 {
    ERC20 public immutable REWARDS_TOKEN;

    constructor(
        string memory _name,
        string memory _symbol,
        uint8 _decimals,
        ERC20 rewardsToken
    ) MockERC20(_name, _symbol, _decimals) {
        REWARDS_TOKEN = rewardsToken;
    }

    function setRate(uint112 rate) external {
        Rewards.setRate(rate);
    }

    function transfer(address to, uint256 amount) public virtual override returns (bool) {
        (Rewards.Storage storage s, uint112 a) = Rewards.load();
        Rewards.updateUserState(s, a, msg.sender, balanceOf[msg.sender]);
        Rewards.updateUserState(s, a, to, balanceOf[to]);

        return super.transfer(to, amount);
    }

    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) public virtual override returns (bool) {
        (Rewards.Storage storage s, uint112 a) = Rewards.load();
        Rewards.updateUserState(s, a, from, balanceOf[from]);
        Rewards.updateUserState(s, a, to, balanceOf[to]);

        return super.transferFrom(from, to, amount);
    }

    function mint(address to, uint256 value) public virtual override {
        (Rewards.Storage storage s, uint112 a) = Rewards.load();
        Rewards.updatePoolState(s, a, totalSupply, totalSupply + value);
        Rewards.updateUserState(s, a, to, balanceOf[to]);

        super.mint(to, value);
    }

    function burn(address from, uint256 value) public virtual override {
        (Rewards.Storage storage s, uint112 a) = Rewards.load();
        Rewards.updatePoolState(s, a, totalSupply, totalSupply - value);
        Rewards.updateUserState(s, a, from, balanceOf[from]);

        super.burn(from, value);
    }

    function claim() external {
        (Rewards.Storage storage s, uint112 a) = Rewards.load();
        REWARDS_TOKEN.transfer(
            msg.sender,
            Rewards.claim(s, a, msg.sender, balanceOf[msg.sender])
        );
    }

    function rewards(address user) external view returns (uint144) {
        (Rewards.Storage storage s, uint112 a) = Rewards.load();
        return Rewards.previewUserState(s, a, user, balanceOf[user]).earned;
    }

    function rewardsRate() external view returns (uint112) {
        (Rewards.Storage storage s, ) = Rewards.load();
        return s.poolState.rate;
    }
}

contract RewardsTest is Test {
    MockERC20 rewardsToken;

    MockERC20Rewards pool;

    function setUp() public {
        rewardsToken = new MockERC20("Rewards", "RWD", 18);
        pool = new MockERC20Rewards("Pool", "POOL", 18, rewardsToken);
    }

    /*//////////////////////////////////////////////////////////////
                               NO REVERT
    //////////////////////////////////////////////////////////////*/

    function test_library_setRate(uint112 rate) public {
        Rewards.setRate(rate);
    }

    function test_library_updatePoolState(uint112 rate, uint112 a, uint256 oldTotalSupply, uint256 newTotalSupply) public {
        Rewards.setRate(rate);
        (Rewards.Storage storage s, ) = Rewards.load();
        Rewards.updatePoolState(s, a, oldTotalSupply, newTotalSupply);
    }

    function test_library_updateUserState(uint112 rate, uint112 a, address user, uint256 balance) public {
        Rewards.setRate(rate);
        (Rewards.Storage storage s, ) = Rewards.load();
        Rewards.updateUserState(s, a, user, balance);
    }

    /*//////////////////////////////////////////////////////////////
                                  MOCK
    //////////////////////////////////////////////////////////////*/

    function test_mock_rateNotSet(address a, address b, uint256 shares) public {
        pool.mint(a, shares);
        skip(60);
        vm.prank(a);
        pool.transfer(b, shares);
        skip(60);
        pool.burn(b, shares);

        assertEq(pool.rewards(a), 0);
        assertEq(pool.rewards(b), 0);
    }

    function test_mock_bandwidthMinTime(uint256 rewardsPerSecond) public {
        uint256 maxTokensPerSecond = uint256(1e6) * 1e18 / (365 days);

        rewardsPerSecond = bound(rewardsPerSecond, 1e10, maxTokensPerSecond);
        pool.setRate(uint112(rewardsPerSecond * 1e17));

        address alice = address(12345);
        vm.startPrank(alice);

        for (uint256 totalSupply = 1; totalSupply <= 1e9; totalSupply *= 10) {
            pool.mint(alice, totalSupply - pool.totalSupply());

            assertEq(pool.rewardsRate(), rewardsPerSecond * 1e17 / pool.totalSupply());

            uint256 rewards = pool.rewards(alice);
            skip(1); // worst-case scenario (shortest timestep)
            pool.transfer(alice, pool.balanceOf(alice)); // no-op balance-wise, just triggering rewards accounting

            // accurate within 1 basis point (0.01%)
            assertApproxEqRel(pool.rewards(alice), rewards + 1 * rewardsPerSecond, 0.0001e18);
        }

        vm.stopPrank();
    }

    function test_mock_bandwidthVarTime(uint256 rewardsPerSecond, uint24 timestep) public {
        uint256 maxTokensPerSecond = uint256(1e6) * 1e18 / (365 days);

        rewardsPerSecond = bound(rewardsPerSecond, 1e10, maxTokensPerSecond);
        pool.setRate(uint112(rewardsPerSecond * 1e17));

        address alice = address(12345);
        vm.startPrank(alice);

        for (uint256 totalSupply = 1; totalSupply <= 1e9; totalSupply *= 10) {
            pool.mint(alice, totalSupply - pool.totalSupply());

            assertEq(pool.rewardsRate(), rewardsPerSecond * 1e17 / pool.totalSupply());

            uint256 rewards = pool.rewards(alice);
            skip(timestep);
            pool.transfer(alice, pool.balanceOf(alice)); // no-op balance-wise, just triggering rewards accounting

            // accurate within 1 basis point (0.01%)
            assertApproxEqRel(pool.rewards(alice), rewards + timestep * rewardsPerSecond, 0.0001e18);
        }

        vm.stopPrank();
    }

    function test_mock_spec(address a, address b, address c) public {
        vm.assume(a != b && b != c && c != a);

        pool.setRate(100 * 1e17);

        pool.mint(a, 4);
        skip(60);
        pool.burn(a, 4);

        assertEq(pool.rewards(a), 6000);
        assertEq(pool.rewards(b), 0);
        assertEq(pool.rewards(c), 0);

        pool.mint(a, 5);
        pool.mint(b, 5);
        skip(60);
        pool.burn(a, 5);
        pool.burn(b, 1);

        assertEq(pool.rewards(a), 9000);
        assertEq(pool.rewards(b), 3000);
        assertEq(pool.rewards(c), 0);

        skip(60);
        pool.burn(b, 4);

        assertEq(pool.rewards(a), 9000);
        assertEq(pool.rewards(b), 9000);
        assertEq(pool.rewards(c), 0);

        pool.mint(a, 2);
        pool.mint(b, 4);
        skip(10);
        vm.prank(a);
        pool.transfer(c, 2);
        pool.burn(b, 2);

        assertEq(pool.rewards(a), 9333);
        assertEq(pool.rewards(b), 9666);
        assertEq(pool.rewards(c), 0);

        skip(1);
        pool.burn(b, 2);
        pool.burn(c, 2);

        assertEq(pool.rewards(a), 9333);
        assertEq(pool.rewards(b), 9715);
        assertEq(pool.rewards(c), 49);
    }

    function test_mock_claim() public {
        pool.setRate(100 * 1e17);

        address alice = address(12345);
        pool.mint(alice, 4);

        assertEq(pool.rewardsRate(), 25 * 1e17);
        assertEq(pool.rewards(alice), 0);
        skip(60);
        assertEq(pool.rewards(alice), 6000);

        rewardsToken.mint(address(pool), 6000);
        
        vm.prank(alice);
        pool.claim();

        assertEq(pool.REWARDS_TOKEN().balanceOf(alice), 6000);
        assertEq(pool.rewards(alice), 0);
    }
}
