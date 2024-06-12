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
contract BaseHalmos is SymTest, Test {
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


    function setUp() public {

        investor = svm.createAddress("investor");
        sysAdmin = svm.createAddress("sysAdmin");

        rewardPerEpoch = 1e18;
        totalRewards = 75_000_000e18;
        rewardToken = IERC20(address(new Token("GLIF", "GLF", sysAdmin, address(this), address(this))));
        lockToken = IERC20(address(new Token("iFIL", "iFIL", sysAdmin, address(this), address(this))));

        deployBlock = block.number;
        lm = new LiquidityMine(rewardToken, lockToken, rewardPerEpoch, sysAdmin);

        MintBurnERC20(address(rewardToken)).mint(sysAdmin, totalRewards);
        MintBurnERC20(address(lockToken)).mint(investor, 1e24);

        vm.deal(sysAdmin, 300 * 1e18);
        vm.deal(investor, 300 * 1e18);

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