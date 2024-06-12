// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {Test, console2} from "forge-std/Test.sol";
import {LiquidityMine} from "src/LiquidityMine.sol";
import {Token} from "src/Token.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SymTest} from "halmos-cheatcodes/SymTest.sol";

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
contract HalmosFVLiquidityMine is SymTest, Test {
    using FixedPointMathLib for uint256;

    LiquidityMine public lm;
    IERC20 public rewardToken;
    IERC20 public lockToken;
    uint256 public rewardPerEpoch;
    uint256 public totalRewards;
    uint256 public deployBlock;

    address public investor;
    address public sysAdmin;


    event Deposit(
        address indexed caller, address indexed beneficiary, uint256 lockTokenAmount, uint256 rewardsUnclaimed
    );
    event LogUpdateAccounting(
        uint64 lastRewardBlock, uint256 lockTokenSupply, uint256 accRewardsPerLockToken, uint256 accRewardsTotal
    );

    // address investor = makeAddr("investor");
    // address sysAdmin = makeAddr("sysAdmin");

    // address investor = vm.addr(1);
    // address sysAdmin = vm.addr(2);


    function setUp() public {
        investor = vm.addr(1);
        sysAdmin = vm.addr(2);

        rewardPerEpoch = 1e18;
        totalRewards = 75_000_000e18;
        rewardToken = IERC20(address(new Token("GLIF", "GLF", sysAdmin, address(this), address(this))));
        lockToken = IERC20(address(new Token("iFIL", "iFIL", sysAdmin, address(this), address(this))));

        deployBlock = block.number;
        lm = new LiquidityMine(rewardToken, lockToken, rewardPerEpoch, sysAdmin);

        // Mint initial rewards to sysAdmin
        MintBurnERC20(address(rewardToken)).mint(sysAdmin, totalRewards);
        
        // Ensure the investor has some lock tokens for testing
        MintBurnERC20(address(lockToken)).mint(investor, 1e24);

        // deal(address(lockToken), investor, 300 * 1e18);
        // deal(address(lockToken), sysAdmin, 300 * 1e18);
        vm.deal(sysAdmin, 300 * 1e18);
        vm.deal(investor, 300 * 1e18);

    }


    // address beneficiary = makeAddr("beneficiary");
    function check_testFuzz_Deposit_CheckBalances(uint256 amount) public {
        // Assumptions
        vm.assume(amount > 0 && amount < 1e24);
        address beneficiary = svm.createAddress("beneficiary");

        vm.assume(beneficiary == address(this));

        // Mint tokens to the beneficiary so they can be deposited
        MintBurnERC20(address(lockToken)).mint(beneficiary, amount);
        vm.prank(beneficiary);
        lockToken.approve(address(lm), amount);

        uint256 initialContractBalance = lockToken.balanceOf(address(lm));
        uint256 initialBeneficiaryBalance = lockToken.balanceOf(beneficiary);


        vm.prank(beneficiary);
        lm.deposit(amount, beneficiary);

        uint256 finalContractBalance = lockToken.balanceOf(address(lm));
        assert(finalContractBalance == initialContractBalance + amount);

        uint256 finalBeneficiaryBalance = lockToken.balanceOf(beneficiary);
        assert(finalBeneficiaryBalance == initialBeneficiaryBalance - amount);
    }


    function check_deposit_positive_amount(uint256 depositAmount) public {
        // Assume that the deposit amount is positivo y dentro de un rango razonable
        vm.assume(depositAmount > 0 && depositAmount < 1e24);
        address beneficiary = svm.createAddress("beneficiary");
        vm.assume(beneficiary == address(this));


        console2.log("address(lm)", address(lm));
        console2.log("beneficiary", beneficiary);

        // Mint lockTokens to the investor
        MintBurnERC20(address(lockToken)).mint(beneficiary, depositAmount);

        // Approve lockTokens for the LiquidityMine contract
        vm.startPrank(beneficiary);
        lockToken.approve(address(lm), depositAmount);

        // Capture the state before the deposit
        uint256 initialLockedTokens = lm.userInfo(beneficiary).lockedTokens;
        uint256 initialRewardDebt = lm.userInfo(beneficiary).rewardDebt;
        uint256 initialContractBalance = lockToken.balanceOf(address(lm));
        uint256 initialBeneficiaryBalance = lockToken.balanceOf(beneficiary);

        vm.stopPrank();


        // Make the deposit
        vm.startPrank(beneficiary);
        lm.deposit(depositAmount);
        vm.stopPrank();

        // Capture the state after the deposit
        uint256 finalLockedTokens = lm.userInfo(beneficiary).lockedTokens;
        uint256 finalRewardDebt = lm.userInfo(beneficiary).rewardDebt;
        uint256 finalContractBalance = lockToken.balanceOf(address(lm));
        uint256 finalBeneficiaryBalance = lockToken.balanceOf(beneficiary);


        // Assert the state changes with detailed error messages
        assert(finalLockedTokens == initialLockedTokens + depositAmount);
        assert(finalContractBalance == initialContractBalance + depositAmount);
        assert(finalRewardDebt == lm.accRewardsPerLockToken().mulWadDown(finalLockedTokens));
        assert(finalBeneficiaryBalance == initialBeneficiaryBalance - depositAmount);

    }

    function check_deposit_updates_reward_debt(uint256 depositAmount) public {
        // Assume that the deposit amount is positivo y dentro de un rango razonable
        vm.assume(depositAmount > 0 && depositAmount < 1e24);
        address beneficiary = svm.createAddress("beneficiary");
        vm.assume(beneficiary == address(this));

        // Mint lockTokens to the beneficiary
        MintBurnERC20(address(lockToken)).mint(beneficiary, depositAmount);

        // Approve lockTokens for the LiquidityMine contract
        vm.startPrank(beneficiary);
        lockToken.approve(address(lm), depositAmount);

        // Capture the state before the deposit
        uint256 initialRewardDebt = lm.userInfo(beneficiary).rewardDebt;
        vm.stopPrank();

        // Make the deposit
        vm.startPrank(beneficiary);
        lm.deposit(depositAmount);
        vm.stopPrank();

        // Capture the state after the deposit
        uint256 finalLockedTokens = lm.userInfo(beneficiary).lockedTokens;
        uint256 finalRewardDebt = lm.userInfo(beneficiary).rewardDebt;

        // Assert the state changes
        assert(finalRewardDebt == lm.accRewardsPerLockToken().mulWadDown(finalLockedTokens));
    }

    function check_deposit_more_than_balance(uint256 depositAmount) public {
        // Assume that the deposit amount es positivo y dentro de un rango razonable
        vm.assume(depositAmount > 0 && depositAmount < 1e24);
        address beneficiary = svm.createAddress("beneficiary");
        vm.assume(beneficiary == address(this));

        // Mint lockTokens to the beneficiary
        uint256 mintAmount = depositAmount / 2; // Mint less than the deposit amount
        MintBurnERC20(address(lockToken)).mint(beneficiary, mintAmount);

        // Approve lockTokens for the LiquidityMine contract
        vm.startPrank(beneficiary);
        lockToken.approve(address(lm), depositAmount);
        vm.stopPrank();

        // Expect revert on deposit
        vm.startPrank(beneficiary);
        lm.deposit(depositAmount);
        vm.stopPrank();
    }

    function check_updateAccounting_with_locked_tokens(uint256 depositAmount) public {
        vm.assume(depositAmount > 0 && depositAmount < 1e24);
        address beneficiary = svm.createAddress("beneficiary");
        vm.assume(beneficiary == address(this));

        // Mint lockTokens to the beneficiary
        MintBurnERC20(address(lockToken)).mint(beneficiary, depositAmount);
        vm.prank(beneficiary);
        lockToken.approve(address(lm), depositAmount);

        // Perform the deposit
        vm.prank(beneficiary);
        lm.deposit(depositAmount, beneficiary);

        // Mint rewards to the beneficiary
        uint256 rewardAmount = 1e24; // Mint some rewards for testing
        MintBurnERC20(address(rewardToken)).mint(beneficiary, rewardAmount);
        vm.prank(beneficiary);
        rewardToken.approve(address(lm), rewardAmount);

        // Load rewards into the contract
        vm.prank(beneficiary);
        lm.loadRewards(rewardAmount);

        // Advance the block number
        uint256 blocksPassed = 100;
        vm.roll(block.number + blocksPassed);

        // Capture the state before updateAccounting
        uint256 initialAccRewardsPerLockToken = lm.accRewardsPerLockToken();
        uint256 initialAccRewardsTotal = lm.accRewardsTotal();
        uint256 initialLastRewardBlock = lm.lastRewardBlock();

        // Call updateAccounting
        lm.updateAccounting();

        // Capture the state after updateAccounting
        uint256 finalAccRewardsPerLockToken = lm.accRewardsPerLockToken();
        uint256 finalAccRewardsTotal = lm.accRewardsTotal();
        uint256 finalLastRewardBlock = lm.lastRewardBlock();

        // Assert the state changes
        assert(finalAccRewardsPerLockToken > initialAccRewardsPerLockToken);
        assert(finalAccRewardsTotal > initialAccRewardsTotal);
        assert(finalLastRewardBlock > initialLastRewardBlock);
    }




    function check_updateAccounting_respects_totalRewardCap(uint256 depositAmount) public {
        vm.assume(depositAmount > 0 && depositAmount < 1e24);
        address beneficiary = svm.createAddress("beneficiary");
        vm.assume(beneficiary == address(this));

        // Mint lockTokens to the beneficiary
        MintBurnERC20(address(lockToken)).mint(beneficiary, depositAmount);
        vm.prank(beneficiary);
        lockToken.approve(address(lm), depositAmount);

        // Perform the deposit
        vm.prank(beneficiary);
        lm.deposit(depositAmount, beneficiary);

        // Mint rewards to the beneficiary
        uint256 rewardAmount = 1e24; // Mint some rewards for testing
        MintBurnERC20(address(rewardToken)).mint(beneficiary, rewardAmount);
        vm.prank(beneficiary);
        rewardToken.approve(address(lm), rewardAmount);

        // Load rewards into the contract
        vm.prank(beneficiary);
        lm.loadRewards(rewardAmount);

        // Set accRewardsTotal to a value close to totalRewardCap
        uint256 rewardBuffer = 1e18; // Small buffer for rewards
        vm.store(address(lm), bytes32(uint256(keccak256("accRewardsTotal"))), bytes32(totalRewards - rewardBuffer));

        // Advance the block number
        uint256 blocksPassed = 100;
        vm.roll(block.number + blocksPassed);

        // Call updateAccounting
        lm.updateAccounting();

        // Capture the state after updateAccounting
        uint256 finalAccRewardsTotal = lm.accRewardsTotal();

        // Assert the state changes
        assert(finalAccRewardsTotal <= totalRewards);
    }

    function check_updateAccounting_invariant(uint256 depositAmount, uint256 rewardAmount) public {
        // Asumir las condiciones iniciales
        vm.assume(depositAmount > 0 && depositAmount < 1e24);
        vm.assume(rewardAmount > 0 && rewardAmount < 1e24);
        address beneficiary = svm.createAddress("beneficiary");
        vm.assume(beneficiary == address(this));

        // Mint lockTokens al beneficiario
        MintBurnERC20(address(lockToken)).mint(beneficiary, depositAmount);
        vm.prank(beneficiary);
        lockToken.approve(address(lm), depositAmount);

        // Realizar el depósito
        vm.prank(beneficiary);
        lm.deposit(depositAmount, beneficiary);

        // Mint rewards al beneficiario
        MintBurnERC20(address(rewardToken)).mint(beneficiary, rewardAmount);
        vm.prank(beneficiary);
        rewardToken.approve(address(lm), rewardAmount);

        // Cargar recompensas en el contrato
        vm.prank(beneficiary);
        lm.loadRewards(rewardAmount);

        // Avanzar el número de bloques
        uint256 blocksPassed = 100;
        vm.roll(block.number + blocksPassed);

        // Actualizar la contabilidad
        lm.updateAccounting();

        // Verificar los invariantes
        assert(lm.accRewardsTotal() <= lm.totalRewardCap());
        assert(lm.rewardTokensClaimed() <= lm.accRewardsTotal());
        assert(lm.totalRewardCap() == lm.rewardTokensClaimed() + rewardToken.balanceOf(address(lm)));
    }


    function check_withdraw_decreases_locked_tokens(uint256 depositAmount, uint256 withdrawAmount) public {
        vm.assume(depositAmount > 0 && depositAmount < 1e24);
        vm.assume(withdrawAmount > 0 && withdrawAmount <= depositAmount);
        address beneficiary = svm.createAddress("beneficiary");
        vm.assume(beneficiary == address(this));

        // Mint lockTokens al beneficiario
        MintBurnERC20(address(lockToken)).mint(beneficiary, depositAmount);
        vm.prank(beneficiary);
        lockToken.approve(address(lm), depositAmount);

        // Realizar el depósito
        vm.prank(beneficiary);
        lm.deposit(depositAmount, beneficiary);

        // Capturar el estado antes del retiro
        uint256 initialLockedTokens = lm.userInfo(beneficiary).lockedTokens;
        uint256 initialContractBalance = lockToken.balanceOf(address(lm));
        uint256 initialBeneficiaryBalance = lockToken.balanceOf(beneficiary);

        // Realizar el retiro
        vm.prank(beneficiary);
        lm.withdraw(withdrawAmount, beneficiary);

        // Capturar el estado después del retiro
        uint256 finalLockedTokens = lm.userInfo(beneficiary).lockedTokens;
        uint256 finalContractBalance = lockToken.balanceOf(address(lm));
        uint256 finalBeneficiaryBalance = lockToken.balanceOf(beneficiary);

        // Verificar los cambios de estado
        assert(finalLockedTokens == initialLockedTokens - withdrawAmount);
        assert(finalContractBalance == initialContractBalance - withdrawAmount);
        assert(finalBeneficiaryBalance == initialBeneficiaryBalance + withdrawAmount);
    }

    function check_harvest_decreases_unclaimed_rewards(uint256 depositAmount, uint256 rewardAmount) public { //@audit
        vm.assume(depositAmount > 0 && depositAmount < 1e24);
        vm.assume(rewardAmount > 0 && rewardAmount < depositAmount);
        address beneficiary = svm.createAddress("beneficiary");
        vm.assume(beneficiary == address(this));

        // Mint lockTokens al beneficiario
        MintBurnERC20(address(lockToken)).mint(beneficiary, depositAmount);
        vm.prank(beneficiary);
        lockToken.approve(address(lm), depositAmount);

        // Realizar el depósito
        vm.prank(beneficiary);
        lm.deposit(depositAmount, beneficiary);

        // Mint rewards al beneficiario
        MintBurnERC20(address(rewardToken)).mint(beneficiary, rewardAmount);
        vm.prank(beneficiary);
        rewardToken.approve(address(lm), rewardAmount);

        // Cargar recompensas en el contrato
        vm.prank(beneficiary);
        lm.loadRewards(rewardAmount);

        // Avanzar el número de bloques
        uint256 blocksPassed = 100;
        vm.roll(block.number + blocksPassed);

        // Actualizar la contabilidad
        lm.updateAccounting();

        // Capturar el estado antes de la cosecha
        uint256 initialUnclaimedRewards = lm.userInfo(beneficiary).unclaimedRewards;
        uint256 initialContractRewardBalance = rewardToken.balanceOf(address(lm));
        uint256 initialBeneficiaryRewardBalance = rewardToken.balanceOf(beneficiary);

        // Realizar la cosecha
        uint256 pendingRewards = lm.pendingRewards(beneficiary);
        if (pendingRewards > 0) {
            // Perform the harvest
            vm.prank(beneficiary);
            lm.harvest(pendingRewards, beneficiary);
        }
        vm.prank(beneficiary);
        lm.harvest(pendingRewards, beneficiary);

        // Capturar el estado después de la cosecha
        uint256 finalUnclaimedRewards = lm.userInfo(beneficiary).unclaimedRewards;
        uint256 finalContractRewardBalance = rewardToken.balanceOf(address(lm));
        uint256 finalBeneficiaryRewardBalance = rewardToken.balanceOf(beneficiary);

        // Verificar los cambios de estado
        assert(finalUnclaimedRewards == initialUnclaimedRewards - pendingRewards);
        assert(finalContractRewardBalance == initialContractRewardBalance - pendingRewards);
        assert(finalBeneficiaryRewardBalance == initialBeneficiaryRewardBalance + pendingRewards);
    }

    function check_updateAccounting_no_change_without_new_blocks(uint256 depositAmount, uint256 rewardAmount) public {
        vm.assume(depositAmount > 0 && depositAmount < 1e24);
        vm.assume(rewardAmount > 0 && rewardAmount < depositAmount);
        address beneficiary = svm.createAddress("beneficiary");
        vm.assume(beneficiary == address(this));

        // Mint lockTokens al beneficiario
        MintBurnERC20(address(lockToken)).mint(beneficiary, depositAmount);
        vm.prank(beneficiary);
        lockToken.approve(address(lm), depositAmount);

        // Realizar el depósito
        vm.prank(beneficiary);
        lm.deposit(depositAmount, beneficiary);

        // Mint rewards al beneficiario
        MintBurnERC20(address(rewardToken)).mint(beneficiary, rewardAmount);
        vm.prank(beneficiary);
        rewardToken.approve(address(lm), rewardAmount);

        // Cargar recompensas en el contrato
        vm.prank(beneficiary);
        lm.loadRewards(rewardAmount);

        // Capturar el estado antes de updateAccounting
        uint256 initialAccRewardsPerLockToken = lm.accRewardsPerLockToken();
        uint256 initialAccRewardsTotal = lm.accRewardsTotal();
        uint256 initialLastRewardBlock = lm.lastRewardBlock();

        // Llamar a updateAccounting sin avanzar el bloque
        lm.updateAccounting();

        // Capturar el estado después de updateAccounting
        uint256 finalAccRewardsPerLockToken = lm.accRewardsPerLockToken();
        uint256 finalAccRewardsTotal = lm.accRewardsTotal();
        uint256 finalLastRewardBlock = lm.lastRewardBlock();

        // Verificar que no hay cambios en los valores
        assert(finalAccRewardsPerLockToken == initialAccRewardsPerLockToken);
        assert(finalAccRewardsTotal == initialAccRewardsTotal);
        assert(finalLastRewardBlock == initialLastRewardBlock);
    }


    function check_loadRewards_increases_totalRewardCap(uint256 depositAmount, uint256 rewardAmount) public {
        vm.assume(depositAmount > 0 && depositAmount < 1e24);
        vm.assume(rewardAmount > 0 && rewardAmount < depositAmount);
        address beneficiary = svm.createAddress("beneficiary");
        vm.assume(beneficiary == address(this));

        // Mint lockTokens al beneficiario
        MintBurnERC20(address(lockToken)).mint(beneficiary, depositAmount);
        vm.prank(beneficiary);
        lockToken.approve(address(lm), depositAmount);

        // Realizar el depósito
        vm.prank(beneficiary);
        lm.deposit(depositAmount, beneficiary);

        // Mint rewards al beneficiario
        MintBurnERC20(address(rewardToken)).mint(beneficiary, rewardAmount);
        vm.prank(beneficiary);
        rewardToken.approve(address(lm), rewardAmount);

        // Capturar el estado antes de loadRewards
        uint256 initialTotalRewardCap = lm.totalRewardCap();

        // Cargar recompensas en el contrato
        vm.prank(beneficiary);
        lm.loadRewards(rewardAmount);

        // Capturar el estado después de loadRewards
        uint256 finalTotalRewardCap = lm.totalRewardCap();

        // Verificar los cambios de estado
        assert(finalTotalRewardCap == initialTotalRewardCap + rewardAmount);
    }


    function check_withdrawAndHarvest(uint256 depositAmount, uint256 rewardAmount, uint256 withdrawAmount) public { //@audit-iisue
        vm.assume(depositAmount > 0 && depositAmount < 1e24);
        vm.assume(rewardAmount > 0 && rewardAmount < depositAmount);
        vm.assume(withdrawAmount > 0 && withdrawAmount <= depositAmount);
        address beneficiary = svm.createAddress("beneficiary");
        vm.assume(beneficiary == address(this));

        // Mint lockTokens al beneficiario
        MintBurnERC20(address(lockToken)).mint(beneficiary, depositAmount);
        vm.prank(beneficiary);
        lockToken.approve(address(lm), depositAmount);

        // Realizar el depósito
        vm.prank(beneficiary);
        lm.deposit(depositAmount, beneficiary);

        // Mint rewards al beneficiario
        MintBurnERC20(address(rewardToken)).mint(beneficiary, rewardAmount);
        vm.prank(beneficiary);
        rewardToken.approve(address(lm), rewardAmount);

        // Cargar recompensas en el contrato
        vm.prank(beneficiary);
        lm.loadRewards(rewardAmount);

        // Avanzar el número de bloques
        uint256 blocksPassed = 100;
        vm.roll(block.number + blocksPassed);

        // Actualizar la contabilidad
        lm.updateAccounting();

        // Capturar el estado antes de withdrawAndHarvest
        uint256 initialLockedTokens = lm.userInfo(beneficiary).lockedTokens;
        uint256 initialUnclaimedRewards = lm.userInfo(beneficiary).unclaimedRewards;
        uint256 initialContractBalance = lockToken.balanceOf(address(lm));
        uint256 initialContractRewardBalance = rewardToken.balanceOf(address(lm));
        uint256 initialBeneficiaryBalance = lockToken.balanceOf(beneficiary);
        uint256 initialBeneficiaryRewardBalance = rewardToken.balanceOf(beneficiary);

        // Realizar el retiro y la cosecha
        vm.prank(beneficiary);
        lm.withdrawAndHarvest(withdrawAmount, beneficiary);

        // Capturar el estado después de withdrawAndHarvest
        uint256 finalLockedTokens = lm.userInfo(beneficiary).lockedTokens;
        uint256 finalUnclaimedRewards = lm.userInfo(beneficiary).unclaimedRewards;
        uint256 finalContractBalance = lockToken.balanceOf(address(lm));
        uint256 finalContractRewardBalance = rewardToken.balanceOf(address(lm));
        uint256 finalBeneficiaryBalance = lockToken.balanceOf(beneficiary);
        uint256 finalBeneficiaryRewardBalance = rewardToken.balanceOf(beneficiary);

        // Verificar los cambios de estado
        assert(finalLockedTokens == initialLockedTokens - withdrawAmount);
        assert(finalContractBalance == initialContractBalance - withdrawAmount);
        assert(finalBeneficiaryBalance == initialBeneficiaryBalance + withdrawAmount);

        uint256 pendingRewards = initialLockedTokens.mulWadDown(lm.accRewardsPerLockToken()) - initialUnclaimedRewards;
        assert(finalUnclaimedRewards == 0);
        assert(finalContractRewardBalance == initialContractRewardBalance - pendingRewards);
        assert(finalBeneficiaryRewardBalance == initialBeneficiaryRewardBalance + pendingRewards);
    }


    function check_setRewardPerEpoch(uint256 newRewardPerEpoch) public { //@audit
        vm.assume(newRewardPerEpoch > 0 && newRewardPerEpoch < 1e24);

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


    function check_pendingRewards(uint256 depositAmount, uint256 rewardAmount) public {
        vm.assume(depositAmount > 0 && depositAmount < 1e24);
        vm.assume(rewardAmount > 0 && rewardAmount < depositAmount);
        address beneficiary = svm.createAddress("beneficiary");
        vm.assume(beneficiary == address(this));

        // Mint lockTokens al beneficiario
        MintBurnERC20(address(lockToken)).mint(beneficiary, depositAmount);
        vm.prank(beneficiary);
        lockToken.approve(address(lm), depositAmount);

        // Realizar el depósito
        vm.prank(beneficiary);
        lm.deposit(depositAmount, beneficiary);

        // Mint rewards al beneficiario
        MintBurnERC20(address(rewardToken)).mint(beneficiary, rewardAmount);
        vm.prank(beneficiary);
        rewardToken.approve(address(lm), rewardAmount);

        // Cargar recompensas en el contrato
        vm.prank(sysAdmin);
        lm.loadRewards(rewardAmount);

        // Avanzar el número de bloques
        uint256 blocksPassed = 100;
        vm.roll(block.number + blocksPassed);

        // Actualizar la contabilidad
        lm.updateAccounting();

        // Verificar las recompensas pendientes
        uint256 expectedPendingRewards = depositAmount.mulWadDown(lm.accRewardsPerLockToken()) - lm.userInfo(beneficiary).rewardDebt;
        assert(lm.pendingRewards(beneficiary) == expectedPendingRewards);
    }


    function check_userInfo(uint256 depositAmount) public {
        vm.assume(depositAmount > 0 && depositAmount < 1e24);
        address beneficiary = svm.createAddress("beneficiary");
        vm.assume(beneficiary == address(this));

        // Mint lockTokens al beneficiario
        MintBurnERC20(address(lockToken)).mint(beneficiary, depositAmount);
        vm.prank(beneficiary);
        lockToken.approve(address(lm), depositAmount);

        // Realizar el depósito
        vm.prank(beneficiary);
        lm.deposit(depositAmount, beneficiary);

        // Obtener la información del usuario
        LiquidityMine.UserInfo memory userInfo = lm.userInfo(beneficiary);

        // Verificar la información del usuario
        assert(userInfo.lockedTokens == depositAmount);
        assert(userInfo.rewardDebt == depositAmount.mulWadDown(lm.accRewardsPerLockToken()));
        assert(userInfo.unclaimedRewards == 0);
    }


    function check_pendingRewards_computes_correct_accRewardsPerLockToken(uint256 depositAmount, uint256 blocksPassed) public {
        vm.assume(depositAmount > 0 && depositAmount < 1e24);
        vm.assume(blocksPassed > 0 && blocksPassed < 1000);
        address beneficiary = svm.createAddress("beneficiary");
        vm.assume(beneficiary == address(this));

        // Mint lockTokens al beneficiario
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
        assert(pendingRewards == expectedPendingRewards);
    }

    function check_fundedEpochsLeft_computes_correct_accRewardsTotal(uint256 depositAmount, uint256 blocksPassed) public {
        vm.assume(depositAmount > 0 && depositAmount < 1e24);
        vm.assume(blocksPassed > 0 && blocksPassed < 1000);
        address beneficiary = svm.createAddress("beneficiary");
        vm.assume(beneficiary == address(this));

        // Mint lockTokens al beneficiario
        MintBurnERC20(address(lockToken)).mint(beneficiary, depositAmount);
        vm.prank(beneficiary);
        lockToken.approve(address(lm), depositAmount);

        // Realizar el depósito
        vm.prank(beneficiary);
        lm.deposit(depositAmount, beneficiary);

        // Avanzar el bloque
        vm.roll(block.number + blocksPassed);

        // Llamar a updateAccounting para actualizar los valores
        lm.updateAccounting();

        // Calcular las nuevas recompensas esperadas
        uint256 currentRewardPerEpoch = lm.rewardPerEpoch();
        uint256 expectedNewRewards = currentRewardPerEpoch * blocksPassed;
        uint256 expectedNewAccRewardsTotal = lm.accRewardsTotal() + expectedNewRewards;

        // Verificar el cálculo de newAccRewardsTotal a través de fundedEpochsLeft
        uint256 fundedEpochsLeft = lm.fundedEpochsLeft();
        uint256 remainingRewards = lm.totalRewardCap() - expectedNewAccRewardsTotal;
        assert(fundedEpochsLeft == remainingRewards / currentRewardPerEpoch);
    }

    function check_fundedEpochsLeft_ifcomputes_correct_accRewardsTotal(uint256 depositAmount, uint256 blocksPassed) public {
        vm.assume(depositAmount > 0 && depositAmount < 1e24);
        vm.assume(blocksPassed > 0 && blocksPassed < 1000);
        address beneficiary = svm.createAddress("beneficiary");
        vm.assume(beneficiary == address(this));

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
            assert(fundedEpochsLeft == expectedFundedEpochsLeft);
        } else {
            // Handle edge cases where remainingRewards < 0 or currentRewardPerEpoch == 0
            assert(fundedEpochsLeft == 0);
        }
    }

    function check_rewardsLeft_respects_totalRewardCap(uint256 depositAmount, uint256 blocksPassed, uint256 totalRewardCap) public { //@audit
        vm.assume(depositAmount > 0 && depositAmount < 1e24);
        vm.assume(blocksPassed > 0 && blocksPassed < 1000);
        vm.assume(totalRewardCap > 0 && totalRewardCap < 1e24);
        address beneficiary = svm.createAddress("beneficiary");
        vm.assume(beneficiary == address(this));

        // Mint lockTokens al beneficiario
        MintBurnERC20(address(lockToken)).mint(beneficiary, depositAmount);
        vm.prank(beneficiary);
        lockToken.approve(address(lm), depositAmount);

        // Realizar el depósito
        vm.prank(beneficiary);
        lm.deposit(depositAmount, beneficiary);

        // Configurar el totalRewardCap
        vm.store(address(lm), bytes32(uint256(keccak256("totalRewardCap"))), bytes32(totalRewardCap));

        // Avanzar el bloque
        vm.roll(block.number + blocksPassed);

        // Llamar a updateAccounting para actualizar los valores
        lm.updateAccounting();

        // Calcular las nuevas recompensas esperadas
        uint256 currentRewardPerEpoch = lm.rewardPerEpoch();
        uint256 expectedNewRewards = currentRewardPerEpoch * blocksPassed;
        if (expectedNewRewards + lm.accRewardsTotal() > totalRewardCap) {
            expectedNewRewards = totalRewardCap - lm.accRewardsTotal();
        }
        uint256 expectedNewAccRewardsTotal = lm.accRewardsTotal() + expectedNewRewards;

        // Verificar el cálculo de newAccRewardsTotal a través de rewardsLeft
        uint256 rewardsLeft = lm.rewardsLeft();
        assert(rewardsLeft == totalRewardCap - expectedNewAccRewardsTotal);
    }

    function check_updateAccounting_computes_correct_lockTokenSupply(uint256 depositAmount) public {
        vm.assume(depositAmount > 0 && depositAmount < 1e24);
        address beneficiary = svm.createAddress("beneficiary");
        vm.assume(beneficiary == address(this));

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

    function check_initial_deposit_and_intermediate_rewards(uint256 depositAmount) public {
        vm.assume(depositAmount > 0 && depositAmount < 1e24);
        address investor2 = svm.createAddress("investor2");
        vm.assume(investor2 == address(this));

        _loadRewards(totalRewards);

        MintBurnERC20(address(lockToken)).mint(investor, depositAmount);
        MintBurnERC20(address(lockToken)).mint(investor2, depositAmount);

        // Verificar el estado inicial de los usuarios
        assertUserInfo(investor, 0, 0, 0, "initial state");
        assertUserInfo(investor2, 0, 0, 0, "initial state");

        // Depositar tokens de bloqueo en nombre del inversor
        vm.startPrank(investor);
        lockToken.approve(address(lm), depositAmount);
        lm.deposit(depositAmount);
        vm.stopPrank();

        // Avanzar al medio del periodo de minería de liquidez y verificar las recompensas pendientes
        vm.roll(block.number + (lm.fundedEpochsLeft().divWadDown(2e18)));
        assert(lm.pendingRewards(investor) == totalRewards.divWadDown(2e18));

        // Verificar que no hay recompensas no reclamadas aún
        assert(lm.userInfo(investor).unclaimedRewards == 0);

        // Actualizar la contabilidad y verificar los valores
        lm.updateAccounting();
        assert(lm.lastRewardBlock() == block.number);
        assert(lm.accRewardsPerLockToken() == totalRewards.divWadDown(depositAmount).divWadDown(2e18));
        assert(lm.pendingRewards(investor) == totalRewards.divWadDown(2e18));
        assert(lm.userInfo(investor).unclaimedRewards == 0);
    }

    //@audit-issue
    function check_intermediate_rewards(uint256 depositAmount) public {
        vm.assume(depositAmount > 0 && depositAmount < 1e24);
        address beneficiary = svm.createAddress("beneficiary");
        vm.assume(beneficiary == address(this));

        _loadRewards(totalRewards);

        MintBurnERC20(address(lockToken)).mint(beneficiary, depositAmount);

        vm.startPrank(beneficiary);
        lockToken.approve(address(lm), depositAmount);
        lm.deposit(depositAmount);
        vm.stopPrank();

        vm.roll(block.number + (lm.fundedEpochsLeft().divWadDown(2e18)));

        assert(lm.pendingRewards(beneficiary) == totalRewards.divWadDown(2e18));
    }


    //@audit-issue
    function check_update_accounting_after_initial_deposit(uint256 depositAmount) public {
        vm.assume(depositAmount > 0 && depositAmount < 1e24);
        address beneficiary = svm.createAddress("beneficiary");
        vm.assume(beneficiary == address(this));

        _loadRewards(totalRewards);

        MintBurnERC20(address(lockToken)).mint(beneficiary, depositAmount);

        // Depositar tokens de bloqueo en nombre del beneficiario
        vm.startPrank(beneficiary);
        lockToken.approve(address(lm), depositAmount);
        lm.deposit(depositAmount);
        vm.stopPrank();

        // Avanzar al medio del periodo de minería de liquidez
        vm.roll(block.number + (lm.fundedEpochsLeft().divWadDown(2e18)));
        lm.updateAccounting();

        // Verificar la actualización de la contabilidad
        assert(lm.lastRewardBlock() == block.number);
        assert(lm.accRewardsPerLockToken() == totalRewards.divWadDown(depositAmount).divWadDown(2e18));
        assert(lm.pendingRewards(beneficiary) == totalRewards.divWadDown(2e18));
        assert(lm.userInfo(beneficiary).unclaimedRewards == 0);
    }

    //@audit-issue
    function check_second_deposit(uint256 depositAmount) public {
        vm.assume(depositAmount > 0 && depositAmount < 1e24);
        address investor2 = svm.createAddress("investor2");
        vm.assume(investor2 == address(this));

        _loadRewards(totalRewards);

        MintBurnERC20(address(lockToken)).mint(investor, depositAmount);
        MintBurnERC20(address(lockToken)).mint(investor2, depositAmount);

        // Depositar tokens de bloqueo en nombre del inversor inicial
        vm.startPrank(investor);
        lockToken.approve(address(lm), depositAmount);
        lm.deposit(depositAmount);
        vm.stopPrank();

        // Avanzar al medio del periodo de minería de liquidez
        vm.roll(block.number + (lm.fundedEpochsLeft().divWadDown(2e18)));
        lm.updateAccounting();

        // Depositar tokens de bloqueo en nombre del segundo inversor
        vm.startPrank(investor2);
        lockToken.approve(address(lm), depositAmount);
        lm.deposit(depositAmount);
        vm.stopPrank();

        // Verificar que el segundo depósito se ha realizado correctamente
        assertUserInfo(investor2, depositAmount, 0, 0, "after second deposit");
    }

    function check_final_rewards(uint256 depositAmount) public {
        vm.assume(depositAmount > 0 && depositAmount < 1e24);
        address investor2 = svm.createAddress("investor2");
        vm.assume(investor2 == address(this));

        _loadRewards(totalRewards);

        MintBurnERC20(address(lockToken)).mint(investor, depositAmount);
        MintBurnERC20(address(lockToken)).mint(investor2, depositAmount);

        // Depositar tokens de bloqueo en nombre del inversor inicial
        vm.startPrank(investor);
        lockToken.approve(address(lm), depositAmount);
        lm.deposit(depositAmount);
        vm.stopPrank();

        // Avanzar al medio del periodo de minería de liquidez
        vm.roll(block.number + (lm.fundedEpochsLeft().divWadDown(2e18)));
        lm.updateAccounting();

        // Depositar tokens de bloqueo en nombre del segundo inversor
        vm.startPrank(investor2);
        lockToken.approve(address(lm), depositAmount);
        lm.deposit(depositAmount);
        vm.stopPrank();

        // Avanzar al final del periodo de minería de liquidez
        vm.roll(block.number + lm.fundedEpochsLeft());
        lm.updateAccounting();

        // Verificar las recompensas pendientes finales
        assert(lm.pendingRewards(investor) == totalRewards.mulWadUp(75e16));
        assert(lm.pendingRewards(investor2) == totalRewards.mulWadUp(25e16));
        assert(lm.rewardsLeft() == 0);
        assert(rewardToken.balanceOf(address(lm)) == totalRewards);
    }


    function assertUserInfo(
        address user,
        uint256 lockedTokens,
        uint256 rewardDebt,
        uint256 unclaimedRewards,
        string memory label
    ) internal view {
        LiquidityMine.UserInfo memory u = lm.userInfo(user);
        assert(
            u.lockedTokens ==
            lockedTokens
        );
        assert(
            u.rewardDebt == rewardDebt
        );
        assert(
            u.unclaimedRewards ==
            unclaimedRewards
        );
    }

    function _loadRewards(uint256 totalRewardsToDistribute) internal {
        MintBurnERC20(address(rewardToken)).mint(address(this), totalRewardsToDistribute);
        rewardToken.approve(address(lm), totalRewardsToDistribute);

        uint256 preloadBal = rewardToken.balanceOf(address(lm));
        uint256 preloadRewardCap = lm.totalRewardCap();
        lm.loadRewards(totalRewardsToDistribute);
        uint256 postloadBal = rewardToken.balanceOf(address(lm));
        uint256 postloadRewardCap = lm.totalRewardCap();

        assert(
            postloadBal ==
            totalRewardsToDistribute + preloadBal
        
        );
        assert(
            postloadRewardCap ==
            preloadRewardCap + totalRewardsToDistribute
            
        );
    }
}
