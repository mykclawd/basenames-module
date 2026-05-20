// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

/**
 * @title IRegistrarController
 * @notice Interface for the Basenames UpgradeableRegistrarController (proxy: 0xa7d2607c6BD39Ae9521e514026CBB078405Ab322)
 * @dev The upgraded controller has an extended RegisterRequest struct with referral/cointype fields.
 */
interface IRegistrarController {
    struct Price {
        uint256 base;
        uint256 premium;
    }

    /**
     * @dev Extended RegisterRequest used by the UpgradeableRegistrarController.
     * @param name          The label to register (e.g. "mycontract" for mycontract.base.eth)
     * @param owner         The address that will own the name
     * @param duration      Registration duration in seconds (min 365 days)
     * @param resolver      The resolver contract address
     * @param data          Multicallable data for setting records (use empty array)
     * @param reverseRecord Whether to set the primary (reverse) name
     * @param coinTypes     Coin types for multi-chain address resolution (use empty array for default)
     * @param referralExpiry Referral expiry timestamp (use 0 for none)
     * @param referralData  Referral signature data (use 0x for none)
     */
    struct RegisterRequest {
        string name;
        address owner;
        uint256 duration;
        address resolver;
        bytes[] data;
        bool reverseRecord;
        uint256[] coinTypes;
        uint256 referralExpiry;
        bytes referralData;
    }

    /**
     * @notice Returns the rent price for a name
     */
    function rentPrice(
        string memory name,
        uint256 duration
    ) external view returns (Price memory);

    /**
     * @notice Registers a new basename
     */
    function register(RegisterRequest calldata request) external payable;

    /**
     * @notice Returns the minimum registration duration
     */
    function MIN_REGISTRATION_DURATION() external view returns (uint256);
}
