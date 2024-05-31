// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

interface INFTLotteryTicket {
  function initialize(string memory uri, bool _isTransferable, address owner, string calldata name, string calldata symbol) external;
  function transferOwnership(address newOwner) external;
  function lotteryMint(address winner) external;
  function setDepositContractAddr(address _depositContractAddr) external;
}