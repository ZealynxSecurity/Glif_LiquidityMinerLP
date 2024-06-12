// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {Test, console} from "forge-std/Test.sol";
import {LiquidityMine} from "src/LiquidityMine.sol";
import {Token} from "src/Token.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {SetUp} from "test/Utils/SetUp.sol";


interface MintBurnERC20 is IERC20 {
    function mint(address to, uint256 value) external;
    function burn(address from, uint256 value) external;
}

contract Utils is SetUp {
    using FixedPointMathLib for uint256;



    function _loadRewards(uint256 totalRewardsToDistribute) internal {
        MintBurnERC20(address(rewardToken)).mint(address(this), totalRewardsToDistribute);
        rewardToken.approve(address(lm), totalRewardsToDistribute);

        uint256 preloadBal = rewardToken.balanceOf(address(lm));
        uint256 preloadRewardCap = lm.totalRewardCap();
        lm.loadRewards(totalRewardsToDistribute);
        uint256 postloadBal = rewardToken.balanceOf(address(lm));
        uint256 postloadRewardCap = lm.totalRewardCap();

        assertEq(
            postloadBal,
            totalRewardsToDistribute + preloadBal,
            "Reward token balance should be the total rewards to distribute"
        );
        assertEq(
            postloadRewardCap,
            preloadRewardCap + totalRewardsToDistribute,
            "Reward token cap should be the total rewards to distribute"
        );
    }

    function _depositLockTokens(address user, uint256 amount) internal {
        MintBurnERC20(address(lockToken)).mint(user, amount);
        uint256 preLockTokens = lm.userInfo(user).lockedTokens;
        vm.startPrank(user);
        lockToken.approve(address(lm), amount);
        lm.deposit(amount);
        vm.stopPrank();

        assertEq(
            lm.userInfo(user).lockedTokens, preLockTokens + amount, "User locked tokens should be the amount deposited"
        );
    }


    function concatStrings(string memory label, string memory a, string memory b)
        internal
        pure
        returns (string memory)
    {
        return string(abi.encodePacked(label, a, b));
    }

    function concatStrings(string memory label, string memory a)
        internal
        pure
        returns (string memory)
    {
        return string(abi.encodePacked(label, a));
    }
    address[] users;

    function prepareUser(address user, uint256 amount) internal {
        if (lockToken.balanceOf(user) < amount) {
            MintBurnERC20(address(lockToken)).mint(user, amount);
        }

        vm.prank(user);
        lockToken.approve(address(lm), amount);

        vm.prank(user);
        lm.deposit(amount, user);

        if (!isUserTracked(user)) {
            users.push(user);
        }
    }

    function isUserTracked(address user) internal view returns (bool) {
        for (uint256 i = 0; i < users.length; i++) {
            if (users[i] == user) {
                return true;
            }
        }
        return false;
    }

}