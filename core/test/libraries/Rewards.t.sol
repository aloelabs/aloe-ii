// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.17;

import "forge-std/Test.sol";

import {ERC20, MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";

import {Rewards, exp2} from "src/libraries/Rewards.sol";

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

    function setRate(uint56 rate) external {
        Rewards.setRate(rate);
    }

    function transfer(address to, uint256 amount) public virtual override returns (bool) {
        (Rewards.Storage storage s, uint144 a) = Rewards.load();
        Rewards.updateUserState(s, a, msg.sender, balanceOf[msg.sender]);
        Rewards.updateUserState(s, a, to, balanceOf[to]);

        return super.transfer(to, amount);
    }

    function transferFrom(address from, address to, uint256 amount) public virtual override returns (bool) {
        (Rewards.Storage storage s, uint144 a) = Rewards.load();
        Rewards.updateUserState(s, a, from, balanceOf[from]);
        Rewards.updateUserState(s, a, to, balanceOf[to]);

        return super.transferFrom(from, to, amount);
    }

    function mint(address to, uint256 value) public virtual override {
        (Rewards.Storage storage s, uint144 a) = Rewards.load();
        Rewards.updatePoolState(s, a, totalSupply + value);
        Rewards.updateUserState(s, a, to, balanceOf[to]);

        super.mint(to, value);
    }

    function burn(address from, uint256 value) public virtual override {
        (Rewards.Storage storage s, uint144 a) = Rewards.load();
        Rewards.updatePoolState(s, a, totalSupply - value);
        Rewards.updateUserState(s, a, from, balanceOf[from]);

        super.burn(from, value);
    }

    function claim() external {
        (Rewards.Storage storage s, uint144 a) = Rewards.load();
        REWARDS_TOKEN.transfer(msg.sender, Rewards.claim(s, a, msg.sender, balanceOf[msg.sender]));
    }

    function rewards(address user) external view returns (uint112) {
        (Rewards.Storage storage s, uint144 a) = Rewards.load();
        return Rewards.previewUserState(s, a, user, balanceOf[user]).earned;
    }

    function rewardsRate() external view returns (uint56) {
        (Rewards.Storage storage s, ) = Rewards.load();
        return s.poolState.rate;
    }

    function rewardsAccumulator() external view returns (uint144 a) {
        (, a) = Rewards.load();
    }

    function log2TotalSupply() external view returns (int24) {
        (Rewards.Storage storage s, ) = Rewards.load();
        return s.poolState.log2TotalSupply;
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

    function test_library_setRate(uint56 rate) public {
        Rewards.setRate(rate);
    }

    function test_library_updatePoolState(uint56 rate, uint144 a, uint256 newTotalSupply) public {
        Rewards.setRate(rate);
        (Rewards.Storage storage s, ) = Rewards.load();
        Rewards.updatePoolState(s, a, newTotalSupply);
    }

    function test_library_updateUserState(uint56 rate, uint144 a, address user, uint256 balance) public {
        Rewards.setRate(rate);
        (Rewards.Storage storage s, ) = Rewards.load();
        Rewards.updateUserState(s, a, user, balance);
    }

    /*//////////////////////////////////////////////////////////////
                                  MOCK
    //////////////////////////////////////////////////////////////*/

    function test_mock_rateNotSet(address a, address b, uint112 shares, uint56 rate) public {
        vm.assume(a != b);

        pool.mint(a, shares);
        skip(60);
        vm.prank(a);
        pool.transfer(b, shares);
        skip(60);
        pool.burn(b, shares);

        assertEq(pool.rewards(a), 0);
        assertEq(pool.rewards(b), 0);

        pool.setRate(rate);
        pool.mint(a, shares);
        skip(60);

        assertLe(pool.rewards(a), 60 * uint256(rate));
        assertEq(pool.rewards(b), 0);
    }

    function test_mock_minRateMaxSupply() public {
        uint256 minRate = (uint256(10) * 1e18) / 365 days;
        uint256 maxSupply = uint256(1e9) * 1e18;

        pool.setRate(uint56(minRate));
        assertEq(pool.rewardsRate(), minRate);

        address alice = address(12345);
        pool.mint(alice, maxSupply);

        uint144 before = pool.rewardsAccumulator();
        assertEq(before, 0);
        skip(1); // Accumulator should change even after just 1 second
        assertGt(pool.rewardsAccumulator(), before);
        assertLe(pool.rewardsAccumulator() - before, minRate * 1e18);
    }

    function test_mock_maxRateMinSupply() public {
        uint256 maxRate = (uint256(1e6) * 1e18) / 365 days;
        uint256 minSupply = 1;

        pool.setRate(uint56(maxRate));
        assertEq(pool.rewardsRate(), maxRate);

        address alice = address(12345);
        pool.mint(alice, minSupply);

        uint144 before = pool.rewardsAccumulator();
        assertEq(before, 0);
        skip(1); // Accumulator should change even after just 1 second
        assertGt(pool.rewardsAccumulator(), before);
        assertLe(pool.rewardsAccumulator() - before, maxRate * 1e18);
    }

    function test_mock_minRateMaxSupplyLongTime() public {
        uint256 minRate = (uint256(10) * 1e18) / 365 days;
        uint256 maxSupply = uint256(1e9) * 1e18;

        pool.setRate(uint56(minRate));
        assertEq(pool.rewardsRate(), minRate);

        address alice = address(12345);
        pool.mint(alice, maxSupply);

        uint144 before = pool.rewardsAccumulator();
        assertEq(before, 0);
        skip(365 days);
        assertGt(pool.rewardsAccumulator(), before);
        assertLe(pool.rewardsAccumulator() - before, minRate * 1e18 * 365 days);
    }

    function test_mock_maxRateMinSupplyLongTime() public {
        uint256 maxRate = (uint256(1e6) * 1e18) / 365 days;
        uint256 minSupply = 1;

        pool.setRate(uint56(maxRate));
        assertEq(pool.rewardsRate(), maxRate);

        address alice = address(12345);
        pool.mint(alice, minSupply);

        uint144 before = pool.rewardsAccumulator();
        assertEq(before, 0);
        skip(365 days);
        assertGt(pool.rewardsAccumulator(), before);
        assertLe(pool.rewardsAccumulator() - before, maxRate * 1e18 * 365 days);
    }

    function test_mock_accumulatorPrecision(uint56 rate, uint112 totalSupply, uint32 deltaT) public {
        rate = uint56(bound(rate, 1e10, type(uint56).max));
        vm.assume(totalSupply > 0);
        vm.assume(deltaT > 0);

        pool.setRate(rate);
        address alice = address(12345);
        pool.mint(alice, totalSupply);

        uint144 before = pool.rewardsAccumulator();
        assertEq(before, 0);
        skip(deltaT);

        uint256 actual = pool.rewardsAccumulator() - before;
        uint256 expected = (1e16 * uint256(deltaT) * rate) / totalSupply;

        assertLe(actual, expected);
        if (actual / deltaT > 1e3) assertApproxEqRel(actual, expected, 0.002e18);
    }

    function test_mock_spec(address a, address b, address c) public {
        vm.assume(a != b && b != c && c != a);

        pool.setRate(uint56(100));

        pool.mint(a, 4000);
        skip(60);
        pool.burn(a, 4000);

        assertEq(pool.rewards(a), 6000);
        assertEq(pool.rewards(b), 0);
        assertEq(pool.rewards(c), 0);

        pool.mint(a, 5000);
        pool.mint(b, 5000);
        skip(60);
        pool.burn(a, 5000);
        pool.burn(b, 1000);

        assertEq(pool.rewards(a), 8999);
        assertEq(pool.rewards(b), 2999);
        assertEq(pool.rewards(c), 0);

        skip(60);
        pool.burn(b, 4000);

        assertEq(pool.rewards(a), 8999);
        assertEq(pool.rewards(b), 8999);
        assertEq(pool.rewards(c), 0);

        pool.mint(a, 2000);
        pool.mint(b, 4000);
        skip(10);
        vm.prank(a);
        pool.transfer(c, 2000);
        pool.burn(b, 2000);

        assertEq(pool.rewards(a), 9332);
        assertEq(pool.rewards(b), 9665);
        assertEq(pool.rewards(c), 0);

        skip(1);
        pool.burn(b, 2000);
        pool.burn(c, 2000);

        assertEq(pool.rewards(a), 9332);
        assertEq(pool.rewards(b), 9715);
        assertEq(pool.rewards(c), 50);
    }

    function test_mock_claim() public {
        pool.setRate(uint56(100));

        address alice = address(12345);
        pool.mint(alice, 4000);

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
