// SPDX-License-Identifier: Apache-2.0

pragma solidity ^0.8.0;

interface IWFX {
    function deposit() external payable;

    function withdraw(address payable to, uint256 value) external;

    function transferFrom(address from, address to, uint256 amount) external;
}