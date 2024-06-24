// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { VmSafe } from "forge-std/Vm.sol";
import { Script } from "forge-std/Script.sol";

import { console2 as console } from "forge-std/console2.sol";
import { stdJson } from "forge-std/StdJson.sol";

import { GnosisSafe as Safe } from "safe-contracts/GnosisSafe.sol";
import { OwnerManager } from "safe-contracts/base/OwnerManager.sol";
import { GnosisSafeProxyFactory as SafeProxyFactory } from "safe-contracts/proxies/GnosisSafeProxyFactory.sol";
import { Enum as SafeOps } from "safe-contracts/common/Enum.sol";

import { Deployer } from "scripts/Deployer.sol";

import { ProxyAdmin } from "src/universal/ProxyAdmin.sol";
import { AddressManager } from "src/legacy/AddressManager.sol";
import { Proxy } from "src/universal/Proxy.sol";
import { DedicatedBridge } from "src/universal/DedicatedBridge.sol";
import { L1DedicatedBridge } from "src/L1/L1DedicatedBridge.sol";
import { L1DedicatedUSDCBridge } from "src/L1/L1DedicatedUSDCBridge.sol";
import { L2DedicatedBridge } from "src/L2/L2DedicatedBridge.sol";
import { L1ChugSplashProxy } from "src/legacy/L1ChugSplashProxy.sol";
import { ResolvedDelegateProxy } from "src/legacy/ResolvedDelegateProxy.sol";
import { L1CrossDomainMessenger } from "src/L1/L1CrossDomainMessenger.sol";
import { SuperchainConfig } from "src/L1/SuperchainConfig.sol";
import { SystemConfig } from "src/L1/SystemConfig.sol";
import { SystemConfigInterop } from "src/L1/SystemConfigInterop.sol";
import { ResourceMetering } from "src/L1/ResourceMetering.sol";
import { DataAvailabilityChallenge } from "src/L1/DataAvailabilityChallenge.sol";
import { Constants } from "src/libraries/Constants.sol";
import { AnchorStateRegistry } from "src/dispute/AnchorStateRegistry.sol";
import { PreimageOracle } from "src/cannon/PreimageOracle.sol";
import { ProtocolVersions, ProtocolVersion } from "src/L1/ProtocolVersions.sol";
import { StorageSetter } from "src/universal/StorageSetter.sol";
import { Predeploys } from "src/libraries/Predeploys.sol";
import { Proxy } from "src/universal/Proxy.sol";

import { Chains } from "scripts/Chains.sol";
import { Config } from "scripts/Config.sol";

import { IBigStepper } from "src/dispute/interfaces/IBigStepper.sol";
import { IPreimageOracle } from "src/cannon/interfaces/IPreimageOracle.sol";
import { AlphabetVM } from "test/mocks/AlphabetVM.sol";
import "src/dispute/lib/Types.sol";
import { ChainAssertions } from "scripts/ChainAssertions.sol";
import { Types } from "scripts/Types.sol";
import { LibStateDiff } from "scripts/libraries/LibStateDiff.sol";
import { EIP1967Helper } from "test/mocks/EIP1967Helper.sol";
import { ForgeArtifacts } from "scripts/ForgeArtifacts.sol";
import { Process } from "scripts/libraries/Process.sol";

