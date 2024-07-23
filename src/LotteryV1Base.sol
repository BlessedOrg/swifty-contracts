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
    function initialize(StructsLibrary.ILotteryV1BaseConfig memory config) public initializer {
        seller = config._seller;
        operatorAddr = config._gelatoVrfOperator;
        _transferOwnership(config._owner);
        numberOfTickets = config._ticketAmount;
        ticketPrice = config._ticketPrice;
        usdcContractAddr = config._usdcContractAddr;
        nftContractAddr = config._nftContractAddr;
        multisigWalletAddress = config._multisigWalletAddress;
    }

    address public operatorAddr;
    uint256 public randomNumber;
    bool randomnessRequested = false;

    event RandomRequested(address indexed requester);
    event RandomFulfilled(uint256 number);

    function _operator() internal view override returns (address) {
        return operatorAddr;
    }

    function deposit(uint256 amount) public lotteryStarted {
        require(usdcContractAddr != address(0), "USDC contract address not set");
        require(amount >= ticketPrice, "Not enough funds sent");
        require(IERC20(usdcContractAddr).allowance(_msgSender(), address(this)) >= amount, "Insufficient allowance");
        require(randomNumber == 0, "Lottery deposits are locked; random number is generated");
        require(randomnessRequested == false, "Deposits are locked now");

        IERC20(usdcContractAddr).transferFrom(_msgSender(), address(this), amount);

        if (deposits[_msgSender()] == 0) {
            participants.push(_msgSender());
        }
        deposits[_msgSender()] += amount;
        emit BuyerDeposited(_msgSender(), amount);
    }

    function requestRandomness() external onlySeller lotteryStarted {
        randomnessRequested = true;
        lotteryState = LotteryState.ENDED;
        _requestRandomness(abi.encode(_msgSender()));
        emit RandomRequested(_msgSender());
    }

    function _fulfillRandomness(uint256 randomness, uint256, bytes memory) internal override {
        randomNumber = randomness;
        emit RandomFulfilled(randomness);
    }

    function selectWinners() external onlySeller lotteryEnded {
        require(randomNumber > 0, "Random number is not generated");
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
        }

        lotteryState = LotteryState.ENDED;
        transferDepositsBack();
        emit LotteryEnded();
    }

    function mintMyNFT() public hasNotMinted hasWon lotteryEnded {
        hasMinted[_msgSender()] = true;
        INFTLotteryTicket(nftContractAddr).lotteryMint(_msgSender());
    }
}
