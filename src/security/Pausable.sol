// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

abstract contract Pausable {
    error Paused();

    bool public paused;

    event PausedUpdated(bool paused);

    modifier whenNotPaused() {
        if (paused) revert Paused();
        _;
    }

    function _setPaused(bool newPaused) internal {
        paused = newPaused;
        emit PausedUpdated(newPaused);
    }
}
