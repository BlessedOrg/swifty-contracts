// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

contract MockLottery {
    address public depositAddress;

    function setDepositAddress(address _depositAddress) external {
        depositAddress = _depositAddress;
    }

    function changeLotteryState(uint _state) external {
        IDepositContract(depositAddress).changeLotteryState(
            IDepositContract.LotteryState(_state)
        );
    }

    function setWinner(address _winner) external {
        IDepositContract(depositAddress).setWinner(_winner);
    }
}

interface IDepositContract {
    enum LotteryState {
        NOT_STARTED,
        ACTIVE,
        ENDED
    }

    function changeLotteryState(LotteryState _newState) external;

    function setWinner(address _winner) external;
}
