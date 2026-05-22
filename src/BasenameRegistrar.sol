// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {IRegistrarController} from "./interfaces/IRegistrarController.sol";
import {IReverseRegistrar} from "./interfaces/IReverseRegistrar.sol";
import {IL2Resolver} from "./interfaces/IL2Resolver.sol";
import {BasenameUtils} from "./lib/BasenameUtils.sol";

/**
 * @title BasenameRegistrar
 * @notice Abstract contract that enables any smart contract to register and manage
 *         its own Basename (name.base.eth) on Base.
 *
 * @dev Inherit from this contract, then expose public wrappers protected by your
 *      own access control (e.g. onlyOwner). Example:
 *
 *      function registerBasename(string memory name, uint256 duration)
 *          external payable onlyOwner
 *      {
 *          _registerBasename(name, duration);
 *          _setForwardResolution(name);   // sets name.base.eth → address(this)
 *      }
 *
 *      After registration both directions are set:
 *        address(this) → name.base.eth   (reverse — set during registration)
 *        name.base.eth → address(this)   (forward — set by _setForwardResolution)
 *
 *      Rescue: if a contract already owns a name but the forward record is wrong,
 *      call _setForwardResolution(name) at any time to correct it.
 */
abstract contract BasenameRegistrar {

    // =============================================================
    //                           EVENTS
    // =============================================================

    /// @notice Emitted when a basename is successfully registered.
    event BasenameRegistered(
        string indexed name,
        address indexed contractAddress,
        uint256 duration
    );

    /// @notice Emitted when the primary (reverse) name is set or updated.
    event PrimaryBasenameSet(string indexed name, address indexed contractAddress);

    /// @notice Emitted when the forward addr record is set on the resolver.
    event ForwardResolutionSet(string indexed name, address indexed contractAddress);

    /// @notice Emitted when an excess ETH refund fails (e.g. caller is a contract
    ///         with a reverting receive()). Registration already succeeded — the
    ///         stranded ETH can be recovered via a rescue function in the inheritor.
    event RefundFailed(address indexed recipient, uint256 amount);

    // =============================================================
    //                           ERRORS
    // =============================================================

    error InsufficientETH(uint256 required, uint256 provided);
    error InvalidDuration();
    error EmptyName();
    error PartialAddressOverride();

    // =============================================================
    //                           CONSTANTS
    // =============================================================

    /// @notice UpgradeableRegistrarController proxy — the active registration
    ///         contract on Base mainnet (0x4cCb... is deprecated and no longer
    ///         approved by BaseRegistrar).
    address public constant REGISTRAR_CONTROLLER =
        0xa7d2607c6BD39Ae9521e514026CBB078405Ab322;

    /// @notice ReverseRegistrar on Base mainnet.
    address public constant REVERSE_REGISTRAR =
        0x79EA96012eEa67A83431F1701B3dFf7e37F9E282;

    /// @notice L2Resolver on Base mainnet.
    address public constant L2_RESOLVER =
        0xC6d566A56A1aFf6508b41f6c90ff131615583BCD;

    /// @notice Minimum registration duration (365 days).
    uint256 public constant MIN_REGISTRATION_DURATION = 365 days;

    // =============================================================
    //                           STORAGE
    // =============================================================

    /// @dev Set to true when testnet addresses are provided in the constructor.
    bool internal _useCustomAddresses;
    address internal _customRegistrarController;
    address internal _customReverseRegistrar;
    address internal _customL2Resolver;

    // =============================================================
    //                           CONSTRUCTOR
    // =============================================================

    /**
     * @notice Pass (address(0), address(0), address(0)) for Base mainnet.
     *         Pass actual addresses to override for testnets.
     * @dev All three addresses must be set together or all must be zero.
     *      Passing a partial set (e.g. two addresses + address(0)) reverts to
     *      prevent silent fallback to mainnet constants on testnet deployments.
     */
    constructor(
        address registrarController_,
        address reverseRegistrar_,
        address l2Resolver_
    ) {
        bool anySet = registrarController_ != address(0)
                   || reverseRegistrar_   != address(0)
                   || l2Resolver_         != address(0);
        bool allSet = registrarController_ != address(0)
                   && reverseRegistrar_   != address(0)
                   && l2Resolver_         != address(0);
        if (anySet && !allSet) revert PartialAddressOverride();
        if (allSet) {
            _useCustomAddresses = true;
            _customRegistrarController = registrarController_;
            _customReverseRegistrar = reverseRegistrar_;
            _customL2Resolver = l2Resolver_;
        }
    }

    // =============================================================
    //                    REGISTRATION & RESOLUTION
    // =============================================================

    /**
     * @notice Register a new basename and set the reverse (primary) name.
     * @dev Does NOT set forward resolution automatically — call _setForwardResolution
     *      immediately after to complete both directions. Refunds excess ETH.
     *
     * @dev ⚠️ REENTRANCY: This function calls msg.sender (ETH refund) before returning.
     *      Any public wrapper that updates state MUST use a nonReentrant modifier or
     *      follow the checks-effects-interactions pattern.
     *
     * @dev ⚠️ REFUND FAILURE: If msg.sender is a smart contract whose receive() reverts,
     *      the excess ETH refund will fail silently (registration still succeeds). A
     *      RefundFailed event is emitted. Inheriting contracts SHOULD expose an
     *      owner-callable ETH withdrawal function to recover any stranded refunds:
     *
     *          function rescueEth() external onlyOwner {
     *              (bool ok, ) = msg.sender.call{value: address(this).balance}("");
     *              require(ok, "ETH transfer failed");
     *          }
     *
     * @dev ⚠️ PREMIUM DECAY: During premium decay periods, the price changes per block.
     *      Send a 2–5% buffer above getBasenamePrice() to absorb price movement.
     *      Excess is always refunded.
     *
     * @param name     The bare label to register, e.g. "myapp" → myapp.base.eth
     * @param duration Seconds to register for (minimum MIN_REGISTRATION_DURATION)
     */
    function _registerBasename(string memory name, uint256 duration) internal {
        if (bytes(name).length == 0) revert EmptyName();
        if (duration < MIN_REGISTRATION_DURATION) revert InvalidDuration();

        IRegistrarController controller = IRegistrarController(_getRegistrarController());

        // Determine price.
        // We check msg.value (not address(this).balance) for two reasons:
        // 1. Checking address(this).balance causes eth_estimateGas to revert on a
        //    zero-balance contract, giving wallets a wrong gas limit.
        // 2. Only ETH sent with THIS call should fund the registration — the contract
        //    may hold ETH for other purposes (treasury) that must not be touched.
        IRegistrarController.Price memory price = controller.rentPrice(name, duration);
        uint256 totalPrice = price.base + price.premium;
        if (msg.value < totalPrice) revert InsufficientETH(totalPrice, msg.value);

        // Build request. data[] is intentionally empty: the L2Resolver's setAddr
        // is gated to the address stored in resolver.registrarController, which
        // differs from the active controller. Set forward resolution separately
        // via _setForwardResolution() after this call.
        bytes[] memory data = new bytes[](0);
        uint256[] memory coinTypes = new uint256[](0);

        IRegistrarController.RegisterRequest memory request = IRegistrarController
            .RegisterRequest({
                name: name,
                owner: address(this),
                duration: duration,
                resolver: _getL2Resolver(),
                data: data,
                reverseRecord: true,   // sets address(this) → name.base.eth
                coinTypes: coinTypes,
                referralExpiry: 0,
                referralData: ""
            });

        controller.register{value: totalPrice}(request);

        // Emit before refund to preserve CEI order and avoid reentrancy issues
        // with off-chain monitors reading events mid-reentry.
        emit BasenameRegistered(name, address(this), duration);

        // Refund only the excess from THIS call's msg.value — not the contract's
        // total balance, which may include funds held for other purposes.
        // excess = what was sent in - what the registrar charged
        uint256 excess = msg.value - totalPrice;
        if (excess > 0) {
            (bool ok, ) = msg.sender.call{value: excess}("");
            // Non-reverting: registration already succeeded on-chain.
            // If the caller's receive() reverts (e.g. multisig in restricted state),
            // excess ETH is stranded in this contract. Emit event for off-chain recovery.
            if (!ok) emit RefundFailed(msg.sender, excess);
        }
    }

    /**
     * @notice Set the forward addr record: name.base.eth → address(this).
     * @dev Call this right after _registerBasename to complete both directions.
     *      Also works as a rescue function: if a contract already owns a name but
     *      the forward addr record is wrong or missing, call this to fix it.
     *      The contract must own the name (be the registry node owner) for this
     *      to be authorised by the resolver.
     *
     * @dev Accepts ONLY the bare label (e.g. "myapp", not "myapp.base.eth").
     *      Passing a full name like "myapp.base.eth" will set the wrong ENS node
     *      (myapp.base.eth.base.eth) and silently break forward resolution.
     *      Use _setPrimaryBasename if you need to accept both forms.
     *
     * @param name The bare label only (e.g. "myapp" for myapp.base.eth)
     */
    function _setForwardResolution(string memory name) internal {
        if (bytes(name).length == 0) revert EmptyName();
        // Guard: reject full names like "myapp.base.eth" — passing those produces
        // the wrong ENS node (myapp.base.eth.base.eth). Bare labels only.
        if (_endsWithBaseEth(name)) revert EmptyName();
        bytes32 node = BasenameUtils.basenameNode(name);
        // setAddr(bytes32 node, address a) sets coinType 60 (ETH) addr record.
        // Authorised because address(this) is the registry owner of the node.
        IL2Resolver(_getL2Resolver()).setAddr(node, address(this));
        emit ForwardResolutionSet(name, address(this));
    }

    /**
     * @notice Set or update the primary (reverse) name for this contract.
     * @dev Use when the name is already registered but you want to update the
     *      reverse record — e.g. after transferring a name to this contract.
     * @param name The label or full name (e.g. "myapp" or "myapp.base.eth")
     */
    function _setPrimaryBasename(string memory name) internal {
        if (bytes(name).length == 0) revert EmptyName();

        string memory fullName = _endsWithBaseEth(name)
            ? name
            : string(abi.encodePacked(name, ".base.eth"));

        IReverseRegistrar(_getReverseRegistrar()).setName(fullName);
        emit PrimaryBasenameSet(name, address(this));
    }

    // =============================================================
    //                           VIEWS
    // =============================================================

    /**
     * @notice Returns the total cost in wei to register a name for a given duration.
     */
    function getBasenamePrice(
        string memory name,
        uint256 duration
    ) public view returns (uint256) {
        IRegistrarController controller = IRegistrarController(_getRegistrarController());
        IRegistrarController.Price memory price = controller.rentPrice(name, duration);
        return price.base + price.premium;
    }

    // =============================================================
    //                       INTERNAL HELPERS
    // =============================================================

    function _getRegistrarController() internal view returns (address) {
        return _useCustomAddresses ? _customRegistrarController : REGISTRAR_CONTROLLER;
    }

    function _getReverseRegistrar() internal view returns (address) {
        return _useCustomAddresses ? _customReverseRegistrar : REVERSE_REGISTRAR;
    }

    function _getL2Resolver() internal view returns (address) {
        return _useCustomAddresses ? _customL2Resolver : L2_RESOLVER;
    }

    function _endsWithBaseEth(string memory str) internal pure returns (bool) {
        bytes memory b = bytes(str);
        bytes memory suffix = bytes(".base.eth");
        if (b.length < suffix.length) return false;
        for (uint256 i = 0; i < suffix.length; i++) {
            if (b[b.length - suffix.length + i] != suffix[i]) return false;
        }
        return true;
    }

    // =============================================================
    //                           RECEIVE
    // =============================================================

    receive() external payable virtual {}
}
