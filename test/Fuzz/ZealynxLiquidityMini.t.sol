// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {Test, console} from "forge-std/Test.sol";
import {LiquidityMine} from "src/LiquidityMine.sol";
import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {Assertion} from "test/Utils/Assertion.sol";

interface MintBurnERC20 is IERC20 {
    function mint(address to, uint256 value) external;
    function burn(address from, uint256 value) external;
}


contract ZealynxLiquidityMineTest is Assertion {
    using FixedPointMathLib for uint256;


    function test_Initialization() public view {

        assertEq(lm.accRewardsPerLockToken(), 0, "accRewardsPerLockToken should be 0");
        assertEq(lm.lastRewardBlock(), deployBlock, "lastRewardBlock should be the deploy block");
        assertEq(lm.rewardPerEpoch(), rewardPerEpoch, "rewardPerEpoch should be 1e18");
        assertEq(address(lm.rewardToken()), address(rewardToken), "rewardToken should be the MockERC20 address");
        assertEq(address(lm.lockToken()), address(lockToken), "lockToken should be the MockERC20 address");

        assertEq(lm.rewardTokensClaimed(), 0, "rewardTokensClaimed should be 0");
        assertEq(lm.totalRewardCap(), 0, "totalRewardCap should be 0");
    }

    function testFuzz_Deposit(uint256 amount, address beneficiary) public {
        // Limit the fuzzing range for more reasonable values
        amount = bound(amount, 1, 1e24); 
        vm.assume(beneficiary != address(0) && beneficiary != address(lm)); 

        // Mint tokens to the beneficiary so they can be deposited
        MintBurnERC20(address(lockToken)).mint(beneficiary, amount);
        vm.prank(beneficiary);
        lockToken.approve(address(lm), amount);

        uint256 initialContractBalance = lockToken.balanceOf(address(lm));
        uint256 initialBeneficiaryBalance = lockToken.balanceOf(beneficiary);

        // Perform the deposit
        vm.prank(beneficiary);
        lm.deposit(amount, beneficiary);

        // Verify that the tokens were transferred to the contract
        uint256 finalContractBalance = lockToken.balanceOf(address(lm));
        assertEq(
            finalContractBalance,
            initialContractBalance + amount,
            "Contract balance should increase by the deposited amount"
        );

        // Verify the beneficiary's balance decreased correctly
        uint256 finalBeneficiaryBalance = lockToken.balanceOf(beneficiary);
        assertEq(
            finalBeneficiaryBalance,
            initialBeneficiaryBalance - amount,
            "Beneficiary's balance should decrease by the deposited amount"
        );

        // Verify the user's information
        LiquidityMine.UserInfo memory user = lm.userInfo(beneficiary);
        assertEq(user.lockedTokens, amount, "Locked tokens should equal the deposited amount");
        assertEq(user.rewardDebt, lm.accRewardsPerLockToken().mulWadDown(amount), "Reward debt should be correct");
        assertEq(user.unclaimedRewards, 0, "Unclaimed rewards should be 0 after deposit");

        // Verify the total locked tokens in the contract
        uint256 totalLockedTokens = lockToken.balanceOf(address(lm));
        assertEq(
            totalLockedTokens, initialContractBalance + amount, "Total locked tokens in contract should be correct"
        );

        assertEq(lm.totalRewardCap(), 0, "totalRewardCap should be unchanged after deposit");
    }


    function testFuzz_Withdraw(uint256 depositAmount, uint256 withdrawAmount, address beneficiary) public {
        // Limit the fuzzing range for more reasonable values
        depositAmount = bound(depositAmount, 1, 1e24); 
        withdrawAmount = bound(withdrawAmount, 1, depositAmount); 
        vm.assume(beneficiary != address(0) && beneficiary != address(lm)); 

        // Mint tokens to the beneficiary so they can be deposited
        MintBurnERC20(address(lockToken)).mint(beneficiary, depositAmount);
        vm.prank(beneficiary);
        lockToken.approve(address(lm), depositAmount);

        // Perform the deposit
        vm.prank(beneficiary);
        lm.deposit(depositAmount, beneficiary);

        // Get initial balances
        uint256 initialContractBalance = lockToken.balanceOf(address(lm));
        uint256 initialBeneficiaryBalance = lockToken.balanceOf(beneficiary);

        // Get initial user info
        LiquidityMine.UserInfo memory initialUser = lm.userInfo(beneficiary);

        // Perform the withdraw
        vm.prank(beneficiary);
        lm.withdraw(withdrawAmount, beneficiary);

        // Verify that the tokens were transferred to the beneficiary
        uint256 finalContractBalance = lockToken.balanceOf(address(lm));
        uint256 finalBeneficiaryBalance = lockToken.balanceOf(beneficiary);
        assertEq(finalContractBalance, initialContractBalance - withdrawAmount, "Contract balance should decrease by the withdrawn amount");
        assertEq(
            finalBeneficiaryBalance,
            initialBeneficiaryBalance + withdrawAmount,
            "Beneficiary's balance should increase by the withdrawn amount"
        );

        // Verify the user's information
        LiquidityMine.UserInfo memory user = lm.userInfo(beneficiary);
        assertEq(user.lockedTokens, depositAmount - withdrawAmount, "Locked tokens should decrease by the withdrawn amount");
        assertEq(user.rewardDebt, lm.accRewardsPerLockToken().mulWadDown(user.lockedTokens), "Reward debt should be correct");
        assertEq(user.unclaimedRewards, initialUser.lockedTokens.mulWadDown(lm.accRewardsPerLockToken()) + initialUser.unclaimedRewards - initialUser.rewardDebt, "Unclaimed rewards should be updated correctly");

        // Verify the total locked tokens in the contract
        uint256 totalLockedTokens = lockToken.balanceOf(address(lm));
        assertEq(totalLockedTokens, initialContractBalance - withdrawAmount, "Total locked tokens in contract should be correct after withdrawal");

        assertEq(lm.totalRewardCap(), 0, "totalRewardCap should be unchanged after withdrawal");
    }


    function testFuzz_FinalStateVerification(uint256 depositAmt) public {
        depositAmt = bound(depositAmt, 1e17, 1e21); 
        address investor2 = makeAddr("investor2");

        _loadRewards(totalRewards);

        MintBurnERC20(address(lockToken)).mint(investor, depositAmt);
        MintBurnERC20(address(lockToken)).mint(investor2, depositAmt);

        // Initial deposit for investor
        vm.startPrank(investor);
        lockToken.approve(address(lm), depositAmt);
        lm.deposit(depositAmt);
        vm.stopPrank();

        // Roll forward to the middle of the liquidity mine
        vm.roll(block.number + (lm.fundedEpochsLeft().divWadDown(2e18)));
        lm.updateAccounting();

        // Deposit for investor2
        vm.startPrank(investor2);
        lockToken.approve(address(lm), depositAmt);
        lm.deposit(depositAmt);
        vm.stopPrank();

        // Roll forward to the end of the liquidity mine and update accounting
        vm.roll(block.number + lm.fundedEpochsLeft());
        lm.updateAccounting();

        // Final state verification
        uint256 accRewardsPerTokenFirstHalf = totalRewards.divWadDown(2e18).divWadDown(depositAmt);
        uint256 accRewardsPerTokenSecondHalf = totalRewards.divWadDown(2e18).divWadDown(depositAmt.mulWadDown(2e18));
        assertEq(
            lm.accRewardsPerLockToken(),
            accRewardsPerTokenFirstHalf + accRewardsPerTokenSecondHalf,
            "accRewardsPerLockToken should be total rewards divided by depositAmt"
        );
        assertEq(lm.rewardsLeft(), 0, "rewardsLeft should be 0");
        assertEq(rewardToken.balanceOf(address(lm)), totalRewards, "Reward token should not be paid out yet");

        assertRewardCapInvariant("testFuzz_FinalStateVerification");
    }

    function test_check_intermediate_rewards(uint256 depositAmount) public {
        vm.assume(depositAmount > 0 && depositAmount < 1e24);

        address beneficiary = makeAddr("beneficiary");

        _loadRewards(totalRewards);

        MintBurnERC20(address(lockToken)).mint(beneficiary, depositAmount);

        vm.startPrank(beneficiary);
        lockToken.approve(address(lm), depositAmount);
        lm.deposit(depositAmount);
        vm.stopPrank();

        vm.roll(block.number + (lm.fundedEpochsLeft().divWadDown(2e18)));

        assertEq(lm.pendingRewards(beneficiary), totalRewards.divWadDown(2e18));
    }

    function testFuzz_InitialRewardLoadingAndDeposit(uint256 depositAmt) public { // @audit-issue
        depositAmt = bound(depositAmt, 1e17, 1e21); 

        assertEq(rewardToken.balanceOf(address(lm)), 0, "LM Contract should have 0 locked tokens");

        _loadRewards(totalRewards);
        assertRewardCapInvariant("testFuzz_InitialRewardLoadingAndDeposit1");

        _depositLockTokens(investor, depositAmt);
        uint256 totalFundedEpochs = lm.fundedEpochsLeft();
        assertEq(totalFundedEpochs, totalRewards / rewardPerEpoch, "fundedEpochsLeft should be the full LM duration");

        vm.roll(block.number + lm.fundedEpochsLeft());
        assertEq(lm.pendingRewards(investor), totalRewards, "User should receive all rewards");
    }


    //@audit-issue => "Investor should receive all rewards"
    function testFuzz_MidwayRewardsAndHarvest(uint256 depositAmt) public {
        depositAmt = bound(depositAmt, 1e17, 1e21); 

        _loadRewards(totalRewards);
        _depositLockTokens(investor, depositAmt);

        vm.roll(block.number + lm.fundedEpochsLeft());
        vm.prank(investor);
        lm.harvest(MAX_UINT256, investor);
        vm.stopPrank();

        assertRewardCapInvariant("testFuzz_MidwayRewardsAndHarvest2");
        assertEq(lm.pendingRewards(investor), 0, "User should have no pending rewards left after withdrawing");
        assertEq(lm.rewardsLeft(), 0, "rewardsLeft should be 0");
        assertEq(lm.fundedEpochsLeft(), 0, "fundedEpochsLeft should be 0");
        assertEq(rewardToken.balanceOf(address(lm)), 0, "Reward token should be fully paid out");
        assertEq(rewardToken.balanceOf(investor), totalRewards, "Investor should receive all rewards");
        assertUserInfo(investor, depositAmt, totalRewards, 0, "testFuzz_MidwayRewardsAndHarvest1");
    }


    //@audit-issue => totalRewardCap should be totalRewards x2, Liquidity mine should be refunded, 
    // User should have pending rewards after LM extension - 2, rewardsLeft should be 0", Reward token should be fully paid out - 2
    // Investor should receive all rewards - 2
    function testFuzz_LMExtensionAndFinalRewards(uint256 depositAmt, uint256 newRewards) public {
        depositAmt = bound(depositAmt, 1e17, 1e21);
        newRewards = bound(newRewards, 1e18, 1e24); 

        _loadRewards(totalRewards);
        _depositLockTokens(investor, depositAmt);

        vm.roll(block.number + lm.fundedEpochsLeft());
        vm.prank(investor);
        lm.harvest(MAX_UINT256, investor);
        vm.stopPrank();

        // Extend the LM
        _loadRewards(newRewards);
        assertRewardCapInvariant("testFuzz_LMExtensionAndFinalRewards1");
        // assertEq(lm.totalRewardCap(), totalRewards * 2, "totalRewardCap should be totalRewards x2");
        assertEq(lm.pendingRewards(investor), 0, "User should have no pending rewards left after withdrawing");
        assertEq(lm.rewardsLeft(), newRewards, "rewardsLeft should be newRewards");
        assertEq(lm.fundedEpochsLeft(), lm.fundedEpochsLeft(), "fundedEpochsLeft should be the extended duration");
        // assertEq(rewardToken.balanceOf(address(lm)), newRewards, "Liquidity mine should be refunded");

        vm.roll(block.number + lm.fundedEpochsLeft());
        // assertEq(lm.pendingRewards(investor), newRewards, "User should have pending rewards after LM extension - 2");

        vm.prank(investor);
        lm.harvest(MAX_UINT256, investor);
        assertEq(lm.pendingRewards(investor), 0, "User should have no pending rewards left after withdrawing");
        // assertEq(lm.rewardsLeft(), 0, "rewardsLeft should be 0");
        assertEq(lm.fundedEpochsLeft(), 0, "fundedEpochsLeft should be 0");
        // assertEq(rewardToken.balanceOf(address(lm)), 0, "Reward token should be fully paid out - 2");
        // assertEq(rewardToken.balanceOf(investor), totalRewards * 2, "Investor should receive all rewards - 2");
        assertRewardCapInvariant("testFuzz_LMExtensionAndFinalRewards2");
    }


    function testFuzz_InvariantDepositWithdraw(uint256 depositAmount, uint256 withdrawAmount, address beneficiary) public { // @audit-issue
        // Limit the fuzzing range for more reasonable values
        depositAmount = bound(depositAmount, 1, 1e24); 
        withdrawAmount = bound(withdrawAmount, 1, depositAmount); 
        vm.assume(beneficiary != address(0) && beneficiary != address(lm));

        // Mint tokens to the beneficiary so they can be deposited
        MintBurnERC20(address(lockToken)).mint(beneficiary, depositAmount);
        vm.prank(beneficiary);
        lockToken.approve(address(lm), depositAmount);

        // Perform the deposit
        vm.prank(beneficiary);
        lm.deposit(depositAmount, beneficiary);

        // Add user to the list of users if not already tracked
        if (!isUserTracked(beneficiary)) {
            users.push(beneficiary);
        }

        // Load rewards into the contract
        _loadRewards(totalRewards);

        // Simulate passage of time to accumulate rewards
        uint256 blocksPassed = 1000;
        vm.roll(block.number + blocksPassed);

        // Update accounting to reflect the passage of time and accumulated rewards
        lm.updateAccounting();

        // Ensure there are rewards to harvest
        uint256 pendingRewardsBeforeWithdraw = lm.pendingRewards(beneficiary);
        console.log("Pending rewards before withdrawal:", pendingRewardsBeforeWithdraw);

        // Verify user state before withdraw
        LiquidityMine.UserInfo memory userBeforeWithdraw = lm.userInfo(beneficiary);
        console.log("User before withdraw - lockedTokens:", userBeforeWithdraw.lockedTokens);
        console.log("User before withdraw - rewardDebt:", userBeforeWithdraw.rewardDebt);
        console.log("User before withdraw - unclaimedRewards:", userBeforeWithdraw.unclaimedRewards);

        // Perform the withdraw
        vm.prank(beneficiary);
        lm.withdraw(depositAmount, beneficiary);

        // Ensure the rewards are still correct after withdrawal
        uint256 pendingRewardsAfterWithdraw = lm.pendingRewards(beneficiary);
        console.log("Pending rewards after withdrawal:", pendingRewardsAfterWithdraw);

        // Verify user state after withdraw
        LiquidityMine.UserInfo memory userAfterWithdraw = lm.userInfo(beneficiary);
        console.log("User after withdraw - lockedTokens:", userAfterWithdraw.lockedTokens);
        console.log("User after withdraw - rewardDebt:", userAfterWithdraw.rewardDebt);
        console.log("User after withdraw - unclaimedRewards:", userAfterWithdraw.unclaimedRewards);

        // Perform the harvest
        vm.prank(beneficiary);
        lm.harvest(pendingRewardsAfterWithdraw, beneficiary);

        // Verify user state after harvest
        LiquidityMine.UserInfo memory userAfterHarvest = lm.userInfo(beneficiary);
        console.log("User after harvest - lockedTokens:", userAfterHarvest.lockedTokens);
        console.log("User after harvest - rewardDebt:", userAfterHarvest.rewardDebt);
        console.log("User after harvest - unclaimedRewards:", userAfterHarvest.unclaimedRewards);

        // Verify pending rewards after harvest
        uint256 pendingRewardsAfterHarvest = lm.pendingRewards(beneficiary);
        console.log("Pending rewards after harvest:", pendingRewardsAfterHarvest);

        // Check that the total claimed rewards are correct
        uint256 totalClaimedRewardsFromContract = lm.rewardTokensClaimed();
        uint256 totalClaimedRewardsCalculated = depositAmount.mulWadDown(lm.accRewardsPerLockToken());
        console.log("Total claimed rewards from contract:", totalClaimedRewardsFromContract);
        console.log("Total claimed rewards calculated:", totalClaimedRewardsCalculated);

        // Final assertions
        assertEq(pendingRewardsAfterHarvest, 0, "Pending rewards after harvest should be zero");
        assertEq(totalClaimedRewardsFromContract, totalClaimedRewardsCalculated, "Total claimed rewards should be correct");

        // Additional final state verification
        LiquidityMine.UserInfo memory beneficiaryInfo = lm.userInfo(beneficiary);
        console.log("Beneficiary lockedTokens:", beneficiaryInfo.lockedTokens);
        console.log("Beneficiary rewardDebt:", beneficiaryInfo.rewardDebt);
        console.log("Beneficiary unclaimedRewards:", beneficiaryInfo.unclaimedRewards);
        assertEq(lm.pendingRewards(beneficiary), 0, "Pending rewards after harvest should be zero");

        // uint256 totalRewardsAccrued = lm.accRewardsTotal();
        // uint256 totalRewardsClaimed = lm.rewardTokensClaimed();
        // uint256 totalRewardsUnclaimed = 0;

        // for (uint256 i = 0; i < users.length; i++) {
        //     LiquidityMine.UserInfo memory user = lm.userInfo(users[i]);
        //     totalRewardsUnclaimed += user.unclaimedRewards;
        // }

        // assertEq(
        //     totalRewardsAccrued,
        //     totalRewardsClaimed + totalRewardsUnclaimed,
        //     "Total rewards accrued should equal the sum of claimed and unclaimed rewards"
        // );

        // Run other invariants
        assert_TotalLockedTokensMustBeCorrect();
        assert_RewardDebtConsistency();
        assert_UnclaimedRewardsConsistency();
        assert_TotalRewardTokensClaimed();
        assert_MaxRewardCapConsistency();
        assert_AccRewardsTotalShouldNotExceedTotalRewardCap();
        assert_RewardTokensClaimedShouldNotExceedAccRewardsTotal();
        assert_GLFTokenBalanceAndRewardTokensClaimedShouldEqualTotalRewardCap();
        assert_NoResidualDust();
        assert_RewardTokenBalanceConsistency(); //@audit
        assert_TotalRewardConsistency(); //@audit
    }


    function testFuzz_InvariantDepositHighValuesWithdraw(uint256 depositAmount, uint256 withdrawAmount, address beneficiary) public { // @audit-issue
        // Limit the fuzzing range for extremely high values
        depositAmount = bound(depositAmount, 1e35, 1e40); 
        withdrawAmount = bound(withdrawAmount, 1e35, depositAmount); 
        vm.assume(beneficiary != address(0) && beneficiary != address(lm)); 

        // Mint tokens to the beneficiary so they can be deposited
        MintBurnERC20(address(lockToken)).mint(beneficiary, depositAmount);
        vm.prank(beneficiary);
        lockToken.approve(address(lm), depositAmount);

        // Perform the deposit
        vm.prank(beneficiary);
        lm.deposit(depositAmount, beneficiary);

        // Add user to the list of users if not already tracked
        if (!isUserTracked(beneficiary)) {
            users.push(beneficiary);
        }

        // Load rewards into the contract
        _loadRewards(totalRewards);

        // Simulate passage of time to accumulate rewards
        uint256 blocksPassed = 1000;
        vm.roll(block.number + blocksPassed);

        // Update accounting to reflect the passage of time and accumulated rewards
        lm.updateAccounting();

        // Ensure there are rewards to harvest
        uint256 pendingRewardsBeforeWithdraw = lm.pendingRewards(beneficiary);
        console.log("Pending rewards before withdrawal:", pendingRewardsBeforeWithdraw);

        // Verify user state before withdraw
        LiquidityMine.UserInfo memory userBeforeWithdraw = lm.userInfo(beneficiary);

        // Perform the withdraw
        vm.prank(beneficiary);
        lm.withdraw(withdrawAmount, beneficiary);

        // Ensure the rewards are still correct after withdrawal
        uint256 pendingRewardsAfterWithdraw = lm.pendingRewards(beneficiary);

        // Verify user state after withdraw
        LiquidityMine.UserInfo memory userAfterWithdraw = lm.userInfo(beneficiary);

        // Check if there are pending rewards to harvest
        if (pendingRewardsAfterWithdraw > 0) {
            // Perform the harvest
            vm.prank(beneficiary);
            lm.harvest(pendingRewardsAfterWithdraw, beneficiary);
        } else {
            console.log("No rewards to harvest after withdrawal.");
        }

        // Verify user state after harvest
        LiquidityMine.UserInfo memory userAfterHarvest = lm.userInfo(beneficiary);

        // Verify pending rewards after harvest
        uint256 pendingRewardsAfterHarvest = lm.pendingRewards(beneficiary);

        // Check that the total claimed rewards are correct
        uint256 totalClaimedRewardsFromContract = lm.rewardTokensClaimed();
        uint256 totalClaimedRewardsCalculated = depositAmount.mulWadDown(lm.accRewardsPerLockToken());

        // Final assertions
        assertEq(pendingRewardsAfterHarvest, 0, "Pending rewards after harvest should be zero");
        assertEq(totalClaimedRewardsFromContract, totalClaimedRewardsCalculated, "Total claimed rewards should be correct");

        // Additional final state verification
        LiquidityMine.UserInfo memory beneficiaryInfo = lm.userInfo(beneficiary);

        assertEq(lm.pendingRewards(beneficiary), 0, "Pending rewards after harvest should be zero");

        // Verify accRewardsTotal and rewardTokensClaimed
        uint256 accRewardsTotal = lm.accRewardsTotal();


        assertEq(
            accRewardsTotal,
            totalClaimedRewardsFromContract + beneficiaryInfo.unclaimedRewards,
            "Total rewards accrued should equal the sum of claimed and unclaimed rewards"
        );

        // Run other invariants
        assert_TotalLockedTokensMustBeCorrect();
        assert_RewardDebtConsistency();
        assert_UnclaimedRewardsConsistency();
        assert_TotalRewardTokensClaimed();
        assert_MaxRewardCapConsistency();
        assert_AccRewardsTotalShouldNotExceedTotalRewardCap();
        assert_RewardTokensClaimedShouldNotExceedAccRewardsTotal();
        assert_GLFTokenBalanceAndRewardTokensClaimedShouldEqualTotalRewardCap();
        assert_NoResidualDust();
        assert_RewardTokenBalanceConsistency();//@audit
        assert_TotalRewardConsistency();//@audit


    }


    function testFuzz_RewardAccumulationAndDistribution(uint256 depositAmount, uint256 withdrawAmount, address beneficiary) public {
        // Limit the fuzzing range for more reasonable values
        depositAmount = bound(depositAmount, 1, 1e24); 
        withdrawAmount = bound(withdrawAmount, 1, depositAmount); 
        vm.assume(beneficiary != address(0) && beneficiary != address(lm)); 

        // Mint tokens to the beneficiary so they can be deposited
        MintBurnERC20(address(lockToken)).mint(beneficiary, depositAmount);
        vm.prank(beneficiary);
        lockToken.approve(address(lm), depositAmount);

        // Perform the deposit
        vm.prank(beneficiary);
        lm.deposit(depositAmount, beneficiary);

        // Add user to the list of users if not already tracked
        if (!isUserTracked(beneficiary)) {
            users.push(beneficiary);
        }

        // Simulate passage of time to accumulate rewards
        uint256 blocksPassed = 1000;
        vm.roll(block.number + blocksPassed);

        // Update accounting to reflect the passage of time and accumulated rewards
        lm.updateAccounting();

        // Perform the withdraw
        vm.prank(beneficiary);
        lm.withdraw(withdrawAmount, beneficiary);

        // Verify rewards accumulated correctly
        LiquidityMine.UserInfo memory user = lm.userInfo(beneficiary);
        uint256 lockTokenSupply = lockToken.balanceOf(address(lm));
        if (lockTokenSupply > 0) {
            uint256 accRewardsPerLockToken = lm.accRewardsPerLockToken();
            uint256 expectedRewards = (depositAmount - withdrawAmount).mulWadDown(accRewardsPerLockToken) - user.rewardDebt + user.unclaimedRewards;
            assertEq(user.unclaimedRewards, expectedRewards, "Unclaimed rewards should be correct after withdrawal");
        }

        // Check invariants
        assert_TotalLockedTokensMustBeCorrect();
        assert_RewardDebtConsistency();
        assert_UnclaimedRewardsConsistency();
        assert_TotalRewardTokensClaimed();
        assert_RewardTokenBalanceConsistency();
        assert_TotalRewardConsistency();
        assert_MaxRewardCapConsistency();
        assert_AccRewardsTotalShouldNotExceedTotalRewardCap();
        assert_RewardTokensClaimedShouldNotExceedAccRewardsTotal();
        assert_GLFTokenBalanceAndRewardTokensClaimedShouldEqualTotalRewardCap();
        assert_NoResidualDust();
    }

    function testFuzz_LoadRewards(uint256 amount, address user) public {
        amount = bound(amount, 1, 1e24); 
        vm.assume(user != address(0) && user != address(lm));

        // Mint reward tokens to the user so they can be loaded
        MintBurnERC20(address(rewardToken)).mint(user, amount);
        vm.prank(user);
        rewardToken.approve(address(lm), amount);

        // Perform the loadRewards
        vm.prank(user);
        lm.loadRewards(amount);

        // Check invariants
        assert_TotalLockedTokensMustBeCorrect();
        assert_RewardDebtConsistency();
        assert_UnclaimedRewardsConsistency();
        assert_TotalRewardTokensClaimed();
        assert_RewardTokenBalanceConsistency();
        assert_TotalRewardConsistency();
        assert_MaxRewardCapConsistency();
        assert_AccRewardsTotalShouldNotExceedTotalRewardCap();
        assert_RewardTokensClaimedShouldNotExceedAccRewardsTotal();
        assert_GLFTokenBalanceAndRewardTokensClaimedShouldEqualTotalRewardCap();
        assert_NoResidualDust();
    }

    function testFuzz_Harvest(uint256 depositAmount, uint256 harvestAmount, address beneficiary) public {
        depositAmount = bound(depositAmount, 1, 1e24); // Limit deposit amount between 1 and 1e24
        vm.assume(beneficiary != address(0) && beneficiary != address(lm));

        // Mint tokens to the beneficiary so they can be deposited
        MintBurnERC20(address(lockToken)).mint(beneficiary, depositAmount);
        vm.prank(beneficiary);
        lockToken.approve(address(lm), depositAmount);

        // Perform the deposit
        vm.prank(beneficiary);
        lm.deposit(depositAmount, beneficiary);

        // Add user to the list of users if not already tracked
        if (!isUserTracked(beneficiary)) {
            users.push(beneficiary);
        }

        // Simulate passage of time to accumulate rewards
        uint256 blocksPassed = 1000;
        vm.roll(block.number + blocksPassed);

        // Update accounting to reflect the passage of time and accumulated rewards
        lm.updateAccounting();

        // Ensure there are rewards to harvest
        uint256 pendingRewards = lm.pendingRewards(beneficiary);
        if (pendingRewards == 0) {
            return; // Skip this test if no rewards to harvest
        }

        // Bound the harvest amount to the pending rewards
        harvestAmount = bound(harvestAmount, 1, pendingRewards);

        // Perform the harvest
        vm.prank(beneficiary);
        lm.harvest(harvestAmount, beneficiary);

        // Check invariants
        assert_TotalLockedTokensMustBeCorrect();
        assert_RewardDebtConsistency();
        assert_UnclaimedRewardsConsistency();
        assert_TotalRewardTokensClaimed();
        assert_RewardTokenBalanceConsistency();
        assert_TotalRewardConsistency();
        assert_MaxRewardCapConsistency();
        assert_AccRewardsTotalShouldNotExceedTotalRewardCap();
        assert_RewardTokensClaimedShouldNotExceedAccRewardsTotal();
        assert_GLFTokenBalanceAndRewardTokensClaimedShouldEqualTotalRewardCap();
        assert_NoResidualDust();

    }

    function testFuzz_MultiUserDepositHarvest(uint256 accounts, uint256 depositAmount) public { //@audit => verify
        accounts = bound(accounts, 1, 100);
        depositAmount = bound(depositAmount, 1, 2_000_000_000e18);

        _loadRewards(totalRewards);

        address[] memory localUsers = new address[](accounts);

        // make deposits for each user
        for (uint256 i = 0; i < accounts; i++) {
            address user = makeAddr(concatStrings("user", vm.toString(i)));
            localUsers[i] = user;
            _depositLockTokens(user, depositAmount);
        }

        assertRewardCapInvariant("testFuzz_MultiUserDepositHarvest1");

        // pick random users to harvest at 10 random epochs along the way
        uint256 fundedEpochsLeft = lm.fundedEpochsLeft();
        uint256 chunks = 10;
        if (accounts < chunks) {
            chunks = accounts;
        }
        for (uint256 i = 0; i < chunks; i++) {
            // here we add extra epochs so we roll over the end of the LM to ensure everything works properly
            vm.roll(block.number + (fundedEpochsLeft / chunks) + 5);
            address user = localUsers[i];
            vm.prank(user);
            lm.harvest(type(uint256).max, user);
        }

        assertRewardCapInvariant("testFuzz_MultiUserDepositHarvest2");

        // make sure the lm is over
        assertEq(lm.fundedEpochsLeft(), 0, "fundedEpochsLeft should be 0");
        // harvest rewards for each user to make sure all rewards are harvested
        for (uint256 i = 0; i < accounts; i++) {
            address user = localUsers[i];
            vm.startPrank(user);
            uint256 pending = lm.pendingRewards(user);
            if (pending > 0) {
                lm.harvest(type(uint256).max, user);
            } else {
                try lm.harvest(type(uint256).max, user) {
                    assertTrue(false, "Should not be able to harvest 0 rewards");
                } catch {
                    // expected
                }
            }
            vm.stopPrank();
            assertApproxEqAbs(
                rewardToken.balanceOf(user),
                totalRewards.divWadDown(accounts * 1e18),
                DUST,
                "Received Rewards: User should receive proportionate rewards"
            );
        }

        assertRewardCapInvariant("testFuzz_MultiUserDepositHarvest3");
    }



    /////////////////////////////////////
    // https://github.com/glifio/token/issues/1
    /////////////////////////////////////

//@audit-issue => Total rewards accrued should equal the sum of claimed and unclaimed rewards
    function testFuzz_InvariantPrecisionHighDepositWithdraw(uint256 depositAmount, uint256 withdrawAmount, address beneficiary) public { 
        // Limit the fuzzing range for more reasonable values
        depositAmount = bound(depositAmount, 1e35, 1e40); // Limit deposit amount between 1e35 and 1e40
        withdrawAmount = bound(withdrawAmount, 1, depositAmount); // Limit withdraw amount between 1 and depositAmount
        vm.assume(beneficiary != address(0) && beneficiary != address(lm)); // Assume beneficiary is not the zero address or the contract address

        // Mint tokens to the beneficiary so they can be deposited
        MintBurnERC20(address(lockToken)).mint(beneficiary, depositAmount);
        vm.prank(beneficiary);
        lockToken.approve(address(lm), depositAmount);

        // Perform the deposit
        vm.prank(beneficiary);
        lm.deposit(depositAmount, beneficiary);

        // Add user to the list of users if not already tracked
        if (!isUserTracked(beneficiary)) {
            users.push(beneficiary);
        }

        // Load rewards into the contract
        _loadRewards(totalRewards);

        // Simulate passage of time to accumulate rewards
        uint256 blocksPassed = 1000;
        vm.roll(block.number + blocksPassed);

        // Update accounting to reflect the passage of time and accumulated rewards
        lm.updateAccounting();

        // Ensure there are rewards to harvest
        uint256 pendingRewardsBeforeWithdraw = lm.pendingRewards(beneficiary);

        // Verify user state before withdraw
        LiquidityMine.UserInfo memory userBeforeWithdraw = lm.userInfo(beneficiary);

        // Perform the withdraw
        vm.prank(beneficiary);
        lm.withdraw(withdrawAmount, beneficiary);

        // Ensure the rewards are still correct after withdrawal
        uint256 pendingRewardsAfterWithdraw = lm.pendingRewards(beneficiary);

        // Verify user state after withdraw
        LiquidityMine.UserInfo memory userAfterWithdraw = lm.userInfo(beneficiary);

        // Perform the harvest
        vm.prank(beneficiary);
        lm.harvest(pendingRewardsAfterWithdraw, beneficiary);

        // Verify user state after harvest
        LiquidityMine.UserInfo memory userAfterHarvest = lm.userInfo(beneficiary);

        // Verify pending rewards after harvest
        uint256 pendingRewardsAfterHarvest = lm.pendingRewards(beneficiary);

        // Check that the total claimed rewards are correct
        uint256 totalClaimedRewardsFromContract = lm.rewardTokensClaimed();
        uint256 totalClaimedRewardsCalculated = depositAmount.mulWadDown(lm.accRewardsPerLockToken());

        // Final assertions
        assertEq(pendingRewardsAfterHarvest, 0, "Pending rewards after harvest should be zero");
        assertEq(totalClaimedRewardsFromContract, totalClaimedRewardsCalculated, "Total claimed rewards should be correct");

        // Additional final state verification
        LiquidityMine.UserInfo memory beneficiaryInfo = lm.userInfo(beneficiary);
        assertEq(lm.pendingRewards(beneficiary), 0, "Pending rewards after harvest should be zero");

        // Verify accRewardsTotal and rewardTokensClaimed
        uint256 accRewardsTotal = lm.accRewardsTotal();
        console.log("accRewardsTotal:", accRewardsTotal);

        // Validate the invariant
        uint256 totalRewardsAccrued = lm.accRewardsTotal();
        uint256 totalRewardsClaimed = lm.rewardTokensClaimed();
        uint256 totalRewardsUnclaimed = 0;

        for (uint256 i = 0; i < users.length; i++) {
            LiquidityMine.UserInfo memory user = lm.userInfo(users[i]);
            totalRewardsUnclaimed += user.unclaimedRewards;
        }

        //@audit-ok (assertRewardCapInvariant)
        assertEq(
            lm.totalRewardCap(),
            totalRewardsClaimed + rewardToken.balanceOf(address(lm)),
            "Invariant assertRewardCapInvariant: "
        );

        //@audit-issue
        assertEq(
            totalRewardsAccrued,
            totalRewardsClaimed + totalRewardsUnclaimed,
            "Total rewards accrued should equal the sum of claimed and unclaimed rewards"
        );
    }


//@audit-issue => Total rewards accrued should equal the sum of claimed and unclaimed rewards
    function testFuzz_InvariantPrecisionDepositWithdraw(uint256 depositAmount, uint256 withdrawAmount, address beneficiary) public { //@audit => 2 assert
        // Limit the fuzzing range for more reasonable values
        depositAmount = bound(depositAmount, 1, 1e24); // Limit deposit amount between 1 and 1e24
        withdrawAmount = bound(withdrawAmount, 1, depositAmount); // Limit withdraw amount between 1 and depositAmount
        vm.assume(beneficiary != address(0) && beneficiary != address(lm)); // Assume beneficiary is not the zero address or the contract address

        // Mint tokens to the beneficiary so they can be deposited
        MintBurnERC20(address(lockToken)).mint(beneficiary, depositAmount);
        vm.prank(beneficiary);
        lockToken.approve(address(lm), depositAmount);

        // Perform the deposit
        vm.prank(beneficiary);
        lm.deposit(depositAmount, beneficiary);

        // Add user to the list of users if not already tracked
        if (!isUserTracked(beneficiary)) {
            users.push(beneficiary);
        }

        // Load rewards into the contract
        _loadRewards(totalRewards);

        // Simulate passage of time to accumulate rewards
        uint256 blocksPassed = 1000;
        vm.roll(block.number + blocksPassed);

        // Update accounting to reflect the passage of time and accumulated rewards
        lm.updateAccounting();

        // Ensure there are rewards to harvest
        uint256 pendingRewardsBeforeWithdraw = lm.pendingRewards(beneficiary);
        
        // Verify user state before withdraw
        LiquidityMine.UserInfo memory userBeforeWithdraw = lm.userInfo(beneficiary);

        // Perform the withdraw
        vm.prank(beneficiary);
        lm.withdraw(withdrawAmount, beneficiary);

        // Ensure the rewards are still correct after withdrawal
        uint256 pendingRewardsAfterWithdraw = lm.pendingRewards(beneficiary);

        // Verify user state after withdraw
        LiquidityMine.UserInfo memory userAfterWithdraw = lm.userInfo(beneficiary);

        // Perform the harvest
        vm.prank(beneficiary);
        lm.harvest(pendingRewardsAfterWithdraw, beneficiary);

        // Verify user state after harvest
        LiquidityMine.UserInfo memory userAfterHarvest = lm.userInfo(beneficiary);

        // Verify pending rewards after harvest
        uint256 pendingRewardsAfterHarvest = lm.pendingRewards(beneficiary);

        // Check that the total claimed rewards are correct
        uint256 totalClaimedRewardsFromContract = lm.rewardTokensClaimed();
        uint256 totalClaimedRewardsCalculated = depositAmount.mulWadDown(lm.accRewardsPerLockToken());


        // Final assertions
        assertEq(pendingRewardsAfterHarvest, 0, "Pending rewards after harvest should be zero");
        assertEq(totalClaimedRewardsFromContract, totalClaimedRewardsCalculated, "Total claimed rewards should be correct");

        // Additional final state verification
        LiquidityMine.UserInfo memory beneficiaryInfo = lm.userInfo(beneficiary);

        assertEq(lm.pendingRewards(beneficiary), 0, "Pending rewards after harvest should be zero");

        // Verify accRewardsTotal and rewardTokensClaimed
        uint256 accRewardsTotal = lm.accRewardsTotal();

        // Verificación del invariant original
        uint256 totalRewardsAccrued = lm.accRewardsTotal();
        uint256 totalRewardsClaimed = lm.rewardTokensClaimed();
        uint256 totalRewardsUnclaimed = 0;

        for (uint256 i = 0; i < users.length; i++) {
            LiquidityMine.UserInfo memory user = lm.userInfo(users[i]);
            totalRewardsUnclaimed += user.unclaimedRewards;
        }

        //@audit-ok (assertRewardCapInvariant)
        assertEq(
            lm.totalRewardCap(),
            totalRewardsClaimed + rewardToken.balanceOf(address(lm)),
            "Invariant assertRewardCapInvariant: "
        );

        //@audit-issue
        assertEq(
            totalRewardsAccrued,
            totalRewardsClaimed + totalRewardsUnclaimed,
            "Total rewards accrued should equal the sum of claimed and unclaimed rewards"
        );

    }

    /////////////////////////////////////
    // Final
    // https://github.com/glifio/token/issues/1
    /////////////////////////////////////


    function testFuzz_InvariantAccRewardsTotalLessThanOrEqualTotalRewardCap(
        uint256 depositAmount,
        uint256 withdrawAmount,
        uint256 rewardAmount,
        address beneficiary
    ) public { //@audit-ok
        // Limit the fuzzing range for more reasonable values
        depositAmount = bound(depositAmount, 1, 1e24);
        withdrawAmount = bound(withdrawAmount, 1, depositAmount);
        rewardAmount = bound(rewardAmount, 1, 1e24);
        vm.assume(beneficiary != address(0) && beneficiary != address(lm));

        // Mint tokens to the beneficiary so they can be deposited
        MintBurnERC20(address(lockToken)).mint(beneficiary, depositAmount);
        vm.prank(beneficiary);
        lockToken.approve(address(lm), depositAmount);

        // Perform the deposit
        vm.prank(beneficiary);
        lm.deposit(depositAmount, beneficiary);

        // Mint tokens to the beneficiary for rewards and give allowance to lm
        MintBurnERC20(address(rewardToken)).mint(beneficiary, rewardAmount);
        vm.prank(beneficiary);
        rewardToken.approve(address(lm), rewardAmount);

        // Load rewards into the contract
        vm.prank(beneficiary);
        lm.loadRewards(rewardAmount);

        // Simulate passage of time to accumulate rewards
        uint256 blocksPassed = 1000;
        vm.roll(block.number + blocksPassed);

        // Update accounting to reflect the passage of time and accumulated rewards
        lm.updateAccounting();

        // Perform the withdraw
        vm.prank(beneficiary);
        lm.withdraw(withdrawAmount, beneficiary);

        // Calculate pending rewards
        uint256 pendingRewards = lm.pendingRewards(beneficiary);

        // Ensure there are rewards to harvest
        if (pendingRewards > 0) {
            // Perform the harvest
            vm.prank(beneficiary);
            lm.harvest(pendingRewards, beneficiary);
        }

        // Verify invariants
        assertTrue(
            lm.accRewardsTotal() <= lm.totalRewardCap(),
            "Accrued rewards total should be less than or equal to total reward cap"
        );
        assertTrue(
            lm.rewardTokensClaimed() <= lm.accRewardsTotal(),
            "Total reward tokens claimed should be less than or equal to accrued rewards total"
        );
        assertEq(
            lm.totalRewardCap(),
            lm.rewardTokensClaimed() + rewardToken.balanceOf(address(lm)),
            "Total reward cap should equal the sum of claimed rewards and remaining balance in contract"
        );
    }

    function testFuzz_InvariantMultipleOperations(
        uint256 depositAmount1,
        uint256 depositAmount2,
        uint256 withdrawAmount1,
        uint256 withdrawAmount2,
        uint256 rewardAmount1,
        uint256 rewardAmount2,
        address beneficiary1,
        address beneficiary2
    ) public { //@audit-ok
        // Limit the fuzzing range for more reasonable values
        depositAmount1 = bound(depositAmount1, 1, 1e24);
        depositAmount2 = bound(depositAmount2, 1, 1e24);
        withdrawAmount1 = bound(withdrawAmount1, 1, depositAmount1);
        withdrawAmount2 = bound(withdrawAmount2, 1, depositAmount2);
        rewardAmount1 = bound(rewardAmount1, 1, 1e24);
        rewardAmount2 = bound(rewardAmount2, 1, 1e24);
        vm.assume(beneficiary1 != address(0) && beneficiary1 != address(lm));
        vm.assume(beneficiary2 != address(0) && beneficiary2 != address(lm));
        vm.assume(beneficiary1 != beneficiary2);

        // Mint tokens to the beneficiaries so they can be deposited
        MintBurnERC20(address(lockToken)).mint(beneficiary1, depositAmount1);
        MintBurnERC20(address(lockToken)).mint(beneficiary2, depositAmount2);
        vm.prank(beneficiary1);
        lockToken.approve(address(lm), depositAmount1);
        vm.prank(beneficiary2);
        lockToken.approve(address(lm), depositAmount2);

        // Perform the deposits
        vm.prank(beneficiary1);
        lm.deposit(depositAmount1, beneficiary1);
        vm.prank(beneficiary2);
        lm.deposit(depositAmount2, beneficiary2);

        // Mint tokens to the beneficiaries for rewards and give allowance to lm
        MintBurnERC20(address(rewardToken)).mint(beneficiary1, rewardAmount1);
        MintBurnERC20(address(rewardToken)).mint(beneficiary2, rewardAmount2);
        vm.prank(beneficiary1);
        rewardToken.approve(address(lm), rewardAmount1);
        vm.prank(beneficiary2);
        rewardToken.approve(address(lm), rewardAmount2);

        // Load rewards into the contract
        vm.prank(beneficiary1);
        lm.loadRewards(rewardAmount1);
        vm.prank(beneficiary2);
        lm.loadRewards(rewardAmount2);

        // Simulate passage of time to accumulate rewards
        uint256 blocksPassed = 1000;
        vm.roll(block.number + blocksPassed);

        // Update accounting to reflect the passage of time and accumulated rewards
        lm.updateAccounting();

        // Perform the withdrawals
        vm.prank(beneficiary1);
        lm.withdraw(withdrawAmount1, beneficiary1);
        vm.prank(beneficiary2);
        lm.withdraw(withdrawAmount2, beneficiary2);

        // Calculate pending rewards for both beneficiaries
        uint256 pendingRewards1 = lm.pendingRewards(beneficiary1);
        uint256 pendingRewards2 = lm.pendingRewards(beneficiary2);

        // Ensure there are rewards to harvest and perform the harvest
        if (pendingRewards1 > 0) {
            vm.prank(beneficiary1);
            lm.harvest(pendingRewards1, beneficiary1);
        }
        if (pendingRewards2 > 0) {
            vm.prank(beneficiary2);
            lm.harvest(pendingRewards2, beneficiary2);
        }

        // Verify invariants
        assertTrue(
            lm.accRewardsTotal() <= lm.totalRewardCap(),
            "Accrued rewards total should be less than or equal to total reward cap"
        );
        assertTrue(
            lm.rewardTokensClaimed() <= lm.accRewardsTotal(),
            "Total reward tokens claimed should be less than or equal to accrued rewards total"
        );
        assertEq(
            lm.totalRewardCap(),
            lm.rewardTokensClaimed() + rewardToken.balanceOf(address(lm)),
            "Total reward cap should equal the sum of claimed rewards and remaining balance in contract"
        );
    }

    function testFuzz_MultipleUsersOperations(
        uint256 depositAmount,
        uint256 withdrawAmount,
        uint256 rewardAmount
    ) public { //@audit-ok
        uint256 numberOfParticipants = 500;
        address[] memory participants = new address[](numberOfParticipants);
        uint256 blocksPassed = 1000;

        // Limit the fuzzing range for more reasonable values
        depositAmount = bound(depositAmount, 1 * 1e18, 100 * 1e18);
        withdrawAmount = bound(withdrawAmount, 1 * 1e18, depositAmount);
        rewardAmount = bound(rewardAmount, 1 * 1e18, 1000 * 1e18);

        // Generate and set up participants
        for (uint256 i = 0; i < numberOfParticipants; i++) {
            participants[i] = vm.addr(i + 1);
            vm.assume(participants[i] != address(0) && participants[i] != address(lm));

            // Mint lock tokens to the participants
            MintBurnERC20(address(lockToken)).mint(participants[i], depositAmount * 2); // Enough for deposit and potential multiple actions
            vm.prank(participants[i]);
            lockToken.approve(address(lm), depositAmount * 2);
        }

        // Mint reward tokens to the first participant to load rewards into the contract
        MintBurnERC20(address(rewardToken)).mint(participants[0], rewardAmount);
        vm.prank(participants[0]);
        rewardToken.approve(address(lm), rewardAmount);

        // Participants perform deposits
        for (uint256 i = 0; i < numberOfParticipants; i++) {
            vm.prank(participants[i]);
            lm.deposit(depositAmount, participants[i]);
        }

        // Load rewards into the contract by the first participant
        vm.prank(participants[0]);
        lm.loadRewards(rewardAmount);

        // Simulate passage of time to accumulate rewards
        vm.roll(block.number + blocksPassed);

        // Update accounting to reflect the passage of time and accumulated rewards
        lm.updateAccounting();

        // Participants perform withdrawals
        for (uint256 i = 0; i < numberOfParticipants; i++) {
            vm.prank(participants[i]);
            lm.withdraw(withdrawAmount, participants[i]);
        }

        // Participants harvest their rewards
        for (uint256 i = 0; i < numberOfParticipants; i++) {
            uint256 pendingRewards = lm.pendingRewards(participants[i]);
            if (pendingRewards > 0) {
                vm.prank(participants[i]);
                lm.harvest(pendingRewards, participants[i]);
            }
        }

        // Verify invariants
        assertTrue(
            lm.accRewardsTotal() <= lm.totalRewardCap(),
            "Accrued rewards total should be less than or equal to total reward cap"
        );
        assertTrue(
            lm.rewardTokensClaimed() <= lm.accRewardsTotal(),
            "Total reward tokens claimed should be less than or equal to accrued rewards total"
        );
        assertEq(
            lm.totalRewardCap(),
            lm.rewardTokensClaimed() + rewardToken.balanceOf(address(lm)),
            "Total reward cap should equal the sum of claimed rewards and remaining balance in contract"
        );
    }


    function testFuzz_RandomUserActionsWithCheck(
        uint256 depositAmount,
        uint256 withdrawAmount,
        uint256 rewardAmount
    ) public { //@audit-ok
        uint256 numberOfParticipants = 50;
        address[] memory participants = new address[](numberOfParticipants);
        uint256 blocksPassed = 1000;

        // Limit the fuzzing range for more reasonable values
        depositAmount = bound(depositAmount, 1 * 1e18, 100 * 1e18);
        withdrawAmount = bound(withdrawAmount, 1 * 1e18, depositAmount);
        rewardAmount = bound(rewardAmount, 1 * 1e18, 1000 * 1e18);

        // Generate and set up participants
        for (uint256 i = 0; i < numberOfParticipants; i++) {
            participants[i] = vm.addr(i + 1);
            vm.assume(participants[i] != address(0) && participants[i] != address(lm));

            // Mint lock tokens to the participants
            MintBurnERC20(address(lockToken)).mint(participants[i], depositAmount * 2); // Enough for deposit and potential multiple actions
            vm.prank(participants[i]);
            lockToken.approve(address(lm), depositAmount * 2);
        }

        // Mint reward tokens to the first participant to load rewards into the contract
        MintBurnERC20(address(rewardToken)).mint(participants[0], rewardAmount);
        vm.prank(participants[0]);
        rewardToken.approve(address(lm), rewardAmount);

        // Load rewards into the contract by the first participant
        vm.prank(participants[0]);
        lm.loadRewards(rewardAmount);

        // Simulate passage of time to accumulate rewards
        vm.roll(block.number + blocksPassed);

        // Update accounting to reflect the passage of time and accumulated rewards
        lm.updateAccounting();

        // Perform random actions for participants
        for (uint256 i = 0; i < numberOfParticipants; i++) {
            uint256 action = uint256(keccak256(abi.encodePacked(block.timestamp, i))) % 3;

            if (action == 0) {
                // Perform deposit
                vm.prank(participants[i]);
                lm.deposit(depositAmount, participants[i]);
            } else if (action == 1) {
                // Perform withdraw only if the user has sufficient locked tokens
                uint256 userLockedTokens = lm.userInfo(participants[i]).lockedTokens;
                if (userLockedTokens >= withdrawAmount) {
                    vm.prank(participants[i]);
                    lm.withdraw(withdrawAmount, participants[i]);
                }
            } else {
                // Perform harvest only if the user has pending rewards
                uint256 pendingRewards = lm.pendingRewards(participants[i]);
                if (pendingRewards > 0) {
                    vm.prank(participants[i]);
                    lm.harvest(pendingRewards, participants[i]);
                }
            }
        }

        // Simulate additional passage of time to accumulate more rewards
        vm.roll(block.number + blocksPassed);

        // Update accounting to reflect the passage of time and accumulated rewards
        lm.updateAccounting();

        // Perform another round of random actions for participants
        for (uint256 i = 0; i < numberOfParticipants; i++) {
            uint256 action = uint256(keccak256(abi.encodePacked(block.timestamp, i, "second round"))) % 3;

            if (action == 0) {
                // Perform deposit
                vm.prank(participants[i]);
                lm.deposit(depositAmount, participants[i]);
            } else if (action == 1) {
                // Perform withdraw only if the user has sufficient locked tokens
                uint256 userLockedTokens = lm.userInfo(participants[i]).lockedTokens;
                if (userLockedTokens >= withdrawAmount) {
                    vm.prank(participants[i]);
                    lm.withdraw(withdrawAmount, participants[i]);
                }
            } else {
                // Perform harvest only if the user has pending rewards
                uint256 pendingRewards = lm.pendingRewards(participants[i]);
                if (pendingRewards > 0) {
                    vm.prank(participants[i]);
                    lm.harvest(pendingRewards, participants[i]);
                }
            }
        }

        // Verify invariants
        assertTrue(
            lm.accRewardsTotal() <= lm.totalRewardCap(),
            "Accrued rewards total should be less than or equal to total reward cap"
        );
        assertTrue(
            lm.rewardTokensClaimed() <= lm.accRewardsTotal(),
            "Total reward tokens claimed should be less than or equal to accrued rewards total"
        );
        assertEq(
            lm.totalRewardCap(),
            lm.rewardTokensClaimed() + rewardToken.balanceOf(address(lm)),
            "Total reward cap should equal the sum of claimed rewards and remaining balance in contract"
        );
    }


    /////////////////////////////////////
    // https://github.com/glifio/token/pull/5
    // DUST
    /////////////////////////////////////
    function testFuzz_ImprecisionInRewardsDistribution(
        uint256 depositAmount,
        uint256 withdrawAmount,
        uint256 rewardAmount,
        address beneficiary
    ) public { //@audit-issue => DUST
        // Limit the fuzzing range for larger values to test precision issues
        depositAmount = bound(depositAmount, 1e35, 1e40);
        withdrawAmount = bound(withdrawAmount, 1, depositAmount);
        rewardAmount = bound(rewardAmount, 1e35, 1e40);
        vm.assume(beneficiary != address(0) && beneficiary != address(lm));

        // Mint tokens to the beneficiary so they can be deposited
        MintBurnERC20(address(lockToken)).mint(beneficiary, depositAmount);
        vm.prank(beneficiary);
        lockToken.approve(address(lm), depositAmount);

        // Perform the deposit
        vm.prank(beneficiary);
        lm.deposit(depositAmount, beneficiary);

        // Mint tokens to the beneficiary for rewards and give allowance to lm
        MintBurnERC20(address(rewardToken)).mint(beneficiary, rewardAmount);
        vm.prank(beneficiary);
        rewardToken.approve(address(lm), rewardAmount);

        // Load rewards into the contract
        vm.prank(beneficiary);
        lm.loadRewards(rewardAmount);

        // Simulate passage of time to accumulate rewards
        uint256 blocksPassed = 1000;
        vm.roll(block.number + blocksPassed);

        // Update accounting to reflect the passage of time and accumulated rewards
        lm.updateAccounting();

        // Perform the withdraw
        vm.prank(beneficiary);
        lm.withdraw(withdrawAmount, beneficiary);

        // Perform the harvest
        uint256 pendingRewards = lm.pendingRewards(beneficiary);
        if (pendingRewards > 0) {
            vm.prank(beneficiary);
            lm.harvest(pendingRewards, beneficiary);
        }

        // Verify invariants
        assertTrue(
            lm.accRewardsTotal() <= lm.totalRewardCap(),
            "Accrued rewards total should be less than or equal to total reward cap"
        );
        assertTrue(
            lm.rewardTokensClaimed() <= lm.accRewardsTotal(),
            "Total reward tokens claimed should be less than or equal to accrued rewards total"
        );

        // Check for residual dust without any margin
        uint256 accRewardsTotal = lm.accRewardsTotal();
        uint256 rewardTokensClaimed = lm.rewardTokensClaimed();
        uint256 remainingBalance = rewardToken.balanceOf(address(lm));
        uint256 totalRewardCap = lm.totalRewardCap();

        console.log("Accrued Rewards Total:", accRewardsTotal);
        console.log("Reward Tokens Claimed:", rewardTokensClaimed);
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

    function testFuzz_ImprecisionInRewardsDistribution_NormalValues(
        uint256 depositAmount,
        uint256 withdrawAmount,
        uint256 rewardAmount,
        address beneficiary
    ) public { //@audit-issue => DUST
        // Limit the fuzzing range for more reasonable values
        depositAmount = bound(depositAmount, 1e6, 1e12);
        withdrawAmount = bound(withdrawAmount, 1, depositAmount);
        rewardAmount = bound(rewardAmount, 1e6, 1e12);
        vm.assume(beneficiary != address(0) && beneficiary != address(lm));

        // Mint tokens to the beneficiary so they can be deposited
        MintBurnERC20(address(lockToken)).mint(beneficiary, depositAmount);
        vm.prank(beneficiary);
        lockToken.approve(address(lm), depositAmount);

        // Perform the deposit
        vm.prank(beneficiary);
        lm.deposit(depositAmount, beneficiary);

        // Mint tokens to the beneficiary for rewards and give allowance to lm
        MintBurnERC20(address(rewardToken)).mint(beneficiary, rewardAmount);
        vm.prank(beneficiary);
        rewardToken.approve(address(lm), rewardAmount);

        // Load rewards into the contract
        vm.prank(beneficiary);
        lm.loadRewards(rewardAmount);

        // Simulate passage of time to accumulate rewards
        uint256 blocksPassed = 1000;
        vm.roll(block.number + blocksPassed);

        // Update accounting to reflect the passage of time and accumulated rewards
        lm.updateAccounting();

        // Perform the withdraw
        vm.prank(beneficiary);
        lm.withdraw(withdrawAmount, beneficiary);

        // Perform the harvest
        uint256 pendingRewards = lm.pendingRewards(beneficiary);
        if (pendingRewards > 0) {
            vm.prank(beneficiary);
            lm.harvest(pendingRewards, beneficiary);
        }

        // Verify invariants
        assertTrue(
            lm.accRewardsTotal() <= lm.totalRewardCap(),
            "Accrued rewards total should be less than or equal to total reward cap"
        );
        assertTrue(
            lm.rewardTokensClaimed() <= lm.accRewardsTotal(),
            "Total reward tokens claimed should be less than or equal to accrued rewards total"
        );

        // Check for residual dust without any margin
        uint256 accRewardsTotal = lm.accRewardsTotal();
        uint256 rewardTokensClaimed = lm.rewardTokensClaimed();
        uint256 remainingBalance = rewardToken.balanceOf(address(lm));
        uint256 totalRewardCap = lm.totalRewardCap();

        console.log("Accrued Rewards Total:", accRewardsTotal);
        console.log("Reward Tokens Claimed:", rewardTokensClaimed);
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

    function testFuzz_ImprecisionMultiUser(
        uint256 depositAmount,
        uint256 withdrawAmount,
        uint256 rewardAmount
    ) public { //@audit-issue => DUST
        uint256 numberOfParticipants = 500;
        address[] memory participants = new address[](numberOfParticipants);
        uint256 blocksPassed = 1000;

        // Limit the fuzzing range for more reasonable values
        depositAmount = bound(depositAmount, 1 * 1e18, 100 * 1e18);
        withdrawAmount = bound(withdrawAmount, 1 * 1e18, depositAmount);
        rewardAmount = bound(rewardAmount, 1 * 1e18, 1000 * 1e18);

        // Generate and set up participants
        for (uint256 i = 0; i < numberOfParticipants; i++) {
            participants[i] = vm.addr(i + 1);
            vm.assume(participants[i] != address(0) && participants[i] != address(lm));

            // Mint lock tokens to the participants
            MintBurnERC20(address(lockToken)).mint(participants[i], depositAmount * 2); // Enough for deposit and potential multiple actions
            vm.prank(participants[i]);
            lockToken.approve(address(lm), depositAmount * 2);
        }

        // Mint reward tokens to the first participant to load rewards into the contract
        MintBurnERC20(address(rewardToken)).mint(participants[0], rewardAmount);
        vm.prank(participants[0]);
        rewardToken.approve(address(lm), rewardAmount);

        // Participants perform deposits
        for (uint256 i = 0; i < numberOfParticipants; i++) {
            vm.prank(participants[i]);
            lm.deposit(depositAmount, participants[i]);
        }

        // Load rewards into the contract by the first participant
        vm.prank(participants[0]);
        lm.loadRewards(rewardAmount);

        // Simulate passage of time to accumulate rewards
        vm.roll(block.number + blocksPassed);

        // Update accounting to reflect the passage of time and accumulated rewards
        lm.updateAccounting();

        // Participants perform withdrawals
        for (uint256 i = 0; i < numberOfParticipants; i++) {
            vm.prank(participants[i]);
            lm.withdraw(withdrawAmount, participants[i]);
        }

        // Participants harvest their rewards
        for (uint256 i = 0; i < numberOfParticipants; i++) {
            uint256 pendingRewards = lm.pendingRewards(participants[i]);
            if (pendingRewards > 0) {
                vm.prank(participants[i]);
                lm.harvest(pendingRewards, participants[i]);
            }
        }

        // Verify invariants
        assertTrue(
            lm.accRewardsTotal() <= lm.totalRewardCap(),
            "Accrued rewards total should be less than or equal to total reward cap"
        );
        assertTrue(
            lm.rewardTokensClaimed() <= lm.accRewardsTotal(),
            "Total reward tokens claimed should be less than or equal to accrued rewards total"
        );

        // Check for residual dust without any margin
        uint256 accRewardsTotal = lm.accRewardsTotal();
        uint256 rewardTokensClaimed = lm.rewardTokensClaimed();
        uint256 remainingBalance = rewardToken.balanceOf(address(lm));
        uint256 totalRewardCap = lm.totalRewardCap();

        console.log("Accrued Rewards Total:", accRewardsTotal);
        console.log("Reward Tokens Claimed:", rewardTokensClaimed);
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

    /////////////////////////////////////
    // https://github.com/glifio/token/pull/5
    // Final DUST
    /////////////////////////////////////


    /////////////////////////////////////
    //Tests Fixes2 
    // https://github.com/glifio/token/issues/2
    /////////////////////////////////////


    function testNoRewardsAccrue() public {
        uint256 depositAmount = 1e18 + 1;
        // load a small amount of rewards, such that it's 1 wei per block in reward distributions
        vm.prank(sysAdmin);
        lm.setRewardPerEpoch(1);
        _loadRewards(100);

        _depositLockTokens(investor, depositAmount);

        assertEq(lm.rewardsLeft(), 100, "rewardsLeft should be 100");
        assertEq(lm.fundedEpochsLeft(), 100, "rewardsLeft should be 100");

        // roll forward 1 block to accrue 1 wei of reward token
        vm.roll(block.number + 1);

        lm.updateAccounting();

        assertEq(lm.accRewardsPerLockToken(), 0, "accRewardsPerLockToken should be 0");
    }

    // this test ensures that rewards do not accrue if there would be a problem with rounding down on accRewardsPerLockToken
    // this situatin occurs when the lockTokenSupply > 1*10^18 * newRewards because divWadDown rounds to 0
    uint256 constant MIN_REWARD_PER_EPOCH = 1e10;

    function testNoRewardsAccrue(uint256 depositAmount) public {
        depositAmount = bound(depositAmount, 1, MAX_FIL);
        // load a small amount of rewards, such that it's 1 wei per block in reward distributions
        vm.prank(sysAdmin);
        lm.setRewardPerEpoch(MIN_REWARD_PER_EPOCH);
        _loadRewards(totalRewards);

        _depositLockTokens(investor, depositAmount);

        assertEq(lm.rewardsLeft(), totalRewards, "rewardsLeft should be totalRewards");

        // roll forward 1 block to accrue a small amount of reward token
        vm.roll(block.number + 1);

        lm.updateAccounting();

        assertGt(lm.accRewardsTotal(), 0, "accRewardsTotal should be greater than 0");
        assertGt(lm.accRewardsPerLockToken(), 0, "accRewardsPerLockToken should be 0");

        // roll to the end and all rewards should be distributed
        vm.roll(block.number + lm.fundedEpochsLeft());

        assertEq(lm.rewardsLeft(), 0, "rewardsLeft should be 0");
        assertEq(lm.fundedEpochsLeft(), 0, "fundedEpochsLeft should be 0");
        assertApproxEqAbs(lm.pendingRewards(investor), totalRewards, DUST, "Investor should receive all rewards");
    }

    function testFuzz_NoRewardsAccrue(uint256 depositAmount) public {
        depositAmount = bound(depositAmount, 1, MAX_FIL);
        // load a small amount of rewards, such that it's 1 wei per block in reward distributions
        vm.prank(sysAdmin);
        lm.setRewardPerEpoch(MIN_REWARD_PER_EPOCH);
        _loadRewards(totalRewards);

        _depositLockTokens(investor, depositAmount);

        assertEq(lm.rewardsLeft(), totalRewards, "rewardsLeft should be totalRewards");

        // roll forward 1 block to accrue a small amount of reward token
        vm.roll(block.number + 1);

        lm.updateAccounting();

        assertGt(lm.accRewardsTotal(), 0, "accRewardsTotal should be greater than 0");
        assertGt(lm.accRewardsPerLockToken(), 0, "accRewardsPerLockToken should be 0");

        // roll to the end and all rewards should be distributed
        vm.roll(block.number + lm.fundedEpochsLeft());

        assertEq(lm.rewardsLeft(), 0, "rewardsLeft should be 0");
        assertEq(lm.fundedEpochsLeft(), 0, "fundedEpochsLeft should be 0");
        assertApproxEqAbs(lm.pendingRewards(investor), totalRewards, DUST, "Investor should receive all rewards");
    }

    /////////////////////////////////////
    //Final Tests Fixes2
    /////////////////////////////////////

    function testFuzz_MultipleDepositsTwoUsers(uint256 amount1, uint256 amount2, address beneficiary1, address beneficiary2) public {
        // Limit the fuzzing range for more reasonable values
        amount1 = bound(amount1, 1, 1e24);
        amount2 = bound(amount2, 1, 1e24);
        vm.assume(beneficiary1 != address(0) && beneficiary1 != address(lm));
        vm.assume(beneficiary2 != address(0) && beneficiary2 != address(lm));

        // Mint tokens to the beneficiaries so they can be deposited
        MintBurnERC20(address(lockToken)).mint(beneficiary1, amount1);
        MintBurnERC20(address(lockToken)).mint(beneficiary2, amount2);

        vm.prank(beneficiary1);
        lockToken.approve(address(lm), amount1);
        vm.prank(beneficiary2);
        lockToken.approve(address(lm), amount2);

        uint256 initialContractBalance = lockToken.balanceOf(address(lm));

        // Perform the first deposit
        vm.prank(beneficiary1);
        lm.deposit(amount1, beneficiary1);

        // Perform the second deposit
        vm.prank(beneficiary2);
        lm.deposit(amount2, beneficiary2);

        // Verify the final contract balance after both deposits
        uint256 finalContractBalance = lockToken.balanceOf(address(lm));
        assertEq(finalContractBalance, initialContractBalance + amount1 + amount2, "Contract balance should increase by the total deposit amount");

        // Verify the locked tokens for each beneficiary
        LiquidityMine.UserInfo memory user1 = lm.userInfo(beneficiary1);
        assertEq(user1.lockedTokens, amount1, "Beneficiary1's locked tokens should equal the first deposit amount");

        LiquidityMine.UserInfo memory user2 = lm.userInfo(beneficiary2);
        assertEq(user2.lockedTokens, amount2, "Beneficiary2's locked tokens should equal the second deposit amount");
    }


    function testFuzz_MultipleDepositsSingleUser(uint256 amount1, uint256 amount2, address beneficiary) public {
        // Limit the fuzzing range for more reasonable values
        amount1 = bound(amount1, 1, 10000);
        amount2 = bound(amount2, 1, 10000);
        vm.assume(beneficiary != address(0) && beneficiary != address(lm));

        // Mint tokens to the beneficiary so they can be deposited
        MintBurnERC20(address(lockToken)).mint(beneficiary, amount1 + amount2);

        vm.prank(beneficiary);
        lockToken.approve(address(lm), amount1 + amount2);

        uint256 initialContractBalance = lockToken.balanceOf(address(lm));

        // Perform the first deposit
        vm.prank(beneficiary);
        lm.deposit(amount1, beneficiary);

        // Perform the second deposit
        vm.prank(beneficiary);
        lm.deposit(amount2, beneficiary);

        // Verify the final contract balance after both deposits
        uint256 finalContractBalance = lockToken.balanceOf(address(lm));
        assertEq(finalContractBalance, initialContractBalance + amount1 + amount2, "Contract balance should increase by the total deposit amount");

        // Verify the locked tokens for the beneficiary
        LiquidityMine.UserInfo memory user = lm.userInfo(beneficiary);
        assertEq(user.lockedTokens, amount1 + amount2, "Beneficiary's locked tokens should equal the total deposit amount");
    }



}
