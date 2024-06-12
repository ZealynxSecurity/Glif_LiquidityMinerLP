// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {Test, console} from "forge-std/Test.sol";
import {LiquidityMine} from "src/LiquidityMine.sol";
import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {StdInvariant} from "forge-std/StdInvariant.sol";

import "lib/solidity_utils/lib.sol";

interface MintBurnERC20 is IERC20 {
    function mint(address to, uint256 value) external;
    function burn(address from, uint256 value) external;
}

    // constants
    uint256 constant DUST = 1e11;
    uint256 constant MAX_UINT256 = type(uint256).max;
    uint256 constant MAX_FIL = 2_000_000_000e18;
    uint256 constant EPOCHS_IN_DAY = 2880;
    uint256 constant EPOCHS_IN_YEAR = EPOCHS_IN_DAY * 365;

contract ZealynxItyfuzz is Test {
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
        targetContract(address(lm));


    }

    // address[] users;


    // function invariant_TotalLockedTokensMustBeCorrect() public {
    //     uint256 totalLockedTokens = lockToken.balanceOf(address(lm));
    //     uint256 expectedTotalLockedTokens = 0;

    //     for (uint256 i = 0; i < users.length; i++) {
    //         LiquidityMine.UserInfo memory user = lm.userInfo(users[i]);
    //         expectedTotalLockedTokens += user.lockedTokens;
    //     }

    //     assertEq(totalLockedTokens, expectedTotalLockedTokens, "Total locked tokens in contract should be correct");
    // }

    // function invariant_RewardDebtConsistency() public {
    //     for (uint256 i = 0; i < users.length; i++) {
    //         LiquidityMine.UserInfo memory user = lm.userInfo(users[i]);
    //         uint256 expectedRewardDebt = user.lockedTokens.mulWadDown(lm.accRewardsPerLockToken());
    //         assertEq(user.rewardDebt, expectedRewardDebt, "Reward debt should be consistent with locked tokens and accRewardsPerLockToken");
    //     }
    // }

    // function invariant_UnclaimedRewardsConsistency() public {
    //     for (uint256 i = 0; i < users.length; i++) {
    //         LiquidityMine.UserInfo memory user = lm.userInfo(users[i]);
    //         uint256 expectedPending = user.lockedTokens.mulWadDown(lm.accRewardsPerLockToken()) + user.unclaimedRewards - user.rewardDebt;
    //         uint256 pending = lm.pendingRewards(users[i]);
    //         assertEq(pending, expectedPending, "Pending rewards should be consistent with locked tokens, accRewardsPerLockToken, and reward debt");
    //     }
    // }

    // function invariant_TotalRewardTokensClaimed() public {
    //     uint256 totalClaimedRewards = 0;

    //     for (uint256 i = 0; i < users.length; i++) {
    //         LiquidityMine.UserInfo memory user = lm.userInfo(users[i]);
    //         totalClaimedRewards += user.unclaimedRewards;
    //     }

    //     // Verificar que las recompensas reclamadas se mantengan consistentes
    //     assertEq(totalClaimedRewards, lm.rewardTokensClaimed(), "Total claimed rewards should be correct");
    // }

    // function invariant_RewardTokenBalanceConsistency() public {
    //     uint256 totalRewardTokenBalance = rewardToken.balanceOf(address(lm));
    //     uint256 totalRewardsAccrued = (block.number - lm.lastRewardBlock()) * lm.rewardPerEpoch();
    //     uint256 expectedRewardTokenBalance = lm.totalRewardCap() - lm.rewardTokensClaimed() - totalRewardsAccrued;

    //     assertEq(totalRewardTokenBalance, expectedRewardTokenBalance, "Reward token balance should be correct");
    // }

    // function invariant_TotalRewardConsistency() public {
    //     uint256 totalRewardsAccrued = lm.accRewardsTotal();
    //     uint256 totalRewardsClaimed = lm.rewardTokensClaimed();
    //     uint256 totalRewardsUnclaimed = 0;

    //     for (uint256 i = 0; i < users.length; i++) {
    //         LiquidityMine.UserInfo memory user = lm.userInfo(users[i]);
    //         totalRewardsUnclaimed += user.unclaimedRewards;
    //     }

    //     assertEq(
    //         totalRewardsAccrued,
    //         totalRewardsClaimed + totalRewardsUnclaimed,
    //         "Total rewards accrued should equal the sum of claimed and unclaimed rewards"
    //     );
    // }

    // function invariant_MaxRewardCapConsistency() public {
    //     uint256 totalRewardsAccrued = lm.accRewardsTotal();
    //     uint256 maxRewardCap = lm.totalRewardCap();

    //     assertLe(
    //         totalRewardsAccrued,
    //         maxRewardCap,
    //         "Total rewards accrued should not exceed the maximum reward cap"
    //     );
    // }

    // function invariant_AccRewardsTotalShouldNotExceedTotalRewardCap() public {
    //     uint256 accRewardsTotal = lm.accRewardsTotal();
    //     uint256 totalRewardCap = lm.totalRewardCap();
    //     assertLe(accRewardsTotal, totalRewardCap, "Accrued rewards total should not exceed the total reward cap");
    // }

    // function invariant_RewardTokensClaimedShouldNotExceedAccRewardsTotal() public {
    //     uint256 rewardTokensClaimed = lm.rewardTokensClaimed();
    //     uint256 accRewardsTotal = lm.accRewardsTotal();
    //     assertLe(rewardTokensClaimed, accRewardsTotal, "Claimed rewards should not exceed the accrued rewards total");
    // }

    // function invariant_GLFTokenBalanceAndRewardTokensClaimedShouldEqualTotalRewardCap() public {
    //     uint256 glfTokenBalance = rewardToken.balanceOf(address(lm));
    //     uint256 rewardTokensClaimed = lm.rewardTokensClaimed();
    //     uint256 totalRewardCap = lm.totalRewardCap();
    //     assertEq(glfTokenBalance + rewardTokensClaimed, totalRewardCap, "GLF token balance plus claimed rewards should equal total reward cap");
    // }

    // function invariant_NoResidualDust() public {
    //     uint256 accRewardsTotal = lm.accRewardsTotal();
    //     uint256 remainingBalance = rewardToken.balanceOf(address(lm));
    //     uint256 totalRewardCap = lm.totalRewardCap();


    //     uint256 calculatedSum = accRewardsTotal + remainingBalance;


    //     assertEq(
    //         totalRewardCap,
    //         calculatedSum,
    //         "Total Reward Cap should equal the sum of Accrued Rewards Total and Remaining Balance"
    //     );
    // }

    // function testFuzz_Deposit(uint256 amount, address beneficiary) public { //@audit => no assume
    //     // Limit the fuzzing range for more reasonable values
    //     amount = bound(amount, 1, 1e24); // Limit amount between 1 and 1e24
    //     vm.assume(beneficiary != address(0) && beneficiary != address(lm)); // Assume beneficiary is not the zero address or the contract address

    //     // Mint tokens to the beneficiary so they can be deposited
    //     MintBurnERC20(address(lockToken)).mint(beneficiary, amount);
    //     vm.prank(beneficiary);
    //     lockToken.approve(address(lm), amount);

    //     uint256 initialContractBalance = lockToken.balanceOf(address(lm));
    //     uint256 initialBeneficiaryBalance = lockToken.balanceOf(beneficiary);



    //     vm.prank(beneficiary);
    //     lm.deposit(amount, beneficiary);

    //     uint256 finalContractBalance = lockToken.balanceOf(address(lm));
    //     assert(finalContractBalance == initialContractBalance + amount);

    //     uint256 finalBeneficiaryBalance = lockToken.balanceOf(beneficiary);
    //     assert(finalBeneficiaryBalance == initialBeneficiaryBalance - amount);
    // }

//     function testDeposit(uint256 amount) public {
//     // Limit the fuzzing range for more reasonable values
//     amount = bound(amount, 1, 1e24); // Limit amount between 1 and 1e24

//     // Specify a beneficiary address
//     address beneficiary = makeAddr("beneficiary");

//     // Mint tokens to the beneficiary so they can be deposited
//     MintBurnERC20(address(lockToken)).mint(beneficiary, amount);
//     vm.prank(beneficiary);
//     lockToken.approve(address(lm), amount);

//     uint256 initialContractBalance = lockToken.balanceOf(address(lm));
//     uint256 initialBeneficiaryBalance = lockToken.balanceOf(beneficiary);

//     // Perform the deposit
//     vm.prank(beneficiary);
//     lm.deposit(amount, beneficiary);

//     // Verify that the tokens were transferred to the contract
//     uint256 finalContractBalance = lockToken.balanceOf(address(lm));
//     assert(finalContractBalance == initialContractBalance + amount);

//     // Verify the beneficiary's balance decreased correctly
//     uint256 finalBeneficiaryBalance = lockToken.balanceOf(beneficiary);
//     assert(finalBeneficiaryBalance == initialBeneficiaryBalance - amount);
// }

}