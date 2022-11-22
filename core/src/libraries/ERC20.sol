// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

library ERC20 {
    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    event Transfer(address indexed from, address indexed to, uint256 amount);

    event Approval(address indexed owner, address indexed spender, uint256 amount);

    /*//////////////////////////////////////////////////////////////
                              ERC20 STORAGE
    //////////////////////////////////////////////////////////////*/

    bytes32 constant ERC20_POSITION = keccak256("erc20.storage");

    struct ERC20Storage {
        mapping(address => uint256) balanceOf;
        mapping(address => mapping(address => uint256)) allowance;
    }

    function erc20Storage() internal pure returns (ERC20Storage storage s) {
        bytes32 position = ERC20_POSITION;
        assembly {
            s.slot := position
        }
    }

    /*//////////////////////////////////////////////////////////////
                            EIP-2612 STORAGE
    //////////////////////////////////////////////////////////////*/

    bytes32 constant EIP2612_POSITION = keccak256("eip2612.storage");

    struct EIP2612Storage {
        bytes32 lastDomainSeparator;
        uint256 lastChainId;
        mapping(address => uint256) nonces;
    }

    function eip2612Storage() internal pure returns (EIP2612Storage storage s) {
        bytes32 position = EIP2612_POSITION;
        assembly {
            s.slot := position
        }
    }

    /*//////////////////////////////////////////////////////////////
                               ERC20 LOGIC
    //////////////////////////////////////////////////////////////*/

    function approve(address spender, uint256 amount) internal returns (bool) {
        erc20Storage().allowance[msg.sender][spender] = amount;

        emit Approval(msg.sender, spender, amount);

        return true;
    }

    function transfer(address to, uint256 amount) internal returns (bool) {
        ERC20Storage storage s = erc20Storage();

        s.balanceOf[msg.sender] -= amount;

        // A single address should be able to hold all the tokens, so as long
        // as `totalSupply` doesn't exceed type(uint256).max, this won't overflow.
        // It's up to the consumer to track `totalSupply` properly.
        unchecked {
            s.balanceOf[to] += amount;
        }

        emit Transfer(msg.sender, to, amount);

        return true;
    }

    function transferFrom(address from, address to, uint256 amount) internal returns (bool) {
        ERC20Storage storage s = erc20Storage();

        uint256 allowed = s.allowance[from][msg.sender]; // Saves gas for limited approvals.

        if (allowed != type(uint256).max) s.allowance[from][msg.sender] = allowed - amount;

        s.balanceOf[from] -= amount;

        // A single address should be able to hold all the tokens, so as long
        // as `totalSupply` doesn't exceed type(uint256).max, this won't overflow.
        // It's up to the consumer to track `totalSupply` properly.
        unchecked {
            s.balanceOf[to] += amount;
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
    ) internal {
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
                                eip2612Storage().nonces[owner]++,
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

            erc20Storage().allowance[recoveredAddress][spender] = value;
        }

        emit Approval(owner, spender, value);
    }

    function DOMAIN_SEPARATOR() internal returns (bytes32) {
        EIP2612Storage storage s = eip2612Storage();

        if (s.lastDomainSeparator == bytes32(0) || s.lastChainId != block.chainid) {
            s.lastDomainSeparator = computeDomainSeparator();
            s.lastChainId = block.chainid;
        }

        return s.lastDomainSeparator;
    }

    function computeDomainSeparator() private view returns (bytes32) {
        return
            keccak256(
                abi.encode(
                    keccak256("EIP712Domain(string version,uint256 chainId,address verifyingContract)"),
                    // TODO is it ok that we omit `name`?!
                    keccak256("1"),
                    block.chainid,
                    address(this)
                )
            );
    }

    /*//////////////////////////////////////////////////////////////
                        INTERNAL MINT/BURN LOGIC
    //////////////////////////////////////////////////////////////*/

    // function _mint(address to, uint256 amount) internal virtual {
    //     totalSupply += amount;

    //     // Cannot overflow because the sum of all user
    //     // balances can't exceed the max uint256 value.
    //     unchecked {
    //         balanceOf[to] += amount;
    //     }

    //     emit Transfer(address(0), to, amount);
    // }

    // function _burn(address from, uint256 amount) internal virtual {
    //     balanceOf[from] -= amount;

    //     // Cannot underflow because a user's balance
    //     // will never be larger than the total supply.
    //     unchecked {
    //         totalSupply -= amount;
    //     }

    //     emit Transfer(from, address(0), amount);
    // }
}
