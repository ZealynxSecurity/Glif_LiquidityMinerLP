// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {Test, console} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {LiquidityMine} from "src/LiquidityMine.sol";
import {Token} from "src/Token.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface MintBurnERC20 is IERC20 {
    function mint(address to, uint256 value) external;
    function burn(address from, uint256 value) external;
}

contract ZealynxLiquidityMineInvariants is StdInvariant, Test {
    using FixedPointMathLib for uint256;

    LiquidityMine public lm;
    IERC20 public rewardToken;
    IERC20 public lockToken;
    uint256 public rewardPerEpoch;
    uint256 public totalRewards;
    uint256 public deployBlock;

    address investor = makeAddr("investor");
    address sysAdmin = makeAddr("sysAdmin");


    // constants
    uint256 constant DUST = 1e11;
    uint256 constant MAX_UINT256 = type(uint256).max;
    uint256 constant MAX_FIL = 2_000_000_000e18;
    uint256 constant EPOCHS_IN_DAY = 2880;
    uint256 constant EPOCHS_IN_YEAR = EPOCHS_IN_DAY * 365;

    function setUp() public {
        rewardPerEpoch = 1e18;
        totalRewards = 75_000_000e18;
        rewardToken = IERC20(address(new Token("GLIF", "GLF", sysAdmin, address(this), address(this))));
        lockToken = IERC20(address(new Token("iFIL", "iFIL", sysAdmin, address(this), address(this))));

        deployBlock = block.number;
        lm = new LiquidityMine(rewardToken, lockToken, rewardPerEpoch, sysAdmin);

        // Mint initial rewards to sysAdmin
        MintBurnERC20(address(rewardToken)).mint(sysAdmin, totalRewards);

        // Target the contract for invariant testing
        targetContract(address(lm));
    }

    function invariant_TotalLockedTokensMustBeCorrect() public {
        uint256 totalLockedTokens = lockToken.balanceOf(address(lm));
        uint256 expectedTotalLockedTokens = 0;

        for (uint256 i = 0; i < users.length; i++) {
            LiquidityMine.UserInfo memory user = lm.userInfo(users[i]);
            expectedTotalLockedTokens += user.lockedTokens;
        }

        assertEq(totalLockedTokens, expectedTotalLockedTokens, "Total locked tokens in contract should be correct");
    }

    function invariant_RewardDebtConsistency() public {
        for (uint256 i = 0; i < users.length; i++) {
            LiquidityMine.UserInfo memory user = lm.userInfo(users[i]);
            uint256 expectedRewardDebt = user.lockedTokens.mulWadDown(lm.accRewardsPerLockToken());
            assertEq(user.rewardDebt, expectedRewardDebt, "Reward debt should be consistent with locked tokens and accRewardsPerLockToken");
        }
    }

    function invariant_UnclaimedRewardsConsistency() public {
        for (uint256 i = 0; i < users.length; i++) {
            LiquidityMine.UserInfo memory user = lm.userInfo(users[i]);
            uint256 expectedPending = user.lockedTokens.mulWadDown(lm.accRewardsPerLockToken()) + user.unclaimedRewards - user.rewardDebt;
            uint256 pending = lm.pendingRewards(users[i]);
            assertEq(pending, expectedPending, "Pending rewards should be consistent with locked tokens, accRewardsPerLockToken, and reward debt");
        }
    }

    function invariant_TotalRewardTokensClaimed() public {
        uint256 totalClaimedRewards = 0;

        for (uint256 i = 0; i < users.length; i++) {
            LiquidityMine.UserInfo memory user = lm.userInfo(users[i]);
            totalClaimedRewards += user.unclaimedRewards;
        }

        // Verificar que las recompensas reclamadas se mantengan consistentes
        assertEq(totalClaimedRewards, lm.rewardTokensClaimed(), "Total claimed rewards should be correct");
    }

    function invariant_RewardTokenBalanceConsistency() public {
        uint256 totalRewardTokenBalance = rewardToken.balanceOf(address(lm));
        uint256 totalRewardsAccrued = (block.number - lm.lastRewardBlock()) * lm.rewardPerEpoch();
        uint256 expectedRewardTokenBalance = lm.totalRewardCap() - lm.rewardTokensClaimed() - totalRewardsAccrued;

        assertEq(totalRewardTokenBalance, expectedRewardTokenBalance, "Reward token balance should be correct");
    }

    function invariant_TotalRewardConsistency() public {
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

    function invariant_MaxRewardCapConsistency() public {
        uint256 totalRewardsAccrued = lm.accRewardsTotal();
        uint256 maxRewardCap = lm.totalRewardCap();

        assertLe(
            totalRewardsAccrued,
            maxRewardCap,
            "Total rewards accrued should not exceed the maximum reward cap"
        );
    }

    function invariant_AccRewardsTotalShouldNotExceedTotalRewardCap() public {
        uint256 accRewardsTotal = lm.accRewardsTotal();
        uint256 totalRewardCap = lm.totalRewardCap();
        assertLe(accRewardsTotal, totalRewardCap, "Accrued rewards total should not exceed the total reward cap");
    }

    function invariant_RewardTokensClaimedShouldNotExceedAccRewardsTotal() public {
        uint256 rewardTokensClaimed = lm.rewardTokensClaimed();
        uint256 accRewardsTotal = lm.accRewardsTotal();
        assertLe(rewardTokensClaimed, accRewardsTotal, "Claimed rewards should not exceed the accrued rewards total");
    }

    function invariant_GLFTokenBalanceAndRewardTokensClaimedShouldEqualTotalRewardCap() public {
        uint256 glfTokenBalance = rewardToken.balanceOf(address(lm));
        uint256 rewardTokensClaimed = lm.rewardTokensClaimed();
        uint256 totalRewardCap = lm.totalRewardCap();
        assertEq(glfTokenBalance + rewardTokensClaimed, totalRewardCap, "GLF token balance plus claimed rewards should equal total reward cap");
    }

function invariant_NoResidualDust() public {
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

    function testFuzz_InvariantDepositWithdraw(uint256 depositAmount, uint256 withdrawAmount, address beneficiary) public { // @audit-issue
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

        uint256 totalRewardsAccrued = lm.accRewardsTotal();
        uint256 totalRewardsClaimed = lm.rewardTokensClaimed();
        uint256 totalRewardsUnclaimed = 0;

        for (uint256 i = 0; i < users.length; i++) {
            LiquidityMine.UserInfo memory user = lm.userInfo(users[i]);
            totalRewardsUnclaimed += user.unclaimedRewards;
        }

        // assertEq(
        //     totalRewardsAccrued,
        //     totalRewardsClaimed + totalRewardsUnclaimed,
        //     "Total rewards accrued should equal the sum of claimed and unclaimed rewards"
        // );

        // Run other invariants
        invariant_TotalLockedTokensMustBeCorrect();
        invariant_RewardDebtConsistency();
        invariant_UnclaimedRewardsConsistency();
        invariant_MaxRewardCapConsistency();
        invariant_AccRewardsTotalShouldNotExceedTotalRewardCap();
        invariant_RewardTokensClaimedShouldNotExceedAccRewardsTotal();
        invariant_GLFTokenBalanceAndRewardTokensClaimedShouldEqualTotalRewardCap();
        invariant_RewardTokenBalanceConsistency();//@audit
        invariant_TotalRewardConsistency();//@audit
    }


    function testFuzz_InvariantDepositHighValuesWithdraw(uint256 depositAmount, uint256 withdrawAmount, address beneficiary) public { // @audit-issue
        // Limit the fuzzing range for extremely high values
        depositAmount = bound(depositAmount, 1e35, 1e40); // Limit deposit amount between 1e35 and 1e40
        withdrawAmount = bound(withdrawAmount, 1e35, depositAmount); // Limit withdraw amount between 1e35 and depositAmount
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
        console.log("Pending rewards before withdrawal:", pendingRewardsBeforeWithdraw);

        // Verify user state before withdraw
        LiquidityMine.UserInfo memory userBeforeWithdraw = lm.userInfo(beneficiary);
        console.log("User before withdraw - lockedTokens:", userBeforeWithdraw.lockedTokens);
        console.log("User before withdraw - rewardDebt:", userBeforeWithdraw.rewardDebt);
        console.log("User before withdraw - unclaimedRewards:", userBeforeWithdraw.unclaimedRewards);

        // Perform the withdraw
        vm.prank(beneficiary);
        lm.withdraw(withdrawAmount, beneficiary);

        // Ensure the rewards are still correct after withdrawal
        uint256 pendingRewardsAfterWithdraw = lm.pendingRewards(beneficiary);
        console.log("Pending rewards after withdrawal:", pendingRewardsAfterWithdraw);

        // Verify user state after withdraw
        LiquidityMine.UserInfo memory userAfterWithdraw = lm.userInfo(beneficiary);
        console.log("User after withdraw - lockedTokens:", userAfterWithdraw.lockedTokens);
        console.log("User after withdraw - rewardDebt:", userAfterWithdraw.rewardDebt);
        console.log("User after withdraw - unclaimedRewards:", userAfterWithdraw.unclaimedRewards);

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

        // Verify accRewardsTotal and rewardTokensClaimed
        uint256 accRewardsTotal = lm.accRewardsTotal();
        console.log("accRewardsTotal:", accRewardsTotal);
        console.log("rewardTokensClaimed:", totalClaimedRewardsFromContract);
        assertEq(
            accRewardsTotal,
            totalClaimedRewardsFromContract + beneficiaryInfo.unclaimedRewards,
            "Total rewards accrued should equal the sum of claimed and unclaimed rewards"
        );

        // Run other invariants
        invariant_TotalLockedTokensMustBeCorrect();
        invariant_RewardDebtConsistency();
        invariant_UnclaimedRewardsConsistency();
        invariant_MaxRewardCapConsistency();
        invariant_AccRewardsTotalShouldNotExceedTotalRewardCap();
        invariant_RewardTokensClaimedShouldNotExceedAccRewardsTotal();
        invariant_GLFTokenBalanceAndRewardTokensClaimedShouldEqualTotalRewardCap();
        invariant_RewardTokenBalanceConsistency();//@audit
        invariant_TotalRewardConsistency();//@audit

    }


    function testFuzz_RewardAccumulationAndDistribution(uint256 depositAmount, uint256 withdrawAmount, address beneficiary) public {
        // Limit the fuzzing range for more reasonable values
        depositAmount = bound(depositAmount, 1, 1e24); // Limit deposit amount between 1 y 1e24
        withdrawAmount = bound(withdrawAmount, 1, depositAmount); // Limit withdraw amount between 1 y depositAmount
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
        invariant_TotalLockedTokensMustBeCorrect();
        invariant_RewardDebtConsistency();
        invariant_UnclaimedRewardsConsistency();
        invariant_TotalRewardTokensClaimed();
        invariant_RewardTokenBalanceConsistency();
        invariant_TotalRewardConsistency();
        invariant_MaxRewardCapConsistency();
        invariant_AccRewardsTotalShouldNotExceedTotalRewardCap();
        invariant_RewardTokensClaimedShouldNotExceedAccRewardsTotal();
        invariant_GLFTokenBalanceAndRewardTokensClaimedShouldEqualTotalRewardCap();
    }

    function testFuzz_LoadRewards(uint256 amount, address user) public {
        amount = bound(amount, 1, 1e24); // Limit amount between 1 and 1e24
        vm.assume(user != address(0) && user != address(lm)); // Assume user is not the zero address or the contract address

        // Mint reward tokens to the user so they can be loaded
        MintBurnERC20(address(rewardToken)).mint(user, amount);
        vm.prank(user);
        rewardToken.approve(address(lm), amount);

        // Perform the loadRewards
        vm.prank(user);
        lm.loadRewards(amount);

        // Check invariants
        invariant_TotalLockedTokensMustBeCorrect();
        invariant_RewardDebtConsistency();
        invariant_UnclaimedRewardsConsistency();
        invariant_TotalRewardTokensClaimed();
        invariant_RewardTokenBalanceConsistency();
        invariant_TotalRewardConsistency();
        invariant_MaxRewardCapConsistency();
        invariant_AccRewardsTotalShouldNotExceedTotalRewardCap();
        invariant_RewardTokensClaimedShouldNotExceedAccRewardsTotal();
        invariant_GLFTokenBalanceAndRewardTokensClaimedShouldEqualTotalRewardCap();
    }

    function testFuzz_Harvest(uint256 depositAmount, uint256 harvestAmount, address beneficiary) public {
        depositAmount = bound(depositAmount, 1, 1e24); // Limit deposit amount between 1 and 1e24
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
        invariant_TotalLockedTokensMustBeCorrect();
        invariant_RewardDebtConsistency();
        invariant_UnclaimedRewardsConsistency();
        invariant_TotalRewardTokensClaimed();
        invariant_RewardTokenBalanceConsistency();
        invariant_TotalRewardConsistency();
        invariant_MaxRewardCapConsistency();
        invariant_AccRewardsTotalShouldNotExceedTotalRewardCap();
        invariant_RewardTokensClaimedShouldNotExceedAccRewardsTotal();
        invariant_GLFTokenBalanceAndRewardTokensClaimedShouldEqualTotalRewardCap();
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

    function concatStrings(string memory a, string memory b) internal pure returns (string memory) {
        return string(abi.encodePacked(a, b));
    }



//////////////////////////////////////
// https://github.com/glifio/token/issues/1

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
    console.log("Pending rewards before withdrawal:", pendingRewardsBeforeWithdraw);

    // Verify user state before withdraw
    LiquidityMine.UserInfo memory userBeforeWithdraw = lm.userInfo(beneficiary);
    console.log("User before withdraw - lockedTokens:", userBeforeWithdraw.lockedTokens);
    console.log("User before withdraw - rewardDebt:", userBeforeWithdraw.rewardDebt);
    console.log("User before withdraw - unclaimedRewards:", userBeforeWithdraw.unclaimedRewards);

    // Perform the withdraw
    vm.prank(beneficiary);
    lm.withdraw(withdrawAmount, beneficiary);

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

    // Verify accRewardsTotal and rewardTokensClaimed
    uint256 accRewardsTotal = lm.accRewardsTotal();
    console.log("accRewardsTotal:", accRewardsTotal);
    console.log("rewardTokensClaimed:", totalClaimedRewardsFromContract);

    // Validate the invariant
    uint256 totalRewardsAccrued = lm.accRewardsTotal();
    uint256 totalRewardsClaimed = lm.rewardTokensClaimed();
    uint256 totalRewardsUnclaimed = 0;

    for (uint256 i = 0; i < users.length; i++) {
        LiquidityMine.UserInfo memory user = lm.userInfo(users[i]);
        totalRewardsUnclaimed += user.unclaimedRewards;
    }

    console.log("Total rewards accrued:", totalRewardsAccrued);
    console.log("Total rewards claimed:", totalRewardsClaimed);
    console.log("Total rewards unclaimed:", totalRewardsUnclaimed);

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
    console.log("Pending rewards before withdrawal:", pendingRewardsBeforeWithdraw);

    // Verify user state before withdraw
    LiquidityMine.UserInfo memory userBeforeWithdraw = lm.userInfo(beneficiary);
    console.log("User before withdraw - lockedTokens:", userBeforeWithdraw.lockedTokens);
    console.log("User before withdraw - rewardDebt:", userBeforeWithdraw.rewardDebt);
    console.log("User before withdraw - unclaimedRewards:", userBeforeWithdraw.unclaimedRewards);

    // Perform the withdraw
    vm.prank(beneficiary);
    lm.withdraw(withdrawAmount, beneficiary);

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

    // Verify accRewardsTotal and rewardTokensClaimed
    uint256 accRewardsTotal = lm.accRewardsTotal();
    console.log("accRewardsTotal:", accRewardsTotal);
    console.log("rewardTokensClaimed:", totalClaimedRewardsFromContract);

    // Verificación del invariant original
    uint256 totalRewardsAccrued = lm.accRewardsTotal();
    uint256 totalRewardsClaimed = lm.rewardTokensClaimed();
    uint256 totalRewardsUnclaimed = 0;

    for (uint256 i = 0; i < users.length; i++) {
        LiquidityMine.UserInfo memory user = lm.userInfo(users[i]);
        totalRewardsUnclaimed += user.unclaimedRewards;
    }

    console.log("Total rewards accrued:", totalRewardsAccrued);
    console.log("Total rewards claimed:", totalRewardsClaimed);
    console.log("Total rewards unclaimed:", totalRewardsUnclaimed);


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

//////////////////////////////////////


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


//////////////////////////////////////
// https://github.com/glifio/token/pull/5
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

//////////////////////////////////////


////////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////


    function testNoRewardsAccrue() public {
        // make this number a tiny bit bigger than 1e18
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
}