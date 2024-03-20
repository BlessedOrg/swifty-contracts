// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

interface IDeposit {
    enum LotteryState {
        NOT_STARTED,
        ACTIVE,
        ENDED
    }

    function getParticipants() external view returns (address[] memory);

    function getDepositedAmount(
        address participant
    ) external view returns (uint256);

    function lotteryState() external view returns (LotteryState);

    function changeLotteryState(LotteryState _newState) external;

    function isWinner(address _participant) external view returns (bool);

    function getWinners() external view returns (address[] memory);

    function setWinner(address _winner) external;

    function buyerWithdraw() external;

    function sellerWithdraw() external;
}
