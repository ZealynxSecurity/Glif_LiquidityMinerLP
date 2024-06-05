// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Votes} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import {Nonces} from "@openzeppelin/contracts/utils/Nonces.sol";
import {Ownable} from "src/Ownable.sol";
import {FilAddress} from "shim/FilAddress.sol";

contract Token is ERC20, ERC20Permit, ERC20Votes, Ownable {
    using FilAddress for address;

    address public minter;
    address public burner;

    constructor(string memory _name, string memory _symbol, address _owner, address _minter, address _burner)
        ERC20(_name, _symbol)
        ERC20Permit(_name)
        Ownable(_owner)
    {
        minter = _minter;
        burner = _burner;
    }

    function balanceOf(address account) public view override(ERC20) returns (uint256) {
        return super.balanceOf(account.normalize());
    }

    function allowance(address owner, address spender) public view override(ERC20) returns (uint256) {
        return super.allowance(owner.normalize(), spender.normalize());
    }

    function approve(address spender, uint256 value) public override(ERC20) returns (bool) {
        return super.approve(spender.normalize(), value);
    }

    function transfer(address to, uint256 value) public override returns (bool) {
        return super.transfer(to.normalize(), value);
    }

    function transferFrom(address from, address to, uint256 value) public override returns (bool) {
        return super.transferFrom(from.normalize(), to.normalize(), value);
    }

    function mint(address account, uint256 value) public {
        if (msg.sender != minter) revert Unauthorized();
        super._mint(account.normalize(), value);
    }

    function burn(address account, uint256 value) public {
        super._burn(account.normalize(), value);
    }

    function _update(address from, address to, uint256 value) internal override(ERC20, ERC20Votes) {
        super._update(from.normalize(), to.normalize(), value);
    }

    function nonces(address owner) public view override(ERC20Permit, Nonces) returns (uint256) {
        return super.nonces(owner.normalize());
    }

    function setMinter(address _minter) external onlyOwner {
        minter = _minter;
    }

    function setBurner(address _burner) external onlyOwner {
        burner = _burner;
    }
}