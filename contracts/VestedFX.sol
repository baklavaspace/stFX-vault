// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import {IStakeFXVault} from "./interfaces/IStakeFXVault.sol";

contract VestedFX is Initializable, UUPSUpgradeable, OwnableUpgradeable, ReentrancyGuardUpgradeable {
    
    using SafeERC20Upgradeable for IERC20Upgradeable;
    address private stakeFXVault;
    address private fxFeeTreasury;

    struct VestingSchedule {
        uint64 startTime;
        uint64 endTime;
        uint256 quantity;
        uint256 vestedQuantity;
    }

    /// @dev vesting schedule of an account
    mapping(address => VestingSchedule[]) private accountVestingSchedules;

    /// @dev An account's total escrowed balance per token to save recomputing this for fee extraction purposes
    mapping(address => uint256) public accountEscrowedBalance;

    /// @dev An account's total vested swap per token
    mapping(address => uint256) public accountVestedBalance;

    /* ========== EVENTS ========== */
    event VestingEntryCreated(address indexed beneficiary, uint256 startTime, uint256 endTime, uint256 quantity);
    event Vested(address indexed beneficiary, uint256 vestedQuantity, uint256 index);

    receive() external payable {}

    /* ========== MODIFIERS ========== */
    modifier onlyStakeFX() {
        require(msg.sender == (stakeFXVault), "Only stakeFX can call");
        _;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /****************************************** Core Functions ******************************************/
    /**
    * @dev Allow a user to vest all ended schedules
    */
    function vestCompletedSchedules() public nonReentrant returns (uint256) {
        uint256 totalVesting = 0;
        totalVesting = _vestCompletedSchedules();

        return totalVesting;
    }

    /**************************************** View Functions ****************************************/
    /**
    * @notice The number of vesting dates in an account's schedule.
    */
    function numVestingSchedules(address account) external view returns (uint256) {
        return accountVestingSchedules[account].length;
    }

    /**
    * @dev manually get vesting schedule at index
    */
    function getVestingScheduleAtIndex(address account, uint256 index) external view returns (VestingSchedule memory) {
        return accountVestingSchedules[account][index];
    }

    /**
    * @dev Get all schedules for an account.
    */
    function getVestingSchedules(address account) external view returns (VestingSchedule[] memory) {
        return accountVestingSchedules[account];
    }

    function getstakeFXVault() external view returns (address) {
        return address(stakeFXVault);
    }

    function getFxFeeTreasury() external view returns (address) {
        return address(fxFeeTreasury);
    }

    /* ==================== INTERNAL FUNCTIONS ==================== */
    /**
    * @dev Allow a user to vest all ended schedules
    */
    function _vestCompletedSchedules() internal returns (uint256) {
        VestingSchedule[] storage schedules = accountVestingSchedules[msg.sender];
        uint256 schedulesLength = schedules.length;

        uint256 totalVesting = 0;
        for (uint256 i = 0; i < schedulesLength; i++) {
            VestingSchedule memory schedule = schedules[i];
            if (_getBlockTime() < schedule.endTime) {
                continue;
            }

            uint256 vestQuantity = (schedule.quantity) - (schedule.vestedQuantity);
            if (vestQuantity == 0) {
                continue;
            }
            schedules[i].vestedQuantity = schedule.quantity;
            totalVesting = totalVesting + (vestQuantity);

            emit Vested(msg.sender, vestQuantity, i);
        }
        _completeVesting(totalVesting);
        _clearClaimedSchedule();
        
        return totalVesting;
    }

    function _completeVesting(uint256 totalVesting) internal {
        require(totalVesting != 0, '0 vesting amount');

        accountEscrowedBalance[msg.sender] = accountEscrowedBalance[msg.sender] - (totalVesting);
        accountVestedBalance[msg.sender] = accountVestedBalance[msg.sender] + (totalVesting);

        uint256 liquidity = (stakeFXVault).balance;

        if(liquidity < totalVesting) {
             uint256 feesTreasuryLiquidity = address(fxFeeTreasury).balance;
             require((liquidity + feesTreasuryLiquidity) >= totalVesting, "Insuffient liq");
             IStakeFXVault(fxFeeTreasury).sendVestedFX(totalVesting - liquidity);
             IStakeFXVault(stakeFXVault).sendVestedFX(liquidity);
        } else {
            IStakeFXVault(stakeFXVault).sendVestedFX(totalVesting);
        }
        address recipient = payable(msg.sender);
        (bool success, ) = recipient.call{value: totalVesting}("");
        require(success, "Failed to send FX");
    }

    /**
    * @dev Delete User claimed schedule
    */
    function _clearClaimedSchedule() internal {
        VestingSchedule[] storage schedules = accountVestingSchedules[msg.sender];
        uint256 schedulesLength = schedules.length;
        uint256 index;
        for (index = 0; index < schedulesLength; index++) {
            VestingSchedule memory schedule = schedules[index];

            uint256 vestQuantity = (schedule.quantity) - (schedule.vestedQuantity);
            if (vestQuantity == 0) {
                continue;
            } else {
                break;
            }
        }
        
        if (index != 0) {            
            for(uint256 i = 0; i < schedules.length-index; i++) {
                schedules[i] = schedules[i+index];      
            }
            for(uint256 i = 0; i < index; i++) {
                schedules.pop();
            }
        }
    }

    /**
    * @dev wrap block.timestamp so we can easily mock it
    */
    function _getBlockTime() internal virtual view returns (uint32) {
        return uint32(block.timestamp);
    }

    /**************************************** Only Authorised Functions ****************************************/

    function lockWithEndTime(address account, uint256 quantity, uint256 endTime) external onlyStakeFX {
        require(quantity > 0, '0 quantity');

        VestingSchedule[] storage schedules = accountVestingSchedules[account];

        // append new schedule
        schedules.push(VestingSchedule({
            startTime: uint64(block.timestamp),
            endTime: uint64(endTime),
            quantity: quantity,
            vestedQuantity: 0
        }));

        // record total vesting balance of user
        accountEscrowedBalance[account] = accountEscrowedBalance[account] + (quantity);

        emit VestingEntryCreated(account, block.timestamp, endTime, quantity);
    }

    function recoverToken(address token, uint256 amount, address recipient) external onlyOwner {
        require(recipient != address(0), "Send to zero address");
        IERC20Upgradeable(token).safeTransfer(recipient, amount);
    }

    function updateStakeFXVault(address _stakeFXVault) external onlyOwner {
        stakeFXVault = _stakeFXVault;
    }

    function updateFxFeeTreasury(address _fxFeeTreasury) external onlyOwner {
        fxFeeTreasury = _fxFeeTreasury;
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}

    /**************************************************************
     * @dev Initialize the states
     *************************************************************/

    function initialize(address _stakeFXVault, address _fxFeeTreasury) public initializer {
        stakeFXVault = _stakeFXVault;
        fxFeeTreasury = _fxFeeTreasury;

        __Ownable_init();
        __UUPSUpgradeable_init();
    }
}