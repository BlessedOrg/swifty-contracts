// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

interface ILotteryBase {
  function initialize(address _seller, address _operatorAddr, address _owner) external;
  function transferOwnership(address newOwner) external;
  function setNftContractAddr(address _nftContractAddr) external;
}