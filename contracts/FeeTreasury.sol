// SPDX-License-Identifier: MIT
pragma solidity ^0.8.2;
pragma abicoder v2;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {SafeERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import {IERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {IVestedFX} from "./interfaces/IVestedFX.sol";

/**
 * @title Treasury
 * @author Baklava
 *
 * @notice Holds an FX token. Allows the owner to transfer the token or set allowances.
 */
contract FeeTreasury is Initializable, OwnableUpgradeable, UUPSUpgradeable {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    uint256 private constant REVISION = 1;
    IVestedFX public vestedFX;


    event VestedFXChanged(address newAddress);
    event Received(address, uint);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }
    
    receive() external payable {
        emit Received(msg.sender, msg.value);
    }

    modifier onlyVestedFX() {
        require(msg.sender == address(vestedFX), "Only VestedFX can call");
        _;
    }

    function getRevision() internal pure returns (uint256) {
        return REVISION;
    }

    function recoverToken(
        IERC20Upgradeable token,
        address recipient,
        uint256 amount
    ) external onlyOwner {
        require(recipient != address(0), "Send to zero address");
        token.safeTransfer(recipient, amount);
    }

    function recoverFx(
        uint256 safeAmount,
        address _recipient
    ) external onlyOwner {
        address recipient = payable(_recipient);
        (bool success, ) = recipient.call{value: safeAmount}("");
        require(success, "Failed to send FX");
    }

    function sendVestedFX(
        uint256 safeAmount
    ) external onlyVestedFX {
        address recipient = payable(msg.sender);
        (bool success, ) = recipient.call{value: safeAmount}("");
        require(success, "Failed to send FX");
    }

    function updateVestedFX(address newAddress) external onlyOwner {
        vestedFX = IVestedFX(newAddress);
        emit VestedFXChanged(newAddress);
    }

    function _authorizeUpgrade(address newImplementation)
        internal
        override
        onlyOwner
    {}

    function initialize() external initializer {
        __Ownable_init();
        __UUPSUpgradeable_init();
    }
}
