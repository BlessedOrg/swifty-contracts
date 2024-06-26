// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import { Ownable } from "../lib/openzeppelin-contracts/contracts/access/Ownable.sol";
import { GelatoVRFConsumerBase } from "../lib/vrf-contracts/contracts/GelatoVRFConsumerBase.sol";
import { ERC2771Context } from "../lib/relay-context-contracts/contracts/vendor/ERC2771Context.sol";
import { Context } from "../lib/openzeppelin-contracts/contracts/utils/Context.sol";
import { SaleBase } from "./SaleBase.sol";
import "src/vendor/StructsLibrary.sol";
import "src/interfaces/INFTLotteryTicket.sol";
import "src/interfaces/IERC20.sol";
import "src/interfaces/ILotteryV2.sol";

contract LotteryV1Base is SaleBase, GelatoVRFConsumerBase {
    function initialize(StructsLibrary.ILotteryBaseConfig memory config) public {
        require(initialized == false, "Already initialized");
        seller = config._blessedOperator;
        operatorAddr = config._gelatoVrfOperator;
        _transferOwnership(config._owner);
        numberOfTickets = config._ticketAmount;
        minimumDepositAmount = config._ticketPrice;
        usdcContractAddr = config._usdcContractAddr;
        multisigWalletAddress = config._multisigWalletAddress;

        initialized = true;
    }

    bool public initialized = false;

    address public operatorAddr;
    uint256 public randomNumber;

    event RandomRequested(address indexed requester);
    event RandomFulfilled(uint256 number);

    function _operator() internal view override returns (address) {
        return operatorAddr;
    }

    function deposit(uint256 amount) public lotteryStarted {
        require(usdcContractAddr != address(0), "USDC contract address not set");
        require(amount >= minimumDepositAmount, "Not enough funds sent");
        require(
            IERC20(usdcContractAddr).allowance(_msgSender(), address(this)) >= amount,
            "Insufficient allowance"
        );

        IERC20(usdcContractAddr).transferFrom(_msgSender(), address(this), amount);

        if (deposits[_msgSender()] == 0) {
            participants.push(_msgSender());
        }
        deposits[_msgSender()] += amount;
    }

    function requestRandomness() external onlySeller {
        _requestRandomness(abi.encode(_msgSender()));
        emit RandomRequested(_msgSender());
    }

    function _fulfillRandomness(uint256 randomness, uint256, bytes memory) internal override {
        randomNumber = randomness;
        emit RandomFulfilled(randomness);
    }

    function selectWinners() external onlySeller lotteryStarted {
        require(numberOfTickets > 0, "No tickets left to allocate");
        uint256 participantsLength = participants.length;

        if(numberOfTickets >= participantsLength) {
            // If demand is less than or equal to supply, everyone wins
            for (uint256 i = 0; i < participantsLength; i++) {
                address selectedWinner = participants[i];
                if (!isWinner(selectedWinner)) {
                    setWinner(selectedWinner);
                    emit WinnerSelected(selectedWinner);
                }
            }
            // Clear the participants list since all are winners
            delete participants;
            numberOfTickets = 0;
        } else {
            // Shuffle the array of participants
            for (uint j = 0; j < participantsLength; j++) {
                uint n = j + randomNumber % (participantsLength - j);
                address temp = participants[n];
                participants[n] = participants[j];
                participants[j] = temp;
            }

            // Select the first `numberOfTickets` winners
            for (uint256 i = 0; i < numberOfTickets; i++) {
                address selectedWinner = participants[i];
                if (!isWinner(selectedWinner)) {
                    setWinner(selectedWinner);
                    emit WinnerSelected(selectedWinner);
                }
            }

            // Remove the winners from the participants list by shifting non-winners up
            uint256 shiftIndex = 0;
            for (uint256 i = numberOfTickets; i < participantsLength; i++) {
                participants[shiftIndex] = participants[i];
                shiftIndex++;
            }
            for (uint256 i = shiftIndex; i < participantsLength; i++) {
                participants.pop();
            }

            numberOfTickets = 0;
        }

        if (numberOfTickets == 0) {
            emit LotteryEnded();
            lotteryState = LotteryState.ENDED;
        }
    }

    function mintMyNFT() public hasNotMinted lotteryEnded {
        require(isWinner(_msgSender()), "Caller is not a winner");
        hasMinted[_msgSender()] = true;
        uint256 remainingBalance = deposits[_msgSender()] - minimumDepositAmount;
        if (remainingBalance > 0) {
            IERC20(usdcContractAddr).transfer(_msgSender(), remainingBalance);
        }
        deposits[_msgSender()] = 0;
        INFTLotteryTicket(nftContractAddr).lotteryMint(_msgSender());
    }

    function transferNonWinnerDeposits(address lotteryV2addr) public onlySeller {
        for(uint256 i = 0; i < participants.length; i++) {
            uint256 currentDeposit = deposits[participants[i]];
            deposits[participants[i]] = 0;
            IERC20(usdcContractAddr).transfer(lotteryV2addr, currentDeposit);
            ILotteryV2(lotteryV2addr).transferDeposit(participants[i], currentDeposit);

            if (i < participants.length - 1) {
                participants[i] = participants[participants.length - 1];
            }
            participants.pop();
        }
    }
}
