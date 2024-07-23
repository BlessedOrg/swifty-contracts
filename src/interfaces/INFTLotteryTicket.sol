// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

interface INFTLotteryTicket {
    function initialize(string memory uri, bool _isTransferable, address _owner, string calldata _name, string calldata _symbol) external;
    function lotteryMint(address winner) external;
    function setDepositContractAddr(address _depositContractAddr) external;
}