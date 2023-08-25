// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {IERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import {SafeERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

import {IStakeFXVault} from "./interfaces/IStakeFXVault.sol";
import {PrecompileStaking} from "./imp/PrecompileStaking.sol";

contract MultiCall is
    Initializable,
    UUPSUpgradeable,
    OwnableUpgradeable,
    PrecompileStaking
{
    using SafeERC20Upgradeable for IERC20Upgradeable;

    address stFX;

    struct ValidatorDelegationInfo {
        string validator;
        uint256 allocPoint;
        uint256 delegationAmount;
        uint256 delegationReward;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**************************************** Public/External View Functions ****************************************

    /**
    * @dev Get all validator delegation for stFX.
    */
    function getAllValidatorDelegation() external view returns (ValidatorDelegationInfo[] memory validatorDelegations) {
        uint256 validatorsLength = IStakeFXVault(stFX).getValLength();

        validatorDelegations = new ValidatorDelegationInfo[](validatorsLength);
        for (uint256 i = 0; i < validatorsLength; i++) {
            (uint256 valAllocPoint, string memory validatorAddress) = IStakeFXVault(stFX).getValInfo(i);
            (, uint256 delegationAmount) = _delegation(validatorAddress, stFX);
            uint256 delegationReward = _delegationRewards(validatorAddress, stFX);

            validatorDelegations[i] = ValidatorDelegationInfo({
                validator: validatorAddress,
                allocPoint: valAllocPoint,
                delegationAmount: delegationAmount,
                delegationReward: delegationReward
            });
        }
    }

    /**************************************** Only Owner Functions ****************************************/

    function updateStFX(
        address _stFX
    ) external onlyOwner() {
        require(_stFX != address(0), "Cannot 0 add");
        require(_stFX != stFX, "Cannot same add");
        stFX = _stFX;
    }

    function recoverToken(
        address token,
        uint256 amount,
        address _recipient
    ) external onlyOwner() {
        require(_recipient != address(0), "Send to zero address");
        IERC20Upgradeable(token).safeTransfer(_recipient, amount);
    }

    function _authorizeUpgrade(
        address
    ) internal override onlyOwner() {} 

    /**************************************************************
     * @dev Initialize the states
     *************************************************************/

    function initialize(address _stFX) public initializer {
        stFX = _stFX;
        __Ownable_init();
        __UUPSUpgradeable_init();
    }
}