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
import "src/interfaces/IAuctionV2.sol";

contract AuctionV1Base is SaleBase, GelatoVRFConsumerBase {
    function initialize(StructsLibrary.IAuctionV1BaseConfig memory config) public {
        require(initialized == false, "Already initialized");
        seller = config._blessedOperator;
        operatorAddr = config._gelatoVrfOperator;
        _transferOwnership(config._owner);
        totalNumberOfTickets = config._ticketAmount;
        numberOfTickets = config._ticketPrice;
        prevRoundTicketsAmount = config._ticketPrice;
        minimumDepositAmount = config._ticketPrice;
        currentPrice = config._ticketPrice;
        initialPrice = config._ticketPrice;
        increasePriceStep = config._priceIncreaseStep;
        usdcContractAddr = config._usdcContractAddr;
        nftContractAddr = config._nftContractAddr;
        multisigWalletAddress = config._multisigWalletAddress;
        lotteryV2Addr = config._prevPhaseContractAddr;

        initialized = true;
    }

    struct Round {
        uint256 number;
        uint256 finishAt;
        uint256 numberOfTickets;
        bool lotteryStarted;
        bool winnersSelected;
    }
    mapping(uint256 => Round) public rounds;
    uint256 public roundCounter = 1;
    mapping(address => bool) public operators;
    address public lotteryV2Addr;
    address public operatorAddr;
    uint256 public currentPrice;
    uint256 public initialPrice;
    uint256 public prevRoundDeposits = 1;
    uint256 public prevRoundTicketsAmount = 1;
    uint256 public increasePriceStep = 5;
    uint256 public totalNumberOfTickets;
    uint256 public randomNumber;

    event RandomRequested(address indexed requester);
    event RandomFulfilled(uint256 number);
    event RoundSet(uint256 indexed roundNumber, uint256 finishAt, uint256 numberOfTickets);

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
        require(amount >= minimumDepositAmount, "Not enough funds sent");
        require(IERC20(usdcContractAddr).allowance(_msgSender(), address(this)) >= amount, "Insufficient allowance");

        IERC20(usdcContractAddr).transferFrom(_msgSender(), address(this), amount);
        
        if(deposits[_msgSender()] == 0) {
            participants.push(_msgSender());
        }
        deposits[_msgSender()] += amount;
        if (amount >= currentPrice) {
            prevRoundDeposits += 1;
        }
        emit BuyerDeposited(_msgSender(), amount);
    }

    function setOperator(address _operatorAddr, bool _flag) public onlyOwner {
        operators[_operatorAddr] = _flag;
    }

    function setupNewRound(uint256 _finishAt, uint256 _numberOfTickets) public onlyOperator {
        require(_numberOfTickets <= totalNumberOfTickets, "Tickets per round cannot be higher than total number of tickets in AuctionV1");

        uint256 newPrice = 0;
        if (prevRoundDeposits >= totalNumberOfTickets) {
            // higher demand than supply, increase price
            newPrice = currentPrice + increasePriceStep * (prevRoundDeposits / prevRoundTicketsAmount);
        } else {
            // lower demand than supply, decrease price
            uint256 decreaseAmount = increasePriceStep * (1 - prevRoundDeposits / prevRoundTicketsAmount);
            if (currentPrice > decreaseAmount) {
                newPrice = currentPrice - decreaseAmount;
            } else {
                newPrice = initialPrice;
            }
        }
        currentPrice = newPrice;
        prevRoundDeposits = 0;
        numberOfTickets = _numberOfTickets;
        prevRoundTicketsAmount = _numberOfTickets;
        totalNumberOfTickets -= _numberOfTickets;

        rounds[roundCounter] = Round({
            number: roundCounter,
            finishAt: _finishAt,
            numberOfTickets: _numberOfTickets,
            lotteryStarted: true,
            winnersSelected: false
        });
        emit RoundSet(roundCounter, _finishAt, _numberOfTickets);

        changeLotteryState(LotteryState.ACTIVE);

        roundCounter++;
    }

    function requestRandomness() external onlySeller {
        _requestRandomness(abi.encode(_msgSender()));
        emit RandomRequested(_msgSender());
    } 

    function _fulfillRandomness(uint256 randomness, uint256, bytes memory) internal override {
        randomNumber = randomness;
        emit RandomFulfilled(randomness);
    }

    function selectWinners() external onlySeller {
        require(numberOfTickets > 0, "No tickets left to allocate");
        lotteryState = LotteryState.ACTIVE;
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

        rounds[roundCounter - 1].winnersSelected = true;
        lotteryState = LotteryState.NOT_STARTED;
        if (totalNumberOfTickets == 0) {
            lotteryState = LotteryState.ENDED;
            emit LotteryEnded();
        }
    }

    function mintMyNFT() public {
        require(isWinner(_msgSender()), "Caller is not a winner");
        require(!hasMinted[_msgSender()], "NFT already minted");
        hasMinted[_msgSender()] = true;
        uint256 remainingBalance = deposits[_msgSender()] - currentPrice;
        if (remainingBalance > 0) {
            IERC20(usdcContractAddr).transfer(_msgSender(), remainingBalance);
        }
        deposits[_msgSender()] = 0;
        INFTLotteryTicket(nftContractAddr).lotteryMint(_msgSender());
    }

    function transferDeposit(address _participant, uint256 _amount) public {
        require(lotteryV2Addr == _msgSender(), "Only whitelisted may call this function");

        if(deposits[_msgSender()] == 0) {
            participants.push(_participant);
        }
        deposits[_participant] += _amount;
        prevRoundDeposits += 1;
    }

    function transferNonWinnerBids(address destinationAddr) public onlySeller {
        for(uint256 i = 0; i < participants.length; i++) {
            uint256 currentDeposit = deposits[participants[i]];
            deposits[participants[i]] = 0;
            IERC20(usdcContractAddr).transfer(destinationAddr, currentDeposit);
            IAuctionV2(destinationAddr).transferDeposit(participants[i], currentDeposit);

            if (i < participants.length - 1) {
                participants[i] = participants[participants.length - 1];
            }
            participants.pop();
        }
    }
}
