// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./EchidnaConfig.sol";
import "./MockERC20.sol";

contract EchidnaSetup is EchidnaConfig {
    MockERC20 internal rewardToken;
    MockERC20 internal lockToken;
    address internal _erc20rewardToken;
    address internal _erc20lockToken;

    constructor() {
        hevm.prank(USER1);
        rewardToken = new MockERC20("GLIF", "GLF");
        hevm.prank(USER1);
        lockToken = new MockERC20("GLIF", "GLF");
        _erc20rewardToken = address(rewardToken);
        _erc20lockToken = address(lockToken);
    }
}