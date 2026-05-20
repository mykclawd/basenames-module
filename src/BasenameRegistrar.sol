// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {IRegistrarController} from "./interfaces/IRegistrarController.sol";
import {IReverseRegistrar} from "./interfaces/IReverseRegistrar.sol";
import {IL2Resolver} from "./interfaces/IL2Resolver.sol";
import {BasenameUtils} from "./lib/BasenameUtils.sol";

/**
 * @title BasenameRegistrar
 * @notice Abstract contract that enables any smart contract to easily register
 *         and manage its own Basename (primary name on Base)
 * @dev Inherit from this contract to gain basename registration capabilities.
 *
 *      IMPORTANT: The inheriting contract must be able to receive ETH or have
 *      sufficient balance when calling registration functions.
 *
 *      Mainnet addresses are hardcoded. Use the constructor for testnets.
 */
abstract contract BasenameRegistrar {
    using BasenameUtils for string;

    // =============================================================
    //                           EVENTS
    // =============================================================

    /**
     * @notice Emitted when a basename is successfully registered for this contract
     */
    event BasenameRegistered(
        string indexed name,
        address indexed contractAddress,
        uint256 duration
    );

    /**
     * @notice Emitted when the primary basename is set/reset for this contract
     */
    event PrimaryBasenameSet(string indexed name, address indexed contractAddress);

    // =============================================================
    //                           ERRORS
    // =============================================================

    error InsufficientETH(uint256 required, uint256 provided);
    error RegistrationFailed();
    error InvalidDuration();
    error EmptyName();

    // =============================================================
    //                           CONSTANTS
    // =============================================================

    /// @notice RegistrarController on Base mainnet
    /// @dev This is the UpgradeableRegistrarController (proxy) — the original
    ///      RegistrarController (0x4cCb...) is no longer approved by BaseRegistrar.
    address public constant REGISTRAR_CONTROLLER =
        0xa7d2607c6BD39Ae9521e514026CBB078405Ab322;

    /// @notice ReverseRegistrar on Base mainnet
    address public constant REVERSE_REGISTRAR =
        0x79EA96012eEa67A83431F1701B3dFf7e37F9E282;

    /// @notice L2Resolver on Base mainnet
    address public constant L2_RESOLVER =
        0xC6d566A56A1aFf6508b41f6c90ff131615583BCD;

    /// @notice Minimum registration duration (365 days)
    uint256 public constant MIN_REGISTRATION_DURATION = 365 days;

    // =============================================================
    //                           STORAGE
    // =============================================================

    /// @notice Allows overriding addresses for testing / testnets
    bool internal _useCustomAddresses;
    address internal _customRegistrarController;
    address internal _customReverseRegistrar;
    address internal _customL2Resolver;

    // =============================================================
    //                           CONSTRUCTOR
    // =============================================================

    /**
     * @notice Constructor for custom network configuration (mainly for testing)
     * @dev Leave empty to use mainnet constants. Only set if deploying on testnet.
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
    //                           REGISTRATION
    // =============================================================

    /**
     * @notice Internal function to register a new basename for this contract
     * @dev The contract will own the name and set itself as the primary name.
     *      Sends any excess ETH back to the caller.
     * @param name The label to register (e.g. "mycontract" → mycontract.base.eth)
     * @param duration Registration duration in seconds (minimum 365 days)
     */
    function _registerBasename(
        string memory name,
        uint256 duration
    ) internal {
        if (bytes(name).length == 0) revert EmptyName();
        if (duration < MIN_REGISTRATION_DURATION) revert InvalidDuration();

        IRegistrarController controller = IRegistrarController(
            _getRegistrarController()
        );
        IReverseRegistrar reverseRegistrar = IReverseRegistrar(
            _getReverseRegistrar()
        );
        IL2Resolver resolver = IL2Resolver(_getL2Resolver());

        // Get price
        IRegistrarController.Price memory price = controller.rentPrice(
            name,
            duration
        );
        uint256 totalPrice = price.base + price.premium;

        if (address(this).balance < totalPrice) {
            revert InsufficientETH(totalPrice, address(this).balance);
        }

        // Register with empty data[] — the L2Resolver only allows the
        // RegistrarController (stored in its registrarController slot) to call
        // setAddr during registration. Since the active controller address may
        // differ from what's stored in the resolver, we skip the setAddr multicall
        // here and rely on reverseRecord=true for the primary (reverse) name.
        // Forward resolution (name → address) can be set separately by the owner
        // via the L2Resolver after registration.
        bytes[] memory data = new bytes[](0);

        uint256[] memory coinTypes = new uint256[](0);

        IRegistrarController.RegisterRequest memory request = IRegistrarController
            .RegisterRequest({
                name: name,
                owner: address(this),
                duration: duration,
                resolver: _getL2Resolver(),
                data: data,
                reverseRecord: true, // Sets primary (reverse) name: address → name
                coinTypes: coinTypes, // No extra coin type resolution
                referralExpiry: 0,   // No referral
                referralData: ""     // No referral data
            });

        // Execute registration
        controller.register{value: totalPrice}(request);

        // Refund any excess ETH
        uint256 remaining = address(this).balance;
        if (remaining > 0) {
            (bool success, ) = msg.sender.call{value: remaining}("");
            // We don't revert on refund failure to not break registration
            success; // silence warning
        }

        emit BasenameRegistered(name, address(this), duration);
    }

    /**
     * @notice Sets or updates the primary basename for this contract
     * @dev Use this when the name is already registered but you want to set/re-set primary
     * @param name The full name including .base.eth or just the label
     */
    function _setPrimaryBasename(string memory name) internal {
        if (bytes(name).length == 0) revert EmptyName();

        // Normalize: if user passed just label, append .base.eth
        string memory fullName = name;
        if (!_endsWithBaseEth(name)) {
            fullName = string(abi.encodePacked(name, ".base.eth"));
        }

        IReverseRegistrar reverseRegistrar = IReverseRegistrar(
            _getReverseRegistrar()
        );

        // Calling setName from this contract sets the reverse record for address(this)
        reverseRegistrar.setName(fullName);

        emit PrimaryBasenameSet(name, address(this));
    }

    // =============================================================
    //                           VIEWS
    // =============================================================

    /**
     * @notice Returns the total cost to register a name for a given duration
     */
    function getBasenamePrice(
        string memory name,
        uint256 duration
    ) public view returns (uint256) {
        IRegistrarController controller = IRegistrarController(
            _getRegistrarController()
        );
        IRegistrarController.Price memory price = controller.rentPrice(
            name,
            duration
        );
        return price.base + price.premium;
    }

    // =============================================================
    //                           INTERNAL HELPERS
    // =============================================================

    function _getRegistrarController() internal view returns (address) {
        return
            _useCustomAddresses
                ? _customRegistrarController
                : REGISTRAR_CONTROLLER;
    }

    function _getReverseRegistrar() internal view returns (address) {
        return
            _useCustomAddresses
                ? _customReverseRegistrar
                : REVERSE_REGISTRAR;
    }

    function _getL2Resolver() internal view returns (address) {
        return _useCustomAddresses ? _customL2Resolver : L2_RESOLVER;
    }

    function _endsWithBaseEth(
        string memory str
    ) internal pure returns (bool) {
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

    /**
     * @notice Allows the contract to receive ETH for registration payments
     */
    receive() external payable virtual {}
}
