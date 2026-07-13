// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

library PositionIdLib {
    function derive(
        address vault,
        address owner,
        uint256 nonce,
        uint256 shares,
        bytes32 metadataHash
    ) internal view returns (uint256) {
        return uint256(
            keccak256(
                abi.encodePacked(
                    bytes1(0x50),
                    block.chainid,
                    vault,
                    owner,
                    nonce,
                    shares,
                    block.timestamp,
                    metadataHash
                )
            )
        );
    }

    function shortId(uint256 positionId) internal pure returns (bytes8) {
        return bytes8(bytes32(positionId));
    }
}
