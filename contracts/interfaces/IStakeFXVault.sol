// SPDX-License-Identifier: Apache-2.0

pragma solidity ^0.8.0;

interface IStakeFXVault {

    function sendVestedFX(uint256 safeAmount) external;

    function updateRewards() external;

    function getValLength() external view returns (uint256);

    function getValInfo(uint256 index) external view returns (uint256, string memory);
}
