// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import {ImmutableArgs} from "clones-with-immutable-args/ImmutableArgs.sol";
import {ERC20, SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";

import {FullMath} from "./libraries/FullMath.sol";
import {SafeCastLib} from "./libraries/SafeCastLib.sol";

import {InterestModel} from "./InterestModel.sol";
import {Factory} from "./Factory.sol";

import {Ledger} from "./Ledger.sol";

interface IFlashBorrower {
    function onFlashLoan(address initiator, uint256 amount, bytes calldata data) external;
}

/*
                                           'K^                                            
                                          ~Q@@J                                           
                                         i@@@@@D'                                         
                                        q@@@@@@@Q!                                        
                                      `6@@@@@@@@@@!                                       
                                     ~Q@@@@@@@@@@@@f                                      
                                    7@@@@@@@@@@@@@@@%'                                    
                                   K@@@@@@@@@@@@@@@@@Q^                                   
                                 .q@@@@@@@@@@@@@@@@@@@@^                                  
                                ;Q@@@@@@@@@@@@@@@@@@@@@@o`                                
                               z@@@@@@@@@@@@@@@@@@@@@@@@@U`                             ``
                             `D@@@@@@@@@@@@@@@@@@@@QUs=,                `,;+LzjmqRNQQQbJ;`
                            .K@@@@@@@@@@@@@@@@&P7!`             `~+\jXgQ@@@@@@@@@@Nyr`    
                           ;Q@@@@@@@@@@@@NSL~            `~<{XWQ@@@@@@@@@@@@@@QS!`        
                          s@@@@@@@@@Q67;           .;|jRQ@@@@@@@@@@@@@@@@@Qw<'            
                        `D@@@@@@QS*.          '^zXQ@@@@@@@@@@@@@@@@@@@@%J~                
                       'D@@@@K|'          _?5NQQQQ@@@@@@@@@@@@@@@@@@%J'                   
                      ;Q@K\,         .!zDQQQQQQQ@QQQ@@@@@@@@@@@@@X<.                      
                     <j!`        .^5WQQQQQQQQQQQQQQ@@@@@@@@@@Qh=`                         
                              ;zKQQQQQQQQQQQQQQQQQQQQQQ@@@@%*`                            
                          ,|hQQQQQQQQQQQQQQQQQQQQQQQQQ@Q%c'        ~\hI`                  
                      `!uNQQQQQQQQQQQQQQQQQQQQQQQQQQQQy,        :7XAqAAw~                 
                   .LXQQQQQQQQQQQQQQQQQQQQQQQQQQQQQX^`       ,LEAqqqqqqq6?                
                .<wBQQQQQQQQQQQQQQQQQQQQQQQQQQQQQh:        ;jAAqqqqqqqqqqqJ               
             .<qQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQBz'       ,iXAqqqqqqqqqqqqqAA}.             
          '?6QQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQB<`       ~yqqqqqqqqqqqqqqqqqqqqh;            
       `^SQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQ#i`      `^SqAqqqqqqqqqqqqqqqqqqqqqAi`          
     ,JgQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQ}.       ^wAAqqqqqqqqqqqqqqqqqqqqqqqqA}`         
  `+XQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQD,       ;5Aqqqqqqqqqqqqqqqqqqqqqqqqqqqqqy'        
_}NQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQ7`      ,f666666666666666666666666666666666X!       
*/

contract Lender is Ledger {
    using SafeTransferLib for ERC20;
    using FullMath for uint256;
    using SafeCastLib for uint256;

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

    constructor(address treasury) Ledger(treasury) {}

    function initialize(InterestModel interestModel_, uint8 reserveFactor_) public virtual {
        require(borrowIndex == 0, "Already initialized"); // TODO use real Error
        borrowIndex = uint72(ONE);
        lastAccrualTime = uint32(block.timestamp);

        initialDomainSeparator = _computeDomainSeparator();
        initialChainId = block.chainid;

        interestModel = interestModel_;
        require(4 <= reserveFactor_ && reserveFactor_ <= 20);
        reserveFactor = reserveFactor_;
    }

    /*//////////////////////////////////////////////////////////////
                        DEPOSIT/WITHDRAWAL LOGIC
    //////////////////////////////////////////////////////////////*/

    function deposit(uint256 amount, address beneficiary) external returns (uint256 shares) {
        // Guard against reentrancy, accrue interest, and update reserves
        (Cache memory cache, uint256 inventory) = _load();

        shares = _convertToShares(amount, inventory, cache.totalSupply, /* roundUp: */ false);
        require(shares != 0, "Aloe: 0 shares"); // TODO use real Error

        // Ensure tokens were transferred
        cache.lastBalance += amount;
        require(cache.lastBalance <= asset().balanceOf(address(this)));

        // Mint shares (emits event that can be interpreted as a deposit)
        cache.totalSupply += shares;
        _unsafeMint(beneficiary, shares);

        // Save state to storage (thus far, only mappings have been updated, so we must address everything else)
        _save(cache, /* didChangeBorrowBase: */ false);

        emit Deposit(msg.sender, beneficiary, amount, shares);
    }

    function redeem(uint256 shares, address recipient, address owner) external returns (uint256 amount) {
        // Guard against reentrancy, accrue interest, and update reserves
        (Cache memory cache, uint256 inventory) = _load();

        // Conditionally modify inputs, for convenience
        if (shares == 0) shares = balanceOf[owner];

        amount = _convertToAssets(shares, inventory, cache.totalSupply, /* roundUp: */ false);
        require(amount != 0, "Aloe: amount too low"); // TODO use real Error

        if (msg.sender != owner) {
            uint256 allowed = allowance[owner][msg.sender];
            if (allowed != type(uint256).max) allowance[owner][msg.sender] = allowed - shares;
        }

        // Transfer tokens
        cache.lastBalance -= amount;
        asset().safeTransfer(recipient, amount);

        // Burn shares (emits event that can be interpreted as a withdrawal)
        _unsafeBurn(owner, shares);
        unchecked {
            cache.totalSupply -= shares;
        }

        // Save state to storage (thus far, only mappings have been updated, so we must address everything else)
        _save(cache, /* didChangeBorrowBase: */ false);

        emit Withdraw(msg.sender, recipient, owner, amount, shares);
    }

    function mint(uint256 shares, address beneficiary) external returns (uint256 amount) {
        amount = previewMint(shares);
        require(shares == this.deposit(amount, beneficiary));
    }

    function withdraw(uint256 amount, address recipient, address owner) external returns (uint256 shares) {
        shares = previewWithdraw(amount);
        require(amount == this.redeem(shares, recipient, owner));
    }

    /*//////////////////////////////////////////////////////////////
                           BORROW/REPAY LOGIC
    //////////////////////////////////////////////////////////////*/

    function borrow(uint256 amount, address recipient) external {
        require(FACTORY.isBorrowerAllowed(this, msg.sender), "Aloe: bad account");

        // Guard against reentrancy, accrue interest, and update reserves
        (Cache memory cache, ) = _load();

        uint256 base = amount.mulDivRoundingUp(BORROWS_SCALER, cache.borrowIndex);
        cache.borrowBase += base;
        unchecked {
            borrows[msg.sender] += base;
        }

        // Transfer tokens
        cache.lastBalance -= amount;
        asset().safeTransfer(recipient, amount);

        // Save state to storage (thus far, only mappings have been updated, so we must address everything else)
        _save(cache, /* didChangeBorrowBase: */ true);
        // TODO emit event
    }

    function repay(uint256 amount, address beneficiary) external {
        // Guard against reentrancy, accrue interest, and update reserves
        (Cache memory cache, ) = _load();

        // Conditionally modify inputs, for convenience
        uint256 base;
        if (amount == 0) {
            base = borrows[beneficiary];
            amount = base.mulDivRoundingUp(cache.borrowIndex, BORROWS_SCALER);
        } else {
            base = amount.mulDiv(BORROWS_SCALER, cache.borrowIndex);
        }

        borrows[beneficiary] -= base;
        unchecked {
            cache.borrowBase -= base;
        }

        // Ensure tokens were transferred
        cache.lastBalance += amount;
        require(cache.lastBalance <= asset().balanceOf(address(this)));

        // Save state to storage (thus far, only mappings have been updated, so we must address everything else)
        _save(cache, /* didChangeBorrowBase: */ true);
        // TODO emit event
    }

    /// @dev Reentrancy guard is critical here! Without it, one could use a flash loan to repay a normal loan.
    function flash(uint256 amount, address to, bytes calldata data) external {
        // Guard against reentrancy
        uint32 _lastAccrualTime = lastAccrualTime;
        require(_lastAccrualTime != 0);
        lastAccrualTime = 0;

        ERC20 asset_ = asset();

        uint256 balance = asset_.balanceOf(address(this));
        asset_.safeTransfer(to, amount);
        IFlashBorrower(to).onFlashLoan(msg.sender, amount, data);
        require(asset_.balanceOf(address(this)) == balance, "Aloe: failed repay"); // TODO use real Error

        lastAccrualTime = _lastAccrualTime;
    }

    function accrueInterest() external {
        (Cache memory cache, ) = _load();
        _save(cache, /* didChangeBorrowBase: */ false);
    }

    function _load() private returns (Cache memory cache, uint256 inventory) {
        cache = Cache(totalSupply, lastBalance, lastAccrualTime, borrowBase, borrowIndex);
        // Guard against reentrancy
        require(cache.lastAccrualTime != 0);
        lastAccrualTime = 0;

        // Accrue interest (only in memory)
        uint256 newTotalSupply;
        (cache, inventory, newTotalSupply) = _accrueInterestView(cache);

        // Update reserves (new `totalSupply` is only in memory, but `balanceOf` is updated in storage)
        if (newTotalSupply != cache.totalSupply) {
            _unsafeMint(TREASURY, newTotalSupply - cache.totalSupply);
            cache.totalSupply = newTotalSupply;
        }
    }

    function _save(Cache memory cache, bool didChangeBorrowBase) private {
        if (cache.lastAccrualTime == 0) {
            // `cache.lastAccrualTime == 0` implies that `cache.borrowIndex` was updated.
            // `cache.borrowBase` MAY also have been updated, so we store both components of the slot.
            borrowBase = cache.borrowBase.safeCastTo184();
            borrowIndex = cache.borrowIndex.safeCastTo72();
            // Now that we've read the flag, we can update `cache.lastAccrualTime` to a more appropriate value
            cache.lastAccrualTime = block.timestamp;

        } else if (didChangeBorrowBase) {
            // Here, `cache.lastAccrualTime` is a real timestamp (could be `block.timestamp` or older). We can infer
            // that `cache.borrowIndex` was *not* updated. So we only have to store `cache.borrowBase`.
            borrowBase = cache.borrowBase.safeCastTo184();
        }

        totalSupply = cache.totalSupply.safeCastTo112();
        lastBalance = cache.lastBalance.safeCastTo112();
        lastAccrualTime = cache.lastAccrualTime.safeCastTo32(); // Disables reentrancy guard
    }

    /*//////////////////////////////////////////////////////////////
                               ERC20 LOGIC
    //////////////////////////////////////////////////////////////*/

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;

        emit Approval(msg.sender, spender, amount);

        return true;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        balanceOf[msg.sender] -= amount;

        // Cannot overflow because the sum of all user
        // balances can't exceed the max uint256 value.
        unchecked {
            balanceOf[to] += amount;
        }

        emit Transfer(msg.sender, to, amount);

        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        uint256 allowed = allowance[from][msg.sender]; // Saves gas for limited approvals.

        if (allowed != type(uint256).max) allowance[from][msg.sender] = allowed - amount;

        balanceOf[from] -= amount;

        // Cannot overflow because the sum of all user
        // balances can't exceed the max uint256 value.
        unchecked {
            balanceOf[to] += amount;
        }

        emit Transfer(from, to, amount);

        return true;
    }

    /*//////////////////////////////////////////////////////////////
                             EIP-2612 LOGIC
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
        require(deadline >= block.timestamp, "PERMIT_DEADLINE_EXPIRED");

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

            require(recoveredAddress != address(0) && recoveredAddress == owner, "INVALID_SIGNER");

            allowance[recoveredAddress][spender] = value;
        }

        emit Approval(owner, spender, value);
    }

    /*//////////////////////////////////////////////////////////////
                        INTERNAL MINT/BURN LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @dev You must do `totalSupply += amount` separately. Do so in a checked context.
    function _unsafeMint(address to, uint256 amount) private {
        unchecked {
            balanceOf[to] += amount;
        }

        emit Transfer(address(0), to, amount);
    }

    /// @dev You must do `totalSupply -= amount` separately. Do so in an unchecked context.
    function _unsafeBurn(address from, uint256 amount) private {
        balanceOf[from] -= amount;

        emit Transfer(from, address(0), amount);
    }
}