/// @title Deploy
/// @notice Script used to deploy a dedicated bridge.
contract DeployDedicatedBridge is Deployer {
    using stdJson for string;

    ////////////////////////////////////////////////////////////////
    //                        Modifiers                           //
    ////////////////////////////////////////////////////////////////

    /// @notice Modifier that wraps a function in broadcasting.
    modifier broadcast() {
        vm.startBroadcast(msg.sender);
        _;
        vm.stopBroadcast();
    }

    /// @notice Modifier that will only allow a function to be called on devnet.
    modifier onlyDevnet() {
        uint256 chainid = block.chainid;
        if (chainid == Chains.LocalDevnet || chainid == Chains.GethDevnet) {
            _;
        }
    }

    /// @notice Modifier that will only allow a function to be called on a public
    ///         testnet or devnet.
    modifier onlyTestnetOrDevnet() {
        uint256 chainid = block.chainid;
        if (
            chainid == Chains.Goerli || chainid == Chains.Sepolia || chainid == Chains.LocalDevnet
                || chainid == Chains.GethDevnet
        ) {
            _;
        }
    }

    /// @notice Modifier that wraps a function with statediff recording.
    ///         The returned AccountAccess[] array is then written to
    ///         the `snapshots/state-diff/<name>.json` output file.
    modifier stateDiff() {
        vm.startStateDiffRecording();
        _;
        VmSafe.AccountAccess[] memory accesses = vm.stopAndReturnStateDiff();
        console.log(
            "Writing %d state diff account accesses to snapshots/state-diff/%s.json",
            accesses.length,
            vm.toString(block.chainid)
        );
        string memory json = LibStateDiff.encodeAccountAccesses(accesses);
        string memory statediffPath =
            string.concat(vm.projectRoot(), "/snapshots/state-diff/", vm.toString(block.chainid), ".json");
        vm.writeJson({ json: json, path: statediffPath });
    }

    ////////////////////////////////////////////////////////////////
    //                        Accessors                           //
    ////////////////////////////////////////////////////////////////

    /// @notice The create2 salt used for deployment of the contract implementations.
    ///         Using this helps to reduce config across networks as the implementation
    ///         addresses will be the same across networks when deployed with create2.
    function _implSalt() internal view returns (bytes32) {
        return keccak256(bytes(Config.implSalt()));
    }

    /// @notice Returns the proxy addresses. If a proxy is not found, it will have address(0).
    function _proxies() internal view returns (Types.ContractSet memory proxies_) {
        proxies_ = Types.ContractSet({
            L1CrossDomainMessenger: mustGetAddress("L1CrossDomainMessengerProxy"),
            L1StandardBridge: mustGetAddress("L1StandardBridgeProxy"),
            L2OutputOracle: mustGetAddress("L2OutputOracleProxy"),
            DisputeGameFactory: mustGetAddress("DisputeGameFactoryProxy"),
            DelayedWETH: mustGetAddress("DelayedWETHProxy"),
            AnchorStateRegistry: mustGetAddress("AnchorStateRegistryProxy"),
            OptimismMintableERC20Factory: mustGetAddress("OptimismMintableERC20FactoryProxy"),
            OptimismPortal: mustGetAddress("OptimismPortalProxy"),
            OptimismPortal2: mustGetAddress("OptimismPortalProxy"),
            SystemConfig: mustGetAddress("SystemConfigProxy"),
            L1ERC721Bridge: mustGetAddress("L1ERC721BridgeProxy"),
            ProtocolVersions: mustGetAddress("ProtocolVersionsProxy"),
            SuperchainConfig: mustGetAddress("SuperchainConfigProxy")
        });
    }

    /// @notice Returns the proxy addresses, not reverting if any are unset.
    function _proxiesUnstrict() internal view returns (Types.ContractSet memory proxies_) {
        proxies_ = Types.ContractSet({
            L1CrossDomainMessenger: getAddress("L1CrossDomainMessengerProxy"),
            L1StandardBridge: getAddress("L1StandardBridgeProxy"),
            L2OutputOracle: getAddress("L2OutputOracleProxy"),
            DisputeGameFactory: getAddress("DisputeGameFactoryProxy"),
            DelayedWETH: getAddress("DelayedWETHProxy"),
            AnchorStateRegistry: getAddress("AnchorStateRegistryProxy"),
            OptimismMintableERC20Factory: getAddress("OptimismMintableERC20FactoryProxy"),
            OptimismPortal: getAddress("OptimismPortalProxy"),
            OptimismPortal2: getAddress("OptimismPortalProxy"),
            SystemConfig: getAddress("SystemConfigProxy"),
            L1ERC721Bridge: getAddress("L1ERC721BridgeProxy"),
            ProtocolVersions: getAddress("ProtocolVersionsProxy"),
            SuperchainConfig: getAddress("SuperchainConfigProxy")
        });
    }

    ////////////////////////////////////////////////////////////////
    //            State Changing Helper Functions                 //
    ////////////////////////////////////////////////////////////////

    /// @notice Gets the address of the SafeProxyFactory and Safe singleton for use in deploying a new GnosisSafe.
    function _getSafeFactory() internal returns (SafeProxyFactory safeProxyFactory_, Safe safeSingleton_) {
        if (getAddress("SafeProxyFactory") != address(0)) {
            // The SafeProxyFactory is already saved, we can just use it.
            safeProxyFactory_ = SafeProxyFactory(getAddress("SafeProxyFactory"));
            safeSingleton_ = Safe(getAddress("SafeSingleton"));
            return (safeProxyFactory_, safeSingleton_);
        }

        // These are the standard create2 deployed contracts. First we'll check if they are deployed,
        // if not we'll deploy new ones, though not at these addresses.
        address safeProxyFactory = 0xa6B71E26C5e0845f74c812102Ca7114b6a896AB2;
        address safeSingleton = 0xd9Db270c1B5E3Bd161E8c8503c55cEABeE709552;

        safeProxyFactory.code.length == 0
            ? safeProxyFactory_ = new SafeProxyFactory()
            : safeProxyFactory_ = SafeProxyFactory(safeProxyFactory);

        safeSingleton.code.length == 0 ? safeSingleton_ = new Safe() : safeSingleton_ = Safe(payable(safeSingleton));

        save("SafeProxyFactory", address(safeProxyFactory_));
        save("SafeSingleton", address(safeSingleton_));
    }

    /// @notice Make a call from the Safe contract to an arbitrary address with arbitrary data
    function _callViaSafe(Safe _safe, address _target, bytes memory _data) internal {
        // This is the signature format used the caller is also the signer.
        bytes memory signature = abi.encodePacked(uint256(uint160(msg.sender)), bytes32(0), uint8(1));

        _safe.execTransaction({
            to: _target,
            value: 0,
            data: _data,
            operation: SafeOps.Operation.Call,
            safeTxGas: 0,
            baseGas: 0,
            gasPrice: 0,
            gasToken: address(0),
            refundReceiver: payable(address(0)),
            signatures: signature
        });
    }

    /// @notice Call from the Safe contract to the Proxy Admin's upgrade and call method
    function _upgradeAndCallViaSafe(address _proxy, address _implementation, bytes memory _innerCallData) internal {
        address proxyAdmin = mustGetAddress("ProxyAdmin");

        bytes memory data =
            abi.encodeCall(ProxyAdmin.upgradeAndCall, (payable(_proxy), _implementation, _innerCallData));

        Safe safe = Safe(mustGetAddress("SystemOwnerSafe"));
        _callViaSafe({ _safe: safe, _target: proxyAdmin, _data: data });
    }

    /// @notice Transfer ownership of the ProxyAdmin contract to the final system owner
    function transferProxyAdminOwnership() public {
        ProxyAdmin proxyAdmin = ProxyAdmin(mustGetAddress("ProxyAdmin"));
        address owner = proxyAdmin.owner();
        address safe = mustGetAddress("SystemOwnerSafe");
        if (owner != safe) {
            proxyAdmin.transferOwnership(safe);
            console.log("ProxyAdmin ownership transferred to Safe at: %s", safe);
        }
    }

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

    // /// @notice Deploy the L1DedicatedBridge
    // function deployAndInitializeL2DedicatedBridge(
    //     address _proxy,
    //     address _otherBridge,
    //     address _l1Token,
    //     address _l2Token
    // )
    //     public
    //     returns (address addr_)
    // {
    //     addr_ = deployL2DedicatedBridge();
    //     initializeL2DedicatedBridge(_proxy, _otherBridge, _l1Token, _l2Token);

    //     addr_;
    // }

    ////////////////////////////////////////////////////////////////
    //              Non-Proxied Deployment Functions              //
    ////////////////////////////////////////////////////////////////

    /// @notice Deploy the Safe
    function deploySafe(string memory _name) public returns (address addr_) {
        address[] memory owners = new address[](0);
        addr_ = deploySafe(_name, owners, 1, true);
    }

    /// @notice Deploy a new Safe contract. If the keepDeployer option is used to enable further setup actions, then
    ///         the removeDeployerFromSafe() function should be called on that safe after setup is complete.
    ///         Note this function does not have the broadcast modifier.
    /// @param _name The name of the Safe to deploy.
    /// @param _owners The owners of the Safe.
    /// @param _threshold The threshold of the Safe.
    /// @param _keepDeployer Wether or not the deployer address will be added as an owner of the Safe.
    function deploySafe(
        string memory _name,
        address[] memory _owners,
        uint256 _threshold,
        bool _keepDeployer
    )
        public
        broadcast
        returns (address addr_)
    {
        bytes32 salt = keccak256(abi.encode(_name, _implSalt()));
        console.log("Deploying safe: %s with salt %s", _name, vm.toString(salt));
        (SafeProxyFactory safeProxyFactory, Safe safeSingleton) = _getSafeFactory();

        address[] memory expandedOwners = new address[](_owners.length + 1);
        if (_keepDeployer) {
            // By always adding msg.sender first we know that the previousOwner will be SENTINEL_OWNERS, which makes it
            // easier to call removeOwner later.
            expandedOwners[0] = msg.sender;
            for (uint256 i = 0; i < _owners.length; i++) {
                expandedOwners[i + 1] = _owners[i];
            }
            _owners = expandedOwners;
        }

        bytes memory initData = abi.encodeCall(
            Safe.setup, (_owners, _threshold, address(0), hex"", address(0), address(0), 0, payable(address(0)))
        );
        addr_ = address(safeProxyFactory.createProxyWithNonce(address(safeSingleton), initData, uint256(salt)));

        save(_name, addr_);
        console.log("New safe: %s deployed at %s\n    Note that this safe is owned by the deployer key", _name, addr_);
    }

    /// @notice If the keepDeployer option was used with deploySafe(), this function can be used to remove the deployer.
    ///         Note this function does not have the broadcast modifier.
    function removeDeployerFromSafe(string memory _name, uint256 _newThreshold) public {
        Safe safe = Safe(mustGetAddress(_name));

        // The sentinel address is used to mark the start and end of the linked list of owners in the Safe.
        address sentinelOwners = address(0x1);

        // Because deploySafe() always adds msg.sender first (if keepDeployer is true), we know that the previousOwner
        // will be sentinelOwners.
        _callViaSafe({
            _safe: safe,
            _target: address(safe),
            _data: abi.encodeCall(OwnerManager.removeOwner, (sentinelOwners, msg.sender, _newThreshold))
        });
        console.log("Removed deployer owner from ", _name);
    }

    /// @notice Deploy the AddressManager
    function deployAddressManager() public broadcast returns (address addr_) {
        console.log("Deploying AddressManager");
        AddressManager manager = new AddressManager();
        require(manager.owner() == msg.sender);

        save("AddressManager", address(manager));
        console.log("AddressManager deployed at %s", address(manager));
        addr_ = address(manager);
    }

    /// @notice Deploy the ProxyAdmin
    function deployProxyAdmin() public broadcast returns (address addr_) {
        console.log("Deploying ProxyAdmin");
        ProxyAdmin admin = new ProxyAdmin({ _owner: msg.sender });
        require(admin.owner() == msg.sender);

        AddressManager addressManager = AddressManager(mustGetAddress("AddressManager"));
        if (admin.addressManager() != addressManager) {
            admin.setAddressManager(addressManager);
        }

        require(admin.addressManager() == addressManager);

        save("ProxyAdmin", address(admin));
        console.log("ProxyAdmin deployed at %s", address(admin));
        addr_ = address(admin);
    }

    /// @notice Deploy the StorageSetter contract, used for upgrades.
    function deployStorageSetter() public broadcast returns (address addr_) {
        console.log("Deploying StorageSetter");
        StorageSetter setter = new StorageSetter{ salt: _implSalt() }();
        console.log("StorageSetter deployed at: %s", address(setter));
        string memory version = setter.version();
        console.log("StorageSetter version: %s", version);
        addr_ = address(setter);
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

    /// @notice Deploys an ERC1967Proxy contract with the ProxyAdmin as the owner.
    /// @param _name The name of the proxy contract to be deployed.
    /// @return addr_ The address of the deployed proxy contract.
    function deployERC1967Proxy(string memory _name) public broadcast returns (address addr_) {
        addr_ = deployERC1967ProxyWithOwner(_name, mustGetAddress("ProxyAdmin"));
    }

    /// @notice Deploys an ERC1967Proxy contract with a specified owner.
    /// @param _name The name of the proxy contract to be deployed.
    /// @param _proxyOwner The address of the owner of the proxy contract.
    /// @return addr_ The address of the deployed proxy contract.
    function deployERC1967ProxyWithOwner(
        string memory _name,
        address _proxyOwner
    )
        public
        broadcast
        returns (address addr_)
    {
        console.log(string.concat("Deploying ERC1967 proxy for ", _name));
        Proxy proxy = new Proxy({ _admin: _proxyOwner });

        require(EIP1967Helper.getAdmin(address(proxy)) == _proxyOwner);

        save(_name, address(proxy));
        console.log("   at %s", address(proxy));
        addr_ = address(proxy);
    }

    ////////////////////////////////////////////////////////////////
    //             Implementation Deployment Functions            //
    ////////////////////////////////////////////////////////////////

    /// @notice Deploy the SuperchainConfig contract
    function deploySuperchainConfig() public broadcast {
        SuperchainConfig superchainConfig = new SuperchainConfig{ salt: _implSalt() }();

        require(superchainConfig.guardian() == address(0));
        bytes32 initialized = vm.load(address(superchainConfig), bytes32(0));
        require(initialized != 0);

        save("SuperchainConfig", address(superchainConfig));
        console.log("SuperchainConfig deployed at %s", address(superchainConfig));
    }

    /// @notice Transfer ownership of the address manager to the ProxyAdmin
    function transferAddressManagerOwnership() public broadcast {
        console.log("Transferring AddressManager ownership to ProxyAdmin");
        AddressManager addressManager = AddressManager(mustGetAddress("AddressManager"));
        address owner = addressManager.owner();
        address proxyAdmin = mustGetAddress("ProxyAdmin");
        if (owner != proxyAdmin) {
            addressManager.transferOwnership(proxyAdmin);
            console.log("AddressManager ownership transferred to %s", proxyAdmin);
        }

        require(addressManager.owner() == proxyAdmin);
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

    /// @notice Initialize the SuperchainConfig
    function initializeSuperchainConfig() public broadcast {
        address payable superchainConfigProxy = mustGetAddress("SuperchainConfigProxy");
        address payable superchainConfig = mustGetAddress("SuperchainConfig");
        _upgradeAndCallViaSafe({
            _proxy: superchainConfigProxy,
            _implementation: superchainConfig,
            _innerCallData: abi.encodeCall(SuperchainConfig.initialize, (cfg.superchainConfigGuardian(), false))
        });

        ChainAssertions.checkSuperchainConfig({ _contracts: _proxiesUnstrict(), _cfg: cfg, _isPaused: false });
    }

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
        bytes memory data = abi.encodeCall(L2DedicatedBridge.initialize, (_otherBridge, _l1Token, _l2Token));
        Proxy(_proxy).upgradeToAndCall(_implementation, _data);
    }
}
