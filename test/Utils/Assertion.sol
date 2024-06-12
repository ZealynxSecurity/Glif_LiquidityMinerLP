// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {Test, console} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {LiquidityMine} from "src/LiquidityMine.sol";
import {Token} from "src/Token.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {Utils} from "test/Utils/Utils.sol";


contract Assertion is Utils  {
    using FixedPointMathLib for uint256;


    // Assert Total Locked Tokens Must Be Correct
    function assert_TotalLockedTokensMustBeCorrect() public {
        uint256 totalLockedTokens = lockToken.balanceOf(address(lm));
        uint256 expectedTotalLockedTokens = 0;

        for (uint256 i = 0; i < users.length; i++) {
            LiquidityMine.UserInfo memory user = lm.userInfo(users[i]);
            expectedTotalLockedTokens += user.lockedTokens;
        }

        assertEq(totalLockedTokens, expectedTotalLockedTokens, "Total locked tokens in contract should be correct");
    }

    // Assert Reward Debt Consistency
    function assert_RewardDebtConsistency() public {
        for (uint256 i = 0; i < users.length; i++) {
            LiquidityMine.UserInfo memory user = lm.userInfo(users[i]);
            uint256 expectedRewardDebt = user.lockedTokens.mulWadDown(lm.accRewardsPerLockToken());
            assertEq(user.rewardDebt, expectedRewardDebt, "Reward debt should be consistent with locked tokens and accRewardsPerLockToken");
        }
    }

    // Assert Unclaimed Rewards Consistency
    function assert_UnclaimedRewardsConsistency() public {
        for (uint256 i = 0; i < users.length; i++) {
            LiquidityMine.UserInfo memory user = lm.userInfo(users[i]);
            uint256 expectedPending = user.lockedTokens.mulWadDown(lm.accRewardsPerLockToken()) + user.unclaimedRewards - user.rewardDebt;
            uint256 pending = lm.pendingRewards(users[i]);
            assertEq(pending, expectedPending, "Pending rewards should be consistent with locked tokens, accRewardsPerLockToken, and reward debt");
        }
    }

    // Assert Total Reward Tokens Claimed
    function assert_TotalRewardTokensClaimed() public {
        uint256 totalClaimedRewards = 0;

        for (uint256 i = 0; i < users.length; i++) {
            LiquidityMine.UserInfo memory user = lm.userInfo(users[i]);
            totalClaimedRewards += user.unclaimedRewards;
        }

        // Verificar que las recompensas reclamadas se mantengan consistentes
        assertEq(totalClaimedRewards, lm.rewardTokensClaimed(), "Total claimed rewards should be correct");
    }

    // Assert Reward Token Balance Consistency
    function assert_RewardTokenBalanceConsistency() public {
        uint256 totalRewardTokenBalance = rewardToken.balanceOf(address(lm));
        uint256 totalRewardsAccrued = (block.number - lm.lastRewardBlock()) * lm.rewardPerEpoch();
        uint256 expectedRewardTokenBalance = lm.totalRewardCap() - lm.rewardTokensClaimed() - totalRewardsAccrued;

        assertEq(totalRewardTokenBalance, expectedRewardTokenBalance, "Reward token balance should be correct");
    }

    // Assert Total Reward Consistency
    function assert_TotalRewardConsistency() public {
        uint256 totalRewardsAccrued = lm.accRewardsTotal();
        uint256 totalRewardsClaimed = lm.rewardTokensClaimed();
        uint256 totalRewardsUnclaimed = 0;

        for (uint256 i = 0; i < users.length; i++) {
            LiquidityMine.UserInfo memory user = lm.userInfo(users[i]);
            totalRewardsUnclaimed += user.unclaimedRewards;
        }

        assertEq(
            totalRewardsAccrued,
            totalRewardsClaimed + totalRewardsUnclaimed,
            "Total rewards accrued should equal the sum of claimed and unclaimed rewards"
        );
    }

    // Assert Max Reward Cap Consistency
    function assert_MaxRewardCapConsistency() public {
        uint256 totalRewardsAccrued = lm.accRewardsTotal();
        uint256 maxRewardCap = lm.totalRewardCap();

        assertLe(
            totalRewardsAccrued,
            maxRewardCap,
            "Total rewards accrued should not exceed the maximum reward cap"
        );
    }

    // Assert Accrued Rewards Total Should Not Exceed Total Reward Cap
    function assert_AccRewardsTotalShouldNotExceedTotalRewardCap() public {
        uint256 accRewardsTotal = lm.accRewardsTotal();
        uint256 totalRewardCap = lm.totalRewardCap();
        assertLe(accRewardsTotal, totalRewardCap, "Accrued rewards total should not exceed the total reward cap");
    }

    // Assert Claimed Rewards Should Not Exceed Accrued Rewards Total
    function assert_RewardTokensClaimedShouldNotExceedAccRewardsTotal() public {
        uint256 rewardTokensClaimed = lm.rewardTokensClaimed();
        uint256 accRewardsTotal = lm.accRewardsTotal();
        assertLe(rewardTokensClaimed, accRewardsTotal, "Claimed rewards should not exceed the accrued rewards total");
    }

    // Assert GLF Token Balance and Claimed Rewards Should Equal Total Reward Cap
    function assert_GLFTokenBalanceAndRewardTokensClaimedShouldEqualTotalRewardCap() public {
        uint256 glfTokenBalance = rewardToken.balanceOf(address(lm));
        uint256 rewardTokensClaimed = lm.rewardTokensClaimed();
        uint256 totalRewardCap = lm.totalRewardCap();
        assertEq(glfTokenBalance + rewardTokensClaimed, totalRewardCap, "GLF token balance plus claimed rewards should equal total reward cap");
    }

    // Assert No Residual Dust
    function assert_NoResidualDust() public {
        uint256 accRewardsTotal = lm.accRewardsTotal();
        uint256 remainingBalance = rewardToken.balanceOf(address(lm));
        uint256 totalRewardCap = lm.totalRewardCap();

        console.log("Accrued Rewards Total:", accRewardsTotal);
        console.log("Reward Tokens Claimed:", lm.rewardTokensClaimed());
        console.log("Remaining Balance:", remainingBalance);
        console.log("Total Reward Cap:", totalRewardCap);

        uint256 calculatedSum = accRewardsTotal + remainingBalance;

        console.log("Calculated Sum:", calculatedSum);

        assertEq(
            totalRewardCap,
            calculatedSum,
            "Total Reward Cap should equal the sum of Accrued Rewards Total and Remaining Balance"
        );
    }

    function assertRewardCapInvariant(string memory testName) internal {
        uint256 accRewardsTotal = lm.accRewardsTotal();
        uint256 totalRewardCap = lm.totalRewardCap();
        uint256 rewardTokensClaimed = lm.rewardTokensClaimed();
        uint256 rewardTokenBalance = rewardToken.balanceOf(address(lm));

        // Invariant: The LM accRewardsTotal should always be less than or equal to totalRewardCap
        assertGe(totalRewardCap, accRewardsTotal, string(abi.encodePacked(testName, ": accRewardsTotal should be <= totalRewardCap")));

        // Invariant: The LM rewardTokensClaimed should always be less than or equal to accRewardsTotal
        assertGe(accRewardsTotal, rewardTokensClaimed, string(abi.encodePacked(testName, ": rewardTokensClaimed should be <= accRewardsTotal")));

        // Invariant: The LM balanceOf GLF tokens + rewardTokensClaimed should always equal totalRewardCap
        assertEq(rewardTokenBalance + rewardTokensClaimed, totalRewardCap, string(abi.encodePacked(testName, ": rewardToken balance + rewardTokensClaimed should equal totalRewardCap")));
    }
    function assertUserInfo(
        address user,
        uint256 lockedTokens,
        uint256 rewardDebt,
        uint256 unclaimedRewards,
        string memory label
    ) internal view {
        LiquidityMine.UserInfo memory u = lm.userInfo(user);
        assertEq(
            u.lockedTokens,
            lockedTokens,
            concatStrings(label, " User lockedTokens should be: ", vm.toString(lockedTokens))
        );
        assertEq(
            u.rewardDebt, rewardDebt, concatStrings(label, " User rewardDebt should be: ", vm.toString(rewardDebt))
        );
        assertEq(
            u.unclaimedRewards,
            unclaimedRewards,
            concatStrings(label, " User unclaimedRewards should be: ", vm.toString(unclaimedRewards))
        );
    }

    // function assertRewardCapInvariant(string memory label) internal view {
    //     assertEq(
    //         lm.totalRewardCap(),
    //         lm.rewardTokensClaimed() + rewardToken.balanceOf(address(lm)),
    //         string(abi.encodePacked("Invariant assertRewardCapInvariant: ", label))
    //     );
    // }








}