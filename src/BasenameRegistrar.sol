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

    // =============================================================
    //                           ERRORS
    // =============================================================

    error InsufficientETH(uint256 required, uint256 provided);
    error InvalidDuration();
    error EmptyName();

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
     */
    constructor(
        address registrarController_,
        address reverseRegistrar_,
        address l2Resolver_
    ) {
        if (
            registrarController_ != address(0) &&
            reverseRegistrar_ != address(0) &&
            l2Resolver_ != address(0)
        ) {
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
     * @param name     The label to register, e.g. "myapp" → myapp.base.eth
     * @param duration Seconds to register for (minimum MIN_REGISTRATION_DURATION)
     */
    function _registerBasename(string memory name, uint256 duration) internal {
        if (bytes(name).length == 0) revert EmptyName();
        if (duration < MIN_REGISTRATION_DURATION) revert InvalidDuration();

        IRegistrarController controller = IRegistrarController(_getRegistrarController());

        // Get the price and forward the exact amount to the registrar.
        // We intentionally do NOT check address(this).balance here — doing so
        // causes eth_estimateGas to revert when the contract has no pre-existing
        // balance, which gives MetaMask a wrong gas limit and shows "likely to fail".
        // Instead we forward msg.value directly; if it's insufficient the registrar
        // will revert with its own InsufficientValue() error.
        IRegistrarController.Price memory price = controller.rentPrice(name, duration);
        uint256 totalPrice = price.base + price.premium;

        // Build request. data[] is intentionally empty: the L2Resolver's setAddr
        // is gated to the address stored in resolver.registrarController, which
        // may differ from the active controller. Set forward resolution separately
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

        // Refund any excess ETH to the caller
        uint256 excess = address(this).balance;
        if (excess > 0) {
            (bool ok, ) = msg.sender.call{value: excess}("");
            ok; // non-reverting — registration already succeeded
        }

        emit BasenameRegistered(name, address(this), duration);
    }

    /**
     * @notice Set the forward addr record: name.base.eth → address(this).
     * @dev Call this right after _registerBasename to complete both directions.
     *      Also works as a rescue function: if a contract already owns a name but
     *      the forward addr record is wrong or missing, call this to fix it.
     *      The contract must own the name (be the registry node owner) for this
     *      to be authorised by the resolver.
     * @param name The label (e.g. "myapp" for myapp.base.eth)
     */
    function _setForwardResolution(string memory name) internal {
        if (bytes(name).length == 0) revert EmptyName();
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
