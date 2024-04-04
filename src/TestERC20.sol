// SPDX-License-Identifier: MIT
// Compatible with OpenZeppelin Contracts ^5.0.0
pragma solidity ^0.8.13;

import "../lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import "../lib/openzeppelin-contracts/contracts/access/Ownable.sol";
import "../lib/openzeppelin-contracts/contracts/token/ERC20/extensions/ERC20Permit.sol";
import {
    ERC2771Context
} from "../lib/relay-context-contracts/contracts/vendor/ERC2771Context.sol";
import { Context } from "../lib/openzeppelin-contracts/contracts/utils/Context.sol";

contract TestERC20 is ERC20, Ownable, ERC20Permit, ERC2771Context {
    constructor(address initialOwner)
        ERC2771Context(0xd8253782c45a12053594b9deB72d8e8aB2Fca54c)
        ERC20("MyToken", "MTK")
        Ownable(initialOwner)
        ERC20Permit("MyToken")
    {}

    function _msgSender() internal view override(ERC2771Context, Context)
        returns (address sender) {
        sender = ERC2771Context._msgSender();
    }

    function _msgData() internal view override(ERC2771Context, Context)
        returns (bytes calldata) {
        return ERC2771Context._msgData();
    }        

    function mint(address to, uint256 amount) public onlyOwner {
        _mint(to, amount);
    }
}