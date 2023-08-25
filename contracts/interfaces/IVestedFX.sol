// SPDX-License-Identifier: Apache-2.0

pragma solidity ^0.8.0;

interface IVestedFX {
    
    struct VestingSchedule {
        uint64 startTime;
        uint64 endTime;
        uint256 quantity;
        uint256 vestedQuantity;
    }

    function lockWithEndTime(address account, uint256 quantity, uint256 endTime) external;

    function getVestingSchedules(address account) external view returns (VestingSchedule[] memory);

    function accountEscrowedBalance(address account) external view returns (uint256);

    function accountVestedBalance(address account) external view returns (uint256);
}