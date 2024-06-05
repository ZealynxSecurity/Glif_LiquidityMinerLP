// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {Test, console} from "forge-std/Test.sol";
import {LiquidityMine} from "src/LiquidityMine.sol";
import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface MintBurnERC20 is IERC20 {
    function mint(address to, uint256 value) external;
    function burn(address from, uint256 value) external;
}

// constants
uint256 constant DUST = 1e12;
uint256 constant MAX_UINT256 = type(uint256).max;
uint256 constant MAX_FIL = 2_000_000_000e18;
uint256 constant EPOCHS_IN_DAY = 2880;
uint256 constant EPOCHS_IN_YEAR = EPOCHS_IN_DAY * 365;

contract ZealynxLiquidityMineTest is Test {
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

        // Verify initial balances
        assertEq(rewardToken.balanceOf(sysAdmin), totalRewards, "SysAdmin should have initial total rewards balance");
    }

    function test_Initialization() public view {
        // Verify contract variables
        assertEq(lm.accRewardsPerLockToken(), 0, "accRewardsPerLockToken should be 0");
        assertEq(lm.lastRewardBlock(), deployBlock, "lastRewardBlock should be the deploy block");
        assertEq(lm.rewardPerEpoch(), rewardPerEpoch, "rewardPerEpoch should be 1e18");
        assertEq(address(lm.rewardToken()), address(rewardToken), "rewardToken should be the MockERC20 address");
        assertEq(address(lm.lockToken()), address(lockToken), "lockToken should be the MockERC20 address");

        // Verify additional variables
        assertEq(lm.rewardTokensClaimed(), 0, "rewardTokensClaimed should be 0");
        assertEq(lm.totalRewardCap(), 0, "totalRewardCap should be 0");
    }

    function testFuzz_Deposit(uint256 amount, address beneficiary) public {
        // Limit the fuzzing range for more reasonable values
        amount = bound(amount, 1, 1e24); // Limit amount between 1 and 1e24
        vm.assume(beneficiary != address(0) && beneficiary != address(lm)); // Assume beneficiary is not the zero address or the contract address

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

        // Verify total reward cap is unchanged (since this is only a deposit)
        assertEq(lm.totalRewardCap(), 0, "totalRewardCap should be unchanged after deposit");
    }



    function testFuzz_Withdraw(uint256 depositAmount, uint256 withdrawAmount, address beneficiary) public {
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

        // Verify total reward cap is unchanged (since this is only a withdrawal)
        assertEq(lm.totalRewardCap(), 0, "totalRewardCap should be unchanged after withdrawal");

        // Verify events (if applicable and supported by your testing framework)
        // For simplicity, we log and manually verify the output
        console.log("Withdraw event should be emitted with correct values.");
    }

}
