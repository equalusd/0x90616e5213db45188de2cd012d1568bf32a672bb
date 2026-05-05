
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title EUSDToken
 * @dev Decentralized ERC20 token with 10 billion fixed supply
 * Features: 2-step ownership transfer with 3-day timelock
 * Security: Full validation, proper event emissions, no duplicate events
 */
contract EUSDToken is ERC20, ERC20Burnable, Ownable {
    using SafeERC20 for IERC20;

    // ===== Custom Errors =====
    error ZeroAddress();
    error InvalidAmount();
    error TransferFailed();
    error NoOwnershipTransferPending();
    error TimelockNotExpired();
    error SameAddressTransfer();
    error UnauthorizedCaller();
    error OwnershipTransferAlreadyPending();

    // Supply constant - 10 Billion tokens with 18 decimals
    uint256 public constant TOTAL_SUPPLY = 10_000_000_000 * 1e18;

    // 3-day timelock (259200 seconds)
    uint256 public constant TIMELOCK_DURATION = 3 days;

    // Pending owner for 2-step transfer
    address public pendingOwner;
    uint256 public ownershipTransferInitiatedAt;

    // ================= EVENTS =================
    event TokenBurned(address indexed burner, uint256 amount);
    event NativeWithdrawn(address indexed recipient, uint256 amount);
    event TokenWithdrawn(
        address indexed tokenAddress,
        address indexed recipient,
        uint256 amount
    );
    
    // Ownership transfer events
    event OwnershipTransferInitiated(
        address indexed currentOwner,
        address indexed pendingOwner,
        uint256 executionTime
    );
    
    event OwnershipTransferCancelled(
        address indexed currentOwner,
        address indexed cancelledPendingOwner
    );

    // ================= CONSTRUCTOR =================
    /**
     * @dev Constructor - mints all 10B tokens to owner
     * @param owner_ The owner address that receives all tokens
     */
    constructor(address owner_) ERC20("Equal USD", "EUSD") Ownable(owner_) {
        if (owner_ == address(0)) revert ZeroAddress();
        
        // Mint all tokens to owner
        _mint(owner_, TOTAL_SUPPLY);
    }

    // ================= OWNERSHIP TRANSFER (2-STEP WITH TIMELOCK) =================
    
    /**
     * @dev Initiate ownership transfer - STEP 1
     * Only current owner can initiate
     * Cannot re-initiate if transfer already pending
     * @param newOwner New owner address
     */
    function initiateOwnershipTransfer(address newOwner) external onlyOwner {
        // Validation: address check
        if (newOwner == address(0)) revert ZeroAddress();
        
        // Validation: cannot transfer to self
        if (newOwner == owner()) revert SameAddressTransfer();
        
        // Validation: cannot re-initiate if transfer already pending
        if (pendingOwner != address(0)) revert OwnershipTransferAlreadyPending();

        // Set pending owner and record initiation time
        pendingOwner = newOwner;
        ownershipTransferInitiatedAt = block.timestamp;
        
        // Calculate execution time (3 days from now)
        uint256 executionTime = block.timestamp + TIMELOCK_DURATION;

        // Emit event with all details
        emit OwnershipTransferInitiated(msg.sender, newOwner, executionTime);
    }

    /**
     * @dev Cancel pending ownership transfer
     * Only current owner can cancel
     * Clears pending owner and resets timelock
     */
    function cancelOwnershipTransfer() external onlyOwner {
        // Validation: check if transfer is pending
        if (pendingOwner == address(0)) revert NoOwnershipTransferPending();
        
        // Store pending owner for event logging
        address cancelledOwner = pendingOwner;
        
        // Clear pending state
        pendingOwner = address(0);
        ownershipTransferInitiatedAt = 0;

        // Emit event
        emit OwnershipTransferCancelled(msg.sender, cancelledOwner);
    }

    /**
     * @dev Complete ownership transfer - STEP 2
     * Can ONLY be called after 3-day timelock
     * Can ONLY be called by pending owner (confirmation required)
     * Uses Ownable's _transferOwnership which emits OwnershipTransferred event
     */
    function completeOwnershipTransfer() external {
        // Validation 1: caller must be pending owner
        if (msg.sender != pendingOwner) revert UnauthorizedCaller();
        
        // Validation 2: pending owner must exist
        if (pendingOwner == address(0)) revert NoOwnershipTransferPending();
        
        // Validation 3: timelock must have expired
        uint256 timelockExpiryTime = ownershipTransferInitiatedAt + TIMELOCK_DURATION;
        if (block.timestamp < timelockExpiryTime) revert TimelockNotExpired();

        // Store new owner before clearing state
        address newOwner = pendingOwner;

        // Clear pending state BEFORE transfer (security: prevent reentrancy)
        pendingOwner = address(0);
        ownershipTransferInitiatedAt = 0;

        // Transfer ownership - Ownable emits OwnershipTransferred internally
        // NO DUPLICATE EVENT - we rely on Ownable's event
        _transferOwnership(newOwner);
    }

    /**
     * @dev Get remaining time before ownership transfer can be completed
     * @return remainingSeconds Seconds remaining (0 if ready to transfer or no transfer pending)
     */
    function getRemainingLockTime() external view returns (uint256 remainingSeconds) {
        // If no transfer pending, return 0
        if (pendingOwner == address(0)) return 0;
        
        // Calculate unlock time
        uint256 unlockTime = ownershipTransferInitiatedAt + TIMELOCK_DURATION;
        
        // If already unlocked, return 0
        if (block.timestamp >= unlockTime) return 0;
        
        // Return remaining time
        return unlockTime - block.timestamp;
    }

    /**
     * @dev Get ownership transfer status
     * @return isPending Is transfer currently pending
     * @return currentPendingOwner Address of pending owner (if any)
     * @return initiatedAt Timestamp when transfer was initiated
     * @return canCompleteAt Timestamp when transfer can be completed
     */
    function getOwnershipTransferStatus() 
        external 
        view 
        returns (
            bool isPending,
            address currentPendingOwner,
            uint256 initiatedAt,
            uint256 canCompleteAt
        ) 
    {
        isPending = pendingOwner != address(0);
        currentPendingOwner = pendingOwner;
        initiatedAt = ownershipTransferInitiatedAt;
        canCompleteAt = isPending 
            ? ownershipTransferInitiatedAt + TIMELOCK_DURATION 
            : 0;
    }

    // ================= BURN FUNCTIONS =================
    
    /**
     * @dev Burn tokens (decrease total supply)
     * Anyone can burn their own tokens
     * @param amount Amount of tokens to burn
     */
    function burn(uint256 amount) public override {
        if (amount == 0) revert InvalidAmount();
        super.burn(amount);
        emit TokenBurned(msg.sender, amount);
    }

    /**
     * @dev Burn tokens from another account (with allowance)
     * @param account Account to burn from
     * @param amount Amount of tokens to burn
     */
    function burnFrom(address account, uint256 amount) public override {
        if (account == address(0)) revert ZeroAddress();
        if (amount == 0) revert InvalidAmount();
        super.burnFrom(account, amount);
        emit TokenBurned(account, amount);
    }

    // ================= WITHDRAW FUNCTIONS (OWNER ONLY) =================
    
    /**
     * @dev Withdraw native ETH from contract
     * Only owner can withdraw
     * @param to Recipient address (cannot be zero address)
     * @param amount Amount of ETH to withdraw
     */
    function withdrawNative(address payable to, uint256 amount) external onlyOwner {
        // Validation: recipient check
        if (to == address(0)) revert ZeroAddress();
        
        // Validation: amount check
        if (amount == 0) revert InvalidAmount();
        if (amount > address(this).balance) revert InvalidAmount();

        // Transfer ETH using low-level call (gas-efficient)
        (bool success, ) = to.call{value: amount}("");
        if (!success) revert TransferFailed();

        emit NativeWithdrawn(to, amount);
    }

    /**
     * @dev Withdraw any ERC20 token from contract
     * Only owner can withdraw
     * Cannot withdraw EUSD itself (to prevent accidental loss)
     * @param token Token address to withdraw
     * @param to Recipient address
     * @param amount Amount to withdraw
     */
    function withdrawToken(
        address token,
        address to,
        uint256 amount
    ) external onlyOwner {
        // Validation: address checks
        if (to == address(0)) revert ZeroAddress();
        if (token == address(0)) revert ZeroAddress();
        
        // Validation: cannot withdraw EUSD itself
        if (token == address(this)) revert InvalidAmount();
        
        // Validation: amount check
        if (amount == 0) revert InvalidAmount();

        // Validation: sufficient balance check
        IERC20 tokenContract = IERC20(token);
        uint256 balance = tokenContract.balanceOf(address(this));
        if (amount > balance) revert InvalidAmount();

        // Safe transfer using SafeERC20
        tokenContract.safeTransfer(to, amount);
        
        emit TokenWithdrawn(token, to, amount);
    }

    // ================= RECEIVE ETH =================
    
    /**
     * @dev Allow contract to receive ETH donations/payments
     */
    receive() external payable {}

    // ================= METADATA =================
    
    /**
     * @dev Get contract version string
     */
    function version() external pure returns (string memory) {
        return "EUSD-V1-Timelock-Final";
    }
}
