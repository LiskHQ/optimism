// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { VmSafe } from "forge-std/Vm.sol";
import { Script } from "forge-std/Script.sol";

import { console2 as console } from "forge-std/console2.sol";
import { stdJson } from "forge-std/StdJson.sol";

import { GnosisSafe as Safe } from "safe-contracts/GnosisSafe.sol";

import { Deploy } from "scripts/Deploy.s.sol";

import { ProxyAdmin } from "src/universal/ProxyAdmin.sol";
import { DedicatedBridge } from "src/universal/DedicatedBridge.sol";
import { L1DedicatedBridge } from "src/L1/L1DedicatedBridge.sol";
import { L1DedicatedUSDCBridge } from "src/L1/L1DedicatedUSDCBridge.sol";
import { L2DedicatedBridge } from "src/L2/L2DedicatedBridge.sol";
import { L1ChugSplashProxy } from "src/legacy/L1ChugSplashProxy.sol";
import { L1CrossDomainMessenger } from "src/L1/L1CrossDomainMessenger.sol";
import { SuperchainConfig } from "src/L1/SuperchainConfig.sol";
import { SystemConfig } from "src/L1/SystemConfig.sol";
import { Proxy } from "src/universal/Proxy.sol";


import "src/dispute/lib/Types.sol";
import { EIP1967Helper } from "test/mocks/EIP1967Helper.sol";

/// @title DeployDedicatedBridge
/// @notice Script used to deploy a dedicated bridge.
contract DeployDedicatedBridge is Deploy {
    using stdJson for string;


    ////////////////////////////////////////////////////////////////
    //           High Level Deployment Functions                  //
    ////////////////////////////////////////////////////////////////

    /// @notice Deploy L1 dedicated bridge
    function runL1DedicatedBridgeDeployment(address _otherBridge, address _l1Token, address _l2Token) public {
        console.log("Deploying L1 Dedicated bridge");

        deploySafe("SystemOwnerSafe");

        // Deploy a new ProxyAdmin and AddressManager
        // This proxy will be used on the SuperchainConfig and ProtocolVersions contracts, as well as the contracts
        // in the OP Chain system.
        deployAddressManager();
        deployProxyAdmin();
        transferProxyAdminOwnership();

        // Deploy the SuperchainConfigProxy
        deployERC1967Proxy("SuperchainConfigProxy");
        deploySuperchainConfig();
        initializeSuperchainConfig();

        deployL1DedicatedBridgeProxy();
        transferAddressManagerOwnership(); // to the ProxyAdmin
        deployL1DedicatedBridge();
        initializeL1DedicatedBridge(_otherBridge, _l1Token, _l2Token);
        console.log("Done!");
    }

    ////////////////////////////////////////////////////////////////
    //                Proxy Deployment Functions                  //
    ////////////////////////////////////////////////////////////////

    /// @notice Deploy the L1DedicatedBridgeProxy using a ChugSplashProxy
    function deployL1DedicatedBridgeProxy() public broadcast returns (address addr_) {
        console.log("Deploying proxy for L1DedicatedUSDCBridge");
        address proxyAdmin = mustGetAddress("ProxyAdmin");
        L1ChugSplashProxy proxy = new L1ChugSplashProxy(proxyAdmin);

        require(EIP1967Helper.getAdmin(address(proxy)) == proxyAdmin);

        save("L1DedicatedBridgeProxy", address(proxy));
        console.log("L1DedicatedBridgeProxy deployed at %s", address(proxy));
        addr_ = address(proxy);
    }

    /// @notice Deploy the L2DedicatedBridgeProxy using a Proxy
    function deployL2DedicatedBridgeProxy() public returns (address addr_) {
        console.log("Deploying proxy for L2DedicatedBridge");
        addr_ = deployERC1967ProxyWithOwner("L2DedicatedBridgeProxy", msg.sender);
    }

    /// @notice Deploy the L1DedicatedUSDCBridge
    function deployL1DedicatedBridge() public broadcast returns (address addr_) {
        console.log("Deploying L1DedicatedUSDCBridge implementation");

        L1DedicatedUSDCBridge bridge = new L1DedicatedUSDCBridge{ salt: _implSalt() }();

        save("L1DedicatedUSDCBridge", address(bridge));
        console.log("L1DedicatedUSDCBridge deployed at %s", address(bridge));

        addr_ = address(bridge);
    }

    /// @notice Deploy the L2DedicatedBridge
    function deployL2DedicatedBridge() public broadcast returns (address addr_) {
        console.log("Deploying L2DedicatedBridge implementation");

        L2DedicatedBridge bridge = new L2DedicatedBridge{ salt: _implSalt() }();

        save("L2DedicatedBridge", address(bridge));
        console.log("L2DedicatedBridge deployed at %s", address(bridge));

        addr_ = address(bridge);
    }

    ////////////////////////////////////////////////////////////////
    //                    Initialize Functions                    //
    ////////////////////////////////////////////////////////////////

    /// @notice Initialize the L1DedicatedUSDCBridge
    function initializeL1DedicatedBridge(address _otherBridge, address _l1Token, address _l2Token) public broadcast {
        console.log("Upgrading and initializing L1DedicatedUSDCBridge proxy");
        ProxyAdmin proxyAdmin = ProxyAdmin(mustGetAddress("ProxyAdmin"));
        address l1DedicatedBridgeProxy = mustGetAddress("L1DedicatedBridgeProxy");

        uint256 proxyType = uint256(proxyAdmin.proxyType(l1DedicatedBridgeProxy));
        Safe safe = Safe(mustGetAddress("SystemOwnerSafe"));
        if (proxyType != uint256(ProxyAdmin.ProxyType.CHUGSPLASH)) {
            _callViaSafe({
                _safe: safe,
                _target: address(proxyAdmin),
                _data: abi.encodeCall(ProxyAdmin.setProxyType, (l1DedicatedBridgeProxy, ProxyAdmin.ProxyType.CHUGSPLASH))
            });
        }
        require(uint256(proxyAdmin.proxyType(l1DedicatedBridgeProxy)) == uint256(ProxyAdmin.ProxyType.CHUGSPLASH));

        _upgradeAndCallViaSafe({
            _proxy: payable(l1DedicatedBridgeProxy),
            _implementation: mustGetAddress("L1DedicatedUSDCBridge"),
            _innerCallData: abi.encodeCall(
                L1DedicatedBridge.initialize,
                (
                    L1CrossDomainMessenger(cfg.l1CrossDomainMessengerProxy()),
                    SuperchainConfig(mustGetAddress("SuperchainConfigProxy")),
                    SystemConfig(cfg.systemConfigProxy()),
                    _otherBridge,
                    _l1Token,
                    _l2Token
                )
            )
        });

        string memory version = L1DedicatedUSDCBridge(payable(l1DedicatedBridgeProxy)).version();
        console.log("L1DedicatedUSDCBridge version: %s", version);
    }

    /// @notice Initialize the L2DedicatedBridge
    function initializeL2DedicatedBridge(
        address _proxy,
        address _implementation,
        address _otherBridge,
        address _l1Token,
        address _l2Token
    )
        public
        broadcast
    {
        bytes memory _data = abi.encodeCall(L2DedicatedBridge.initialize, (_otherBridge, _l1Token, _l2Token));
        Proxy(payable(_proxy)).upgradeToAndCall(_implementation, _data);
    }
}
