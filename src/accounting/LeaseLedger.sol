// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { IERC20 } from "../interfaces/IERC20.sol";
import { SafeTransferLib } from "../libraries/SafeTransferLib.sol";
import { PalisadeAccess } from "../security/PalisadeAccess.sol";
import { ReentrancyGuard } from "../security/ReentrancyGuard.sol";

/// @title LeaseLedger
/// @notice Tracks withdrawable owner proceeds and protocol fees from lease payments.
contract LeaseLedger is PalisadeAccess, ReentrancyGuard {
    using SafeTransferLib for IERC20;

    error CallerNotMarket(address caller);
    error InvalidToken();
    error InvalidAccount();
    error InvalidAmount();
    error InsufficientCredit(uint256 available, uint256 requested);

    event MarketUpdated(address indexed previousMarket, address indexed newMarket);
    event PaymentCredited(
        address indexed token,
        address indexed owner,
        address indexed feeRecipient,
        uint256 ownerAmount,
        uint256 protocolAmount
    );
    event CreditWithdrawn(
        address indexed token, address indexed account, address indexed receiver, uint256 amount
    );

    address public market;

    mapping(address token => mapping(address account => uint256 amount)) public creditOf;
    mapping(address token => uint256 amount) public totalCredits;

    constructor(address initialGovernor, address initialGuardian)
        PalisadeAccess(initialGovernor, initialGuardian)
    { }

    modifier onlyMarket() {
        if (msg.sender != market) revert CallerNotMarket(msg.sender);
        _;
    }

    function setMarket(address newMarket) external onlyGovernor {
        if (newMarket == address(0)) revert ZeroAddress();
        address previous = market;
        market = newMarket;
        emit MarketUpdated(previous, newMarket);
    }

    function creditPayment(
        address token,
        address owner,
        address feeRecipient,
        uint256 ownerAmount,
        uint256 protocolAmount
    ) external onlyMarket {
        if (token == address(0)) revert InvalidToken();
        if (owner == address(0) || feeRecipient == address(0)) revert InvalidAccount();
        if (ownerAmount == 0 && protocolAmount == 0) revert InvalidAmount();

        if (ownerAmount != 0) {
            creditOf[token][owner] += ownerAmount;
        }
        if (protocolAmount != 0) {
            creditOf[token][feeRecipient] += protocolAmount;
        }
        totalCredits[token] += ownerAmount + protocolAmount;

        emit PaymentCredited(token, owner, feeRecipient, ownerAmount, protocolAmount);
    }

    function withdraw(address token, address receiver, uint256 amount)
        external
        nonReentrant
        returns (uint256 withdrawn)
    {
        if (token == address(0)) revert InvalidToken();
        if (receiver == address(0)) revert InvalidAccount();
        if (amount == 0) revert InvalidAmount();

        uint256 available = creditOf[token][msg.sender];
        if (available < amount) revert InsufficientCredit(available, amount);

        creditOf[token][msg.sender] = available - amount;
        totalCredits[token] -= amount;
        IERC20(token).safeTransfer(receiver, amount);

        emit CreditWithdrawn(token, msg.sender, receiver, amount);
        return amount;
    }

    function withdrawAll(address token, address receiver) external nonReentrant returns (uint256) {
        if (token == address(0)) revert InvalidToken();
        if (receiver == address(0)) revert InvalidAccount();

        uint256 amount = creditOf[token][msg.sender];
        if (amount == 0) revert InvalidAmount();

        creditOf[token][msg.sender] = 0;
        totalCredits[token] -= amount;
        IERC20(token).safeTransfer(receiver, amount);

        emit CreditWithdrawn(token, msg.sender, receiver, amount);
        return amount;
    }
}
