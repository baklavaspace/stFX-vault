// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.10;

/**
 * @title IPrecompileStaking
 *
 * @dev Interface to interact to network precompile staking contract functions.
 */
interface IPrecompileStaking {

    function delegate(string memory _val) external payable returns (uint256, uint256);

    function undelegate(string memory _val, uint256 _shares) external returns (uint256, uint256, uint256);

    function withdraw(string memory _val) external returns (uint256);

    function transferFromShares(string memory _val, address _from, address _to, uint256 _shares) external returns (uint256, uint256);

    function delegation(string memory _val, address _del) external view returns (uint256, uint256);

    function delegationRewards(string memory _val, address _del) external view returns (uint256);

}