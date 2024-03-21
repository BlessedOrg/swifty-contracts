// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

interface ILotteryV2 {
  function transferDeposit(address _participant, uint256 _amount) external;
}