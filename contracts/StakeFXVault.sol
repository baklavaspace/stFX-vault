// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {IERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import {SafeERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import {MathUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/math/MathUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";

import {IVestedFX} from "./interfaces/IVestedFX.sol";
import {IRewardDistributor} from "./interfaces/IRewardDistributor.sol";
import {IWFX} from "./interfaces/IWFX.sol";
import {BaseVault} from "./vaults/BaseVault.sol";
import {PrecompileStaking} from "./imp/PrecompileStaking.sol";

contract StakeFXVault is
    Initializable,
    UUPSUpgradeable,
    PrecompileStaking,
    ReentrancyGuardUpgradeable,
    BaseVault
{
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using MathUpgradeable for uint256;

    uint256 internal constant BIPS_DIVISOR = 10000;
    uint256 internal constant PRECISION = 1e30;
    address constant WFX = 0x80b5a32E4F032B2a058b4F29EC95EEfEEB87aDcd;  // WFX mainnet: 0x80b5a32E4F032B2a058b4F29EC95EEfEEB87aDcd; WFX testnet: 0x3452e23F9c4cC62c70B7ADAd699B264AF3549C19

    uint256 public pendingFxReward;             // FX delegation rewards inside the contract pending for compound
    uint256 public feeOnReward;                 // Compound reward protocol fee
    uint256 public feeOnCompounder;             // Compound reward compounder fee
    uint256 public feeOnWithdrawal;             // Withdrawal fee
    address public vestedFX;                    // Contract that stored user's withdrawal info
    address public feeTreasury;                 // Contract that keep compound reward fee
    address public distributor;                 // Reward token distributor

    uint256 private MIN_COMPOUND_AMOUNT;        // Minimum reward amount to compound when stake happen
    uint256 private CAP_STAKE_FX_TARGET;        // Cap amount of stFX
    uint256 private STAKE_FX_TARGET;            // Target stake amount to do whole validator list delegate
    uint256 private UNSTAKE_FX_TARGET;          // Target unstake amount to split undelegate
    
    VaultInfo public vaultInfo;                     // Vault Info
    mapping(uint256 => ValInfo) public valInfo;     // Validator info
    mapping (address => UserInfo) public userInfo;  // User info
    mapping(string => bool) public addedValidator;  // True if validator is added

    struct VaultInfo {
        uint256 stakeId;
        uint256 unstakeId;
        uint256 length;        
        uint256 totalAllocPoint;
        uint256 cumulativeRewardPerToken;
    }

    struct ValInfo {
        uint256 allocPoint;
        string validator;
    }

    struct UserInfo {
        uint256 claimableReward;
        uint256 previousCumulatedRewardPerToken;
    }

    event Stake(address indexed user, uint256 amount, uint256 shares);
    event Unstake(address indexed user, uint256 amount, uint256 shares);
    event Compound(address indexed user, uint256 compoundAmount);
    event Claim(address receiver, uint256 amount);
    event ValidatorAdded(string val, uint256 newAllocPoint);
    event ValidatorRemoved(string val);
    event ValidatorUpdated(string val, uint256 newAllocPoint);
    event VestedFXChanged(address newAddress);
    event FeeTreasuryChanged(address newAddress);
    event DistributorChanged(address newAddress);

    receive() external payable {}

    modifier onlyVestedFX() {
        require(msg.sender == vestedFX, "Only VestedFX can call");
        _;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /****************************************** Core External Functions ******************************************/
    /**
     * @notice user stake FX to this contract
     */
    function stake() external payable whenNotPaused {
        require(msg.value > 0, "Stake: 0 amount");
        uint256 totalAsset = totalAssets();
        require(msg.value + totalAsset <= CAP_STAKE_FX_TARGET, "Stake: > Cap");

        uint256 delegationReward = getTotalDelegationRewards();
        if(delegationReward >= MIN_COMPOUND_AMOUNT) {
            compound();
        }
        _claim(msg.sender, msg.sender);

        uint256 shares = previewDeposit(msg.value);
        _mint(msg.sender, shares);

        _stake(msg.value);

        emit Stake(msg.sender, msg.value, shares);
    }

    /**
     * @notice user stake WFX to this contract
     */
    function stakeWFX(uint256 amount) external whenNotPaused {
        require(amount > 0, "Stake: 0 amount");
        uint256 totalAsset = totalAssets();
        require(amount + totalAsset <= CAP_STAKE_FX_TARGET, "Stake: > Cap");

        uint256 delegationReward = getTotalDelegationRewards();
        if(delegationReward >= MIN_COMPOUND_AMOUNT) {
            compound();
        }
        _claim(msg.sender, msg.sender);

        IWFX(WFX).transferFrom(msg.sender, address(this), amount); 
        IWFX(WFX).withdraw(payable(address(this)), amount);

        uint256 shares = previewDeposit(amount);
        _mint(msg.sender, shares);

        _stake(amount);

        emit Stake(msg.sender, amount, shares);
    }

    /**
     * @notice user unstake/ request undelegate FX
     * @param amount User's fx-LP receipt tokens
     */
    function unstake(uint256 amount) external whenNotPaused {
        require(amount > 0, "Unstake: 0 amount");
        uint256 sharesBalance = balanceOf(msg.sender);
        require(sharesBalance >= amount, "Amount > stake");

        _claim(msg.sender, msg.sender);

        uint256 undelegateAmount = previewRedeem(amount);
        uint256 undelegateAmountAfterFee = undelegateAmount * (BIPS_DIVISOR - feeOnWithdrawal) / BIPS_DIVISOR;

        _burn(msg.sender, amount);
        if (undelegateAmountAfterFee > 0) {
            _unstake(undelegateAmountAfterFee);
        }
     
        emit Unstake(msg.sender, undelegateAmountAfterFee, amount);
    }

    /**
     * @notice transfer user delegation shares to this contract
     * @param val validator address
     * @param amount Amount of user's delegate shares transferred to this contract
     */
    function entrustDelegatedShare(string memory val, uint256 amount) external whenNotPaused {
        require(amount > 0, "Entrust: 0 share");

        (uint256 sharesAmount, uint256 delegationAmount) = _delegation(val, msg.sender);
        require(sharesAmount >= amount, "Not enough share");

        uint256 delegationReward = getTotalDelegationRewards();
        if(delegationReward >= MIN_COMPOUND_AMOUNT) {
            compound();
        }
        _claim(msg.sender, msg.sender);
        
        uint256 totalAsset = totalAssets();
        uint256 estimateDelegateAmount = amount / sharesAmount * delegationAmount;
        require(estimateDelegateAmount + totalAsset <= CAP_STAKE_FX_TARGET, "Stake: > Cap");

        uint256 supply = totalSupply();
        (uint256 fxAmountToTransfer, uint256 returnRewards) = _transferFromShares(val, msg.sender, address(this), amount);

        pendingFxReward += returnRewards;

        uint256 shares = (fxAmountToTransfer == 0 || supply == 0)
                ? _initialConvertToShares(fxAmountToTransfer, MathUpgradeable.Rounding.Down)
                : fxAmountToTransfer.mulDiv(supply, totalAsset, MathUpgradeable.Rounding.Down);

        _mint(msg.sender, shares);

        emit Stake(msg.sender, fxAmountToTransfer, shares); 
    }

    function claim(address receiver) external nonReentrant returns (uint256) {
        return _claim(msg.sender, receiver);
    }

    /**
     * @notice compound delegation rewards
     */
    function compound() public nonReentrant whenNotPaused {
        uint256 delegateReward = _withdrawReward() + pendingFxReward;
        pendingFxReward = 0;

        uint256 feeProtocol = (delegateReward * feeOnReward) / BIPS_DIVISOR;
        uint256 feeCompounder = (delegateReward * feeOnCompounder) / BIPS_DIVISOR;

        delegateReward = delegateReward - feeProtocol - feeCompounder;
        _stake(delegateReward);

        address treasury = payable(feeTreasury);
        address user = payable(msg.sender);
        (bool successTreasury, ) = treasury.call{value: feeProtocol}("");
        (bool successUser, ) = user.call{value: feeCompounder}("");
        require(successTreasury && successUser, "Failed to send FX");

        emit Compound(msg.sender, delegateReward);
    }

    function sendVestedFX(
        uint256 safeAmount
    ) external onlyVestedFX {
        address recipient = payable(msg.sender);
        (bool success, ) = recipient.call{value: safeAmount}("");
        require(success, "Failed to send FX");
    }

    function updateRewards() external nonReentrant {
        _updateRewards(address(0));
    }

    /**************************************** Internal and Private Functions ****************************************/

    /**
    * @dev Helper function to delegate FX amount to validators.
    * @param  amount  The amount: FX delegate to validators.
    */
    function _stake(uint256 amount) internal {
        VaultInfo memory vault = vaultInfo;
        uint256 totalAllocPoint = vault.totalAllocPoint;
        uint256 index = vault.stakeId;
        uint256 vaultLength = vault.length;
        uint256 totalReturnReward;
        uint256 _totalAssets = totalAssets();

        // After execute removeValidator, stakeId may equal or greater than vaultLength
        if (index >= vaultLength) {
            index = 0;
        }

        if (amount <= STAKE_FX_TARGET) {
            uint256 numValidators = _calculateNumberofValidators(amount);
            uint256 amountPerValidator = amount / numValidators;
            uint256 remainingAmount = amount;
            uint256 delegateAmount;
            
            while (remainingAmount != 0) {
                ValInfo memory val = valInfo[index];
                uint256 allocPoint = val.allocPoint;
                index = (index + 1) % vaultLength;

                if (allocPoint == 0) {
                    continue;
                }
                
                if (_totalAssets >= CAP_STAKE_FX_TARGET) {
                    delegateAmount = remainingAmount;
                } else {
                    (, uint256 delegationAmount) = _delegation(val.validator, address(this));
                    uint256 maxValSize = allocPoint * CAP_STAKE_FX_TARGET / totalAllocPoint;

                    if (delegationAmount >= maxValSize) {
                        continue;
                    }

                    if (remainingAmount <= amountPerValidator) {
                        delegateAmount = remainingAmount;
                    } else {
                        delegateAmount = amountPerValidator;
                    }
                }

                (, uint256 returnReward) = _delegate(val.validator, delegateAmount);
                _totalAssets += delegateAmount;
                totalReturnReward += returnReward;
                remainingAmount -= delegateAmount;
            }
        } else {
            uint256 remainingAmount = amount;
            uint256 delegateAmount;
            
            while (remainingAmount != 0) {
                ValInfo memory val = valInfo[index];
                uint256 allocPoint = val.allocPoint;
                
                index = (index + 1) % vaultLength;

                // Skip validators that has 0 allocPoint
                if (allocPoint == 0) {
                    continue;
                }

                if (_totalAssets >= CAP_STAKE_FX_TARGET) {
                    delegateAmount = remainingAmount;
                } else {
                    (, uint256 delegationAmount) = _delegation(val.validator, address(this));
                    uint256 maxValSize = allocPoint * CAP_STAKE_FX_TARGET / totalAllocPoint;
                    
                    // Skip validators that has reach max of its allocation FX delegation
                    if (delegationAmount >= maxValSize) {
                        continue;
                    }

                    // If remainingAmount more than allocDelegateAmount, only delegate allocDelegateAmount
                    uint256 allocDelegateAmount = amount * allocPoint / totalAllocPoint;

                    if (remainingAmount <= allocDelegateAmount) {
                        delegateAmount = remainingAmount;
                    } else {
                        delegateAmount = allocDelegateAmount;
                    }
                }
                
                (, uint256 returnReward) = _delegate(val.validator, delegateAmount);
                _totalAssets += delegateAmount;
                totalReturnReward += returnReward;
                remainingAmount -= delegateAmount;
            }
        }

        vaultInfo.stakeId = index;
        pendingFxReward += totalReturnReward;
    }
    
    /**
    * @dev Helper function to undelegate FX amount from validators.
    * @param  amount  The amount: FX to unstake from the vault.
    */
    function _unstake(uint256 amount) internal {
        VaultInfo memory vault = vaultInfo;
        uint256 index = vault.unstakeId;
        uint256 vaultLength = vault.length;

        uint256 remainingAmount = amount;
        uint256 totalReward;        
        uint256 returnUndelegatedAmount;
        uint256 returnReward;
        uint256 endTime;
        
        // After execute removeValidator, stakeId may equal or greater than vaultLength
        if (index >= vaultLength) {
            index = 0;
        }   

        if (amount >= UNSTAKE_FX_TARGET) {
            uint256 halfOfUndelegateAmount = amount / 2; 
            (returnUndelegatedAmount, returnReward, endTime) = _toUndelegate(index, halfOfUndelegateAmount);
                
            remainingAmount -= returnUndelegatedAmount;
            index = (index + 1) % vaultLength;
            totalReward += returnReward;
        }

        while (remainingAmount != 0) {
            (returnUndelegatedAmount, returnReward, endTime) = _toUndelegate(index, remainingAmount);
            
            remainingAmount -= returnUndelegatedAmount;
            index = (index + 1) % vaultLength;
            totalReward += returnReward;
        }

        IVestedFX(vestedFX).lockWithEndTime(
            msg.sender,            
            amount,
            endTime
        );

        vaultInfo.unstakeId = index;
        pendingFxReward += totalReward;
    }

    /**
    * @dev Helper function to undelegate FX amount from validators.
    * @param  index Validator ID in validator list.
    * @param  remainingAmount Amount to undelegate from validators.
    */
    function _toUndelegate(uint256 index, uint256 remainingAmount) internal returns(uint256, uint256, uint256) {
        (uint256 sharesAmount, uint256 delegationAmount) = _delegation(valInfo[index].validator, address(this));

        uint256 amountToUndelegate;
        uint256 returnReward;
        uint256 endTime;

        if (delegationAmount > 0) {
            if (delegationAmount >= remainingAmount) {
                amountToUndelegate = remainingAmount;
            } else {
                amountToUndelegate = delegationAmount;
            }

            uint256 shareToWithdraw = (sharesAmount * amountToUndelegate) / delegationAmount;
            if (shareToWithdraw > 0) {
                (amountToUndelegate, returnReward, endTime) = _undelegate(valInfo[index].validator, shareToWithdraw);
            }
        }

        return (amountToUndelegate, returnReward, endTime);
    }

    /**
    * @dev Helper function to withdraw delegation fx rewards from all validators.
    */
    function _withdrawReward() internal returns (uint256) {
        VaultInfo memory vault = vaultInfo;
        uint256 reward = 0;
        
        uint256 vaultLength = vault.length;

        for (uint256 i; i < vaultLength; i++) {
            string memory validator = valInfo[i].validator;
            uint256 delegationReward = _delegationRewards(validator, address(this));
            if(delegationReward > 0) {
                uint256 returnReward = _withdraw(validator);
                reward += returnReward;
            }
        }

        return reward;
    }

    /**
    * @dev Helper function to help to calculate number of validator to delegate based on input amount.
    * @param delegateAmount Fx Amount to stake.
    * @return Number of validators to delegate.
    */
    function _calculateNumberofValidators(
        uint256 delegateAmount
    ) internal view returns (uint256) {
        uint256 numValidators;
        uint256 delegateAmountInEther = delegateAmount / 10**18;

        uint256 valLength = getValLength();
        while (delegateAmountInEther >= 10) {
            delegateAmountInEther /= 10;
            numValidators++;
        }

        return (numValidators == 0) ? 1 : (numValidators > valLength
                ? valLength
                : numValidators);
    }

    /**
    * @dev Helper function to help to query total FX delegation.
    */
    function _getUnderlyingFX() internal view returns (uint256) {
        uint256 totalAmount;
        uint256 valLength = getValLength();
        for (uint256 i; i < valLength; i++) {
            string memory validator = valInfo[i].validator;
            (, uint256 delegationAmount) = _delegation(validator, address(this));
            totalAmount += delegationAmount;
        }
        return totalAmount;
    }

    function _claim(address account, address receiver) private returns (uint256) {
        _updateRewards(account);
        UserInfo storage user = userInfo[account];
        uint256 tokenAmount = user.claimableReward;
        user.claimableReward = 0;

        if (tokenAmount > 0) {
            IERC20Upgradeable(rewardToken()).safeTransfer(receiver, tokenAmount);
            emit Claim(account, tokenAmount);
        }

        return tokenAmount;
    }

    function _updateRewards(address account) private {
        uint256 blockReward = IRewardDistributor(distributor).distribute();

        uint256 supply = totalSupply();
        uint256 _cumulativeRewardPerToken = vaultInfo.cumulativeRewardPerToken;
        if (supply > 0 && blockReward > 0) {
            _cumulativeRewardPerToken = _cumulativeRewardPerToken + (blockReward * (PRECISION) / (supply));
            vaultInfo.cumulativeRewardPerToken = _cumulativeRewardPerToken;
        }

        // cumulativeRewardPerToken can only increase
        // so if cumulativeRewardPerToken is zero, it means there are no rewards yet
        if (_cumulativeRewardPerToken == 0) {
            return;
        }

        if (account != address(0)) {
            UserInfo storage user = userInfo[account];
            uint256 stakedAmount = balanceOf(account);
            uint256 accountReward = stakedAmount * (_cumulativeRewardPerToken - (user.previousCumulatedRewardPerToken)) / (PRECISION);
            uint256 _claimableReward = user.claimableReward + (accountReward);

            user.claimableReward = _claimableReward;
            user.previousCumulatedRewardPerToken = _cumulativeRewardPerToken;
        }
    }

    function _beforeTokenTransfer(address from, address to, uint256 amount)
        internal
        whenNotPaused
        override
    {
        _updateRewards(from);
        _updateRewards(to);

        super._beforeTokenTransfer(from, to, amount);
    }

    function _authorizeUpgrade(
        address
    ) internal override onlyRole(OWNER_ROLE) {} 


    /**************************************** Public/External View Functions ****************************************/

    /**
     * @notice Return total asset(FX) deposited
     * @return Amount of asset(FX) deposited
     */
    function totalAssets() public view override returns (uint256) {
        uint256 underlying = _getUnderlyingFX();
        return underlying;
    }

    function getValLength() public view returns (uint256) {
        return vaultInfo.length;
    }

    /**
     * @notice Return delegation share and fx amount
     */
    function getDelegationInfo(
        uint256 index
    ) external view returns (uint256, uint256) {
        (uint256 sharesAmount, uint256 delegationAmount) = _delegation(valInfo[index].validator, address(this));
        return (sharesAmount, delegationAmount);
    }

    /**
     * @notice Return validator address and allocPoint
     */
    function getValInfo(uint256 index) public view returns (uint256, string memory) {
        return (valInfo[index].allocPoint, valInfo[index].validator);
    }

    /**
     * @notice Return total delegation reward
     */
    function getTotalDelegationRewards() public view returns (uint256) {
        uint256 totalAmount;
        uint256 valLength = getValLength();
        for (uint256 i; i < valLength; i++) {
            string memory validator = valInfo[i].validator;
            uint256 delegationReward = _delegationRewards(validator, address(this));
            totalAmount += delegationReward;
        }
        return totalAmount + pendingFxReward;
    }

    function getVaultConfigs() public view returns (uint256, uint256, uint256, uint256) {
        return (MIN_COMPOUND_AMOUNT, CAP_STAKE_FX_TARGET, UNSTAKE_FX_TARGET, STAKE_FX_TARGET);
    }

    function rewardToken() public view returns (address) {
        return IRewardDistributor(distributor).rewardToken();
    }

    function claimable(address account) public view returns (uint256) {
        UserInfo memory user = userInfo[account];
        uint256 stakedAmount = balanceOf(account);
        if (stakedAmount == 0) {
            return user.claimableReward;
        }
        uint256 supply = totalSupply();
        uint256 pendingRewards = IRewardDistributor(distributor).pendingRewards() * (PRECISION);
        uint256 nextCumulativeRewardPerToken = vaultInfo.cumulativeRewardPerToken + (pendingRewards / (supply));
        return user.claimableReward + (
            stakedAmount * (nextCumulativeRewardPerToken - (user.previousCumulatedRewardPerToken)) / (PRECISION));
    }

    /**************************************** Only Governor Functions ****************************************/

    function addValidator(
        string memory _validator,
        uint256 _allocPoint
    ) external onlyRole(GOVERNOR_ROLE) {
        require(addedValidator[_validator] == false, "addedVal");
        valInfo[vaultInfo.length].validator = _validator;
        valInfo[vaultInfo.length].allocPoint = _allocPoint;

        vaultInfo.length++;
        vaultInfo.totalAllocPoint += _allocPoint;

        addedValidator[_validator]=true;

        emit ValidatorAdded(_validator, _allocPoint);
    }

    /**
     * @notice remove validators which has 0 allocPoint and 0 delegation in the list 
     */
    function removeValidator() external onlyRole(GOVERNOR_ROLE) {
        VaultInfo memory vault = vaultInfo;
        uint256 vaultLength = vault.length;

        for (uint256 i = 0; i < vaultLength; i++) {
            if (valInfo[i].allocPoint == 0) {
                string memory val = valInfo[i].validator;
                (uint256 sharesAmount, ) = _delegation(val, address(this));
                if (sharesAmount == 0) {
                    addedValidator[val] = false;
                    uint256 lastIndex = vaultLength - 1;
                    valInfo[i] = valInfo[lastIndex];
                    delete valInfo[lastIndex];

                    emit ValidatorRemoved(val);
                    vaultLength--;
                    i--;
                }
            }
        }
        vaultInfo.length = vaultLength;
    }

    function updateValidator(
        uint256 id,
        uint256 newAllocPoint
    ) external onlyRole(GOVERNOR_ROLE) {
        require(id < vaultInfo.length, "Invalid ID");
        uint256 oldAllocPoint = valInfo[id].allocPoint;

        vaultInfo.totalAllocPoint = vaultInfo.totalAllocPoint + newAllocPoint - oldAllocPoint;
        valInfo[id].allocPoint = newAllocPoint;

        emit ValidatorUpdated(valInfo[id].validator, newAllocPoint);
    }

    function updateConfigs(uint256 newMinCompound, uint256 newCapStakeFxTarget, uint256 newUnstakeFxTarget, uint256 newStakeFxTarget) external onlyRole(GOVERNOR_ROLE) {
        MIN_COMPOUND_AMOUNT = newMinCompound;
        CAP_STAKE_FX_TARGET = newCapStakeFxTarget;
        UNSTAKE_FX_TARGET = newUnstakeFxTarget;
        STAKE_FX_TARGET = newStakeFxTarget;
    }

    function updateFees(uint256 newFeeOnReward, uint256 newFeeOnCompounder, uint256 newFeeOnWithdrawal) external onlyRole(GOVERNOR_ROLE) {
        feeOnReward = newFeeOnReward;
        feeOnCompounder = newFeeOnCompounder;
        feeOnWithdrawal = newFeeOnWithdrawal;
    }

    /**************************************** Only Owner Functions ****************************************/

    function updateVestedFX(address newAddress) external onlyRole(OWNER_ROLE) {
        vestedFX = newAddress;
        emit VestedFXChanged(newAddress);
    }

    function updateFeeTreasury(address newAddress) external onlyRole(OWNER_ROLE) {
        feeTreasury = newAddress;
        emit FeeTreasuryChanged(newAddress);
    }
    
    function updateDistributor(address newAddress) external onlyRole(OWNER_ROLE) {
        distributor = newAddress;
        emit DistributorChanged(newAddress);
    }

    function recoverToken(
        address token,
        uint256 amount,
        address _recipient
    ) external onlyRole(OWNER_ROLE) {
        require(_recipient != address(0), "Send to zero address");
        IERC20Upgradeable(token).safeTransfer(_recipient, amount);
    }

    function recoverFx(
        uint256 safeAmount,
        address _recipient
    ) external onlyRole(OWNER_ROLE) {
        address recipient = payable(_recipient);
        (bool success, ) = recipient.call{value: safeAmount}("");
        require(success, "Failed to send FX");
    }

    /**************************************************************
     * @dev Initialize the states
     *************************************************************/

    function initialize(
        address _asset,
        address _owner,
        address _governor
    ) public initializer {
        __BaseVaultInit(
            _asset,
            "Staked FX Token",
            "StFX",
            _owner,
            _governor
        );
        __Governable_init(_owner, _governor);
        __UUPSUpgradeable_init();
    }
}