// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {Test, console} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {LiquidityMine} from "src/LiquidityMine.sol";
import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";
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

    function setUp() public {
        rewardPerEpoch = 1e18;
        totalRewards = 75_000_000e18;
        rewardToken = IERC20(address(new MockERC20("GLIF", "GLF", 18)));
        lockToken = IERC20(address(new MockERC20("iFIL", "iFIL", 18)));

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

function testFuzz_InvariantDepositWithdraw(uint256 depositAmount, uint256 withdrawAmount, address beneficiary) public {
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

    // Perform the withdraw
    vm.prank(beneficiary);
    lm.withdraw(withdrawAmount, beneficiary);

    // Check invariants
    invariant_TotalLockedTokensMustBeCorrect();
    invariant_RewardDebtConsistency();
    invariant_UnclaimedRewardsConsistency();
    invariant_TotalRewardTokensClaimed();
    invariant_RewardTokenBalanceConsistency();
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
}










}
