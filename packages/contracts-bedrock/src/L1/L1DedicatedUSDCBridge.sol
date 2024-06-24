// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { L1DedicatedBridge } from "src/L1/L1DedicatedBridge.sol";
import { ISemver } from "src/universal/ISemver.sol";
import { CrossDomainMessenger } from "src/universal/CrossDomainMessenger.sol";
import { SuperchainConfig } from "src/L1/SuperchainConfig.sol";
import { OptimismPortal } from "src/L1/OptimismPortal.sol";
import { SystemConfig } from "src/L1/SystemConfig.sol";

/// @custom:proxied
/// @title L1DedicatedUSDCBridge
/// @notice The L1DedicatedUSDCBridge is responsible for transfering the USDC token between L1 and
///         L2.
contract L1DedicatedUSDCBridge is L1DedicatedBridge {
    /// @notice Burns all locked USDC if the bridge is already paused
    function burnAllLockedUSDC() external {
        require(paused() == true, "Bridge should be paused before burning all locked USDC");
        require(msg.sender == superchainConfig.guardian(), "SuperchainConfig: only guardian can burn all USDC");
        deposits[l1Token][l2Token] = 0;
        // IERC20(l1USDC).burn(_balance); // check if this needs to be done
    }
}
