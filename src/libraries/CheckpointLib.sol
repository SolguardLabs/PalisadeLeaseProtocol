// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { MathLib } from "./MathLib.sol";

library CheckpointLib {
    using MathLib for uint256;

    struct Cursor {
        uint256 index;
        uint256 debt;
        uint40 updatedAt;
    }

    event CursorAdvanced(uint256 indexed id, uint256 previousIndex, uint256 newIndex, uint256 debt);

    function preview(Cursor memory cursor, uint256 weight, uint256 currentIndex)
        internal
        pure
        returns (uint256)
    {
        if (currentIndex <= cursor.index) return cursor.debt;
        return cursor.debt + weight.mulDivDown(currentIndex - cursor.index, MathLib.RAY);
    }

    function advance(Cursor storage cursor, uint256 weight, uint256 currentIndex)
        internal
        returns (uint256 delta, uint256 debt)
    {
        uint256 previous = cursor.index;
        if (currentIndex > previous) {
            delta = weight.mulDivDown(currentIndex - previous, MathLib.RAY);
            cursor.debt += delta;
            cursor.index = currentIndex;
        }
        cursor.updatedAt = MathLib.toUint40(block.timestamp);
        debt = cursor.debt;
    }

    function reset(Cursor storage cursor, uint256 currentIndex) internal {
        cursor.index = currentIndex;
        cursor.debt = 0;
        cursor.updatedAt = MathLib.toUint40(block.timestamp);
    }
}
