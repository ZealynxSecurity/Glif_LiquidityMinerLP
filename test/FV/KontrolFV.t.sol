// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {Test, console2} from "forge-std/Test.sol";
import {LiquidityMine} from "src/LiquidityMine.sol";
import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Token} from "src/Token.sol";

import {Assertion} from "test/Utils/Assertion.sol";

interface MintBurnERC20 is IERC20 {
    function mint(address to, uint256 value) external;
    function burn(address from, uint256 value) external;
}

contract KontrolFVLiquidityKontrol is Assertion {
    using FixedPointMathLib for uint256;


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

        console2.log("Initial contract balance:", initialContractBalance);
        console2.log("Initial beneficiary balance:", initialBeneficiaryBalance);
        console2.log("Deposit amount:", amount);

        vm.prank(beneficiary);
        lm.deposit(amount, beneficiary);

        uint256 finalContractBalance = lockToken.balanceOf(address(lm));
        console2.log("Final contract balance:", finalContractBalance);
        assert(finalContractBalance == initialContractBalance + amount);

        uint256 finalBeneficiaryBalance = lockToken.balanceOf(beneficiary);
        console2.log("Final beneficiary balance:", finalBeneficiaryBalance);
        assert(finalBeneficiaryBalance == initialBeneficiaryBalance - amount);
    }


    function test_check_deposit_positive_amount(uint256 depositAmount) public {
        // Assume that the deposit amount is positive
        vm.assume(depositAmount > 0 && depositAmount < 1e24);

        // Mint lockTokens to the investor
        MintBurnERC20(address(lockToken)).mint(investor, depositAmount);

        // Approve lockTokens for the LiquidityMine contract
        vm.startPrank(investor);
        lockToken.approve(address(lm), depositAmount);

        // Capture the state before the deposit
        uint256 initialLockedTokens = lm.userInfo(investor).lockedTokens;
        uint256 initialRewardDebt = lm.userInfo(investor).rewardDebt;
        uint256 initialContractBalance = lockToken.balanceOf(address(lm));
        vm.stopPrank();

        // Make the deposit
        vm.startPrank(investor);
        lm.deposit(depositAmount);
        vm.stopPrank();

        // Capture the state after the deposit
        uint256 finalLockedTokens = lm.userInfo(investor).lockedTokens;
        uint256 finalRewardDebt = lm.userInfo(investor).rewardDebt;
        uint256 finalContractBalance = lockToken.balanceOf(address(lm));

        // Assert the state changes
        assert(finalLockedTokens == initialLockedTokens + depositAmount);
        assert(finalContractBalance == initialContractBalance + depositAmount);
        assert(finalRewardDebt ==  lm.accRewardsPerLockToken().mulWadDown(finalLockedTokens));
    }

    function testcheck_deposit_positive_amount() public {
        // Assume that the deposit amount is positive


        // Mint lockTokens to the investor
        MintBurnERC20(address(lockToken)).mint(investor, 604469827338532661755903);

        // Approve lockTokens for the LiquidityMine contract
        vm.startPrank(investor);
        lockToken.approve(address(lm), 604469827338532661755903);

        // Capture the state before the deposit
        uint256 initialLockedTokens = lm.userInfo(investor).lockedTokens;
        uint256 initialRewardDebt = lm.userInfo(investor).rewardDebt;
        uint256 initialContractBalance = lockToken.balanceOf(address(lm));
        vm.stopPrank();

        // Make the deposit
        vm.startPrank(investor);
        lm.deposit(604469827338532661755903);
        vm.stopPrank();

        // Capture the state after the deposit
        uint256 finalLockedTokens = lm.userInfo(investor).lockedTokens;
        uint256 finalRewardDebt = lm.userInfo(investor).rewardDebt;
        uint256 finalContractBalance = lockToken.balanceOf(address(lm));

        // Assert the state changes
        assert(finalLockedTokens == initialLockedTokens + 604469827338532661755903);
        assert(finalContractBalance == initialContractBalance + 604469827338532661755903);
        assert(finalRewardDebt == lm.accRewardsPerLockToken().mulWadDown(finalLockedTokens));
    }


    function testcheck_updateAccounting_without_locked_tokens() public {
        vm.assume(true); // No need to assume anything for this test
        address beneficiary = investor;

        vm.assume(beneficiary != address(lm) && beneficiary != address(0));

        // Capture the state before updateAccounting
        uint256 initialAccRewardsPerLockToken = lm.accRewardsPerLockToken();
        uint256 initialAccRewardsTotal = lm.accRewardsTotal();
        uint256 initialLastRewardBlock = lm.lastRewardBlock();

        // Advance the block number
        vm.roll(block.number + 10);

        // Call updateAccounting
        vm.startPrank(beneficiary);
        lm.updateAccounting();
        vm.stopPrank();

        // Capture the state after updateAccounting
        uint256 finalAccRewardsPerLockToken = lm.accRewardsPerLockToken();
        uint256 finalAccRewardsTotal = lm.accRewardsTotal();
        uint256 finalLastRewardBlock = lm.lastRewardBlock();

        // Assert the state changes
        assert(finalAccRewardsPerLockToken == initialAccRewardsPerLockToken);
        assert(finalAccRewardsTotal == initialAccRewardsTotal);
        assert(finalLastRewardBlock == initialLastRewardBlock);
    }

    function testcheck_setRewardPerEpoch(uint256 newRewardPerEpoch, address owner) public {
        vm.assume(newRewardPerEpoch > 0);

        // address owner = svm.createAddress("owner");
        // vm.assume(owner == address(this));

        // Capturar el estado antes de setRewardPerEpoch
        uint256 initialRewardPerEpoch = lm.rewardPerEpoch();

        // Cambiar el rewardPerEpoch
        vm.prank(sysAdmin);
        lm.setRewardPerEpoch(newRewardPerEpoch);

        // Capturar el estado después de setRewardPerEpoch
        uint256 finalRewardPerEpoch = lm.rewardPerEpoch();

        // Verificar el cambio de estado
        assert(finalRewardPerEpoch == newRewardPerEpoch);
        assert(finalRewardPerEpoch != initialRewardPerEpoch);
    }


    //


    function test_pendingRewards_computes_correct_accRewardsPerLockToken(uint256 depositAmount, uint256 blocksPassed) public {
        // Limit the fuzzing range for more reasonable values
        depositAmount = bound(depositAmount, 1, 1e24);
        blocksPassed = bound(blocksPassed, 1, 1000);
        address beneficiary = makeAddr("beneficiary");

        // Mint lockTokens to the beneficiary
        MintBurnERC20(address(lockToken)).mint(beneficiary, depositAmount);
        vm.prank(beneficiary);
        lockToken.approve(address(lm), depositAmount);

        // Perform the deposit
        vm.prank(beneficiary);
        lm.deposit(depositAmount, beneficiary);

        // Advance the block
        vm.roll(block.number + blocksPassed);

        // Calculate expected new rewards and accRewardsPerLockToken
        uint256 currentRewardPerEpoch = lm.rewardPerEpoch();
        uint256 newRewards = currentRewardPerEpoch * blocksPassed;
        uint256 lockTokenSupply = depositAmount;

        // Adjust newRewards if it exceeds totalRewardCap
        if (lm.accRewardsTotal() + newRewards > lm.totalRewardCap()) {
            newRewards = lm.totalRewardCap() - lm.accRewardsTotal();
        }

        uint256 expectedNewAccRewardsPerLockToken = lm.accRewardsPerLockToken() + newRewards.divWadDown(lockTokenSupply);

        // Call updateAccounting to update the contract state
        lm.updateAccounting();

        // Verify the calculation of newAccRewardsPerLockToken through pendingRewards
        uint256 pendingRewards = lm.pendingRewards(beneficiary);
        uint256 expectedPendingRewards = depositAmount.mulWadDown(expectedNewAccRewardsPerLockToken);
        assertEq(pendingRewards, expectedPendingRewards, "Pending rewards should match expected rewards");
    }


    function test_fundedEpochsLeft_computes_correct_accRewardsTotal(uint256 depositAmount, uint256 blocksPassed) public {
        depositAmount = bound(depositAmount, 1, 1e24); // Limit depositAmount between 1 and 1e24
        blocksPassed = bound(blocksPassed, 1, 1000); // Limit blocksPassed between 1 and 1000
        address beneficiary = makeAddr("beneficiary");

        // Mint lockTokens to the beneficiary
        MintBurnERC20(address(lockToken)).mint(beneficiary, depositAmount);
        vm.prank(beneficiary);
        lockToken.approve(address(lm), depositAmount);

        // Perform the deposit
        vm.prank(beneficiary);
        lm.deposit(depositAmount, beneficiary);

        // Advance the block
        vm.roll(block.number + blocksPassed);

        // Call updateAccounting to update the values
        lm.updateAccounting();

        // Calculate expected new rewards and accRewardsTotal
        uint256 currentRewardPerEpoch = lm.rewardPerEpoch();
        uint256 expectedNewRewards = currentRewardPerEpoch * blocksPassed;

        // Ensure expectedNewAccRewardsTotal does not exceed totalRewardCap
        uint256 initialAccRewardsTotal = lm.accRewardsTotal();
        if (initialAccRewardsTotal + expectedNewRewards > lm.totalRewardCap()) {
            expectedNewRewards = lm.totalRewardCap() - initialAccRewardsTotal;
        }

        uint256 expectedNewAccRewardsTotal = initialAccRewardsTotal + expectedNewRewards;

        // Verify the calculation of newAccRewardsTotal through fundedEpochsLeft
        uint256 fundedEpochsLeft = lm.fundedEpochsLeft();
        uint256 remainingRewards = lm.totalRewardCap() - expectedNewAccRewardsTotal;

        // Ensure remaining rewards are non-negative and currentRewardPerEpoch is non-zero to avoid division by zero
        if (remainingRewards >= 0 && currentRewardPerEpoch > 0) {
            uint256 expectedFundedEpochsLeft = remainingRewards / currentRewardPerEpoch;
            assertEq(fundedEpochsLeft, expectedFundedEpochsLeft, "fundedEpochsLeft should be correctly calculated");
        } else {
            // Handle edge cases where remainingRewards < 0 or currentRewardPerEpoch == 0
            assertEq(fundedEpochsLeft , 0, "fundedEpochsLeft should be zero in edge cases");
        }
    }






    function test_rewardsLeft_respects_totalRewardCap(uint256 depositAmount, uint256 blocksPassed, uint256 totalRewardCap) public { //@audit
        depositAmount = bound(depositAmount, 1, 1e24); // Limit depositAmount between 1 and 1e24
        blocksPassed = bound(blocksPassed, 1, 1000); // Limit blocksPassed between 1 and 1000
        totalRewardCap = bound(totalRewardCap, 1, 1e24); // Limit totalRewardCap between 1 and 1e24
        address beneficiary = makeAddr("beneficiary");

        // Mint lockTokens to the beneficiary
        MintBurnERC20(address(lockToken)).mint(beneficiary, depositAmount);
        vm.prank(beneficiary);
        lockToken.approve(address(lm), depositAmount);

        // Perform the deposit
        vm.prank(beneficiary);
        lm.deposit(depositAmount, beneficiary);

        // Directly set the totalRewardCap
        vm.store(address(lm), keccak256("totalRewardCap"), bytes32(totalRewardCap));

        // Log totalRewardCap after setting
        console2.log("totalRewardCap after setting:", totalRewardCap);

        // Advance the block
        vm.roll(block.number + blocksPassed);

        // Call updateAccounting to update the values
        lm.updateAccounting();


        // Calculate the expected new rewards and accRewardsTotal
        uint256 currentRewardPerEpoch = lm.rewardPerEpoch();
        uint256 expectedNewRewards = currentRewardPerEpoch * blocksPassed;

        // Ensure expectedNewAccRewardsTotal does not exceed totalRewardCap
        uint256 initialAccRewardsTotal = lm.accRewardsTotal();
        if (initialAccRewardsTotal + expectedNewRewards > totalRewardCap) {
            expectedNewRewards = totalRewardCap - initialAccRewardsTotal;
        }

        uint256 expectedNewAccRewardsTotal = initialAccRewardsTotal + expectedNewRewards;


        // Verify the calculation of rewardsLeft
        uint256 rewardsLeft = lm.rewardsLeft();
        uint256 expectedRewardsLeft = totalRewardCap - expectedNewAccRewardsTotal;

        console2.log("Final values:");
        console2.log("expectedRewardsLeft:", expectedRewardsLeft);
        console2.log("rewardsLeft:", rewardsLeft);

        // Assertion to ensure rewardsLeft is correctly calculated
        assert(rewardsLeft == expectedRewardsLeft);
    }




    function test_updateAccounting_computes_correct_lockTokenSupply(uint256 depositAmount) public {
        depositAmount = bound(depositAmount, 1, 1e24); // Limit depositAmount between 1 and 1e24
        address beneficiary = makeAddr("beneficiary");

        // Mint lockTokens al beneficiario
        MintBurnERC20(address(lockToken)).mint(beneficiary, depositAmount);
        vm.prank(beneficiary);
        lockToken.approve(address(lm), depositAmount);

        // Realizar el depósito
        vm.prank(beneficiary);
        lm.deposit(depositAmount, beneficiary);

        // Llamar a updateAccounting para actualizar los valores
        lm.updateAccounting();

        // Obtener el suministro esperado de lockToken
        uint256 expectedLockTokenSupply = depositAmount;

        // Verificar el cálculo de lockTokenSupply a través de la función pública que llama a _computeAccRewards
        uint256 actualLockTokenSupply = lockToken.balanceOf(address(lm));
        assert(actualLockTokenSupply == expectedLockTokenSupply);
    }




    function testFuzz_InitialDeposit(uint256 depositAmt) public {
        depositAmt = bound(depositAmt, 1e17, 1e21); // Limit depositAmt between 0.1 and 1000 tokens
        totalRewards = bound(totalRewards, 1e18, 1e24); // Limit totalRewards between 1 and 1 million tokens

        _loadRewards(totalRewards);

        MintBurnERC20(address(lockToken)).mint(investor, depositAmt);

        assertRewardCapInvariant("testFuzz_InitialDeposit1");
        assertUserInfo(investor, 0, 0, 0, "testFuzz_InitialDeposit1");

        // deposit depositAmt lockTokens on behalf of investor
        vm.startPrank(investor);
        lockToken.approve(address(lm), depositAmt);
        lm.deposit(depositAmt);

        assertRewardCapInvariant("testFuzz_InitialDeposit2");
        vm.stopPrank();
    }



    function testFuzz_MidwayPointCheck(uint256 depositAmt) public { //@audit
        depositAmt = bound(depositAmt, 1e17, 1e21); // Limit depositAmt between 0.1 and 1000 tokens

        _loadRewards(totalRewards);

        MintBurnERC20(address(lockToken)).mint(investor, depositAmt);

        // Deposit for investor
        vm.startPrank(investor);
        lockToken.approve(address(lm), depositAmt);
        lm.deposit(depositAmt);
        vm.stopPrank();

        // Roll forward to the middle of the liquidity mine and check the pending rewards
        vm.roll(block.number + (lm.fundedEpochsLeft().divWadDown(2e18)));
        assertEq(lm.pendingRewards(investor), totalRewards.divWadDown(2e18), "User should receive 50% of rewards");

        // Test update the pool and the results should not change
        lm.updateAccounting();
        assertEq(lm.lastRewardBlock(), block.number, "lastRewardBlock should be the current block");
        assertEq(lm.pendingRewards(investor), totalRewards.divWadDown(2e18), "User should receive 50% of rewards - 2");

        assertRewardCapInvariant("testFuzz_MidwayPointCheck");
    }

    //@audit-issue =>  Rounding Error in Reward Distribution Calculation
    function testFuzz_FinalRewardsDistribution(uint256 depositAmt) public { 

        depositAmt = bound(depositAmt, 1e17, 1e21); // Limit depositAmt between 0.1 and 1000 tokens
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

        // Roll forward to the end of the liquidity mine and check the pending rewards
        vm.roll(block.number + lm.fundedEpochsLeft());

        assertEq(lm.pendingRewards(investor), totalRewards.mulWadUp(75e16), "User1 should receive 75% of rewards");
        assertEq(lm.pendingRewards(investor2), totalRewards.mulWadUp(25e16), "User2 should receive 25% of rewards");

        // Test update the pool and the results should not change
        lm.updateAccounting();
        assertEq(lm.pendingRewards(investor), totalRewards.mulWadUp(75e16), "User1 should receive 75% of rewards");
        assertEq(lm.pendingRewards(investor2), totalRewards.mulWadUp(25e16), "User2 should receive 25% of rewards");

        assertRewardCapInvariant("testFuzz_FinalRewardsDistribution");
    }

    function testFuzz_FinalStateVerification(uint256 depositAmt) public {
        depositAmt = bound(depositAmt, 1e17, 1e21); // Limit depositAmt between 0.1 and 1000 tokens
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

        // Verificar las recompensas pendientes
        assertEq(lm.pendingRewards(beneficiary), totalRewards.divWadDown(2e18));
    }

    function testFuzz_InitialRewardLoadingAndDeposit(uint256 depositAmt) public { // @audit-issue
        depositAmt = bound(depositAmt, 1e17, 1e21); // Limit depositAmt between 0.1 and 1000 tokens

        assertEq(rewardToken.balanceOf(address(lm)), 0, "LM Contract should have 0 locked tokens");

        _loadRewards(totalRewards);
        assertRewardCapInvariant("testFuzz_InitialRewardLoadingAndDeposit1");

        _depositLockTokens(investor, depositAmt);
        uint256 totalFundedEpochs = lm.fundedEpochsLeft();
        assertEq(totalFundedEpochs, totalRewards / rewardPerEpoch, "fundedEpochsLeft should be the full LM duration");

        vm.roll(block.number + lm.fundedEpochsLeft());
        assertEq(lm.pendingRewards(investor), totalRewards, "User should receive all rewards");
    }


  
}
