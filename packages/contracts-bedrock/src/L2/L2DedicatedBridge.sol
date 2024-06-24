// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import { Predeploys } from "src/libraries/Predeploys.sol";
import { DedicatedBridge } from "src/universal/DedicatedBridge.sol";
import { ISemver } from "src/universal/ISemver.sol";
import { CrossDomainMessenger } from "src/universal/CrossDomainMessenger.sol";
import { L1Block } from "src/L2/L1Block.sol";

/// @custom:proxied
/// @title L2DedicatedBridge
/// @notice The L2DedicatedBridge is responsible for transfering a single ERC20 tokens between L1 and
///         L2. In the case that an ERC20 token is native to L2, it will be escrowed within this
///         contract. If the ERC20 token is native to L1, it will be burnt.
///         This contract is based on the L2StandardBridge contract.
contract L2DedicatedBridge is DedicatedBridge, ISemver {
    /// @custom:legacy
    /// @notice Emitted whenever a withdrawal from L2 to L1 is initiated.
    /// @param l1Token   Address of the token on L1.
    /// @param l2Token   Address of the corresponding token on L2.
    /// @param from      Address of the withdrawer.
    /// @param to        Address of the recipient on L1.
    /// @param amount    Amount of the ERC20 withdrawn.
    /// @param extraData Extra data attached to the withdrawal.
    event WithdrawalInitiated(
        address indexed l1Token,
        address indexed l2Token,
        address indexed from,
        address to,
        uint256 amount,
        bytes extraData
    );

    /// @custom:legacy
    /// @notice Emitted whenever an ERC20 deposit is finalized.
    /// @param l1Token   Address of the token on L1.
    /// @param l2Token   Address of the corresponding token on L2.
    /// @param from      Address of the depositor.
    /// @param to        Address of the recipient on L2.
    /// @param amount    Amount of the ERC20 deposited.
    /// @param extraData Extra data attached to the deposit.
    event DepositFinalized(
        address indexed l1Token,
        address indexed l2Token,
        address indexed from,
        address to,
        uint256 amount,
        bytes extraData
    );

    /// @custom:semver 1.10.0
    string public constant version = "1.10.0";

    /// @notice The address of L1 token address.
    // solhint-disable-next-line var-name-mixedcase
    address public l1Token;

    /// @notice The address of L2 token address.
    address public l2Token;

    /// @notice Constructs the L2DedicatedBridge contract.
    constructor(address _otherBridge, address _l1Token, address _l2Token) DedicatedBridge() {
        initialize({ _otherBridge: _otherBridge, _l1Token: _l1Token, _l2Token: _l2Token });
    }

    /// @notice Initializer.
    /// @param _otherBridge Contract for the corresponding bridge on the other chain.
    function initialize(address _otherBridge, address _l1Token, address _l2Token) public initializer {
        __StandardBridge_init({
            _messenger: CrossDomainMessenger(Predeploys.L2_CROSS_DOMAIN_MESSENGER),
            _otherBridge: DedicatedBridge(payable(_otherBridge))
        });
        l1Token = _l1Token;
        l2Token = _l2Token;
    }

    /// @inheritdoc DedicatedBridge
    function gasPayingToken() internal view override returns (address addr_, uint8 decimals_) {
        (addr_, decimals_) = L1Block(Predeploys.L1_BLOCK_ATTRIBUTES).gasPayingToken();
    }

    /// @custom:legacy
    /// @notice Initiates a withdrawal from L2 to L1.
    ///         Subject to be deprecated in the future.
    /// @param _l2Token     Address of the L2 token to withdraw.
    /// @param _amount      Amount of the L2 token to withdraw.
    /// @param _minGasLimit Minimum gas limit to use for the transaction.
    /// @param _extraData   Extra data attached to the withdrawal.
    function withdraw(
        address _l2Token,
        uint256 _amount,
        uint32 _minGasLimit,
        bytes calldata _extraData
    )
        external
        payable
        virtual
        onlyEOA
    {
        require(isCustomGasToken() == false, "L2DedicatedBridge: not supported with custom gas token");
        _initiateWithdrawal(_l2Token, msg.sender, msg.sender, _amount, _minGasLimit, _extraData);
    }

    /// @custom:legacy
    /// @notice Initiates a withdrawal from L2 to L1 to a target account on L1.
    ///         Subject to be deprecated in the future.
    /// @param _l2Token     Address of the L2 token to withdraw.
    /// @param _to          Recipient account on L1.
    /// @param _amount      Amount of the L2 token to withdraw.
    /// @param _minGasLimit Minimum gas limit to use for the transaction.
    /// @param _extraData   Extra data attached to the withdrawal.
    function withdrawTo(
        address _l2Token,
        address _to,
        uint256 _amount,
        uint32 _minGasLimit,
        bytes calldata _extraData
    )
        external
        payable
        virtual
    {
        require(isCustomGasToken() == false, "L2DedicatedBridge: not supported with custom gas token");
        _initiateWithdrawal(_l2Token, msg.sender, _to, _amount, _minGasLimit, _extraData);
    }

    /// @custom:legacy
    /// @notice Retrieves the access of the corresponding L1 bridge contract.
    /// @return Address of the corresponding L1 bridge contract.
    function l1TokenBridge() external view returns (address) {
        return address(otherBridge);
    }

    /// @custom:legacy
    /// @notice Internal function to initiate a withdrawal from L2 to L1 to a target account on L1.
    /// @param _l2Token     Address of the L2 token to withdraw.
    /// @param _from        Address of the withdrawer.
    /// @param _to          Recipient account on L1.
    /// @param _amount      Amount of the L2 token to withdraw.
    /// @param _minGasLimit Minimum gas limit to use for the transaction.
    /// @param _extraData   Extra data attached to the withdrawal.
    function _initiateWithdrawal(
        address _l2Token,
        address _from,
        address _to,
        uint256 _amount,
        uint32 _minGasLimit,
        bytes memory _extraData
    )
        internal
    {
        _initiateBridgeERC20(_l2Token, l1Token, _from, _to, _amount, _minGasLimit, _extraData);
    }

    /// @inheritdoc DedicatedBridge
    function _isCorrectTokenPair(address _mintableToken, address _otherToken) internal view override returns (bool) {
        return (_mintableToken == l2Token && _otherToken == l1Token);
    }

    /// @notice Emits the legacy WithdrawalInitiated event followed by the ERC20BridgeInitiated
    ///         event. This is necessary for backwards compatibility with the legacy bridge.
    /// @inheritdoc DedicatedBridge
    function _emitERC20BridgeInitiated(
        address _localToken,
        address _remoteToken,
        address _from,
        address _to,
        uint256 _amount,
        bytes memory _extraData
    )
        internal
        override
    {
        emit WithdrawalInitiated(_remoteToken, _localToken, _from, _to, _amount, _extraData);
        super._emitERC20BridgeInitiated(_localToken, _remoteToken, _from, _to, _amount, _extraData);
    }

    /// @notice Emits the legacy DepositFinalized event followed by the ERC20BridgeFinalized event.
    ///         This is necessary for backwards compatibility with the legacy bridge.
    /// @inheritdoc DedicatedBridge
    function _emitERC20BridgeFinalized(
        address _localToken,
        address _remoteToken,
        address _from,
        address _to,
        uint256 _amount,
        bytes memory _extraData
    )
        internal
        override
    {
        emit DepositFinalized(_remoteToken, _localToken, _from, _to, _amount, _extraData);
        super._emitERC20BridgeFinalized(_localToken, _remoteToken, _from, _to, _amount, _extraData);
    }
}
