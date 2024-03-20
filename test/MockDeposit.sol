// MockDeposit.sol

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "../src/interfaces/IDeposit.sol";

contract MockDeposit is IDeposit {
    mapping(address => bool) private winners;
    mapping(address => uint256) private depositedAmounts;

    // Add state variables to track participants and winners
    address[] private participants;
    address[] private winnersArray;

    // Function to simulate setting a winner in the Deposit contract
    function setWinner(address _winner) external override {
        winnersArray.push(_winner);
        winners[_winner] = true;
    }

    // Function to check if an address is a winner
    function isWinner(address _participant) external view override returns (bool) {
        return winners[_participant];
    }

    // Function to simulate setting a deposited amount for a participant
    function setDepositedAmount(address _participant, uint256 _amount) external {
        participants.push(_participant);
        depositedAmounts[_participant] = _amount;
    }

    // Function to get the deposited amount for a participant
    function getDepositedAmount(address _participant) external view override returns (uint256) {
        return depositedAmounts[_participant];
    }

    // Implement other necessary functions from the IDeposit interface
    function getParticipants() external view override returns (address[] memory) {
        return participants;
    }

    function lotteryState() external view override returns (LotteryState) {}

    function changeLotteryState(LotteryState _newState) external override {}

    function getWinners() external view override returns (address[] memory) {
        return winnersArray;
    }

    function buyerWithdraw() external override {}

    function sellerWithdraw() external override {}
}
