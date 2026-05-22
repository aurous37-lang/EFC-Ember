// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "./MaintenancePool.sol";

/// @title MaintenancePoolFactory — stateless deployer for MaintenancePool (Layer 4)
/// @notice Extracted so `EmberFactory` does not embed MaintenancePool's creation
///         bytecode, which would push `EmberFactory` over the EIP-170 runtime-size
///         limit. This contract holds no state and no authority: `create` is a
///         permissionless CREATE wrapper, identical to deploying a MaintenancePool
///         directly. The pool's parameters and governor are supplied entirely by
///         the caller (EmberFactory), so this deployer grants no extra trust.
contract MaintenancePoolFactory {
    event PoolCreated(address indexed pool, address indexed emberToken, address governor);

    function create(
        address emberToken,
        address governor,
        address usdc,
        MaintenancePool.GovernanceMode mode,
        uint256 timelockDelay
    ) external returns (address pool) {
        require(emberToken != address(0), "no ember");
        require(governor != address(0), "no governor");
        require(usdc != address(0), "no USDC");
        require(timelockDelay >= 1 days && timelockDelay <= 30 days, "bad delay");
        pool = address(new MaintenancePool(emberToken, governor, usdc, mode, timelockDelay));
        emit PoolCreated(pool, emberToken, governor);
    }
}
