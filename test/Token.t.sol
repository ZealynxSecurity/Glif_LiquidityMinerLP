// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {Test, console} from "forge-std/Test.sol";
import {Token} from "src/Token.sol";

contract TokenTest is Test {
    Token token;
    address sysAdmin = makeAddr("sysadmin");

    function setUp() public {
        token = new Token("GLIF", "GLF", sysAdmin, address(this), address(this));
    }

    function test_Initialization() public view {
        assertEq(token.name(), "GLIF", "Name incorrect");
        assertEq(token.symbol(), "GLF", "Symbol incorrect");
        assertEq(token.decimals(), 18, "Decimals incorrect");
    }
}
