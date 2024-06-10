// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {Test, console} from "forge-std/Test.sol";
import {LiquidityMine} from "src/LiquidityMine.sol";
import {Token} from "src/Token.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SymTest} from "halmos-cheatcodes/SymTest.sol";

interface MintBurnERC20 is IERC20 {
    function mint(address to, uint256 value) external;
    function burn(address from, uint256 value) external;
}

contract ZealynxLiquidityMineFV is SymTest, Test {
    using FixedPointMathLib for uint256;

    LiquidityMine public lm;
    MintBurnERC20 public rewardToken;
    MintBurnERC20 public lockToken;
    uint256 public rewardPerEpoch;
    uint256 public totalRewards;
    uint256 public deployBlock;

    address public investor;
    address public sysAdmin;

    // constants
    uint256 constant DUST = 1e11;
    uint256 constant MAX_UINT256 = type(uint256).max;
    uint256 constant MAX_FIL = 2_000_000_000e18;
    uint256 constant EPOCHS_IN_DAY = 2880;
    uint256 constant EPOCHS_IN_YEAR = EPOCHS_IN_DAY * 365;

    event Deposit(
        address indexed caller, address indexed beneficiary, uint256 lockTokenAmount, uint256 rewardsUnclaimed
    );
    event LogUpdateAccounting(
        uint64 lastRewardBlock, uint256 lockTokenSupply, uint256 accRewardsPerLockToken, uint256 accRewardsTotal
    );

    function setUp() public {
        sysAdmin = svm.createAddress("sysAdmin");
        investor = svm.createAddress("investor");
        rewardPerEpoch = svm.createUint256("rewardPerEpoch");
        totalRewards = svm.createUint256("totalRewards");
        rewardToken = MintBurnERC20(address(new Token("GLIF", "GLF", sysAdmin, address(this), address(this))));
        lockToken = MintBurnERC20(address(new Token("iFIL", "iFIL", sysAdmin, address(this), address(this))));

        deployBlock = block.number;
        lm = new LiquidityMine(rewardToken, lockToken, rewardPerEpoch, sysAdmin);

        // Mint initial rewards to sysAdmin
        rewardToken.mint(sysAdmin, totalRewards);
    }

    function check_testFuzz_Deposit_CheckBalances(uint256 amount, address beneficiary) public {
        // Assumptions
        vm.assume(amount > 0 && amount <= lockToken.totalSupply());
        vm.assume(beneficiary != address(0) && beneficiary != address(lm));

        // Mint tokens to the beneficiary so they can be deposited
        lockToken.mint(beneficiary, amount);
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
    }


    function check_testFuzz_Deposit_CheckUserInfo(uint256 amount, address beneficiary) public {
        // Create symbolic values
        // amount = svm.createUint256("amount");
        // beneficiary = svm.createAddress("beneficiary");

        // Assumptions
        vm.assume(amount > 0 && amount <= lockToken.totalSupply());
        vm.assume(beneficiary != address(0) && beneficiary != address(lm));

        // Mint tokens to the beneficiary so they can be deposited
        lockToken.mint(beneficiary, amount);
        vm.prank(beneficiary);
        lockToken.approve(address(lm), amount);

        // Perform the deposit
        vm.prank(beneficiary);
        lm.deposit(amount, beneficiary);

        // Verify the user's information
        LiquidityMine.UserInfo memory user = lm.userInfo(beneficiary);
        assertEq(user.lockedTokens, amount, "Locked tokens should equal the deposited amount");
        assertEq(user.rewardDebt, lm.accRewardsPerLockToken().mulWadDown(amount), "Reward debt should be correct");
        assertEq(user.unclaimedRewards, 0, "Unclaimed rewards should be 0 after deposit");
    }

    function check_hola () public {
        console.log("hola");
    }
}
