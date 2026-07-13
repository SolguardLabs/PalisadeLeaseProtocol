// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { MathLib } from "./MathLib.sol";

library RewardAttributionLib {
    using MathLib for uint256;

    struct Segment {
        address beneficiary;
        uint256 startIndex;
        uint256 endIndex;
        uint256 weight;
        uint40 startTime;
        uint40 endTime;
    }

    struct Attribution {
        address beneficiary;
        uint256 rewards;
        uint256 segments;
    }

    error InvalidSegment(uint256 index);
    error SegmentArrayTooLarge();

    function segmentReward(Segment memory segment) internal pure returns (uint256) {
        if (segment.endIndex <= segment.startIndex || segment.weight == 0) return 0;
        return segment.weight.mulDivDown(segment.endIndex - segment.startIndex, MathLib.RAY);
    }

    function validateOrdered(Segment[] memory segments) internal pure returns (bool) {
        if (segments.length > 1024) revert SegmentArrayTooLarge();
        for (uint256 i; i < segments.length; ++i) {
            Segment memory current = segments[i];
            if (current.beneficiary == address(0)) revert InvalidSegment(i);
            if (current.endIndex < current.startIndex) revert InvalidSegment(i);
            if (current.endTime < current.startTime) revert InvalidSegment(i);
            if (i != 0) {
                Segment memory previous = segments[i - 1];
                if (current.startTime < previous.endTime) revert InvalidSegment(i);
            }
        }
        return true;
    }

    function totalRewards(Segment[] memory segments) internal pure returns (uint256 total) {
        validateOrdered(segments);
        for (uint256 i; i < segments.length; ++i) {
            total += segmentReward(segments[i]);
        }
    }

    function rewardsFor(Segment[] memory segments, address beneficiary)
        internal
        pure
        returns (uint256 rewards, uint256 matchedSegments)
    {
        validateOrdered(segments);
        for (uint256 i; i < segments.length; ++i) {
            if (segments[i].beneficiary == beneficiary) {
                rewards += segmentReward(segments[i]);
                matchedSegments += 1;
            }
        }
    }

    function attributions(Segment[] memory segments, address[] memory beneficiaries)
        internal
        pure
        returns (Attribution[] memory result)
    {
        validateOrdered(segments);
        result = new Attribution[](beneficiaries.length);
        for (uint256 i; i < beneficiaries.length; ++i) {
            (uint256 rewards, uint256 matchedSegments) =
                rewardsForUnchecked(segments, beneficiaries[i]);
            result[i] = Attribution({
                beneficiary: beneficiaries[i], rewards: rewards, segments: matchedSegments
            });
        }
    }

    function rewardsForUnchecked(Segment[] memory segments, address beneficiary)
        internal
        pure
        returns (uint256 rewards, uint256 matchedSegments)
    {
        for (uint256 i; i < segments.length; ++i) {
            if (segments[i].beneficiary == beneficiary) {
                rewards += segmentReward(segments[i]);
                matchedSegments += 1;
            }
        }
    }

    function append(
        Segment[] memory segments,
        address beneficiary,
        uint256 startIndex,
        uint256 endIndex,
        uint256 weight,
        uint40 startTime,
        uint40 endTime
    ) internal pure returns (Segment[] memory next) {
        next = new Segment[](segments.length + 1);
        for (uint256 i; i < segments.length; ++i) {
            next[i] = segments[i];
        }
        next[segments.length] = Segment({
            beneficiary: beneficiary,
            startIndex: startIndex,
            endIndex: endIndex,
            weight: weight,
            startTime: startTime,
            endTime: endTime
        });
        validateOrdered(next);
    }

    function mergeAdjacent(Segment[] memory segments)
        internal
        pure
        returns (Segment[] memory merged)
    {
        validateOrdered(segments);
        if (segments.length == 0) return new Segment[](0);

        Segment[] memory scratch = new Segment[](segments.length);
        uint256 count = 1;
        scratch[0] = segments[0];

        for (uint256 i = 1; i < segments.length; ++i) {
            Segment memory current = segments[i];
            Segment memory previous = scratch[count - 1];

            if (
                previous.beneficiary == current.beneficiary
                    && previous.endIndex == current.startIndex && previous.weight == current.weight
                    && previous.endTime == current.startTime
            ) {
                previous.endIndex = current.endIndex;
                previous.endTime = current.endTime;
                scratch[count - 1] = previous;
            } else {
                scratch[count] = current;
                count += 1;
            }
        }

        merged = new Segment[](count);
        for (uint256 i; i < count; ++i) {
            merged[i] = scratch[i];
        }
    }
}
