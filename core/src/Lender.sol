// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.17;

import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {ERC20, SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import {SafeCastLib} from "solmate/utils/SafeCastLib.sol";

import {BORROWS_SCALER, ONE, MIN_RESERVE_FACTOR, MAX_RESERVE_FACTOR} from "./libraries/constants/Constants.sol";
import {Q112} from "./libraries/constants/Q.sol";

import {Ledger} from "./Ledger.sol";
import {RateModel} from "./RateModel.sol";

interface IFlashBorrower {
    function onFlashLoan(address initiator, uint256 amount, bytes calldata data) external;
}

/// @title Lender
/// @author Aloe Labs, Inc.
/// @dev "Test everything; hold fast what is good." - 1 Thessalonians 5:21
contract Lender is Ledger {
    using FixedPointMathLib for uint256;
    using SafeCastLib for uint256;
    using SafeTransferLib for ERC20;

    event Approval(address indexed owner, address indexed spender, uint256 amount);

    event Transfer(address indexed from, address indexed to, uint256 amount);

    event Deposit(address indexed caller, address indexed owner, uint256 assets, uint256 shares);

    event Withdraw(
        address indexed caller,
        address indexed receiver,
        address indexed owner,
        uint256 assets,
        uint256 shares
    );

    event Borrow(address indexed caller, address indexed recipient, uint256 amount, uint256 units);

    event Repay(address indexed caller, address indexed beneficiary, uint256 amount, uint256 units);

    event EnrollCourier(uint32 indexed id, address indexed wallet, uint16 cut);

    event CreditCourier(uint32 indexed id, address indexed account);

    /*//////////////////////////////////////////////////////////////
                       CONSTRUCTOR & INITIALIZER
    //////////////////////////////////////////////////////////////*/

    constructor(address reserve) Ledger(reserve) {}

    function initialize(RateModel rateModel_, uint8 reserveFactor_) external {
        require(borrowIndex == 0);
        borrowIndex = uint72(ONE);
        lastAccrualTime = uint32(block.timestamp);

        initialDomainSeparator = _computeDomainSeparator();
        initialChainId = block.chainid;

        rateModel = rateModel_;
        require(MIN_RESERVE_FACTOR <= reserveFactor_ && reserveFactor_ <= MAX_RESERVE_FACTOR);
        reserveFactor = reserveFactor_;
    }

    function whitelist(address borrower) external {
        // Requirements:
        // - `msg.sender == FACTORY` so that only the factory can whitelist borrowers
        // - `borrows[borrower] == 0` ensures we don't accidentally erase debt
        require(msg.sender == FACTORY && borrows[borrower] == 0);

        // `borrow` and `repay` have to read the `borrows` mapping anyway, so setting this to 1
        // allows them to efficiently check whether a given borrower is whitelisted. This extra
        // unit of debt won't accrue interest or impact solvency calculations.
        borrows[borrower] = 1;
    }

    function enrollCourier(uint32 id, address wallet, uint16 cut) external {
        // Requirements:
        // - `id != 0` because 0 is reserved as the no-courier case
        // - `cut != 0 && cut < 10_000` just means between 0 and 100%
        require(id != 0 && cut != 0 && cut < 10_000);
        // Once an `id` has been enrolled, its info can't be changed
        require(couriers[id].cut == 0);

        couriers[id] = Courier(wallet, cut);

        emit EnrollCourier(id, wallet, cut);
    }

    function creditCourier(uint32 id, address account) external {
        // Callers are free to set their own courier, but they need permission to mess with others'
        require(msg.sender == account || allowance[account][msg.sender] != 0);

        // Prevent `RESERVE` from having a courier, since its principle wouldn't be tracked properly
        require(account != RESERVE);

        // Payout logic can't handle self-reference, so don't let accounts credit themselves
        Courier memory courier = couriers[id];
        require(courier.cut != 0 && courier.wallet != account);

        // Only set courier if account balance is 0. Otherwise a previous courier may
        // be cheated out of their fees.
        require(balances[account] % Q112 == 0);
        balances[account] = uint256(id) << 224;

        emit CreditCourier(id, account);
    }

    /*//////////////////////////////////////////////////////////////
                        DEPOSIT/WITHDRAWAL LOGIC
    //////////////////////////////////////////////////////////////*/

    function deposit(uint256 amount, address beneficiary) public returns (uint256 shares) {
        // Guard against reentrancy, accrue interest, and update reserves
        (Cache memory cache, uint256 inventory) = _load();

        shares = _convertToShares(amount, inventory, cache.totalSupply, /* roundUp: */ false);
        require(shares != 0, "Aloe: zero impact");

        // Ensure tokens are transferred
        ERC20 asset_ = asset();
        cache.lastBalance += amount;
        bool didPrepay = cache.lastBalance <= asset_.balanceOf(address(this));
        if (!didPrepay) {
            asset_.safeTransferFrom(msg.sender, address(this), amount);
        }

        // Mint shares and (if applicable) handle courier accounting
        _unsafeMint(beneficiary, shares, amount);
        cache.totalSupply += shares;

        // Save state to storage (thus far, only mappings have been updated, so we must address everything else)
        _save(cache, /* didChangeBorrowBase: */ false);

        emit Deposit(msg.sender, beneficiary, amount, shares);
    }

    function mint(uint256 shares, address beneficiary) external returns (uint256 amount) {
        amount = previewMint(shares);
        deposit(amount, beneficiary);
    }

    function redeem(uint256 shares, address recipient, address owner) public returns (uint256 amount) {
        // Guard against reentrancy, accrue interest, and update reserves
        (Cache memory cache, uint256 inventory) = _load();

        amount = _convertToAssets(shares, inventory, cache.totalSupply, /* roundUp: */ false);
        require(amount != 0, "Aloe: zero impact");

        if (msg.sender != owner) {
            uint256 allowed = allowance[owner][msg.sender];
            if (allowed != type(uint256).max) allowance[owner][msg.sender] = allowed - shares;
        }

        // Burn shares and (if applicable) handle courier accounting
        _unsafeBurn(owner, shares, inventory, cache.totalSupply);
        unchecked {
            cache.totalSupply -= shares;
        }

        // Transfer tokens
        cache.lastBalance -= amount;
        asset().safeTransfer(recipient, amount);

        // Save state to storage (thus far, only mappings have been updated, so we must address everything else)
        _save(cache, /* didChangeBorrowBase: */ false);

        emit Withdraw(msg.sender, recipient, owner, amount, shares);
    }

    function withdraw(uint256 amount, address recipient, address owner) external returns (uint256 shares) {
        shares = previewWithdraw(amount);
        redeem(shares, recipient, owner);
    }

    /*//////////////////////////////////////////////////////////////
                           BORROW/REPAY LOGIC
    //////////////////////////////////////////////////////////////*/

    function borrow(uint256 amount, address recipient) external returns (uint256 units) {
        uint256 b = borrows[msg.sender];
        require(b != 0, "Aloe: not a borrower");

        // Guard against reentrancy, accrue interest, and update reserves
        (Cache memory cache, ) = _load();

        units = amount.mulDivUp(BORROWS_SCALER, cache.borrowIndex);
        cache.borrowBase += units;
        borrows[msg.sender] = b + units;

        // Transfer tokens
        cache.lastBalance -= amount;
        asset().safeTransfer(recipient, amount);

        // Save state to storage (thus far, only mappings have been updated, so we must address everything else)
        _save(cache, /* didChangeBorrowBase: */ true);

        emit Borrow(msg.sender, recipient, amount, units);
    }

    function repay(uint256 amount, address beneficiary) external returns (uint256 units) {
        uint256 b = borrows[beneficiary];

        // Guard against reentrancy, accrue interest, and update reserves
        (Cache memory cache, ) = _load();

        unchecked {
            units = (amount * BORROWS_SCALER) / cache.borrowIndex;
            require(units < b, "Aloe: repay too much");

            borrows[beneficiary] = b - units;
            cache.borrowBase -= units;
        }

        // Ensure tokens were transferred
        cache.lastBalance += amount;
        require(cache.lastBalance <= asset().balanceOf(address(this)), "Aloe: insufficient pre-pay");

        // Save state to storage (thus far, only mappings have been updated, so we must address everything else)
        _save(cache, /* didChangeBorrowBase: */ true);

        emit Repay(msg.sender, beneficiary, amount, units);
    }

    /// @dev Reentrancy guard is critical here! Without it, one could use a flash loan to repay a normal loan.
    function flash(uint256 amount, IFlashBorrower to, bytes calldata data) external {
        // Guard against reentrancy
        uint32 lastAccrualTime_ = lastAccrualTime;
        require(lastAccrualTime_ != 0, "Aloe: locked");
        lastAccrualTime = 0;

        ERC20 asset_ = asset();

        uint256 balance = asset_.balanceOf(address(this));
        asset_.safeTransfer(address(to), amount);
        to.onFlashLoan(msg.sender, amount, data);
        require(balance <= asset_.balanceOf(address(this)), "Aloe: insufficient pre-pay");

        lastAccrualTime = lastAccrualTime_;
    }

    function accrueInterest() external returns (uint72) {
        (Cache memory cache, ) = _load();
        _save(cache, /* didChangeBorrowBase: */ false);
        return uint72(cache.borrowIndex);
    }

    /*//////////////////////////////////////////////////////////////
                               ERC20 LOGIC
    //////////////////////////////////////////////////////////////*/

    function approve(address spender, uint256 shares) external returns (bool) {
        allowance[msg.sender][spender] = shares;

        emit Approval(msg.sender, spender, shares);

        return true;
    }

    function transfer(address to, uint256 shares) external returns (bool) {
        _transfer(msg.sender, to, shares);

        return true;
    }

    function transferFrom(address from, address to, uint256 shares) external returns (bool) {
        uint256 allowed = allowance[from][msg.sender];
        if (allowed != type(uint256).max) allowance[from][msg.sender] = allowed - shares;

        _transfer(from, to, shares);

        return true;
    }

    /*//////////////////////////////////////////////////////////////
                             ERC2612 LOGIC
    //////////////////////////////////////////////////////////////*/

    function permit(
        address owner,
        address spender,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external {
        require(deadline >= block.timestamp, "Aloe: permit expired");

        // Unchecked because the only math done is incrementing
        // the owner's nonce which cannot realistically overflow.
        unchecked {
            address recoveredAddress = ecrecover(
                keccak256(
                    abi.encodePacked(
                        "\x19\x01",
                        DOMAIN_SEPARATOR(),
                        keccak256(
                            abi.encode(
                                keccak256(
                                    "Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"
                                ),
                                owner,
                                spender,
                                value,
                                nonces[owner]++,
                                deadline
                            )
                        )
                    )
                ),
                v,
                r,
                s
            );

            require(recoveredAddress != address(0) && recoveredAddress == owner, "Aloe: permit invalid");

            allowance[recoveredAddress][spender] = value;
        }

        emit Approval(owner, spender, value);
    }

    /*//////////////////////////////////////////////////////////////
                                HELPERS
    //////////////////////////////////////////////////////////////*/

    function _transfer(address from, address to, uint256 shares) private {
        unchecked {
            // From most to least significant...
            // -------------------------------
            // | courier id       | 32 bits  |
            // | user's principle | 112 bits |
            // | user's balance   | 112 bits |
            // -------------------------------
            uint256 data;

            data = balances[from];
            require(data >> 224 == 0 && shares <= data % Q112);
            balances[from] = data - shares;

            data = balances[to];
            require(data >> 224 == 0);
            balances[to] = data + shares;
        }

        emit Transfer(from, to, shares);
    }

    /// @dev You must do `totalSupply += shares` separately. Do so in a checked context.
    function _unsafeMint(address to, uint256 shares, uint256 amount) private {
        unchecked {
            // From most to least significant...
            // -------------------------------
            // | courier id       | 32 bits  |
            // | user's principle | 112 bits |
            // | user's balance   | 112 bits |
            // -------------------------------
            uint256 data = balances[to];

            if (data >> 224 != 0) {
                // Keep track of principle iff courier deserves credit
                require(amount + ((data >> 112) % Q112) < Q112);
                data += amount << 112;
            }

            // Keep track of balance regardless of courier.
            // Since `totalSupply` fits in uint112, the user's balance will too. No need to check here.
            balances[to] = data + shares;
        }

        emit Transfer(address(0), to, shares);
    }

    /// @dev You must do `totalSupply -= shares` separately. Do so in an unchecked context.
    function _unsafeBurn(address from, uint256 shares, uint256 inventory, uint256 totalSupply_) private {
        unchecked {
            // From most to least significant...
            // -------------------------------
            // | courier id       | 32 bits  |
            // | user's principle | 112 bits |
            // | user's balance   | 112 bits |
            // -------------------------------
            uint256 data = balances[from];
            uint256 balance = data % Q112;

            uint32 id = uint32(data >> 224);
            if (id != 0) {
                uint256 principleAssets = (data >> 112) % Q112;
                uint256 principleShares = principleAssets.mulDivUp(totalSupply_, inventory);

                if (balance > principleShares) {
                    Courier memory courier = couriers[id];

                    // Compute total fee owed to courier. Take it out of balance so that
                    // comparison is correct (`shares <= balance`)
                    uint256 fee = ((balance - principleShares) * courier.cut) / 10_000;
                    balance -= fee;

                    // Compute portion of fee to pay out during this burn.
                    fee = (fee * shares) / balance;

                    // Send `fee` from `from` to `courier.wallet`. NOTE: We skip principle
                    // update on courier, so if couriers credit each other, 100% of `fee`
                    // is treated as profit and will pass through to the next courier.
                    data -= fee;
                    balances[courier.wallet] += fee;
                    emit Transfer(from, courier.wallet, fee);
                }

                // Update principle
                data -= ((principleAssets * shares) / balance) << 112;
            }

            require(shares <= balance);
            balances[from] = data - shares;
        }

        emit Transfer(from, address(0), shares);
    }

    function _load() private returns (Cache memory cache, uint256 inventory) {
        cache = Cache(totalSupply, lastBalance, lastAccrualTime, borrowBase, borrowIndex);
        // Guard against reentrancy
        require(cache.lastAccrualTime != 0, "Aloe: locked");
        lastAccrualTime = 0;

        // Accrue interest (only in memory)
        uint256 newTotalSupply;
        (cache, inventory, newTotalSupply) = _previewInterest(cache);

        // Update reserves (new `totalSupply` is only in memory, but `balanceOf` is updated in storage)
        if (newTotalSupply > cache.totalSupply) {
            _unsafeMint(RESERVE, newTotalSupply - cache.totalSupply, 0);
            cache.totalSupply = newTotalSupply;
        }
    }

    function _save(Cache memory cache, bool didChangeBorrowBase) private {
        // `cache.lastAccrualTime == 0` implies that `cache.borrowIndex` was updated
        if (cache.lastAccrualTime == 0 || didChangeBorrowBase) {
            borrowBase = cache.borrowBase.safeCastTo184();
            borrowIndex = cache.borrowIndex.safeCastTo72();
        }

        totalSupply = cache.totalSupply.safeCastTo112();
        lastBalance = cache.lastBalance.safeCastTo112();
        lastAccrualTime = uint32(block.timestamp); // Disables reentrancy guard
    }
}
