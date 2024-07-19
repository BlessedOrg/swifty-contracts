// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import { Ownable } from "../lib/openzeppelin-contracts/contracts/access/Ownable.sol";
import { GelatoVRFConsumerBase } from "../lib/vrf-contracts/contracts/GelatoVRFConsumerBase.sol";
import { ERC2771Context } from "../lib/relay-context-contracts/contracts/vendor/ERC2771Context.sol";
import { Context } from "../lib/openzeppelin-contracts/contracts/utils/Context.sol";
import { SafeMath } from "lib/foundry-chainlink-toolkit/lib/openzeppelin-contracts/contracts/utils/math/SafeMath.sol";
import { SaleBase } from "./SaleBase.sol";
import "src/vendor/StructsLibrary.sol";
import "src/interfaces/INFTLotteryTicket.sol";
import "src/interfaces/IERC20.sol";
import "src/interfaces/ILotteryV2.sol";
import "src/interfaces/IAuctionV2.sol";

contract AuctionV1Base is SaleBase, GelatoVRFConsumerBase {
    using SafeMath for uint256;

    function initialize(StructsLibrary.IAuctionV1BaseConfig memory config) public initializer {
        seller = config._seller;
        operatorAddr = config._gelatoVrfOperator;
        _transferOwnership(config._owner);
        totalNumberOfTickets = config._ticketAmount;
        numberOfTickets = config._ticketPrice;
        prevRoundTicketsAmount = config._ticketPrice;
        ticketPrice = config._ticketPrice;
        initialPrice = config._ticketPrice;
        increasePriceStep = config._priceIncreaseStep;
        usdcContractAddr = config._usdcContractAddr;
        nftContractAddr = config._nftContractAddr;
        multisigWalletAddress = config._multisigWalletAddress;
        lotteryV2Addr = config._prevPhaseContractAddr;
        roundCounter = 1;
    }

    struct Round {
        uint256 number;
        uint256 finishAt;
        uint256 numberOfTickets;
        uint256 randomNumber;
        bool lotteryStarted;
        bool lotteryFinished;
        bool winnersSelected;
        mapping(address => uint256) deposits;
        address[] participants;
    }
    mapping(uint256 => Round) public rounds;
    uint256 public roundCounter;
    mapping(address => bool) public operators;
    address public lotteryV2Addr;
    address public operatorAddr;
    uint256 public initialPrice;
    uint256 public prevRoundDeposits = 1;
    uint256 public prevRoundTicketsAmount = 1;
    uint256 public increasePriceStep = 5;
    uint256 public totalNumberOfTickets;

    event RandomRequested(address indexed requester);
    event RandomFulfilled(uint256 number, address indexed requester);
    event RoundSet(uint256 indexed roundNumber, uint256 finishAt, uint256 numberOfTickets, uint256 newTicketPrice);
    event DepositsReturned(uint256 returnedDepositsCount, uint256 indexed roundNumber);

    modifier onlyOperator() {
        require(_msgSender() == seller || _msgSender() == owner() || operators[_msgSender()], "Only operator can call this function");
        _;
    }

    function _operator() internal view override returns (address) {
        return operatorAddr;
    }

    function deposit(uint256 amount) public {
        require(!isWinner(_msgSender()), "Winners cannot deposit");
        require(usdcContractAddr != address(0), "USDC contract address not set");
        require(amount >= ticketPrice, "Not enough funds sent");
        require(IERC20(usdcContractAddr).allowance(_msgSender(), address(this)) >= amount, "Insufficient allowance");
        require(rounds[roundCounter - 1].lotteryFinished == false, "You can't deposit after round is finished");

        IERC20(usdcContractAddr).transferFrom(_msgSender(), address(this), amount);

        if(deposits[_msgSender()] == 0) {
            rounds[roundCounter - 1].participants.push(_msgSender());
        }
        rounds[roundCounter - 1].deposits[_msgSender()] += amount;
        if (amount >= ticketPrice) {
            prevRoundDeposits += 1;
        }
        emit BuyerDeposited(_msgSender(), amount);
    }

    function setOperator(address _operatorAddr, bool _flag) public onlyOwner {
        operators[_operatorAddr] = _flag;
    }

    function setupNewRound(uint256 _finishAt, uint256 _numberOfTickets) public onlyOperator {
        require(_numberOfTickets <= totalNumberOfTickets, "Tickets per round cannot be higher than total number of tickets in AuctionV1");
        if (roundCounter > 1) {
            require(rounds[roundCounter - 1].winnersSelected == true, "Finish last round first by selecting winners");
        }

        uint256 newPrice = 0;
        if (prevRoundDeposits >= numberOfTickets) {
            // higher demand than supply, increase price
            newPrice = ticketPrice.add(increasePriceStep.mul(prevRoundDeposits.div(prevRoundTicketsAmount)));
        } else {
            // lower demand than supply, decrease price
            uint256 decreaseAmount = increasePriceStep.mul(prevRoundTicketsAmount.sub(prevRoundDeposits).div(prevRoundTicketsAmount));
            if (ticketPrice > decreaseAmount) {
                newPrice = ticketPrice.sub(decreaseAmount);
            } else {
                newPrice = initialPrice;
            }
        }
        ticketPrice = newPrice;
        prevRoundDeposits = 0;
        numberOfTickets = _numberOfTickets;
        prevRoundTicketsAmount = _numberOfTickets;
        totalNumberOfTickets -= _numberOfTickets;

        Round storage newRound = rounds[roundCounter];
        newRound.number = roundCounter;
        newRound.finishAt = _finishAt;
        newRound.numberOfTickets = _numberOfTickets;
        newRound.randomNumber = 0;
        newRound.lotteryStarted = true;
        newRound.lotteryFinished = false;
        newRound.winnersSelected = false;
        changeLotteryState(LotteryState.ACTIVE);
        emit RoundSet(roundCounter, _finishAt, _numberOfTickets, newPrice);
        roundCounter++;
    }

    function getDepositedAmount(address participant) external view override returns (uint256) {
        return rounds[roundCounter - 1].deposits[participant];
    }

    function getParticipants() public view override returns (address[] memory) {
        return rounds[roundCounter - 1].participants;
    }

    function getDepositedAmountForRound(address participant, uint256 roundIndex) external view returns (uint256) {
        return rounds[roundIndex].deposits[participant];
    }

    function getParticipantsForRound(uint256 roundIndex) public view returns (address[] memory) {
        return rounds[roundIndex].participants;
    }

    function requestRandomness() external onlySeller {
        require(roundCounter > 1, "Setup first round");
        require(rounds[roundCounter - 1].finishAt <= block.timestamp, "Round is not ended yet");
        rounds[roundCounter - 1].lotteryFinished = true;
        _requestRandomness(abi.encode(_msgSender()));
        emit RandomRequested(_msgSender());
    }

    function _fulfillRandomness(uint256 randomness, uint256, bytes memory extraData) internal override {
        rounds[roundCounter - 1].randomNumber = randomness;
        emit RandomFulfilled(randomness, abi.decode(extraData, (address)));
    }

    function selectWinners() external onlySeller {
        require(rounds[roundCounter - 1].randomNumber > 0, "Random number for last round is not generated");
        require(numberOfTickets > 0, "No tickets left to allocate");
        lotteryState = LotteryState.ACTIVE;
        uint256 participantsLength = rounds[roundCounter - 1].participants.length;

        if (numberOfTickets >= participantsLength) {
            // If demand is less than or equal to supply, everyone wins
            for (uint256 i = 0; i < participantsLength; i++) {
                address selectedWinner = rounds[roundCounter - 1].participants[i];
                if (!isWinner(selectedWinner)) {
                    setWinner(selectedWinner);
                    emit WinnerSelected(selectedWinner);
                }
            }
        } else {
            // Shuffle the array of participants
            for (uint j = 0; j < participantsLength; j++) {
                uint n = j + rounds[roundCounter - 1].randomNumber % (participantsLength - j);
                address temp = rounds[roundCounter - 1].participants[n];
                rounds[roundCounter - 1].participants[n] = rounds[roundCounter - 1].participants[j];
                rounds[roundCounter - 1].participants[j] = temp;
            }

            // Select the first `numberOfTickets` winners
            for (uint256 i = 0; i < numberOfTickets; i++) {
                address selectedWinner = rounds[roundCounter - 1].participants[i];
                if (!isWinner(selectedWinner)) {
                    setWinner(selectedWinner);
                    emit WinnerSelected(selectedWinner);
                }
            }
        }

        numberOfTickets = 0;
        rounds[roundCounter - 1].winnersSelected = true;
        transferDepositsBack();
        lotteryState = LotteryState.NOT_STARTED;

        if (totalNumberOfTickets == 0) {
            lotteryState = LotteryState.ENDED;
            emit LotteryEnded();
        }
    }

    function transferDepositsBack() override internal onlySeller {
        require(rounds[roundCounter - 1].winnersSelected = true, "Winners were not selected for the current round");
        uint256 participantsLength = rounds[roundCounter - 1].participants.length;
        address[] memory participantsCopy = new address[](participantsLength);
        for (uint256 i = 0; i < participantsLength; i++) {
            participantsCopy[i] = rounds[roundCounter - 1].participants[i];
        }
        for (uint256 i = 0; i < participantsLength; i++) {
            address participant = participantsCopy[i];
            uint256 depositAmount = rounds[roundCounter - 1].deposits[participant];

            if (isWinner(participant)) {
                if (depositAmount >= ticketPrice) {
                    uint256 winnerRemainingDeposit = depositAmount - ticketPrice;
                    if (winnerRemainingDeposit > 0) {
                        rounds[roundCounter - 1].deposits[participant] -= winnerRemainingDeposit;
                        IERC20(usdcContractAddr).transfer(participant, winnerRemainingDeposit);
                    }
                }
                totalAmountForSeller += rounds[roundCounter - 1].deposits[participant];
                rounds[roundCounter - 1].deposits[participant] = 0;
            } else {
                rounds[roundCounter - 1].deposits[participant] = 0;
                IERC20(usdcContractAddr).transfer(participant, depositAmount);
            }
        }
        sellerWithdraw();
        delete rounds[roundCounter - 1].participants;
        emit DepositsReturned(participantsLength, roundCounter - 1);
    }

    function mintMyNFT() public hasNotMinted hasWon {
        hasMinted[_msgSender()] = true;
        INFTLotteryTicket(nftContractAddr).lotteryMint(_msgSender());
    }
}
