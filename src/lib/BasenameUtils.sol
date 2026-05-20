// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

/**
 * @title BasenameUtils
 * @notice Pure utility library for ENS namehash calculations on Basenames (base.eth)
 * @dev Implements the ENS namehash algorithm without external dependencies
 */
library BasenameUtils {
    /// @notice The namehash of "base.eth"
    bytes32 public constant BASE_ETH_NODE = 0xff1e3c0eb00ec714e2b7139c290c28ae5c1e7069d6d3cf41567aa5806d24a58c;

    /**
     * @notice Computes the ENS namehash of a fully qualified name
     * @param name The domain name (e.g. "myname.base.eth")
     * @return The namehash as bytes32
     */
    function namehash(string memory name) internal pure returns (bytes32) {
        bytes memory nameBytes = bytes(name);
        if (nameBytes.length == 0) {
            return bytes32(0);
        }

        bytes32 node = bytes32(0);

        // Split by '.' and hash labels from right to left
        bytes memory label;
        uint256 lastDot = nameBytes.length;

        for (uint256 i = nameBytes.length; i > 0; i--) {
            if (nameBytes[i - 1] == ".") {
                label = slice(nameBytes, i, lastDot - i);
                node = keccak256(abi.encodePacked(node, keccak256(label)));
                lastDot = i - 1;
            }
        }

        // Hash the leftmost label
        label = slice(nameBytes, 0, lastDot);
        node = keccak256(abi.encodePacked(node, keccak256(label)));

        return node;
    }

    /**
     * @notice Computes the keccak256 hash of a single label
     * @param label The label to hash (without dots)
     */
    function labelHash(string memory label) internal pure returns (bytes32) {
        return keccak256(bytes(label));
    }

    /**
     * @notice Computes the namehash for a basename (appends .base.eth)
     * @param name The label (e.g. "mycontract")
     * @return The namehash of "name.base.eth"
     */
    function basenameNode(string memory name) internal pure returns (bytes32) {
        bytes32 label = labelHash(name);
        return keccak256(abi.encodePacked(BASE_ETH_NODE, label));
    }

    /**
     * @dev Helper to slice bytes (Solidity doesn't have native slicing for memory bytes in older versions)
     */
    function slice(
        bytes memory data,
        uint256 start,
        uint256 length
    ) internal pure returns (bytes memory) {
        bytes memory result = new bytes(length);
        for (uint256 i = 0; i < length; i++) {
            result[i] = data[start + i];
        }
        return result;
    }
}
