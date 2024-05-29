// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

interface ILotteryV1 {
    function isWinner(address _participant) external view returns (bool);
}