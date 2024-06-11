// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./EchidnaSetup.sol";
import "../LiquidityMine.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";

contract EchidnaLiquidityMine is EchidnaSetup {
    using FixedPointMathLib for uint256;

    LiquidityMine internal lm;
    uint256 internal deployBlock;

    uint256 constant internal REWARD_PER_EPOCH = 1e18;
    uint256 constant internal TOTAL_REWARDS = 75_000_000e18;


    address internal constant SYS_ADMIN = address(0x50000);

    constructor() payable {
        deployBlock = block.number;
        lm = new LiquidityMine(rewardToken, lockToken, REWARD_PER_EPOCH, SYS_ADMIN);

        // Mint initial rewards to system admin
        MockERC20(address(rewardToken)).mint(SYS_ADMIN, TOTAL_REWARDS);

        // SysAdmin should have initial total rewards balance
        assert(rewardToken.balanceOf(SYS_ADMIN) == TOTAL_REWARDS); 
    }

    function prepareTokens(uint256 amount) internal {
        MockERC20(address(lockToken)).mint(USER1, amount);
        hevm.prank(USER1);
        lockToken.approve(address(lm), amount);
    }

    function prepareDeposit(uint256 depositAmount) internal {
        prepareTokens(depositAmount);
        hevm.prank(USER1);
        lm.deposit(depositAmount, USER1);
    }

    function loadRewards(uint256 amount) internal {
        MockERC20(address(rewardToken)).mint(address(this), amount);
        rewardToken.approve(address(lm), amount);
        lm.loadRewards(amount);
    }

    function advanceBlocks(uint256 blocks) internal {
        hevm.roll(block.number + blocks);
    }

    // ============================================
    // ==                DEPOSIT                 ==
    // ============================================

    function test_locked_tokens_increase(uint256 amount) public {
        if (amount == 0 ) return;
        if (amount > 10000) return;

        prepareTokens(amount);

        LiquidityMine.UserInfo memory userInfo = lm.userInfo(USER1);
        uint256 initialLockedTokens = userInfo.lockedTokens;

        hevm.prank(USER1);
        try lm.deposit(amount, USER1) {
            // continue
        } catch {
            assert(false);
        }

        uint256 finalLockedTokens = lm.userInfo(USER1).lockedTokens;

        assert(finalLockedTokens == amount + initialLockedTokens);
    }

    function test_unclaimed_rewards_calculation(uint256 amount) public {
        if (amount == 0) return;
        if (amount > 10000) return;

        prepareTokens(amount);
        hevm.prank(USER1);
        lm.deposit(amount, USER1);

        LiquidityMine.UserInfo memory user = lm.userInfo(USER1);

        // Calculate expected unclaimed rewards
        uint256 previousUnclaimedRewards = user.unclaimedRewards;
        uint256 lockedTokens = user.lockedTokens;
        uint256 accRewardsPerLockToken = lm.accRewardsPerLockToken();
        uint256 rewardDebt = user.rewardDebt;

        uint256 newlyAccruedRewards = accRewardsPerLockToken.mulWadDown(lockedTokens);
        uint256 expectedUnclaimedRewards = previousUnclaimedRewards + newlyAccruedRewards - rewardDebt;

        assert(user.unclaimedRewards == expectedUnclaimedRewards);
    }

    function test_reward_debt_calculation(uint256 amount) public {
        if (amount == 0) return;
        if (amount > 10000) return;

        prepareTokens(amount);
        hevm.prank(USER1);
        lm.deposit(amount, USER1);

        LiquidityMine.UserInfo memory userInfo = lm.userInfo(USER1);
        uint256 expectedRewardDebt = lm.accRewardsPerLockToken().mulWadDown(userInfo.lockedTokens);
        
        assert(userInfo.rewardDebt == expectedRewardDebt);
    }

    function test_deposit_transfer_successful(uint256 amount) public {
        if (amount == 0) return;
        if (amount > 10000) return;

        uint256 initialContractBalance = lockToken.balanceOf(address(lm));
        uint256 initialUserBalance = lockToken.balanceOf(USER1);

        prepareTokens(amount);
        hevm.prank(USER1);
        lm.deposit(amount);

        uint256 finalContractBalance = MockERC20(address(lockToken)).balanceOf(address(lm));
        uint256 finalUserBalance = MockERC20(address(lockToken)).balanceOf(USER1);

        Debugger.log("amount", amount);
        Debugger.log("initialContractBalance", initialContractBalance);
        Debugger.log("finalContractBalance", finalContractBalance);
        Debugger.log("difference", finalContractBalance - initialContractBalance);
        assert(finalContractBalance == initialContractBalance + amount);
        Debugger.log("initialUserBalance", initialUserBalance);
        Debugger.log("finalUserBalance", finalUserBalance);
        Debugger.log("difference", initialUserBalance - finalUserBalance);
        assert(finalUserBalance == initialUserBalance - amount);
    }

    // ============================================
    // ==               WITHDRAW                 ==
    // ============================================

    function test_locked_tokens_decrease(uint256 depositAmount, uint256 withdrawAmount) public {
        if (depositAmount == 0 || depositAmount > 10000) return;
        if (withdrawAmount > depositAmount) return;

        prepareDeposit(depositAmount);

        LiquidityMine.UserInfo memory userInfoBefore = lm.userInfo(USER1);
        uint256 initialLockedTokens = userInfoBefore.lockedTokens;
        Debugger.log("initialLockedTokens", initialLockedTokens);

        hevm.prank(USER1);
        lm.withdraw(withdrawAmount);

        uint256 finalLockedTokens = initialLockedTokens - withdrawAmount;

        LiquidityMine.UserInfo memory userInfoAfter = lm.userInfo(USER1);
        uint256 currentLockedTokens = userInfoAfter.lockedTokens;

        Debugger.log("finalLockedTokens", finalLockedTokens);
        Debugger.log("currentLockedTokens", currentLockedTokens);
        Debugger.log("difference", currentLockedTokens - finalLockedTokens);
        assert(finalLockedTokens == currentLockedTokens);
    }


    function test_unclaimed_rewards_update(uint256 depositAmount, uint256 withdrawAmount) public {
        if (depositAmount == 0 || depositAmount > 10000) return;
        if (withdrawAmount > depositAmount) return;

        prepareDeposit(depositAmount);

        LiquidityMine.UserInfo memory userInfoBefore = lm.userInfo(USER1);
        uint256 previousUnclaimedRewards = userInfoBefore.unclaimedRewards;
        uint256 lockedTokens = userInfoBefore.lockedTokens;
        uint256 rewardDebt = userInfoBefore.rewardDebt;
        uint256 accRewardsPerLockToken = lm.accRewardsPerLockToken();

        hevm.prank(USER1);
        lm.withdraw(withdrawAmount);

        LiquidityMine.UserInfo memory userInfoAfter = lm.userInfo(USER1);

        uint256 newlyAccruedRewards = lockedTokens.mulWadDown(accRewardsPerLockToken);
        uint256 expectedUnclaimedRewards = previousUnclaimedRewards + newlyAccruedRewards - rewardDebt;

        uint256 finalUnclaimedRewards = userInfoAfter.unclaimedRewards;

        assert(finalUnclaimedRewards == expectedUnclaimedRewards);
    }

    function test_reward_debt_update(uint256 depositAmount, uint256 withdrawAmount) public {
        if (depositAmount == 0 || depositAmount > 10000) return;
        if (withdrawAmount > depositAmount) return;

        prepareDeposit(depositAmount);

        hevm.prank(USER1);
        lm.withdraw(withdrawAmount);

        LiquidityMine.UserInfo memory userInfoAfter = lm.userInfo(USER1);

        uint256 accRewardsPerLockToken = lm.accRewardsPerLockToken();
        uint256 lockedTokensAfterWithdraw = userInfoAfter.lockedTokens;

        uint256 expectedRewardDebt = lockedTokensAfterWithdraw.mulWadDown(accRewardsPerLockToken);

        assert(userInfoAfter.rewardDebt == expectedRewardDebt);
    }

    function test_withdraw_transfer_successful(uint256 depositAmount, uint256 withdrawAmount) public {
        if (depositAmount == 0 || depositAmount > 10000) return;
        if (withdrawAmount > depositAmount) return;

        prepareDeposit(depositAmount);

        uint256 initialContractBalance = MockERC20(address(lockToken)).balanceOf(address(lm));
        uint256 initialUserBalance = MockERC20(address(lockToken)).balanceOf(USER1);


        hevm.prank(USER1);
        lm.withdraw(withdrawAmount);

        uint256 finalContractBalance = MockERC20(address(lockToken)).balanceOf(address(lm));
        uint256 finalUserBalance = MockERC20(address(lockToken)).balanceOf(USER1);

        uint256 actualWithdrawAmount = (withdrawAmount > depositAmount) ? depositAmount : withdrawAmount;

        Debugger.log("initialContractBalance", initialContractBalance - actualWithdrawAmount);
        Debugger.log("finalContractBalance", finalContractBalance);
        Debugger.log("difference", initialContractBalance - actualWithdrawAmount - finalContractBalance);
        assert(finalContractBalance == initialContractBalance - actualWithdrawAmount);
        assert(finalUserBalance == initialUserBalance + actualWithdrawAmount);
    }

    // ============================================
    // ==                HARVEST                 ==
    // ============================================

    function test_harvest_rewards_update(uint256 depositAmount, uint256 harvestAmount, uint256 nextBlocks) public {
        if (depositAmount == 0 || depositAmount > 10000) return;
        if (harvestAmount > depositAmount) return;

        if (harvestAmount == 0) return;
        if (nextBlocks > 1000) return;

        prepareDeposit(depositAmount);
        loadRewards(TOTAL_REWARDS);
        
        advanceBlocks(nextBlocks);

        LiquidityMine.UserInfo memory userInfo = lm.userInfo(USER1);
        uint256 accRewardsPerLockToken = lm.accRewardsPerLockToken();
        uint256 initialUnclaimedRewards = userInfo.unclaimedRewards;
        uint256 lockedTokens = userInfo.lockedTokens;
        uint256 rewardDebt = userInfo.rewardDebt;

        uint256 newlyAccruedRewards = accRewardsPerLockToken.mulWadDown(lockedTokens);
        uint256 pendingRewards = newlyAccruedRewards + initialUnclaimedRewards - rewardDebt;

        uint256 actualHarvestAmount = (harvestAmount > pendingRewards) ? pendingRewards : harvestAmount;

        hevm.prank(USER1);
        lm.harvest(actualHarvestAmount, USER1);

        uint256 currentUnclaimedRewards = lm.userInfo(USER1).unclaimedRewards;
        uint256 expectedUnclaimedRewards = initialUnclaimedRewards - actualHarvestAmount;

        assert(currentUnclaimedRewards == expectedUnclaimedRewards);
    }

    function test_reward_debt_after_harvest(uint256 depositAmount, uint256 harvestAmount, uint256 nextBlocks) public {
        if (depositAmount == 0 || depositAmount > 10000) return;
        if (harvestAmount > depositAmount) return;

        if (harvestAmount == 0) return;
        if (nextBlocks > 1000) return;

        prepareDeposit(depositAmount);
        loadRewards(TOTAL_REWARDS);
        
        advanceBlocks(nextBlocks);

        LiquidityMine.UserInfo memory userInfo = lm.userInfo(USER1);
        uint256 accRewardsPerLockToken = lm.accRewardsPerLockToken();
        uint256 lockedTokens = userInfo.lockedTokens;

        uint256 expectedRewardDebt = lockedTokens.mulWadDown(accRewardsPerLockToken);

        uint256 actualHarvestAmount = (harvestAmount > lm.pendingRewards(USER1)) ? lm.pendingRewards(USER1) : harvestAmount;

        hevm.prank(USER1);
        lm.harvest(actualHarvestAmount, USER1);

        uint256 finalRewardDebt = lm.userInfo(USER1).rewardDebt;

        assert(finalRewardDebt == expectedRewardDebt);
    }

    // ============================================
    // ==           _COMPUTE ACC REWARDS         ==
    // ============================================

    function test_single_deposit_accrual(uint256 depositAmount, uint256 blocks) public {
        if (depositAmount == 0 || blocks == 0) return;
        if (depositAmount > 10000 || blocks > 10000) return;

        prepareDeposit(depositAmount);
        loadRewards(TOTAL_REWARDS);

        // Ensure initial state
        if(lm.accRewardsPerLockToken() != 0) return;
        if(lm.accRewardsTotal() != 0) return;

        // Advance blocks to accrue rewards
        advanceBlocks(blocks);

        lm.updateAccounting();

        uint256 accRewardsPerLockToken = lm.accRewardsPerLockToken();
        uint256 accRewardsTotal = lm.accRewardsTotal();
        uint256 lockTokenSupply = lockToken.balanceOf(address(lm));

        // Calculate expected values
        uint256 expectedNewRewards = REWARD_PER_EPOCH * blocks;
        uint256 expectedAccRewardsPerLockToken = expectedNewRewards.divWadDown(depositAmount);
        uint256 expectedAccRewardsTotal = expectedNewRewards;

        Debugger.log("accRewardsPerLockToken", accRewardsPerLockToken);
        Debugger.log("expectedAccRewardsPerLockToken", expectedAccRewardsPerLockToken);
        assert(accRewardsPerLockToken == expectedAccRewardsPerLockToken);

        Debugger.log("accRewardsTotal", accRewardsTotal);
        Debugger.log("expectedAccRewardsTotal", expectedAccRewardsTotal);
        assert(accRewardsTotal == expectedAccRewardsTotal);
        assert(lockTokenSupply == depositAmount);
    }

    function test_multiple_deposits_accrual(uint256 depositAmount1, uint256 depositAmount2, uint256 blocks) public {
    if (depositAmount1 == 0 || depositAmount2 == 0 || blocks == 0) return;
    if (depositAmount1 > 10 || depositAmount2 > 10 || blocks > 10) return;

    // First deposit
    prepareDeposit(depositAmount1);
    loadRewards(TOTAL_REWARDS);

    // Ensure initial state
    if(lm.accRewardsPerLockToken() != 0) return;
    if(lm.accRewardsTotal() != 0) return;

    // Advance blocks and accrue rewards for the first deposit
    advanceBlocks(blocks);
    lm.updateAccounting();

    // Capture accrued rewards per lock token after the first deposit
    uint256 firstAccRewardsPerLockToken = lm.accRewardsPerLockToken();
    uint256 firstAccRewardsTotal = lm.accRewardsTotal();

    // Second deposit
    prepareTokens(depositAmount2);
    hevm.prank(USER1);
    lm.deposit(depositAmount2, USER1);

    // Advance blocks and accrue rewards after the second deposit
    advanceBlocks(blocks);
    lm.updateAccounting();

    uint256 secondAccRewardsPerLockToken = lm.accRewardsPerLockToken();
    uint256 secondAccRewardsTotal = lm.accRewardsTotal();
    uint256 lockTokenSupply = lockToken.balanceOf(address(lm));
    Debugger.log("lockTokenSupply", lockTokenSupply);

    // Calculate expected values
    uint256 totalDepositAmount = depositAmount1 + depositAmount2;

    // Accumulated rewards for the first deposit period
    uint256 expectedFirstNewRewards = REWARD_PER_EPOCH * blocks;
    uint256 expectedFirstAccRewardsPerLockToken = expectedFirstNewRewards.divWadDown(depositAmount1);

    // Accumulated rewards for the second deposit period
    uint256 expectedSecondNewRewards = REWARD_PER_EPOCH * blocks;
    uint256 expectedSecondAccRewardsPerLockToken = expectedSecondNewRewards.divWadDown(totalDepositAmount);

    // Combined expected values
    uint256 expectedTotalAccRewardsPerLockToken = firstAccRewardsPerLockToken + expectedSecondAccRewardsPerLockToken;
    uint256 expectedTotalAccRewardsTotal = firstAccRewardsTotal + expectedSecondNewRewards;

    Debugger.log("accRewardsPerLockToken", secondAccRewardsPerLockToken);
    Debugger.log("expectedAccRewardsPerLockToken", expectedTotalAccRewardsPerLockToken);
    Debugger.log("difference", secondAccRewardsPerLockToken - expectedTotalAccRewardsPerLockToken);
    assert(secondAccRewardsPerLockToken == expectedTotalAccRewardsPerLockToken);

    Debugger.log("accRewardsTotal", secondAccRewardsTotal);
    Debugger.log("expectedAccRewardsTotal", expectedTotalAccRewardsTotal);
    assert(secondAccRewardsTotal == expectedTotalAccRewardsTotal);
    assert(lockTokenSupply == totalDepositAmount);
}






}
