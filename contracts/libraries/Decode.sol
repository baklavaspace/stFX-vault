// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

library Decode {
    function delegate(
        bytes memory data
    ) internal pure returns (uint256, uint256) {
        (uint256 shares, uint256 reward) = abi.decode(data, (uint256, uint256));
        return (shares, reward);
    }

    function undelegate(
        bytes memory data
    ) internal pure returns (uint256, uint256, uint256) {
        (uint256 amount, uint256 reward, uint256 endTime) = abi.decode(
            data,
            (uint256, uint256, uint256)
        );
        return (amount, reward, endTime);
    }

    function withdraw(bytes memory data) internal pure returns (uint256) {
        uint256 reward = abi.decode(data, (uint256));
        return reward;
    }

    function transferFromShares(bytes memory data) internal pure returns (uint256, uint256) {
        (uint256 token, uint256 reward) = abi.decode(data, (uint256, uint256));
        return (token, reward);
    }

    function delegation(bytes memory data) internal pure returns (uint256, uint256) {
        (uint256 delegateShare, uint256 delegateAmount) = abi.decode(data, (uint256, uint256));
        return (delegateShare, delegateAmount);
    }

    function delegationRewards(bytes memory data) internal pure returns (uint256) {
        uint256 rewardAmount= abi.decode(data, (uint256));
        return rewardAmount;
    }

    function ok(
        bool _result,
        bytes memory _data,
        string memory _msg
    ) internal pure {
        if (!_result) {
            string memory errMsg = abi.decode(_data, (string));
            if (bytes(_msg).length < 1) {
                revert(errMsg);
            }
            revert(string(abi.encodePacked(_msg, ": ", errMsg)));
        }
    }
}